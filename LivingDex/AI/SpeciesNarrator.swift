import Foundation
import AICreditsCore

/// A Claude-authored "Pokédex entry" for a species.
struct PokedexEntry: Codable, Sendable {
    var entry: String
    var funFacts: [String]

    /// A single display string (entry + fun facts) persisted on the sighting.
    var displayText: String {
        var parts = [entry]
        parts.append(contentsOf: funFacts.map { "• \($0)" })
        return parts.joined(separator: "\n\n")
    }
}

/// Generates grounded Pokédex-entry narration for a caught species by calling
/// mako's `chat.completion` (Claude). Kept cheap (Haiku) for the per-sighting
/// live fill; the richer Sonnet-batch narration is precomputed server-side and
/// cached per species+locale. All identification stays on-device; this is only
/// prose, so a failure degrades to a nil entry (the card still shows fine).
final class SpeciesNarrator: Narrator {
    private let client: AICreditsClient
    private let model = "claude-haiku-4-5"

    init(client: AICreditsClient = AICreditsManager.shared.client) {
        self.client = client
    }

    func entry(for candidate: SpeciesCandidate) async -> PokedexEntry? {
        let prompt = Self.prompt(for: candidate)
        let request = CapabilityRequest.chat(
            messages: [ChatTurn(role: "user", content: prompt)],
            responseJSON: true,
            model: model)
        do {
            let result = try await client.run(request)
            guard let content = MakoChat.messageContent(result.raw) else {
                AppLogger.shared.error("narration parse failed (no content)", category: .ai)
                return nil
            }
            guard let entry = Self.decode(content) else {
                AppLogger.shared.error("narration decode failed: \(content.prefix(200))", category: .ai)
                return nil
            }
            AppLogger.shared.info("narrated \(candidate.commonName)", category: .ai)
            return entry
        } catch {
            AppLogger.shared.error("narration request failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    private static func prompt(for c: SpeciesCandidate) -> String {
        """
        Write a short, wondrous "Pokédex entry" for the real organism below, for a \
        nature-collection game. Ground every claim in well-established biology — do NOT \
        invent facts; if unsure, stay general. No markdown.
        Reply with JSON only: {"entry": "<2-3 evocative sentences>", "funFacts": ["<fact>", "<fact>", "<fact>"]}.

        Common name: \(c.commonName)
        Scientific name: \(c.scientificName)
        Kingdom/realm: \(c.realm.rawValue)
        """
    }

    private static func decode(_ content: String) -> PokedexEntry? {
        if let entry = try? JSONDecoder().decode(PokedexEntry.self, from: Data(content.utf8)) {
            return entry
        }
        guard let json = MakoChat.firstBalancedObject(in: content) else { return nil }
        return try? JSONDecoder().decode(PokedexEntry.self, from: Data(json.utf8))
    }
}
