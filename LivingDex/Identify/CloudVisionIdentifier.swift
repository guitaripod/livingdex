import UIKit
import AICreditsCore

/// Real species identification via cloud vision through mako (Claude/Gemini see
/// the photo). This is the working identifier until the on-device BioCLIP→Core ML
/// model ships; `SpeciesIdentifierFactory` prefers Core ML when bundled. On any
/// failure (offline, credits exhausted, no subject) it defers to a fallback so
/// the capture loop always resolves.
final class CloudVisionIdentifier: SpeciesIdentifier {
    private let client: AICreditsClient
    private let fallback: SpeciesIdentifier
    private let model = "claude-sonnet-4-6"

    init(client: AICreditsClient = AICreditsManager.shared.client, fallback: SpeciesIdentifier) {
        self.client = client
        self.fallback = fallback
    }

    func identify(_ image: UIImage, context: CaptureContext) async -> IdentificationResult {
        guard let base64 = image.jpegData(compressionQuality: 0.6)?.base64EncodedString() else {
            return await fallback.identify(image, context: context)
        }
        let request = CapabilityRequest.chat(
            messages: [ChatTurn(role: "user", content: Self.prompt)],
            images: [base64],
            responseJSON: true,
            model: model)
        do {
            let result = try await client.run(request)
            guard let content = MakoChat.messageContent(result.raw),
                  let candidate = Self.parse(content) else {
                AppLogger.shared.warn("cloud vision no candidate — falling back", category: .identify)
                return await fallback.identify(image, context: context)
            }
            AppLogger.shared.info("cloud vision -> \(candidate.commonName) \(String(format: "%.2f", candidate.confidence))", category: .identify)
            return IdentificationResult(candidates: [candidate])
        } catch {
            AppLogger.shared.warn("cloud vision failed (\(error.localizedDescription)) — falling back", category: .identify)
            return await fallback.identify(image, context: context)
        }
    }

    private static let prompt = """
    Identify the single most prominent living organism in this photo. Use your best \
    taxonomic judgement. Reply with JSON only, no prose:
    {"commonName": "<English common name>", "scientificName": "<binomial>", \
    "realm": "animals|plants|fungi|protists|other", "confidence": <0..1>}.
    If there is no identifiable living organism, set confidence to 0.
    """

    private struct VisionID: Decodable {
        let commonName: String
        let scientificName: String
        let realm: String
        let confidence: Double
    }

    private static func parse(_ content: String) -> SpeciesCandidate? {
        let decoded: VisionID
        if let d = try? JSONDecoder().decode(VisionID.self, from: Data(content.utf8)) {
            decoded = d
        } else if let json = MakoChat.firstBalancedObject(in: content),
                  let d = try? JSONDecoder().decode(VisionID.self, from: Data(json.utf8)) {
            decoded = d
        } else {
            return nil
        }
        guard decoded.confidence > 0, !decoded.scientificName.isEmpty else { return nil }
        return SpeciesCandidate(
            speciesId: "sci:\(decoded.scientificName.lowercased())",
            commonName: decoded.commonName.isEmpty ? decoded.scientificName : decoded.commonName,
            scientificName: decoded.scientificName,
            realm: Realm(rawValue: decoded.realm) ?? .other,
            rarity: .common, // provisional — the domain Worker sets real rarity on enrich
            confidence: min(1, max(0, decoded.confidence)))
    }
}
