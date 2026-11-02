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
        isPro: @escaping @Sendable () async -> Bool = { await MainActor.run { ProAccess.shared.isPro } }
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
            entry: "\(text)\n\n" + String(localized: "Source: Wikipedia, CC BY-SA 4.0.", comment: "Attribution under a species summary taken from Wikipedia"),
            funFacts: [], category: nil, typicalSize: nil)
    }
}

/// The language the interface runs in, so narration reads in the same language as the screen around it.
enum NarrationLanguage {
    /// The interface language named in English for a model prompt ("German", "Chinese (Traditional)"),
    /// or nil when the interface runs in English and the prompt needs no instruction.
    static var promptName: String? {
        guard let code = Bundle.main.preferredLocalizations.first, !code.hasPrefix("en") else { return nil }
        return Locale(identifier: "en").localizedString(forIdentifier: code)
    }

    /// The sentence that asks a model to write its prose in the interface language, or an empty string in English.
    static var promptInstruction: String {
        guard let name = promptName else { return "" }
        return "\nWrite entry, funFacts, category and typicalSize in \(name). Keep the JSON keys in English."
    }
}
