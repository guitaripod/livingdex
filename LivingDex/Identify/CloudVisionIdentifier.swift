import UIKit
import AICreditsCore

/// Real species identification via cloud vision through mako (Claude/Gemini see
/// the photo). This is the working identifier until the on-device BioCLIP→Core ML
/// model ships; `SpeciesIdentifierFactory` prefers Core ML when bundled. On any
/// failure (offline, credits exhausted, no subject) it defers to a fallback so
/// the capture loop always resolves.
final class CloudVisionIdentifier: SpeciesIdentifier {
    private let client: AICreditsClient
    // Gemini vision: ~10x cheaper than Claude Sonnet, no image premium, and plenty
    // accurate for species ID — keeps the free tier's per-ID cost (and the user's
    // credit burn) low. Pro could escalate hard cases to Sonnet later.
    private let model = "gemini-2.5-flash"
    /// Below this the model isn't sure enough — treat as "nothing here" rather
    /// than mint a confident wrong species.
    private let minConfidence = 0.35

    init(client: AICreditsClient = AICreditsManager.shared.client) {
        self.client = client
    }

    func identify(_ image: UIImage, context: CaptureContext) async -> IdentificationResult {
        guard let base64 = image.jpegData(compressionQuality: 0.6)?.base64EncodedString() else {
            return IdentificationResult(candidates: [])
        }
        let request = CapabilityRequest.chat(
            messages: [ChatTurn(role: "user", content: Self.prompt)],
            images: [base64],
            responseJSON: true,
            model: model)
        do {
            let result = try await client.run(request)
            guard let content = MakoChat.messageContent(result.raw),
                  let candidate = Self.parse(content, minConfidence: minConfidence) else {
                AppLogger.shared.info("cloud vision: no clear organism", category: .identify)
                return IdentificationResult(candidates: [])
            }
            AppLogger.shared.info("cloud vision -> \(candidate.scientificName) \(String(format: "%.2f", candidate.confidence))", category: .identify)
            return IdentificationResult(candidates: [candidate])
        } catch {
            AppLogger.shared.warn("cloud vision failed: \(error.localizedDescription)", category: .identify)
            return IdentificationResult(candidates: [])
        }
    }

    private static let prompt = """
    You are a careful field naturalist. Identify the single, clearly-visible living \
    organism that is the main subject of this photo — a wild animal, bird, insect, \
    plant, or fungus.
    Be conservative: if the main subject is a room, furniture, a screen, a manufactured \
    object, food, a human, or if you are not reasonably sure of the species, set \
    confidence to 0. Do not guess.
    Reply with JSON only, no prose:
    {"commonName": "<English common name>", "scientificName": "<genus species binomial>", \
    "realm": "animals|plants|fungi|protists|other", "confidence": <0..1 how sure you are of the species>}.
    """

    private struct VisionID: Decodable {
        let commonName: String
        let scientificName: String
        let realm: String
        let confidence: Double
    }

    private static func parse(_ content: String, minConfidence: Double) -> SpeciesCandidate? {
        let decoded: VisionID
        if let d = try? JSONDecoder().decode(VisionID.self, from: Data(content.utf8)) {
            decoded = d
        } else if let json = MakoChat.firstBalancedObject(in: content),
                  let d = try? JSONDecoder().decode(VisionID.self, from: Data(json.utf8)) {
            decoded = d
        } else {
            return nil
        }
        let sci = decoded.scientificName.trimmingCharacters(in: .whitespaces)
        // Require confidence AND a plausible binomial (two words) — a bare genus or
        // "unknown" is not a catch.
        guard decoded.confidence >= minConfidence, sci.split(separator: " ").count >= 2 else { return nil }
        return SpeciesCandidate(
            speciesId: "sci:\(sci.lowercased())",
            commonName: decoded.commonName.isEmpty ? sci : decoded.commonName,
            scientificName: sci,
            realm: Realm(rawValue: decoded.realm) ?? .other,
            rarity: .common, // provisional — the domain Worker sets real rarity on enrich
            confidence: min(1, max(0, decoded.confidence)))
    }
}
