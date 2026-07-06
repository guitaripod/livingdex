import UIKit

/// Opaque cover shown over the not-yet-live camera preview during cold start. The
/// bare `AVCaptureVideoPreviewLayer` renders solid black until its first frame —
/// that black *is* the "frozen camera" the user perceives. This surface hides it
/// behind an intentional loading state (a faintly warm near-black, never pure
/// `#000`, which reads as "dead") with a slow breathing viewfinder glyph, then the
/// host cross-fades it out the instant real pixels arrive.
final class CameraLoadingView: UIView {
    private let glyph = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.055, alpha: 1)
        isUserInteractionEnabled = false
        accessibilityLabel = "Camera loading"

        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .thin)
        glyph.image = UIImage(systemName: "camera.viewfinder", withConfiguration: config)
        glyph.tintColor = DesignSystem.Color.accent.withAlphaComponent(0.55)
        glyph.contentMode = .center
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !isHidden { startBreathing() }
    }

    /// A slow opacity + scale breath — deliberately calm, so the eventual
    /// cross-fade to the live feed reads as the viewfinder "focusing in" rather
    /// than a spinner snapping away.
    func startBreathing() {
        glyph.layer.removeAllAnimations()
        let pulse = CAAnimationGroup()
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.45
        opacity.toValue = 1.0
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.94
        scale.toValue = 1.04
        pulse.animations = [opacity, scale]
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glyph.layer.add(pulse, forKey: "breathe")
    }

    func stopBreathing() {
        glyph.layer.removeAllAnimations()
    }
}
