import Foundation
import LivingDexCore

/// Produces a grounded "Pokédex entry" for a caught species. Implementations:
/// on-device (Apple Foundation Models, free/offline), cloud (mako → Claude), and a
/// plain grounded summary.
protocol Narrator: Sendable {
    /// - Parameter grounding: an optional factual summary (e.g. from the domain
    ///   Worker's Wikipedia fact-sheet) the narration must stay faithful to.
    func entry(for candidate: SpeciesCandidate, grounding: String?) async -> PokedexEntry?
}

/// The app's narration entry point: prefer the free, private, offline on-device
/// model. Without it, Pro members get the cloud-written entry (it costs them nothing); everyone
/// else gets the sourced Wikipedia summary, so a catch's field entry never spends a credit —
/// credits are for identification only.
final class NarratorService: Narrator {
    static let shared = NarratorService()

    private let onDevice: Narrator?
    private let cloud: Narrator
    private let isPro: @Sendable () async -> Bool

    init(
        onDevice: Narrator? = OnDeviceNarrator.makeIfAvailable(),
        cloud: Narrator = SpeciesNarrator(),
        isPro: @escaping @Sendable () async -> Bool = { await MainActor.run { SubscriptionService.shared.isPro } }
    ) {
        self.onDevice = onDevice
        self.cloud = cloud
        self.isPro = isPro
    }

    func entry(for candidate: SpeciesCandidate, grounding: String?) async -> PokedexEntry? {
        if let onDevice, let entry = await onDevice.entry(for: candidate, grounding: grounding) {
            return entry
        }
        if await isPro(), let entry = await cloud.entry(for: candidate, grounding: grounding) {
            return entry
        }
        return Self.groundedEntry(grounding)
    }

    /// The sourced fallback: the Wikipedia summary the Worker already fetched, with its
    /// attribution, or nothing when there is no summary.
    static func groundedEntry(_ grounding: String?) -> PokedexEntry? {
        guard let text = grounding?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return PokedexEntry(
            entry: "\(text)\n\nSource: Wikipedia, CC BY-SA 4.0.", funFacts: [], category: nil, typicalSize: nil)
    }
}
