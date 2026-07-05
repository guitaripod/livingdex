import UIKit

/// Centralized haptic feedback for the capture loop. Rarity maps to escalating
/// intensity so a legendary find feels physically special. All calls are
/// main-actor and cheap; `prepare()` warms the engine before the first tap.
@MainActor
enum Haptics {
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// Warm the generators so the first capture isn't laggy.
    static func prepare() {
        impactMedium.prepare()
        notification.prepare()
    }

    /// The shutter fires.
    static func shutter() {
        impactMedium.impactOccurred()
    }

    /// A catch succeeded — escalates with rarity, and stronger for a new dex entry.
    static func caught(rarity: Rarity, isNew: Bool) {
        if isNew {
            notification.notificationOccurred(.success)
        } else {
            impactLight.impactOccurred()
        }
        switch rarity {
        case .epic:
            impactRigid.impactOccurred(intensity: 0.9)
        case .legendary:
            impactRigid.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                impactRigid.impactOccurred(intensity: 1.0)
            }
        default:
            break
        }
    }

    /// A capture/identify failure.
    static func failure() {
        notification.notificationOccurred(.error)
    }

    /// A light tap for selections / dismissals.
    static func tap() {
        selection.selectionChanged()
    }
}
