import LivingDexCore
import UIKit

/// Everything the shareable trading card shows.
struct ShareCardModel {
    let commonName: String
    let scientificName: String
    let realm: Realm
    let rarity: Rarity
    let caughtAt: Date
    let photo: UIImage
}

/// Draws a catch as a 4:5 trading card — rarity-colored frame, the photo, name,
/// scientific name and a Living Dex footer — so a share looks like a collectible,
/// not a bare photo.
enum ShareCardRenderer {
    static let size = CGSize(width: 1080, height: 1350)

    static func render(_ model: ShareCardModel) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            drawBackground(in: cg, rarity: model.rarity)
            let card = CGRect(x: 56, y: 56, width: size.width - 112, height: size.height - 112)
            drawCard(card, model: model, in: cg)
        }
    }

    /// The items handed to the share sheet: the card image and a line with the store link.
    static func shareItems(for model: ShareCardModel) -> [Any] {
        [render(model), "\(model.commonName), caught in Living Dex \(LegalLinks.appStore.absoluteString)"]
    }

    // MARK: Drawing

    private static func drawBackground(in cg: CGContext, rarity: Rarity) {
        UIColor(red: 0.04, green: 0.07, blue: 0.06, alpha: 1).setFill()
        cg.fill(CGRect(origin: .zero, size: size))
        let glow = rarity.color.withAlphaComponent(0.55).cgColor
        let clear = rarity.color.withAlphaComponent(0).cgColor
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [glow, clear] as CFArray, locations: [0, 1])
        else { return }
        cg.drawRadialGradient(
            gradient, startCenter: CGPoint(x: size.width / 2, y: 0), startRadius: 0,
            endCenter: CGPoint(x: size.width / 2, y: 0), endRadius: size.height * 0.75, options: [])
    }

    private static func drawCard(_ card: CGRect, model: ShareCardModel, in cg: CGContext) {
        let shape = UIBezierPath(roundedRect: card, cornerRadius: 56)
        UIColor(red: 0.07, green: 0.10, blue: 0.09, alpha: 1).setFill()
        shape.fill()
        model.rarity.color.setStroke()
        shape.lineWidth = 8
        shape.stroke()

        let inset: CGFloat = 28
        let photoRect = CGRect(
            x: card.minX + inset, y: card.minY + inset,
            width: card.width - inset * 2, height: card.width * 0.74)
        drawPhoto(model.photo, in: photoRect, cg: cg)

        let textX = card.minX + 44
        let textWidth = card.width - 88
        var y = photoRect.maxY + 36
        y = drawRarityPill(model.rarity, at: CGPoint(x: textX, y: y)) + 22
        y = drawFitting(
            model.commonName, in: CGRect(x: textX, y: y, width: textWidth, height: 100),
            maxSize: 84, minSize: 46, weight: .heavy, italic: false, color: .white) + 6
        y = drawFitting(
            model.scientificName, in: CGRect(x: textX, y: y, width: textWidth, height: 56),
            maxSize: 40, minSize: 26, weight: .regular, italic: true, color: UIColor.white.withAlphaComponent(0.72)) + 10
        _ = drawFitting(
            "\(model.realm.rawValue.capitalized) · Caught \(dateText(model.caughtAt))",
            in: CGRect(x: textX, y: y, width: textWidth, height: 44),
            maxSize: 32, minSize: 22, weight: .medium, italic: false, color: UIColor.white.withAlphaComponent(0.5))

        drawFooter(in: CGRect(x: textX, y: card.maxY - 100, width: textWidth, height: 56))
    }

    private static func drawPhoto(_ photo: UIImage, in rect: CGRect, cg: CGContext) {
        cg.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: 36).addClip()
        let scale = max(rect.width / photo.size.width, rect.height / photo.size.height)
        let drawn = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
        photo.draw(in: CGRect(
            x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
            width: drawn.width, height: drawn.height))
        cg.restoreGState()
    }

    /// Draws the rarity pill and returns the y of its bottom edge.
    private static func drawRarityPill(_ rarity: Rarity, at origin: CGPoint) -> CGFloat {
        let text = rarity.title.uppercased()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .heavy),
            .foregroundColor: UIColor.white,
            .kern: 2,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let pill = CGRect(x: origin.x, y: origin.y, width: textSize.width + 48, height: textSize.height + 20)
        rarity.color.setFill()
        UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 24, y: pill.minY + 10), withAttributes: attributes)
        return pill.maxY
    }

    /// Draws `text` at the largest size in `minSize...maxSize` that fits one line in `rect`,
    /// and returns the y of its bottom edge.
    private static func drawFitting(
        _ text: String, in rect: CGRect, maxSize: CGFloat, minSize: CGFloat,
        weight: UIFont.Weight, italic: Bool, color: UIColor
    ) -> CGFloat {
        var pointSize = maxSize
        var font = makeFont(pointSize, weight: weight, italic: italic)
        while pointSize > minSize, (text as NSString).size(withAttributes: [.font: font]).width > rect.width {
            pointSize -= 2
            font = makeFont(pointSize, weight: weight, italic: italic)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ]
        let height = ceil(font.lineHeight)
        (text as NSString).draw(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height), withAttributes: attributes)
        return rect.minY + height
    }

    private static func makeFont(_ size: CGFloat, weight: UIFont.Weight, italic: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard italic, let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func drawFooter(in rect: CGRect) {
        let accent = UIColor(red: 0.20, green: 0.80, blue: 0.55, alpha: 1)
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        if let symbol = UIImage(systemName: "camera.viewfinder", withConfiguration: config)?
            .withTintColor(accent, renderingMode: .alwaysOriginal) {
            symbol.draw(in: CGRect(x: rect.minX, y: rect.minY + 4, width: 48, height: 48))
        }
        let name: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 38, weight: .heavy), .foregroundColor: accent,
        ]
        ("Living Dex" as NSString).draw(at: CGPoint(x: rect.minX + 64, y: rect.minY + 6), withAttributes: name)
        let tagline = "Catch the real world" as NSString
        let taglineAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.5),
        ]
        let width = tagline.size(withAttributes: taglineAttributes).width
        tagline.draw(at: CGPoint(x: rect.maxX - width, y: rect.minY + 12), withAttributes: taglineAttributes)
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
