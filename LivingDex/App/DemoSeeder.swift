#if DEBUG
import UIKit

/// DEBUG-only: seeds a rich, varied sample collection so every screen can be
/// driven and screenshotted for design validation. Enabled via the
/// `LIVINGDEX_DEMO` launch environment variable (any value). Generates clean
/// symbol-on-gradient artwork per species so the grid reads as real content.
enum DemoSeeder {
    struct Sample {
        let common: String, scientific: String, realm: Realm, rarity: Rarity, symbol: String
    }

    static let samples: [Sample] = [
        .init(common: "House Sparrow", scientific: "Passer domesticus", realm: .animals, rarity: .common, symbol: "bird.fill"),
        .init(common: "European Robin", scientific: "Erithacus rubecula", realm: .animals, rarity: .common, symbol: "bird.fill"),
        .init(common: "Rock Pigeon", scientific: "Columba livia", realm: .animals, rarity: .common, symbol: "bird.fill"),
        .init(common: "Seven-spot Ladybird", scientific: "Coccinella septempunctata", realm: .animals, rarity: .uncommon, symbol: "ladybug.fill"),
        .init(common: "Red Fox", scientific: "Vulpes vulpes", realm: .animals, rarity: .uncommon, symbol: "pawprint.fill"),
        .init(common: "Common Dandelion", scientific: "Taraxacum officinale", realm: .plants, rarity: .common, symbol: "leaf.fill"),
        .init(common: "Pedunculate Oak", scientific: "Quercus robur", realm: .plants, rarity: .uncommon, symbol: "tree.fill"),
        .init(common: "Grey Heron", scientific: "Ardea cinerea", realm: .animals, rarity: .rare, symbol: "bird.fill"),
        .init(common: "Common Frog", scientific: "Rana temporaria", realm: .animals, rarity: .rare, symbol: "lizard.fill"),
        .init(common: "Fly Agaric", scientific: "Amanita muscaria", realm: .fungi, rarity: .rare, symbol: "circle.hexagongrid.fill"),
        .init(common: "Common Buzzard", scientific: "Buteo buteo", realm: .animals, rarity: .epic, symbol: "bird.fill"),
        .init(common: "Golden Eagle", scientific: "Aquila chrysaetos", realm: .animals, rarity: .legendary, symbol: "bird.fill"),
    ]

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LIVINGDEX_DEMO"] != nil
    }

    /// The requested screen route, if any (dex, profile, card, field).
    static var route: String {
        ProcessInfo.processInfo.environment["LIVINGDEX_DEMO"] ?? ""
    }

    static func seedIfNeeded() {
        guard isEnabled else { return }
        AppSettings.hasOnboarded = true
        let store = CollectionStore.shared
        guard (try? store.dexCount()) == 0 else { return }
        let progress = ProgressStore.shared
        let now = Date()
        for (i, s) in samples.enumerated() {
            let id = "demo-\(i)"
            let image = artwork(for: s)
            let path = ImageStore.save(image, id: id) ?? ""
            let sighting = Sighting(
                id: id, speciesId: "gbif:demo\(i)", commonName: s.common, scientificName: s.scientific,
                realm: s.realm, rarity: s.rarity, confidence: Double.random(in: 0.7...0.98),
                capturedAt: now.addingTimeInterval(Double(-i) * 3600), latitude: 60.17, longitude: 24.94,
                elevationMeters: Double.random(in: 2...40), imagePath: path,
                pokedexEntry: i % 3 == 0 ? "A familiar sight across gardens and cities, this hardy species thrives alongside people.\n\n• Highly adaptable to urban life\n• Feeds on seeds and insects\n• Often seen in small, chattering flocks" : nil)
            let isNew = (try? store.save(sighting)) ?? true
            _ = try? progress.record(rarity: s.rarity, isNew: isNew, now: now)
        }
        AppLogger.shared.info("demo data seeded (\(samples.count) species)", category: .persistence)
    }

    /// A clean gradient tile with the species' symbol — reads as intentional art.
    private static func artwork(for s: Sample) -> UIImage {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext
            let top = s.rarity.color
            let bottom = top.withAlphaComponent(0.65)
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            let config = UIImage.SymbolConfiguration(pointSize: 260, weight: .semibold)
            if let sym = UIImage(systemName: s.symbol, withConfiguration: config)?.withTintColor(.white.withAlphaComponent(0.92), renderingMode: .alwaysOriginal) {
                let r = CGRect(x: (size.width - sym.size.width) / 2, y: (size.height - sym.size.height) / 2, width: sym.size.width, height: sym.size.height)
                sym.draw(in: r)
            }
        }
    }
}
#endif
