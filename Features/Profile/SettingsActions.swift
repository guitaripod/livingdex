import MidgarCore
import UIKit

extension SettingsViewController {
    /// Why a restore did not end with a restored subscription, worded for the alert MidgarUI shows.
    private enum RestoreError: LocalizedError {
        case nothingToRestore
        case failed

        var errorDescription: String? {
            switch self {
            case .nothingToRestore: return "There were no previous purchases to restore for this Apple ID."
            case .failed: return "We couldn't restore your purchases. Check your connection and try again."
            }
        }
    }

    func presentAppearance() {
        let alert = UIAlertController(title: "Theme", message: nil, preferredStyle: .actionSheet)
        for (title, style) in [
            ("System", UIUserInterfaceStyle.unspecified), ("Light", .light), ("Dark", .dark),
        ] {
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                AppSettings.appearance = style
                self?.refreshList()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    /// Turning identification off is immediate; turning it on shows the same disclosure as the first
    /// identification, and the switch stays off if the player declines.
    func setCloudConsent(_ allowed: Bool) {
        guard allowed else {
            AppSettings.hasAcceptedCloudAI = false
            return
        }
        CloudConsent.request(from: self) { [weak self] _ in self?.refreshList() }
    }

    /// Routes through the single ``ProAccess/restore()`` path so the Pro gate updates everywhere, and distinguishes a
    /// genuine empty restore from a failed call: a paying subscriber is never told there was nothing to restore because
    /// the App Store was simply unreachable. The credit balance is refreshed alongside, which also retries a pack that
    /// was paid for and not yet credited.
    func restorePurchases() async throws {
        let access = ProAccess.shared
        do {
            try await access.restore()
        } catch {
            MidgarLog.error("restore failed: \(error)", category: .credits)
            await CreditsModel.shared.refresh()
            throw RestoreError.failed
        }
        await CreditsModel.shared.refresh()
        guard access.isPro else { throw RestoreError.nothingToRestore }
    }

    func exportLogs() {
        guard let log = MidgarLog.logFileURLs.first else {
            presentAlert(title: "No logs yet", message: "Diagnostics appear here after you use the app.")
            return
        }
        let share = UIActivityViewController(activityItems: [log], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = view
        present(share, animated: true)
    }

    /// Deletes the server-side account and every on-device record before returning to the first-run screen. The row
    /// has already confirmed. On failure nothing on the device is erased and the row reports the error, so the player
    /// can retry. A local cleanup that fails after the server account is gone is told to the player, then the app
    /// returns to first run anyway.
    func deleteAccount() async throws {
        let overlay = BusyOverlay(message: "Deleting…")
        overlay.show(in: view.window ?? view)
        let leftovers: Bool
        do {
            try await AccountDeletionService.live().deleteEverything()
            leftovers = false
        } catch AccountDeletionError.localCleanup {
            leftovers = true
        } catch {
            overlay.hide()
            MidgarLog.error("account deletion failed: \(error)", category: .app)
            throw error
        }
        AppSettings.reset()
        CreditsModel.shared.forget()
        MidgarLog.info("account deleted leftovers=\(leftovers)", category: .app)
        Haptics.tap()
        await CreditsModel.shared.refresh()
        overlay.hide()
        finishDeletion(leftovers: leftovers)
    }

    private func finishDeletion(leftovers: Bool) {
        guard leftovers else {
            returnToFirstRun()
            return
        }
        presentAlert(
            title: "Account deleted",
            message: "Your account was deleted from our servers, but some data couldn't be removed from this device. Deleting the app removes the rest.",
            then: { [weak self] in self?.returnToFirstRun() })
    }

    private func returnToFirstRun() {
        (view.window?.windowScene?.delegate as? SceneDelegate)?.presentFirstRun()
    }

    private func presentAlert(title: String, message: String, then handler: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in handler?() })
        present(alert, animated: true)
    }
}
