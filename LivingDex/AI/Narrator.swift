import Foundation

/// Produces a grounded "Pokédex entry" for a caught species. Implementations:
/// on-device (Apple Foundation Models, free/offline) and cloud (mako → Claude).
protocol Narrator: Sendable {
    func entry(for candidate: SpeciesCandidate) async -> PokedexEntry?
}

/// The app's narration entry point: prefer the free, private, offline on-device
/// model; fall back to the cloud (Pro/metered) only when the device model is
/// unavailable or declines. Keeps the free tier at ~zero marginal cost.
final class NarratorService: Narrator {
    static let shared = NarratorService()

    private let onDevice: Narrator?
    private let cloud: Narrator

    init(onDevice: Narrator? = OnDeviceNarrator.makeIfAvailable(), cloud: Narrator = SpeciesNarrator()) {
        self.onDevice = onDevice
        self.cloud = cloud
    }

    func entry(for candidate: SpeciesCandidate) async -> PokedexEntry? {
        if let onDevice, let entry = await onDevice.entry(for: candidate) {
            return entry
        }
        return await cloud.entry(for: candidate)
    }
}
