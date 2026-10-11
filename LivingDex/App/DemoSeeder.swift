#if DEBUG
import AICreditsCore
import UIKit

/// DEBUG-only: seeds a populated collection of real, public-domain or CC0 species
/// photographs so every screen can be driven and recorded. Enabled via the
/// `LIVINGDEX_DEMO` launch environment variable, whose value picks the first
/// screen (dex, caught, nearby, card, profile, reveal). `LIVINGDEX_DEMO_PHOTOS`
/// names a folder of `<photo>.jpg` files; a species without one falls back to a
/// symbol-on-gradient tile. The `reveal` route holds the Golden Eagle back and
/// presents its catch celebration over the collection, saving it on dismissal.
enum DemoSeeder {
    struct Sample {
        let common: String, scientific: String, speciesId: String, realm: Realm, rarity: Rarity
        let photo: String, symbol: String, category: String, size: String, entry: String
    }

    static let samples: [Sample] = [
        .init(common: "Golden Eagle", scientific: "Aquila chrysaetos", speciesId: "demo-golden-eagle", realm: .animals, rarity: .legendary, photo: "golden-eagle", symbol: "bird.fill", category: "Mountain Monarch", size: "~85 cm · ~4.5 kg", entry: "A powerful mountain monarch with a wingspan over two metres, hunting hares and grouse across open ground at breathtaking speed.\n\n• Pairs hold huge territories and return to the same cliff eyries\n• Can dive at well over 150 km/h\n• Named for the golden sheen on its neck feathers"),
        .init(common: "Red Fox", scientific: "Vulpes vulpes", speciesId: "demo-red-fox", realm: .animals, rarity: .uncommon, photo: "red-fox", symbol: "pawprint.fill", category: "Twilight Prowler", size: "~70 cm · ~6 kg", entry: "An agile, clever hunter that has made itself at home from forest edges to city streets, most active at dusk and through the night.\n\n• Pounces on mice and voles with a high arcing leap\n• Uses its bushy tail for balance and warmth\n• Digs dens, called earths, in banks and under sheds"),
        .init(common: "European Robin", scientific: "Erithacus rubecula", speciesId: "gbif:2492462", realm: .animals, rarity: .common, photo: "robin", symbol: "bird.fill", category: "Garden Sentinel", size: "~14 cm · ~18 g", entry: "A bold garden regular whose rusty-orange breast makes it one of the easiest birds to know, and one of the few that sings through winter.\n\n• Fiercely territorial, even toward its own reflection\n• Follows gardeners to catch turned-up worms\n• Sings at dawn, dusk and under street lamps"),
        .init(common: "Great Tit", scientific: "Parus major", speciesId: "gbif:9705453", realm: .animals, rarity: .common, photo: "great-tit", symbol: "bird.fill", category: "Feeder Acrobat", size: "~14 cm · ~19 g", entry: "A bold black-capped songbird with a bright yellow breast, quick to find a feeder and famous for its two-note teacher-teacher call.\n\n• Learns new feeding tricks from other birds\n• Stores seeds for the lean winter months\n• Nests in tree holes and nest boxes"),
        .init(common: "Fly Agaric", scientific: "Amanita muscaria", speciesId: "gbif:8168319", realm: .fungi, rarity: .common, photo: "fly-agaric", symbol: "circle.hexagongrid.fill", category: "Woodland Enchanter", size: "~15 cm cap", entry: "The classic red toadstool with white flecks, a fairy-tale icon of birch and pine woods that is beautiful but poisonous.\n\n• Forms a partnership with tree roots\n• Its red cap fades to orange as it ages\n• Never to be eaten, though it features in folklore"),
        .init(common: "Grey Heron", scientific: "Ardea cinerea", speciesId: "demo-grey-heron", realm: .animals, rarity: .rare, photo: "grey-heron", symbol: "bird.fill", category: "Patient Angler", size: "~95 cm · ~1.5 kg", entry: "A tall, patient angler that stands motionless in shallow water for long minutes before striking at a fish with lightning speed.\n\n• Nests high in tree colonies called heronries\n• Flies with its neck folded back in an S shape\n• Eats fish, frogs and even small mammals"),
        .init(common: "Eurasian Blue Tit", scientific: "Cyanistes caeruleus", speciesId: "gbif:2487879", realm: .animals, rarity: .common, photo: "blue-tit", symbol: "bird.fill", category: "Tiny Acrobat", size: "~12 cm · ~11 g", entry: "A tiny, colourful acrobat that hangs upside down from the thinnest twigs while searching for insects and spiders.\n\n• Wears a blue cap that glows in ultraviolet light\n• Raises up to a dozen chicks in a single nest\n• Often visits garden feeders in winter flocks"),
        .init(common: "Wood Anemone", scientific: "Anemone nemorosa", speciesId: "gbif:3033263", realm: .plants, rarity: .common, photo: "wood-anemone", symbol: "leaf.fill", category: "Spring Carpet", size: "~15 cm tall", entry: "A delicate white woodland flower that carpets the forest floor each spring before the trees above come into leaf.\n\n• Flowers close at night and in dull weather\n• Spreads very slowly through creeping roots\n• A sign of ancient, undisturbed woodland"),
        .init(common: "Barn Swallow", scientific: "Hirundo rustica", speciesId: "gbif:9515886", realm: .animals, rarity: .common, photo: "barn-swallow", symbol: "bird.fill", category: "Summer Messenger", size: "~18 cm · ~19 g", entry: "A graceful long-tailed flier that crosses continents each year, feeding on insects on the wing and building mud nests under eaves.\n\n• Migrates thousands of kilometres to Africa and back\n• Drinks and bathes while skimming over water\n• Returns to the same nesting site year after year"),
        .init(common: "Common Chaffinch", scientific: "Fringilla coelebs", speciesId: "gbif:2494422", realm: .animals, rarity: .common, photo: "chaffinch", symbol: "bird.fill", category: "Woodland Singer", size: "~15 cm · ~22 g", entry: "One of Europe's most abundant birds, the male wears a pinkish breast and blue-grey cap and sings a rattling, descending song.\n\n• Males sing from the same perch for hours\n• Flashes two white wing bars in flight\n• Forages on the ground for seeds and insects"),
        .init(common: "Lily-of-the-valley", scientific: "Convallaria majalis", speciesId: "gbif:7459480", realm: .plants, rarity: .common, photo: "lily-of-the-valley", symbol: "leaf.fill", category: "Fragrant Bell", size: "~20 cm tall", entry: "A small woodland plant with arching sprays of white bell-shaped flowers and a sweet scent that signals the start of late spring.\n\n• Every part of the plant is poisonous\n• Spreads in dense patches through underground stems\n• Produces bright red berries in late summer"),
        .init(common: "Black-headed Gull", scientific: "Chroicocephalus ridibundus", speciesId: "gbif:6065824", realm: .animals, rarity: .common, photo: "black-headed-gull", symbol: "bird.fill", category: "Harbour Drifter", size: "~36 cm · ~280 g", entry: "A sociable, noisy gull whose chocolate-brown head in summer is replaced by a small dark smudge in winter.\n\n• Nests in large, noisy colonies on wetlands\n• Follows ploughs and tractors for turned-up worms\n• Catches insects in flight, like a swallow"),
    ]

    private static let regionalSpecies: [RegionSpecies] = [
        .init(speciesId: "gbif:9705453", commonName: "Great Tit", scientificName: "Parus major", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:3149879", commonName: "Colt's-foot", scientificName: "Tussilago farfara", realm: .plants, rarity: .common),
        .init(speciesId: "gbif:2487879", commonName: "Eurasian Blue Tit", scientificName: "Cyanistes caeruleus", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:3033263", commonName: "Wood Anemone", scientificName: "Anemone nemorosa", realm: .plants, rarity: .common),
        .init(speciesId: "gbif:2542395", commonName: "Red Belted Conk", scientificName: "Fomitopsis pinicola", realm: .fungi, rarity: .common),
        .init(speciesId: "gbif:2492462", commonName: "European Robin", scientificName: "Erithacus rubecula", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:2493052", commonName: "Willow Warbler", scientificName: "Phylloscopus trochilus", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:8168319", commonName: "Fly Agaric", scientificName: "Amanita muscaria", realm: .fungi, rarity: .common),
        .init(speciesId: "gbif:5284884", commonName: "Norway Spruce", scientificName: "Picea abies", realm: .plants, rarity: .common),
        .init(speciesId: "gbif:2494422", commonName: "Common Chaffinch", scientificName: "Fringilla coelebs", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:2882833", commonName: "Bilberry", scientificName: "Vaccinium myrtillus", realm: .plants, rarity: .common),
        .init(speciesId: "gbif:9515886", commonName: "Barn Swallow", scientificName: "Hirundo rustica", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:7459480", commonName: "Lily-of-the-valley", scientificName: "Convallaria majalis", realm: .plants, rarity: .common),
        .init(speciesId: "gbif:2492606", commonName: "European Pied Flycatcher", scientificName: "Ficedula hypoleuca", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:6065824", commonName: "Black-headed Gull", scientificName: "Chroicocephalus ridibundus", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:2484596", commonName: "Goldcrest", scientificName: "Regulus regulus", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:5285637", commonName: "Scots Pine", scientificName: "Pinus sylvestris", realm: .plants, rarity: .common),
        .init(speciesId: "gbif:9809229", commonName: "European Starling", scientificName: "Sturnus vulgaris", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:2493129", commonName: "Sedge Warbler", scientificName: "Acrocephalus schoenobaenus", realm: .animals, rarity: .common),
        .init(speciesId: "gbif:3012167", commonName: "Rowan", scientificName: "Sorbus aucuparia", realm: .plants, rarity: .common),
        .init(speciesId: "gbif:7823145", commonName: "Common Coral Slime", scientificName: "Ceratiomyxa fruticulosa", realm: .protists, rarity: .rare),
        .init(speciesId: "gbif:8222574", commonName: "Bladder Wrack", scientificName: "Fucus vesiculosus", realm: .protists, rarity: .common),
        .init(speciesId: "gbif:8068867", commonName: "Tinder Bracket", scientificName: "Fomes fomentarius", realm: .fungi, rarity: .common),
        .init(speciesId: "gbif:2481139", commonName: "Herring Gull", scientificName: "Larus argentatus", realm: .animals, rarity: .common),
    ]

    private static let heldBackSpeciesId = "demo-golden-eagle"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LIVINGDEX_DEMO"] != nil
    }

    /// The requested screen route, if any (dex, profile, card, caught, nearby, reveal).
    static var route: String {
        ProcessInfo.processInfo.environment["LIVINGDEX_DEMO"] ?? ""
    }

    static func seedIfNeeded() {
        guard isEnabled else { return }
        AppSettings.hasOnboarded = true
        seedRegionalCache()
        let store = CollectionStore.shared
        guard needsReseed(store) else { return }
        let progress = ProgressStore.shared
        let now = Date()
        let seeded = samples.enumerated().filter { route != "reveal" || $0.element.speciesId != heldBackSpeciesId }
        for (i, s) in seeded.reversed() {
            let capturedAt = now.addingTimeInterval(-Double(i / 2) * 86_400 - Double(i % 2) * 3600)
            let sighting = makeSighting(s, id: "demo-\(i)", capturedAt: capturedAt)
            let isNew = (try? store.save(sighting)) ?? false
            _ = try? progress.record(rarity: s.rarity, isNew: isNew, now: capturedAt)
        }
        AppLogger.shared.info("demo data seeded (\(seeded.count) species)", category: .persistence)
    }

    private static let withholdsEagleKey = "demoSeededWithoutEagle"

    /// True when the collection is empty or was seeded for a different route than this
    /// launch: the `reveal` route needs the Golden Eagle absent and every other route
    /// needs it present, so a relaunch on another route wipes and reseeds, while a
    /// relaunch on the same route keeps what is there.
    private static func needsReseed(_ store: CollectionStore) -> Bool {
        let withholds = route == "reveal"
        let defaults = UserDefaults.standard
        let isEmpty = ((try? store.dexCount()) ?? 0) == 0
        if !isEmpty && !withholds && !defaults.bool(forKey: withholdsEagleKey) { return false }
        if !isEmpty { try? DatabaseManager.shared.eraseAllData() }
        defaults.set(withholds, forKey: withholdsEagleKey)
        return true
    }

    /// The Golden Eagle catch celebration, presented over the collection. The
    /// sighting is saved when the card is dismissed so the grid gains its tile live.
    @MainActor
    static func presentReveal(from presenter: UIViewController) {
        guard route == "reveal", let sample = samples.first(where: { $0.speciesId == heldBackSpeciesId }) else { return }
        let sighting = makeSighting(sample, id: "demo-reveal", capturedAt: Date())
        let image = photo(for: sample) ?? artwork(for: sample)
        let event = try? ProgressStore.shared.record(rarity: sample.rarity, isNew: true)
        let card = CardRevealViewController(sighting: sighting, image: image, isNewDexEntry: true, progress: event)
        card.modalPresentationStyle = .overFullScreen
        card.modalTransitionStyle = .crossDissolve
        presenter.present(card, animated: true)
        Task { @MainActor in
            while !card.isBeingDismissed && card.presentingViewController != nil {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            try? await Task.sleep(nanoseconds: 450_000_000)
            _ = try? CollectionStore.shared.save(sighting)
        }
    }

    private static func makeSighting(_ s: Sample, id: String, capturedAt: Date) -> Sighting {
        let image = photo(for: s) ?? artwork(for: s)
        let path = ImageStore.save(image, id: id) ?? ""
        return Sighting(
            id: id, speciesId: s.speciesId, commonName: s.common, scientificName: s.scientific,
            realm: s.realm, rarity: s.rarity, confidence: 0.96,
            capturedAt: capturedAt, latitude: 60.17, longitude: 24.94,
            elevationMeters: 12, imagePath: path,
            pokedexEntry: s.entry, category: s.category, typicalSize: s.size, enriched: true)
    }

    /// Writes the curated Regional Dex for the Helsinki cell so Nearby opens
    /// fresh and offline, with the caught species interleaved among locked slots.
    private static func seedRegionalCache() {
        struct Entry: Codable { var species: [RegionSpecies]; var fetchedAt: Date }
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
            let data = try? JSONEncoder().encode(["120,50": Entry(species: regionalSpecies, fetchedAt: Date())])
        else { return }
        try? data.write(to: support.appendingPathComponent("region-cache.json"), options: .atomic)
    }

    /// The Pro paywall over the Profile tab with live-looking store prices, for the App
    /// Review screenshots of the subscriptions (a simulator has no App Store to price them).
    @MainActor
    static func presentPaywall(from presenter: UIViewController) {
        let service = SubscriptionService(
            backend: DemoSubscriptionBacking(), entitlementStore: ProEntitlementStore(suiteName: "livingdex.demo"))
        PaywallPresenter.present(from: presenter, service: service, reason: "Every identification uses a credit.")
        Task { await service.loadPlans() }
    }

    /// The photograph the `field` route shows in place of the live camera feed:
    /// `field-backdrop.jpg` in the photos folder, else the Golden Eagle portrait.
    static func fieldBackdrop() -> UIImage? {
        guard let folder = ProcessInfo.processInfo.environment["LIVINGDEX_DEMO_PHOTOS"] else { return nil }
        return UIImage(contentsOfFile: "\(folder)/field-backdrop.jpg") ?? UIImage(contentsOfFile: "\(folder)/golden-eagle.jpg")
    }

    private static func photo(for s: Sample) -> UIImage? {
        guard let folder = ProcessInfo.processInfo.environment["LIVINGDEX_DEMO_PHOTOS"] else { return nil }
        return UIImage(contentsOfFile: "\(folder)/\(s.photo).jpg")
    }

    /// A clean gradient tile with the species' symbol, used when no photo is supplied.
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

/// Plans priced like the real App Store products, so the paywall renders as a player sees it.
private struct DemoSubscriptionBacking: SubscriptionBacking {
    func proVerdict() async -> ProVerdict { .free }

    func subscriptionPlans() async throws -> [SubscriptionPlan] {
        [
            SubscriptionPlan(
                id: "$rc_annual", productID: "com.guitaripod.livingdex.pro.annual", localizedPrice: "$29.99",
                price: 29.99, currencyCode: "USD", period: .annual, trialDays: 3, trialEligible: true),
            SubscriptionPlan(
                id: "$rc_monthly", productID: "com.guitaripod.livingdex.pro.monthly", localizedPrice: "$4.99",
                price: 4.99, currencyCode: "USD", period: .monthly, trialDays: nil, trialEligible: false),
        ]
    }

    func purchaseSubscription(_ plan: SubscriptionPlan) async throws {}
    func restoreEntitlements() async throws {}
}
#endif
