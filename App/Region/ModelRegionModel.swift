import Combine
import Foundation
import MidgarCore

/// The model-region answer for the screens. ``modelsAvailable`` follows MidgarModelRegion's stored answer and publishes
/// every flip, so a visible control hides the moment a refusal or a fresh answer changes it. ``refresh()`` asks the
/// gateway with the app's own authorized client, at launch and whenever the app returns to the foreground, and never
/// waits on it.
@MainActor
final class ModelRegionModel {
    static let shared = ModelRegionModel(region: .shared)

    @Published private(set) var modelsAvailable: Bool

    private let region: MidgarModelRegion
    private var changes: AnyCancellable?

    init(region: MidgarModelRegion) {
        self.region = region
        modelsAvailable = region.modelsAvailable
        changes = NotificationCenter.default
            .publisher(for: MidgarModelRegion.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.modelsAvailable = region.modelsAvailable
            }
    }

    var modelsAvailablePublisher: AnyPublisher<Bool, Never> {
        $modelsAvailable.removeDuplicates().eraseToAnyPublisher()
    }

    /// Asks the gateway whether model features work here and remembers the answer. A failed request keeps the last
    /// answer. Does nothing where the app reaches no Midgar service, a test host or a demo capture.
    func refresh() async {
        guard LivingDexMidgar.reachesMidgarServices else { return }
        await region.refresh(client: LivingDexMidgar.shared.account)
    }
}
