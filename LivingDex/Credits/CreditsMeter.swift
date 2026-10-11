import Combine
import Foundation

/// The wallet balance as the UI should show it: `nil` until a refresh has actually
/// succeeded, so an offline launch never displays a made-up zero ("Get more") to a
/// player who still has identifications left.
@MainActor
final class CreditsMeter {
    static let shared = CreditsMeter()

    private let balanceSubject = CurrentValueSubject<Int?, Never>(nil)
    private var cancellables = Set<AnyCancellable>()

    var knownBalancePublisher: AnyPublisher<Int?, Never> {
        balanceSubject.eraseToAnyPublisher()
    }

    var knownBalance: Int? { balanceSubject.value }

    /// Starts following the store. Must run before the first `bootstrap()`: the store's
    /// published balance starts at an unfetched zero, which is skipped; every later
    /// assignment is a real answer from the backend.
    func start(store: AICreditsStoreProviding = LiveCreditsStore()) {
        guard cancellables.isEmpty else { return }
        store.balances
            .dropFirst()
            .sink { [weak self] in self?.balanceSubject.send($0) }
            .store(in: &cancellables)
    }

    func reset() {
        balanceSubject.send(nil)
    }
}

/// The seam between the meter and the credits store, so the meter can be tested
/// without a network.
@MainActor
protocol AICreditsStoreProviding {
    var balances: AnyPublisher<Int, Never> { get }
}

@MainActor
struct LiveCreditsStore: AICreditsStoreProviding {
    var balances: AnyPublisher<Int, Never> {
        AICreditsManager.store.$balance.eraseToAnyPublisher()
    }
}
