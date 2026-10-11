import UIKit

/// Decisions that depend only on the space a screen is given, never on the device or the
/// display it is on, so a fold, a rotation or a Split View resize re-answers them.
enum AdaptiveLayout {
    /// How a screen that pairs media with text arranges them in the width it has.
    enum Arrangement: Equatable {
        case stacked
        case sideBySide

        /// Side by side once the space is both landscape and at least `minimumWidth` wide.
        static func resolve(
            width: CGFloat, height: CGFloat, minimumWidth: CGFloat = sideBySideMinimumWidth
        ) -> Arrangement {
            width > height && width >= minimumWidth ? .sideBySide : .stacked
        }
    }

    static let sideBySideMinimumWidth: CGFloat = 560
    static let paneSplitMinimumWidth: CGFloat = 720
    static let readableTableWidth: CGFloat = 700
    static let readableColumnWidth: CGFloat = 640
    static let wideColumnWidth: CGFloat = 900
    static let phoneGridColumns = 3
    static let phoneGridMaximumWidth: CGFloat = 520
    static let gridTargetCellWidth: CGFloat = 190
    static let foldGap: CGFloat = 40

    /// Columns for a grid of cells about `gridTargetCellWidth` wide. A phone-width space keeps
    /// three; anything wider takes an even count of at least four, so a vertical fold down the
    /// middle of the window falls between two columns instead of through one.
    static func gridColumnCount(forWidth width: CGFloat) -> Int {
        guard width >= phoneGridMaximumWidth else { return phoneGridColumns }
        let fitted = max(4, Int(width / gridTargetCellWidth))
        return fitted + fitted % 2
    }
}

/// A column of content in a vertically scrolling view that stays inside the safe area,
/// centres itself, and never grows past a readable width.
@MainActor
final class ScrollColumn {
    let maxWidth: NSLayoutConstraint
    private let centering: NSLayoutConstraint

    /// Pins `scrollView` to the horizontal safe area of `view` and `content` to a centred,
    /// width-capped column inside the scroll view's content.
    init(
        content: UIView, in scrollView: UIScrollView, of view: UIView,
        margin: CGFloat, maxWidth: CGFloat, top: CGFloat, bottom: CGFloat
    ) {
        let safe = view.safeAreaLayoutGuide
        let frame = scrollView.frameLayoutGuide
        let contentGuide = scrollView.contentLayoutGuide
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.maxWidth = content.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
        let fill = content.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -2 * margin)
        fill.priority = .defaultHigh
        centering = content.centerXAnchor.constraint(equalTo: contentGuide.centerXAnchor)
        centering.priority = UILayoutPriority(rawValue: 999)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            contentGuide.widthAnchor.constraint(equalTo: frame.widthAnchor),
            content.topAnchor.constraint(equalTo: contentGuide.topAnchor, constant: top),
            content.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor, constant: -bottom),
            centering,
            content.leadingAnchor.constraint(greaterThanOrEqualTo: contentGuide.leadingAnchor, constant: margin),
            content.trailingAnchor.constraint(lessThanOrEqualTo: contentGuide.trailingAnchor, constant: -margin),
            self.maxWidth,
            fill,
        ])
    }

    /// Moves the column's centre from the safe area's centre to the window's, so a split down
    /// the middle of the window lands on the fold when a vertical bar takes one side.
    func centerOnWindow(safeAreaInsets insets: UIEdgeInsets) {
        centering.constant = (insets.right - insets.left) / 2
    }
}

/// Items laid out in one column or, when the space allows, two top-aligned columns with a
/// gap wide enough for a fold. Items alternate between the columns in order.
final class ColumnFlow: UIView {
    private let items: [UIView]
    private let columns = [UIStackView(), UIStackView()]
    private let row = UIStackView()
    private(set) var columnCount = 1

    init(items: [UIView], spacing: CGFloat, columnGap: CGFloat) {
        self.items = items
        super.init(frame: .zero)
        for column in columns {
            column.axis = .vertical
            column.alignment = .fill
            column.spacing = spacing
            row.addArrangedSubview(column)
        }
        row.axis = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = columnGap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        arrange(into: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Redistributes the items into `count` columns (1 or 2); a no-op when unchanged.
    func setColumnCount(_ count: Int) {
        let clamped = min(max(count, 1), columns.count)
        guard clamped != columnCount else { return }
        arrange(into: clamped)
    }

    private func arrange(into count: Int) {
        columnCount = count
        columns.forEach { column in column.arrangedSubviews.forEach { $0.removeFromSuperview() } }
        for (index, item) in items.enumerated() {
            columns[index % count].addArrangedSubview(item)
        }
        columns[1].isHidden = count == 1
    }
}

/// A hairline whose thickness is one device pixel, read from the trait collection so it
/// stays right on whichever display the window is on.
final class HairlineView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .separator
        registerForTraitChanges([UITraitDisplayScale.self]) { (view: HairlineView, _) in
            view.invalidateIntrinsicContentSize()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 1 / max(traitCollection.displayScale, 1))
    }
}
