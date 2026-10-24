import LivingDexCore
import UIKit

/// The identification boundary. The v1 implementation is an on-device Core ML
/// classifier (BioCLIP-distilled) whose scores are re-ranked by a cached
/// `species × H3` geo-prior, with a cloud fallback through mako. Everything above
/// this protocol is UI; everything below is swappable.
protocol SpeciesIdentifier: Sendable {
    func identify(_ image: UIImage, context: CaptureContext) async -> IdentificationResult
}
