import UIKit

/// The capture decision pipeline — identify → ground → mint → progress → report —
/// lifted out of `FieldViewController` so the app's riskiest logic path is a pure,
/// injectable unit with a single return value instead of a tangle of side effects
/// inside a view controller. The view controller keeps only rendering (haptics,
/// status copy, card presentation, narration kickoff); everything decision-shaped
/// lives here and is driven entirely through the injected seams below, so the
/// whole matrix (confidence gate, resolved/unresolved/offline grounding,
/// provisional minting, save-failure abort, XP + Game Center side effects) is
/// testable without a camera, a network, or a screen.
struct CaptureFlow: Sendable {
    let identifier: any SpeciesIdentifier
    let enricher: any SpeciesEnriching
    let imageStore: any CaptureImageStoring
    let sightingStore: any SightingPersisting
    let progress: any ProgressRecording
    let reporter: any CatchReporting
    let clock: @Sendable () -> Date

    init(
        identifier: any SpeciesIdentifier,
        enricher: any SpeciesEnriching,
        imageStore: any CaptureImageStoring,
        sightingStore: any SightingPersisting,
        progress: any ProgressRecording,
        reporter: any CatchReporting,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.identifier = identifier
        self.enricher = enricher
        self.imageStore = imageStore
        self.sightingStore = sightingStore
        self.progress = progress
        self.reporter = reporter
        self.clock = clock
    }

    /// Runs the full loop for a captured frame and returns exactly what happened.
    /// Never touches UIKit or presents anything; the caller renders the outcome.
    /// Intentionally not `@MainActor`: the JPEG encode, disk write, and GRDB calls
    /// run off the caller's actor so the reveal animation and status chip never
    /// stall on the main thread.
    func run(image: UIImage, context: CaptureContext) async -> CaptureOutcome {
        let result = await identifier.identify(image, context: context)
        guard var top = result.top else {
            return .identifyFailed(result.error ?? .noSpecies)
        }
        guard top.confidence >= IdentificationPolicy.minConfidence else {
            return .lowConfidence
        }

        guard let grounded = await ground(&top, context: context) else {
            return .unresolvedSpecies
        }

        let id = UUID().uuidString
        guard let path = imageStore.save(image, id: id) else {
            return .saveFailed
        }
        let now = clock()
        let sighting = makeSighting(id: id, path: path, at: now, from: top, context: context, enriched: grounded.confirmed)

        let isNew: Bool
        do {
            isNew = try sightingStore.save(sighting)
        } catch {
            return abortOnSaveFailure(path: path, error: error)
        }

        var event: ProgressEvent?
        do {
            event = try progress.record(rarity: top.rarity, isNew: isNew, now: now)
        } catch {
            AppLogger.shared.error(
                "progression write failed after mint: \(error)", category: .persistence)
        }
        await reportAchievements()

        return .minted(MintedCapture(
            sighting: sighting,
            image: image,
            isNew: isNew,
            provisional: !grounded.confirmed,
            progress: event,
            grounding: grounded.summary,
            candidate: top))
    }

    /// Grounds the candidate against GBIF and applies the confirmed rarity, the
    /// canonical `gbif:<taxonKey>` id + authoritative binomial, and the adopted
    /// common name in place. Returns the grounding summary and whether the catch
    /// was confirmed, or `nil` when GBIF rejected the name — a likely hallucination
    /// that must not be minted. An unreachable service mints provisionally.
    private func ground(_ candidate: inout SpeciesCandidate, context: CaptureContext) async -> Grounded? {
        switch await enricher.enrich(candidate: candidate, context: context) {
        case let .resolved(enrichment):
            candidate.rarity = enrichment.rarity
            if let taxonKey = enrichment.taxonKey {
                candidate.speciesId = "gbif:\(taxonKey)"
                if let sci = enrichment.scientificName, !sci.isEmpty {
                    candidate.scientificName = sci
                }
            }
            candidate.commonName = enrichment.adoptedCommonName(
                current: candidate.commonName, scientificName: candidate.scientificName)
            return Grounded(summary: enrichment.summary, confirmed: true)
        case .unresolved:
            return nil
        case .unavailable:
            return Grounded(summary: nil, confirmed: false)
        }
    }

    private func makeSighting(
        id: String, path: String, at capturedAt: Date, from candidate: SpeciesCandidate,
        context: CaptureContext, enriched: Bool
    ) -> Sighting {
        Sighting(
            id: id,
            speciesId: candidate.speciesId,
            commonName: candidate.commonName,
            scientificName: candidate.scientificName,
            realm: candidate.realm,
            rarity: candidate.rarity,
            confidence: candidate.confidence,
            capturedAt: capturedAt,
            latitude: context.latitude,
            longitude: context.longitude,
            elevationMeters: context.elevationMeters,
            imagePath: path,
            pokedexEntry: nil,
            enriched: enriched)
    }

    /// Undoes the orphaned image file and aborts before any XP, streak, Game Center
    /// credit, card, or narration write, so a lost row never masquerades as a catch.
    private func abortOnSaveFailure(path: String, error: any Error) -> CaptureOutcome {
        imageStore.delete(path)
        AppLogger.shared.error("save sighting failed: \(error)", category: .persistence)
        return .saveFailed
    }

    private func reportAchievements() async {
        guard let stats = try? sightingStore.stats(),
              let current = try? progress.current() else { return }
        await reporter.report(AchievementContext(
            speciesCount: stats.speciesCount,
            realms: stats.realms,
            maxRarity: stats.maxRarity,
            longestStreak: current.longestStreak))
    }

    private struct Grounded {
        let summary: String?
        let confirmed: Bool
    }
}

/// Everything that can come out of a single capture. `minted` is the only success
/// beat; every other case is a distinct, honest recovery state for the UI.
enum CaptureOutcome: Sendable {
    /// Identification itself failed — offline, out of credits, a server fault, or a
    /// genuinely empty frame. Drives distinct status copy per `IdentifyError`.
    case identifyFailed(IdentifyError)
    /// A candidate came back but below the mint threshold.
    case lowConfidence
    /// GBIF rejected the name — treated as a likely hallucination, never minted.
    case unresolvedSpecies
    /// The image or dex row could not be persisted; nothing was awarded.
    case saveFailed
    case minted(MintedCapture)
}

/// A successfully collected capture, ready for the reveal card and narration.
struct MintedCapture: Sendable {
    let sighting: Sighting
    let image: UIImage
    let isNew: Bool
    /// True when minted without GBIF confirmation (offline) — heals on a later open.
    let provisional: Bool
    let progress: ProgressEvent?
    let grounding: String?
    let candidate: SpeciesCandidate
}

// MARK: - Injected seams

/// Grounds a candidate against the domain Worker. Modeled as a protocol so the
/// flow can be exercised against a stubbed enricher.
protocol SpeciesEnriching: Sendable {
    func enrich(candidate: SpeciesCandidate, context: CaptureContext) async -> EnrichmentResult
}

/// Persists the full-resolution capture to disk and can remove an orphan.
protocol CaptureImageStoring: Sendable {
    func save(_ image: UIImage, id: String) -> String?
    func delete(_ relativePath: String)
}

/// Persists a sighting (folding it into its dex entry) and reads collection stats.
protocol SightingPersisting: Sendable {
    @discardableResult func save(_ sighting: Sighting) throws -> Bool
    func stats() throws -> CollectionStore.Stats
}

/// Advances player progression for a catch and reads the current snapshot.
protocol ProgressRecording: Sendable {
    func record(rarity: Rarity, isNew: Bool, now: Date) throws -> ProgressEvent
    func current() throws -> PlayerProgress
}

/// Reports a catch to Game Center (leaderboard + achievements).
protocol CatchReporting: Sendable {
    func report(_ context: AchievementContext) async
}

extension SpeciesEnricher: SpeciesEnriching {}
extension CollectionStore: SightingPersisting {}
extension ProgressStore: ProgressRecording {}

extension GameCenterService: CatchReporting {
    func report(_ context: AchievementContext) async {
        recordCatch(context: context)
    }
}

/// The production image seam over the static `ImageStore`.
struct DefaultCaptureImageStore: CaptureImageStoring {
    func save(_ image: UIImage, id: String) -> String? { ImageStore.save(image, id: id) }
    func delete(_ relativePath: String) { ImageStore.delete(relativePath) }
}

extension CaptureFlow {
    /// The production wiring: real identifier, Worker enricher, disk image store,
    /// GRDB collection + progress stores, and Game Center.
    @MainActor
    static func live() -> CaptureFlow {
        CaptureFlow(
            identifier: SpeciesIdentifierFactory.make(),
            enricher: SpeciesEnricher.shared,
            imageStore: DefaultCaptureImageStore(),
            sightingStore: CollectionStore.shared,
            progress: ProgressStore.shared,
            reporter: GameCenterService.shared)
    }
}
