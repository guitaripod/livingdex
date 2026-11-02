import MidgarUI
import UIKit

extension SettingsViewController {
    private static let supportAddress = "support@midgarcorp.cc"

    func makeSections() -> [MidgarSettingsSection] {
        [appearanceSection(), privacySection(), purchasesSection(), diagnosticsSection(), legalSection(), accountSection()]
    }

    private func appearanceSection() -> MidgarSettingsSection {
        MidgarSettingsSection(
            id: "appearance",
            title: String(localized: "Appearance"),
            rows: [
                .custom(
                    id: "theme", title: String(localized: "Theme"), detail: Self.name(of: AppSettings.appearance),
                    systemImage: "circle.lefthalf.filled"
                ) { [weak self] in self?.presentAppearance() }
            ])
    }

    private func privacySection() -> MidgarSettingsSection {
        MidgarSettingsSection(
            id: "privacy",
            title: String(localized: "Privacy"),
            footer: String(localized: "Your photo goes to a cloud AI service only when you identify something. Turn this off and Living Dex asks again before the next identification."),
            rows: [
                .toggle(
                    id: "cloud", title: String(localized: "Cloud identification"), systemImage: "sparkle.magnifyingglass",
                    isOn: { AppSettings.hasAcceptedCloudAI },
                    setOn: { [weak self] allowed in self?.setCloudConsent(allowed) })
            ])
    }

    private func purchasesSection() -> MidgarSettingsSection {
        MidgarSettingsSection(
            id: "purchases",
            title: String(localized: "Purchases"),
            footer: String(localized: "Every device starts with 30 free identifications."),
            rows: [.restorePurchases { [weak self] in try await self?.restorePurchases() }])
    }

    private func diagnosticsSection() -> MidgarSettingsSection {
        MidgarSettingsSection(
            id: "diagnostics",
            title: String(localized: "Diagnostics"),
            rows: [
                .custom(
                    id: "logs", title: String(localized: "Export logs"), systemImage: "square.and.arrow.up", showsDisclosure: false
                ) { [weak self] in self?.exportLogs() }
            ])
    }

    private func legalSection() -> MidgarSettingsSection {
        MidgarSettingsSection(
            id: "legal",
            title: String(localized: "Legal"),
            rows: [
                .privacyPolicy(url: LegalLinks.privacy),
                .termsOfUse(url: LegalLinks.terms),
                .support(address: Self.supportAddress),
                .custom(id: "credits", title: String(localized: "Credits"), systemImage: "heart.text.square.fill") { [weak self] in
                    self?.navigationController?.pushViewController(CreditsViewController(), animated: true)
                },
            ])
    }

    private func accountSection() -> MidgarSettingsSection {
        MidgarSettingsSection(
            id: "account",
            title: String(localized: "Account"),
            footer: String(localized: "Permanently deletes your Dex, photos, progress and Living Dex account. An App Store subscription is managed separately in iOS Settings. Your Midgar ID, which Midgar's other apps share, is not deleted; the privacy policy says how to have it erased."),
            rows: [
                .deleteAccount(
                    confirmation: .init(
                        title: String(localized: "Delete account and data?"),
                        message: String(localized: "This permanently deletes your Dex, photos, progress, credits and your Living Dex account on our server. It can't be undone.\n\nAn App Store subscription is not cancelled by this. Manage it in iOS Settings, Apple Account, Subscriptions."),
                        confirmTitle: String(localized: "Delete Everything"))
                ) { [weak self] in try await self?.deleteAccount() }
            ])
    }

    private static func name(of style: UIUserInterfaceStyle) -> String {
        switch style {
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        default: return String(localized: "System")
        }
    }
}
