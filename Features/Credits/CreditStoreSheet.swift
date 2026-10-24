import MidgarCreditsUI
import MidgarUI
import SwiftUI
import UIKit

/// The credit store in a sheet: MidgarKit's screen under a navigation bar titled "Get Credits" with a Done button.
/// `shortfall` is how many more credits an action needs, or nil when the person opened the store themselves or the
/// failing call did not say.
struct CreditStoreSheet: View {
    let source: any MidgarCreditStoreSource
    var shortfall: Int?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MidgarCreditStoreView(credits: source, shortfall: shortfall)
                .navigationTitle("Get Credits")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .midgarTheme(.livingDex)
        .tint(Color(DesignSystem.Color.accent))
    }
}

extension CreditStoreSheet {
    /// The sheet as UIKit presents it: a hosting controller that opens at medium height and grows to large. Nil where
    /// the app has no wallet (a test host).
    @MainActor
    static func makeController(credits: CreditsModel, shortfall: Int? = nil) -> UIViewController? {
        guard let source = credits.source else {
            return nil
        }
        let host = UIHostingController(rootView: CreditStoreSheet(source: source, shortfall: shortfall))
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        return host
    }
}
