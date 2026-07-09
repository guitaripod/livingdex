import CoreML
import UIKit
import Vision

/// The real on-device identifier: a Core ML image classifier (BioCLIP-distilled)
/// run through Vision, its scores re-ranked by the local geo-prior and resolved
/// to species metadata via the taxon catalog. Bundled as `SpeciesClassifier`
/// (compiled `.mlmodelc`) + `taxa.json`; until those ship, `SpeciesIdentifierFactory`
/// selects the stub instead, so this type is only ever used when it can work.
final class CoreMLSpeciesIdentifier: SpeciesIdentifier, @unchecked Sendable {
    private let model: VNCoreMLModel
    private let catalog: TaxonCatalog
    private let geoPrior: GeoPrior
    private let topK = 5

    init?(
        modelName: String = "SpeciesClassifier",
        catalog: TaxonCatalog = .shared,
        geoPrior: GeoPrior = .shared,
        bundle: Bundle = .main
    ) {
        guard let url = bundle.url(forResource: modelName, withExtension: "mlmodelc"),
              let mlModel = try? MLModel(contentsOf: url),
              let vnModel = try? VNCoreMLModel(for: mlModel)
        else {
            return nil
        }
        self.model = vnModel
        self.catalog = catalog
        self.geoPrior = geoPrior
    }

    func identify(_ image: UIImage, context: CaptureContext) async -> IdentificationResult {
        let observations = await classify(image)
        let candidates = observations
            .prefix(topK)
            .compactMap { catalog.candidate(forLabel: $0.identifier, confidence: Double($0.confidence)) }
        let ranked = geoPrior.rerank(Array(candidates), context: context)
        AppLogger.shared.info("coreml identify -> \(ranked.first?.commonName ?? "none")", category: .identify)
        return IdentificationResult(candidates: ranked)
    }

    private func classify(_ image: UIImage) async -> [(identifier: String, confidence: Float)] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            // Vision invokes the request's completion handler on failure AND
            // `perform` rethrows; resume exactly once or the continuation traps.
            let resumeOnce = ResumeGuard(continuation)
            let request = VNCoreMLRequest(model: model) { request, _ in
                let results = (request.results as? [VNClassificationObservation]) ?? []
                resumeOnce.resume(with: results.map { ($0.identifier, $0.confidence) })
            }
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImageOrientation)
            do {
                try handler.perform([request])
            } catch {
                AppLogger.shared.error("vision perform failed: \(error.localizedDescription)", category: .identify)
                resumeOnce.resume(with: [])
            }
        }
    }
}

/// Selects the identifier at launch: the real Core ML pipeline when both the
/// model and taxon catalog are bundled, otherwise the stub so the capture loop
/// still works during development.
enum SpeciesIdentifierFactory {
    static func make() -> SpeciesIdentifier {
        if TaxonCatalog.shared.isLoaded, let coreML = CoreMLSpeciesIdentifier() {
            AppLogger.shared.info("using Core ML identifier", category: .identify)
            return coreML
        }
        // No bundled model yet → real cloud-vision ID through mako. No stub
        // fallback in production: an unclear photo must read as "nothing found",
        // never a random minted species.
        AppLogger.shared.info("using cloud-vision identifier", category: .identify)
        return CloudVisionIdentifier()
    }
}

/// Ensures a `CheckedContinuation` is resumed at most once across Vision's dual
/// failure signalling (completion callback + thrown error from `perform`).
private final class ResumeGuard: @unchecked Sendable {
    private let continuation: CheckedContinuation<[(identifier: String, confidence: Float)], Never>
    private let lock = NSLock()
    private var done = false

    init(_ continuation: CheckedContinuation<[(identifier: String, confidence: Float)], Never>) {
        self.continuation = continuation
    }

    func resume(with value: [(identifier: String, confidence: Float)]) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: value)
    }
}

private extension UIImage {
    var cgImageOrientation: CGImagePropertyOrientation {
        CGImagePropertyOrientation(imageOrientation)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
