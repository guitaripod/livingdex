import UIKit

/// The Dex header: a big count, a caption, and a slim completion bar. Reads as
/// "progress you're making", which is the retention hook of a collection game.
final class DexHeaderView: UIView {
    private let countLabel = UILabel()
    private let captionLabel = UILabel()
    private let track = UIView()
    private let fill = UIView()
    private var fillWidth: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)

        countLabel.font = .systemFont(ofSize: 30, weight: .heavy)
        countLabel.textColor = .label
        countLabel.adjustsFontSizeToFitWidth = true
        countLabel.minimumScaleFactor = 0.7

        captionLabel.font = .preferredFont(forTextStyle: .subheadline)
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.textColor = .secondaryLabel

        track.backgroundColor = .tertiarySystemFill
        track.layer.cornerRadius = 4
        track.clipsToBounds = true
        fill.backgroundColor = DesignSystem.Color.accent
        fill.layer.cornerRadius = 4

        for v in [countLabel, captionLabel, track] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        fillWidth = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0)
        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            captionLabel.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 1),
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            captionLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            track.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 12),
            track.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            track.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            track.heightAnchor.constraint(equalToConstant: 8),
            track.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fillWidth,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showCompletion(caught: Int, total: Int, title: String) {
        let pct = total > 0 ? Int((Double(caught) / Double(total) * 100).rounded()) : 0
        countLabel.text = "\(caught) / \(total)"
        captionLabel.text = total > 0 ? "\(title) species · \(pct)% complete" : "\(title) species"
        track.isHidden = false
        setFill(total > 0 ? CGFloat(caught) / CGFloat(total) : 0)
    }

    func showSummary(species: Int, detail: String) {
        countLabel.text = "\(species)"
        captionLabel.text = species == 1 ? "species · \(detail)" : "species · \(detail)"
        track.isHidden = true
        setFill(0)
    }

    private func setFill(_ ratio: CGFloat) {
        let clamped = max(0, min(1, ratio))
        fillWidth.isActive = false
        fillWidth = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: max(0.0001, clamped))
        fillWidth.isActive = true
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseOut) { self.layoutIfNeeded() }
    }
}
