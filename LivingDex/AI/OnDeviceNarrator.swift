import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device Pokédex-entry narration via Apple Foundation Models (iOS 26). Free,
/// private, offline. Grounded by a tight instruction + the supplied names/realm;
/// the model is device-scale, so we keep it to short evocative prose and hedge
/// away from invented specifics. Returns nil when the model is unavailable so
/// `NarratorService` falls back to the cloud.
struct OnDeviceNarrator: Narrator {
    /// Returns an instance only if the on-device model is available on this
    /// device, so the service can decide routing once at startup.
    static func makeIfAvailable() -> OnDeviceNarrator? {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            AppLogger.shared.info("on-device model available", category: .ai)
            return OnDeviceNarrator()
        default:
            AppLogger.shared.info("on-device model unavailable — cloud narration only", category: .ai)
            return nil
        }
        #else
        return nil
        #endif
    }

    func entry(for candidate: SpeciesCandidate) async -> PokedexEntry? {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(
                to: Self.prompt(for: candidate),
                generating: GeneratedEntry.self)
            let generated = response.content
            AppLogger.shared.info("on-device narrated \(candidate.commonName)", category: .ai)
            return PokedexEntry(entry: generated.entry, funFacts: generated.funFacts)
        } catch {
            AppLogger.shared.error("on-device narration failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
        #else
        return nil
        #endif
    }

    private static let instructions = """
        You write short, wondrous "Pokédex entries" for real organisms in a nature-collection game. \
        Ground every claim in well-established biology. Never invent specifics; if unsure, stay general. \
        Keep it vivid but honest.
        """

    private static func prompt(for c: SpeciesCandidate) -> String {
        """
        Write a Pokédex entry for this organism.
        Common name: \(c.commonName)
        Scientific name: \(c.scientificName)
        Kingdom/realm: \(c.realm.rawValue)
        """
    }
}

#if canImport(FoundationModels)
@Generable(description: "A short Pokédex-style entry for a real organism.")
struct GeneratedEntry {
    @Guide(description: "Two or three evocative but factually grounded sentences about the organism.")
    var entry: String

    @Guide(description: "Three short, true fun facts about the organism.", .count(3))
    var funFacts: [String]
}
#endif
