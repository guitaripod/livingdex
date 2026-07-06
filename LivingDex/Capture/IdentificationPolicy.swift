import Foundation

/// Single source of truth for identification decision thresholds, shared by the
/// identifier boundary (each identifier discards candidates it doesn't stand
/// behind) and the capture flow's confidence gate, so the two can never drift.
enum IdentificationPolicy {
    /// Minimum model confidence to mint a catch. Below this the model isn't sure
    /// enough — the capture reads as "nothing found" rather than a confident wrong
    /// species (the anti-hallucination gate).
    static let minConfidence: Double = 0.35
}
