import UIKit

/// The app's illustrated realms of life (animals, plants, fungi, protists, other), shared by the
/// Field Guide, the Dex realm strip, locked slots and the empty states so the artwork shows up
/// wherever a realm does.
@MainActor
enum RealmArt {
    private static let tiles = NSCache<NSString, UIImage>()

    static func image(for realm: Realm) -> UIImage? {
        UIImage(named: "realm-\(realm.rawValue)")
    }

    private static let gridSide = 4
    private static var slotCount: Int { gridSide * gridSide }

    /// A stable seed for a species, so its locked slot always shows the same piece of the realm's
    /// picture (the built-in `hashValue` changes on every launch).
    static func seed(for speciesId: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in speciesId.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Int(truncatingIfNeeded: hash >> 2)
    }

    /// A cropped piece of the realm's illustration. Each seed picks a different part of the picture
    /// (always from its lit middle, never the dark margin), so a grid of locked slots reads as a
    /// glimpse of the realm rather than one repeated tile.
    static func tile(for realm: Realm, seed: Int) -> UIImage? {
        let slot = abs(seed % slotCount)
        let key = "\(realm.rawValue)-\(slot)" as NSString
        if let cached = tiles.object(forKey: key) { return cached }
        guard let cgImage = image(for: realm)?.cgImage else { return nil }
        let side = CGFloat(min(cgImage.width, cgImage.height))
        let crop = side * 0.38
        let column = CGFloat(slot % gridSide)
        let row = CGFloat(slot / gridSide)
        let origin = CGPoint(x: side * 0.12 + column * side * 0.13, y: side * 0.12 + row * side * 0.13)
        guard let piece = cgImage.cropping(to: CGRect(origin: origin, size: CGSize(width: crop, height: crop))) else { return nil }
        let image = UIImage(cgImage: piece)
        tiles.setObject(image, forKey: key)
        return image
    }

    static func displayName(_ realm: Realm) -> String {
        switch realm {
        case .animals: return "Animals"
        case .plants: return "Plants"
        case .fungi: return "Fungi"
        case .protists: return "Protists"
        case .other: return "Other"
        }
    }
}
