import UIKit

/// The first-run flow: Welcome, Choose your starter, Nearby, Ready. It hosts one step at a time over
/// the illustrated backdrop, with progress dots and a Skip that can leave at any moment.
final class OnboardingViewController: UIViewController {
    var onFinish: (() -> Void)?

    private let backdrop = OnboardingBackdropView()
    private let stepHost = UIView()
    private let dots: StepDotsView
    private let skipButton: UIButton
    private let steps: [OnboardingStepViewController]
    private var index = 0
    private var current: OnboardingStepViewController?
    private var isTransitioning = false

    init(starter: StarterCatch = StarterCatch()) {
        var steps: [OnboardingStepViewController] = [WelcomeStepViewController()]
        if !AppSettings.hasChosenStarter {
            steps.append(StarterStepViewController(starterCatch: starter))
        }
        steps.append(NearbyStepViewController())
        steps.append(ReadyStepViewController())
        self.steps = steps
        let state = OnboardingState()
        steps.forEach { $0.state = state }
        self.dots = StepDotsView(count: steps.count)
        self.skipButton = OnboardingStyle.quietButton(title: "Skip") {}
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
        skipButton.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside)
        for step in steps {
            step.onAdvance = { [weak self] in self?.advance() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OnboardingStyle.ink

        view.insertSubview(backdrop, at: 0)
        backdrop.pinEdges(to: view)

        stepHost.translatesAutoresizingMaskIntoConstraints = false
        dots.translatesAutoresizingMaskIntoConstraints = false
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stepHost)
        view.addSubview(dots)
        view.addSubview(skipButton)

        NSLayoutConstraint.activate([
            dots.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: DesignSystem.Spacing.l),
            dots.centerYAnchor.constraint(equalTo: skipButton.centerYAnchor),
            skipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            skipButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -DesignSystem.Spacing.s),
            skipButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            stepHost.topAnchor.constraint(equalTo: skipButton.bottomAnchor),
            stepHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stepHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stepHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard current == nil else { return }
        index = Self.demoStartIndex(in: steps)
        present(step: steps[index], animated: false)
    }

    /// DEBUG-only: `LIVINGDEX_DEMO_STEP` (welcome, starter, nearby, ready) opens the flow at that step,
    /// so a single screen can be captured without driving the ones before it.
    private static func demoStartIndex(in steps: [OnboardingStepViewController]) -> Int {
        #if DEBUG
        let names: [String: AnyClass] = [
            "welcome": WelcomeStepViewController.self, "starter": StarterStepViewController.self,
            "nearby": NearbyStepViewController.self, "ready": ReadyStepViewController.self,
        ]
        if let name = ProcessInfo.processInfo.environment["LIVINGDEX_DEMO_STEP"], let type = names[name],
           let found = steps.firstIndex(where: { Swift.type(of: $0) == type }) {
            return found
        }
        #endif
        return 0
    }

    private func advance() {
        guard !isTransitioning else { return }
        guard index + 1 < steps.count else {
            finish()
            return
        }
        index += 1
        present(step: steps[index], animated: true)
    }

    private func finish() {
        Haptics.tap()
        onFinish?()
    }

    private func present(step next: OnboardingStepViewController, animated: Bool) {
        let previous = current
        current = next
        isTransitioning = true

        addChild(next)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        stepHost.addSubview(next.view)
        next.view.pinEdges(to: stepHost)
        next.didMove(toParent: self)

        backdrop.show(art: next.artName, animated: animated)
        dots.setCurrent(index, animated: animated)
        let showSkip = next.showsSkip
        let slide: CGFloat = Motion.reduced ? 0 : 36

        let finishTransition = {
            if let previous {
                previous.willMove(toParent: nil)
                previous.view.removeFromSuperview()
                previous.removeFromParent()
            }
            self.isTransitioning = false
            next.stepDidAppear()
        }

        guard animated else {
            skipButton.alpha = showSkip ? 1 : 0
            finishTransition()
            return
        }
        next.view.alpha = 0
        next.view.transform = CGAffineTransform(translationX: slide, y: 0)
        UIView.animate(
            withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
            options: [.allowUserInteraction]
        ) {
            next.view.alpha = 1
            next.view.transform = .identity
            previous?.view.alpha = 0
            previous?.view.transform = CGAffineTransform(translationX: -slide, y: 0)
            self.skipButton.alpha = showSkip ? 1 : 0
        } completion: { _ in
            finishTransition()
        }
    }
}

/// A row of capsules: the current step stretches and takes the accent.
private final class StepDotsView: UIView {
    private let dots: [UIView]
    private var widths: [NSLayoutConstraint] = []

    init(count: Int) {
        dots = (0..<count).map { _ in UIView() }
        super.init(frame: .zero)
        isAccessibilityElement = true
        let stack = UIStackView(arrangedSubviews: dots)
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.pinEdges(to: self)
        for dot in dots {
            dot.layer.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
            let width = dot.widthAnchor.constraint(equalToConstant: 6)
            width.isActive = true
            widths.append(width)
        }
        setCurrent(0, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setCurrent(_ index: Int, animated: Bool) {
        accessibilityLabel = "Step \(index + 1) of \(dots.count)"
        for (i, dot) in dots.enumerated() {
            widths[i].constant = i == index ? 22 : 6
            dot.backgroundColor = i == index ? OnboardingStyle.accent : UIColor.white.withAlphaComponent(0.3)
        }
        guard animated else { return }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3) {
            self.layoutIfNeeded()
        }
    }
}
