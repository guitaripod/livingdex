import GameKit
import UIKit

/// Game Center integration: authenticates the local player, shows the access
/// point, submits the unique-species leaderboard score, and reports achievement
/// progress after each catch. Every call degrades gracefully — if Game Center is
/// unavailable, the player isn't signed in, or the ids aren't yet configured in
/// App Store Connect, it logs and no-ops rather than disrupting the capture loop.
@MainActor
final class GameCenterService {
    static let shared = GameCenterService()

    private(set) var isAuthenticated = false

    /// Sets the authentication handler. Present any returned sign-in UI from the
    /// current top view controller.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let viewController {
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            if let error {
                AppLogger.shared.warn("game center auth error: \(error.localizedDescription)", category: .gamecenter)
                return
            }
            let authed = GKLocalPlayer.local.isAuthenticated
            self?.isAuthenticated = authed
            AppLogger.shared.info("game center authenticated=\(authed)", category: .gamecenter)
            if authed {
                GKAccessPoint.shared.location = .topLeading
                GKAccessPoint.shared.isActive = false // shown on demand, not over the camera
            }
        }
    }

    /// Submits the species leaderboard score and reports achievement progress.
    func recordCatch(context: AchievementContext) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        submitSpeciesScore(context.speciesCount)
        reportAchievements(context)
    }

    private func submitSpeciesScore(_ count: Int) {
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    count, context: 0, player: GKLocalPlayer.local,
                    leaderboardIDs: [Achievement.speciesLeaderboardID])
            } catch {
                AppLogger.shared.warn("leaderboard submit failed: \(error.localizedDescription)", category: .gamecenter)
            }
        }
    }

    private func reportAchievements(_ ctx: AchievementContext) {
        let achievements: [GKAchievement] = Achievement.allCases.compactMap { achievement in
            let percent = achievement.percent(ctx)
            guard percent > 0 else { return nil }
            let ga = GKAchievement(identifier: achievement.rawValue)
            ga.percentComplete = percent
            ga.showsCompletionBanner = true
            return ga
        }
        guard !achievements.isEmpty else { return }
        Task {
            do {
                try await GKAchievement.report(achievements)
            } catch {
                AppLogger.shared.warn("achievement report failed: \(error.localizedDescription)", category: .gamecenter)
            }
        }
    }

    /// Presents the Game Center dashboard (leaderboards + achievements).
    func presentDashboard(from presenter: UIViewController) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let dashboard = GKGameCenterViewController(state: .dashboard)
        dashboard.gameCenterDelegate = GameCenterDismissDelegate.shared
        presenter.present(dashboard, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Dismisses the Game Center dashboard when the player taps Done.
final class GameCenterDismissDelegate: NSObject, GKGameCenterControllerDelegate, @unchecked Sendable {
    static let shared = GameCenterDismissDelegate()
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
