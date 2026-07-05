import UIKit

/// Maps a 0…1 identification confidence to the honest green/amber/red signal the
/// plan promises — the app never hides uncertainty, it gamifies resolving it.
enum ConfidenceLevel {
    case high, medium, low

    init(_ value: Double) {
        switch value {
        case 0.85...: self = .high
        case 0.6..<0.85: self = .medium
        default: self = .low
        }
    }

    var color: UIColor {
        switch self {
        case .high: return UIColor.systemGreen
        case .medium: return UIColor.systemYellow
        case .low: return UIColor.systemOrange
        }
    }

    var label: String {
        switch self {
        case .high: return "Confident"
        case .medium: return "Likely"
        case .low: return "Best guess"
        }
    }
}

enum Motion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }
}
