import UIKit

/// One screen of the first-run flow. The container owns the backdrop, progress and Skip; a step
/// owns its content and calls `onAdvance` when the player moves on.
@MainActor
final class OnboardingState {
    var chosenStarter: StarterSpecies?
}

@MainActor
class OnboardingStepViewController: UIViewController {
    var onAdvance: (() -> Void)?
    var state = OnboardingState()

    var artName: String { "realm-animals" }
    var showsSkip: Bool { true }

    /// Wide enough to put text beside the visual (iPad-class windows, the iPhone Duo's inner display).
    var isWide: Bool {
        view.bounds.width > 640 && view.bounds.width > view.bounds.height * 1.15
    }

    /// Runs once the step is on screen and its transition has finished — the cue for entrance animations.
    func stepDidAppear() {}

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}
