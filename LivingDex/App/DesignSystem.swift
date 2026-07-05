import UIKit

/// Central design tokens. Keep bar/HUD backgrounds default where possible so
/// iOS 26 renders its Liquid Glass — a custom opaque background suppresses it.
enum DesignSystem {
    enum Color {
        /// Living, verdant accent — the "collect life" identity.
        static let accent = UIColor(red: 0.20, green: 0.80, blue: 0.55, alpha: 1.0)
        static let rarityCommon = UIColor.systemGray
        static let rarityUncommon = UIColor.systemGreen
        static let rarityRare = UIColor.systemBlue
        static let rarityEpic = UIColor.systemPurple
        static let rarityLegendary = UIColor.systemOrange
    }

    enum Spacing {
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 14
    }
}
