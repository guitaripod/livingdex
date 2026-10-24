import UIKit

/// The first-run backdrop: the app's own realm illustrations, crossfading between steps and
/// drifting very slowly, under a scrim that keeps white type readable. Reduce Motion holds still.
final class OnboardingBackdropView: UIView {
    private let front = UIImageView()
    private let back = UIImageView()
    private let drift = UIView()
    private let scrim = CAGradientLayer()
    private var currentArt: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = OnboardingStyle.ink
        clipsToBounds = true
        isAccessibilityElement = false

        drift.translatesAutoresizingMaskIntoConstraints = false
        addSubview(drift)
        NSLayoutConstraint.activate([
            drift.centerXAnchor.constraint(equalTo: centerXAnchor),
            drift.centerYAnchor.constraint(equalTo: centerYAnchor),
            drift.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 1.25),
            drift.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 1.25),
        ])
        for view in [back, front] {
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.alpha = 0
            drift.addSubview(view)
            view.pinEdges(to: drift)
        }

        scrim.colors = [
            UIColor.black.withAlphaComponent(0.42).cgColor,
            UIColor.black.withAlphaComponent(0.6).cgColor,
            OnboardingStyle.ink.withAlphaComponent(0.96).cgColor,
        ]
        scrim.locations = [0, 0.45, 0.85]
        layer.addSublayer(scrim)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrim.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        startDrift()
    }

    /// Crossfades to the named illustration; the first call just appears.
    func show(art name: String, animated: Bool) {
        guard name != currentArt, let image = UIImage(named: name) else { return }
        currentArt = name
        back.image = front.image
        back.alpha = front.alpha
        front.image = image
        front.alpha = 0
        let reveal = {
            self.front.alpha = 0.9
            self.back.alpha = 0
        }
        if animated && !Motion.reduced {
            UIView.animate(withDuration: 0.9, delay: 0, options: [.curveEaseInOut], animations: reveal)
        } else {
            reveal()
        }
    }

    /// A slow breathing zoom and sway, so the still art feels alive without competing with the content.
    private func startDrift() {
        drift.layer.removeAllAnimations()
        guard !Motion.reduced else { return }
        let zoom = CABasicAnimation(keyPath: "transform.scale")
        zoom.fromValue = 1.0
        zoom.toValue = 1.08
        let sway = CABasicAnimation(keyPath: "transform.translation.x")
        sway.fromValue = -14
        sway.toValue = 14
        let group = CAAnimationGroup()
        group.animations = [zoom, sway]
        group.duration = 26
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        drift.layer.add(group, forKey: "drift")
    }
}
