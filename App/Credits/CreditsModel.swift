import Combine
import Foundation
import MidgarCore
import MidgarCredits
import MidgarCreditsUI

/// The balance of the wallet for the UIKit screens, as the Combine publisher ``knownBalancePublisher`` that the Field
/// meter and the Profile row follow. The balance is `nil` until a read has actually succeeded, so an offline launch never
/// shows a made-up zero ("Get more") to a player who still has identifications left. It is refreshed at launch, when the
/// scene comes to the foreground, after every identification that reached mako and after a restore, and it follows what
/// ``MidgarCredits/events()`` reports, so a purchase made in the credit store reaches every screen without anyone telling
/// them.
///
/// The source is nil where the app reaches no Midgar service (a test host), and the balance then stays unknown.
@MainActor
final class CreditsModel {
    static let shared = CreditsModel.live()

    let source: (any MidgarCreditStoreSource)?

    @Published private(set) var knownBalance: Int?

    private var runTask: Task<Void, Never>?

    init(source: (any MidgarCreditStoreSource)?) {
        self.source = source
    }

    /// The model of the running app: the Midgar wallet, a fixed demo wallet in a DEBUG demo capture, or no wallet in a
    /// test host.
    private static func live() -> CreditsModel {
        #if DEBUG
        if DemoSeeder.isEnabled {
            return CreditsModel(source: DemoCreditsSource(credits: DemoCreditsSource.fieldCredits))
        }
        #endif
        return CreditsModel(source: LivingDexMidgar.shared.credits)
    }

    var knownBalancePublisher: AnyPublisher<Int?, Never> {
        $knownBalance.eraseToAnyPublisher()
    }

    /// Starts reading and following the wallet for the life of the process. Later calls do nothing.
    func start() {
        guard runTask == nil else {
            return
        }
        runTask = Task { await run() }
    }

    /// Reads the balance, then follows the wallet's events until the stream ends.
    func run() async {
        await refresh()
        await observe()
    }

    /// Drops the balance of an account that was deleted, so no screen shows credits the wallet no longer holds.
    func forget() {
        knownBalance = nil
    }

    /// Reads the balance from the wallet. A failed read keeps the last balance known.
    func refresh() async {
        guard let source else {
            return
        }
        do {
            apply(try await source.refresh().credits)
        } catch {
            MidgarLog.notice("credits balance read failed: \(error)", category: .credits)
        }
    }

    func handle(_ event: MidgarCreditsEvent) async {
        switch event {
        case .balanceChanged(let changed):
            apply(changed.credits)
        case .purchaseCredited(let packID, let added):
            MidgarLog.info("credits purchase credited pack=\(packID) added=\(added)", category: .credits)
            if let known = await source?.balance {
                apply(known.credits)
            }
        }
    }

    private func apply(_ credits: Int) {
        guard credits != knownBalance else {
            return
        }
        knownBalance = credits
        MidgarLog.info("credits balance \(credits)", category: .credits)
    }

    private func observe() async {
        guard let source else {
            return
        }
        for await event in await source.events() {
            await handle(event)
        }
    }
}
