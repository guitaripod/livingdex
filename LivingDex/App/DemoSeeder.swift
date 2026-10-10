#if DEBUG
import UIKit

/// DEBUG-only: seeds a rich, varied sample collection so every screen can be
/// driven and screenshotted for design validation. Enabled via the
/// `LIVINGDEX_DEMO` launch environment variable (any value). Generates clean
/// symbol-on-gradient artwork per species so the grid reads as real content.
enum DemoSeeder {
    struct Sample {
        let common: String, scientific: String, realm: Realm, rarity: Rarity, symbol: String
        let category: String, size: String, entry: String
    }

    static let samples: [Sample] = [
        .init(common: "House Sparrow", scientific: "Passer domesticus", realm: .animals, rarity: .common, symbol: "bird.fill", category: "Urban Songbird", size: "~16 cm · ~30 g", entry: "A familiar sight across gardens and cities, this hardy little songbird thrives alongside people and fills the air with chatter.\n\n• Highly adaptable to urban and wild habitats\n• Feeds opportunistically on seeds and insects\n• Often seen in small, chattering groups"),
        .init(common: "European Robin", scientific: "Erithacus rubecula", realm: .animals, rarity: .common, symbol: "bird.fill", category: "Garden Sentinel", size: "~14 cm · ~18 g", entry: "A bold garden regular whose rusty-orange breast makes it one of the easiest birds to know, and one of the few that sings through winter.\n\n• Fiercely territorial, even toward its own reflection\n• Follows gardeners to catch turned-up worms\n• Sings at dawn, dusk and under street lamps"),
        .init(common: "Rock Pigeon", scientific: "Columba livia", realm: .animals, rarity: .common, symbol: "bird.fill", category: "City Glider", size: "~33 cm · ~350 g", entry: "The city's most familiar bird, descended from wild cliff-dwellers and a gifted navigator that can find its way home across hundreds of kilometres.\n\n• Nests on ledges that mimic sea cliffs\n• Feeds on seeds, grain and scraps\n• Mates for life and raises young on crop milk"),
        .init(common: "Seven-spot Ladybird", scientific: "Coccinella septempunctata", realm: .animals, rarity: .uncommon, symbol: "ladybug.fill", category: "Aphid Hunter", size: "~8 mm", entry: "A glossy red beetle with seven black spots, and a gardener's best friend: one ladybird can eat thousands of aphids in its life.\n\n• Warns predators with bright colours and a bitter taste\n• Hibernates in clusters through the winter\n• Lays tiny yellow eggs on aphid-infested leaves"),
        .init(common: "Red Fox", scientific: "Vulpes vulpes", realm: .animals, rarity: .uncommon, symbol: "pawprint.fill", category: "Twilight Prowler", size: "~70 cm · ~6 kg", entry: "An agile, clever hunter that has made itself at home from forest edges to city streets, most active at dusk and through the night.\n\n• Pounces on mice and voles with a high arcing leap\n• Uses its bushy tail for balance and warmth\n• Digs dens, called earths, in banks and under sheds"),
        .init(common: "Common Dandelion", scientific: "Taraxacum officinale", realm: .plants, rarity: .common, symbol: "leaf.fill", category: "Sunlit Wanderer", size: "~30 cm tall", entry: "A cheerful golden flower that carpets meadows and verges, then turns to a clock of parachute seeds that drift for kilometres.\n\n• Every part of the plant is edible\n• Flowers close at night and in the rain\n• A lifeline for early spring pollinators"),
        .init(common: "Pedunculate Oak", scientific: "Quercus robur", realm: .plants, rarity: .uncommon, symbol: "tree.fill", category: "Ancient Sentinel", size: "up to 40 m", entry: "A slow, mighty tree that can live a thousand years and supports more kinds of wildlife than almost any other tree in Europe.\n\n• Hosts hundreds of species of insects, birds and fungi\n• Acorns are buried and forgotten by jays, planting new woods\n• Leaves out late and drops its leaves late"),
        .init(common: "Grey Heron", scientific: "Ardea cinerea", realm: .animals, rarity: .rare, symbol: "bird.fill", category: "Patient Angler", size: "~95 cm · ~1.5 kg", entry: "A tall, patient angler that stands motionless in shallow water for long minutes before striking at a fish with lightning speed.\n\n• Nests high in tree colonies called heronries\n• Flies with its neck folded back in an S shape\n• Eats fish, frogs and even small mammals"),
        .init(common: "Common Frog", scientific: "Rana temporaria", realm: .animals, rarity: .rare, symbol: "lizard.fill", category: "Pond Voice", size: "~9 cm", entry: "A familiar pond visitor that spends most of the year in damp grass and returns to the water each spring to fill it with spawn.\n\n• Breathes partly through its moist skin\n• Can hibernate at the bottom of a frozen pond\n• Tadpoles hatch from clumps of jelly-like spawn"),
        .init(common: "Fly Agaric", scientific: "Amanita muscaria", realm: .fungi, rarity: .rare, symbol: "circle.hexagongrid.fill", category: "Woodland Enchanter", size: "~15 cm cap", entry: "The classic red toadstool with white flecks, a fairy-tale icon of birch and pine woods that is beautiful but poisonous.\n\n• Forms a partnership with tree roots\n• Its red cap fades to orange as it ages\n• Never to be eaten, though it features in folklore"),
        .init(common: "Common Buzzard", scientific: "Buteo buteo", realm: .animals, rarity: .epic, symbol: "bird.fill", category: "Soaring Hunter", size: "~55 cm · ~800 g", entry: "A broad-winged raptor often seen circling on rising warm air, mewing as it scans the fields below for voles and rabbits.\n\n• Soars for hours on thermals with barely a wingbeat\n• Perches on fence posts to watch for prey\n• Highly variable plumage, from pale to dark chocolate"),
        .init(common: "Golden Eagle", scientific: "Aquila chrysaetos", realm: .animals, rarity: .legendary, symbol: "bird.fill", category: "Mountain Monarch", size: "~85 cm · ~4.5 kg", entry: "A powerful mountain monarch with a wingspan over two metres, hunting hares and grouse across open ground at breathtaking speed.\n\n• Pairs hold huge territories and return to the same cliff eyries\n• Can dive at well over 150 km/h\n• Named for the golden sheen on its neck feathers"),
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
                pokedexEntry: s.entry,
                category: s.category, typicalSize: s.size, enriched: true)
            let isNew = (try? store.save(sighting)) ?? false
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
