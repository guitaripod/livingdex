import Foundation

/// Re-ranks raw classifier scores against a local species prior — the lever that
/// makes on-device ID feel magical (a vagrant far from its range shouldn't beat
/// the common local match). The real prior is a downloaded `species × H3` table;
/// this stub is a no-op weight of 1.0 until that ships, so ranking falls back to
/// pure model confidence.
final class GeoPrior: Sendable {
    static let shared = GeoPrior()

    /// Multiplies each candidate's confidence by its local likelihood, then
    /// re-sorts. Returns candidates unchanged when no prior is available.
    func rerank(_ candidates: [SpeciesCandidate], context: CaptureContext) -> [SpeciesCandidate] {
        guard context.latitude != nil else { return candidates }
        let weighted = candidates.map { candidate -> SpeciesCandidate in
            var c = candidate
            c.confidence = candidate.confidence * weight(for: candidate, context: context)
            return c
        }
        return weighted.sorted { $0.confidence > $1.confidence }
    }

    /// Local likelihood weight in 0...1 for a species at a location. Stub: 1.0.
    private func weight(for candidate: SpeciesCandidate, context: CaptureContext) -> Double {
        1.0
    }
}
