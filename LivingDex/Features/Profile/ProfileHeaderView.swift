import UIKit

/// A game-like profile hero: a level ring with XP progress, and stat tiles for
/// species collected and current streak. Reads as identity + progress, not a
/// settings list.
final class ProfileHeaderView: UIView {
    private let ringLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()
    private let levelLabel = UILabel()
    private let levelCaption = UILabel()
    private let speciesTile = StatTile()
    private let streakTile = StatTile()
    private let xpLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let ringContainer = UIView()
        ringContainer.translatesAutoresizingMaskIntoConstraints = false
        trackLayer.strokeColor = UIColor.tertiarySystemFill.cgColor
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineWidth = 8
        ringLayer.strokeColor = DesignSystem.Color.accent.cgColor
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = 8
        ringLayer.lineCap = .round
        ringLayer.strokeEnd = 0
        ringContainer.layer.addSublayer(trackLayer)
        ringContainer.layer.addSublayer(ringLayer)

        levelLabel.font = .systemFont(ofSize: 30, weight: .heavy)
        levelLabel.textColor = .label
        levelLabel.textAlignment = .center
        levelCaption.font = .systemFont(ofSize: 11, weight: .semibold)
        levelCaption.textColor = .secondaryLabel
        levelCaption.text = "LEVEL"
        levelCaption.textAlignment = .center
        let levelStack = UIStackView(arrangedSubviews: [levelCaption, levelLabel])
        levelStack.axis = .vertical
        levelStack.spacing = -2
        levelStack.translatesAutoresizingMaskIntoConstraints = false
        levelStack.isUserInteractionEnabled = false
        ringContainer.addSubview(levelStack)

        let tiles = UIStackView(arrangedSubviews: [speciesTile, streakTile])
        tiles.axis = .vertical
        tiles.distribution = .fillEqually
        tiles.spacing = 10
        tiles.translatesAutoresizingMaskIntoConstraints = false

        let top = UIStackView(arrangedSubviews: [ringContainer, tiles])
        top.axis = .horizontal
        top.spacing = 20
        top.alignment = .center
        top.translatesAutoresizingMaskIntoConstraints = false
        addSubview(top)

        xpLabel.font = .preferredFont(forTextStyle: .footnote)
        xpLabel.adjustsFontForContentSizeCategory = true
        xpLabel.textColor = .secondaryLabel
        xpLabel.textAlignment = .center
        xpLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(xpLabel)

        NSLayoutConstraint.activate([
            ringContainer.widthAnchor.constraint(equalToConstant: 104),
            ringContainer.heightAnchor.constraint(equalToConstant: 104),
            levelStack.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            levelStack.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor),

            top.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            xpLabel.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 14),
            xpLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            xpLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            xpLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        self.ringContainer = ringContainer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private weak var ringContainer: UIView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let ringContainer else { return }
        let inset: CGFloat = 4
        let rect = ringContainer.bounds.insetBy(dx: inset, dy: inset)
        let path = UIBezierPath(ovalIn: rect)
        trackLayer.path = path.cgPath
        // Start at 12 o'clock: rotate the ring layer.
        let ring = UIBezierPath(arcCenter: CGPoint(x: ringContainer.bounds.midX, y: ringContainer.bounds.midY),
                                radius: rect.width / 2, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true)
        ringLayer.path = ring.cgPath
        trackLayer.frame = ringContainer.bounds
        ringLayer.frame = ringContainer.bounds
    }

    func configure(with progress: PlayerProgress, speciesCount: Int) {
        let lp = Level.progress(for: progress.totalXP)
        levelLabel.text = "\(lp.level)"
        speciesTile.configure(value: "\(speciesCount)", label: "SPECIES", symbol: "square.grid.2x2.fill", tint: DesignSystem.Color.accent)
        let streak = progress.currentStreak
        streakTile.configure(value: "\(streak)", label: streak == 1 ? "DAY STREAK" : "DAY STREAK", symbol: "flame.fill", tint: .systemOrange)
        xpLabel.text = "\(lp.into) / \(lp.span) XP to level \(lp.level + 1)"
        layoutIfNeeded()
        let ratio = CGFloat(lp.into) / CGFloat(max(1, lp.span))
        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.fromValue = ringLayer.strokeEnd
        anim.toValue = ratio
        anim.duration = 0.5
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ringLayer.strokeEnd = ratio
        ringLayer.add(anim, forKey: "grow")
    }
}

/// A compact stat: icon + big value + small label.
private final class StatTile: UIView {
    private let icon = UIImageView()
    private let valueLabel = UILabel()
    private let nameLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous

        icon.contentMode = .scaleAspectFit
        valueLabel.font = .systemFont(ofSize: 22, weight: .bold)
        valueLabel.textColor = .label
        nameLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        nameLabel.textColor = .secondaryLabel

        let text = UIStackView(arrangedSubviews: [valueLabel, nameLabel])
        text.axis = .vertical
        text.spacing = -2
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(value: String, label: String, symbol: String, tint: UIColor) {
        icon.image = UIImage(systemName: symbol)
        icon.tintColor = tint
        valueLabel.text = value
        nameLabel.text = label
    }
}
