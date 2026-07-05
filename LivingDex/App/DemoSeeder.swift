#if DEBUG
import UIKit

/// DEBUG-only: seeds a rich, varied sample collection so every screen can be
/// driven and screenshotted for design validation. Enabled via the
/// `LIVINGDEX_DEMO` launch environment variable (any value). Generates clean
/// symbol-on-gradient artwork per species so the grid reads as real content.
enum DemoSeeder {
    struct Sample {
        let common: String, scientific: String, realm: Realm, rarity: Rarity, symbol: String
        let category: String, size: String
    }

    static let samples: [Sample] = [
        .init(common: "House Sparrow", scientific: "Passer domesticus", realm: .animals, rarity: .common, symbol: "bird.fill", category: "Urban Songbird", size: "~16 cm · ~30 g"),
        .init(common: "European Robin", scientific: "Erithacus rubecula", realm: .animals, rarity: .common, symbol: "bird.fill", category: "Garden Sentinel", size: "~14 cm · ~18 g"),
        .init(common: "Rock Pigeon", scientific: "Columba livia", realm: .animals, rarity: .common, symbol: "bird.fill", category: "City Glider", size: "~33 cm · ~350 g"),
        .init(common: "Seven-spot Ladybird", scientific: "Coccinella septempunctata", realm: .animals, rarity: .uncommon, symbol: "ladybug.fill", category: "Aphid Hunter", size: "~8 mm"),
        .init(common: "Red Fox", scientific: "Vulpes vulpes", realm: .animals, rarity: .uncommon, symbol: "pawprint.fill", category: "Twilight Prowler", size: "~70 cm · ~6 kg"),
        .init(common: "Common Dandelion", scientific: "Taraxacum officinale", realm: .plants, rarity: .common, symbol: "leaf.fill", category: "Sunlit Wanderer", size: "~30 cm tall"),
        .init(common: "Pedunculate Oak", scientific: "Quercus robur", realm: .plants, rarity: .uncommon, symbol: "tree.fill", category: "Ancient Sentinel", size: "up to 40 m"),
        .init(common: "Grey Heron", scientific: "Ardea cinerea", realm: .animals, rarity: .rare, symbol: "bird.fill", category: "Patient Angler", size: "~95 cm · ~1.5 kg"),
        .init(common: "Common Frog", scientific: "Rana temporaria", realm: .animals, rarity: .rare, symbol: "lizard.fill", category: "Pond Voice", size: "~9 cm"),
        .init(common: "Fly Agaric", scientific: "Amanita muscaria", realm: .fungi, rarity: .rare, symbol: "circle.hexagongrid.fill", category: "Woodland Enchanter", size: "~15 cm cap"),
        .init(common: "Common Buzzard", scientific: "Buteo buteo", realm: .animals, rarity: .epic, symbol: "bird.fill", category: "Soaring Hunter", size: "~55 cm · ~800 g"),
        .init(common: "Golden Eagle", scientific: "Aquila chrysaetos", realm: .animals, rarity: .legendary, symbol: "bird.fill", category: "Mountain Monarch", size: "~85 cm · ~4.5 kg"),
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
                pokedexEntry: i % 2 == 0 ? "A familiar sight across gardens and cities, this hardy species thrives alongside people, filling the air with life.\n\n• Highly adaptable to urban and wild habitats\n• Feeds opportunistically on seeds and insects\n• Often seen in small, chattering groups" : nil,
                category: s.category, typicalSize: s.size)
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
