import MidgarCore
import UIKit

/// One of the real species a new player can start their Dex with. Everything is bundled, so
/// a starter works offline and never touches the identification service or a credit.
struct StarterSpecies: Sendable, Equatable, Identifiable {
    let id: String
    let speciesId: String
    let commonName: String
    let scientificName: String
    let realm: Realm
    let tag: String
    let category: String
    let typicalSize: String
    let entry: String
    let photoResource: String

    var image: UIImage? { SampleLibrary.image(named: photoResource) }

    var candidate: SpeciesCandidate {
        SpeciesCandidate(
            speciesId: speciesId, commonName: commonName, scientificName: scientificName,
            realm: realm, rarity: .common, confidence: 1)
    }
}

enum StarterCatalog {
    static let all: [StarterSpecies] = [
        StarterSpecies(
            id: "robin", speciesId: "gbif:2492462", commonName: "European Robin",
            scientificName: "Erithacus rubecula", realm: .animals, tag: "Songbird",
            category: "Garden Sentinel", typicalSize: "~14 cm · ~18 g",
            entry: "A bold garden regular whose rusty-orange breast makes it one of the easiest birds to know, and one of the few that sings through winter.\n\n• Fiercely territorial, even toward its own reflection\n• Follows gardeners to catch turned-up worms\n• Sings at dawn, dusk and under street lamps",
            photoResource: "sample-robin"),
        StarterSpecies(
            id: "fox", speciesId: "gbif:5219243", commonName: "Red Fox",
            scientificName: "Vulpes vulpes", realm: .animals, tag: "Mammal",
            category: "Twilight Prowler", typicalSize: "~70 cm · ~6 kg",
            entry: "An agile, clever hunter that has made itself at home from forest edges to city streets, most active at dusk and through the night.\n\n• Pounces on mice and voles with a high arcing leap\n• Uses its bushy tail for balance and warmth\n• Digs dens, called earths, in banks and under sheds",
            photoResource: "sample-red-fox"),
        StarterSpecies(
            id: "agaric", speciesId: "gbif:8168319", commonName: "Fly Agaric",
            scientificName: "Amanita muscaria", realm: .fungi, tag: "Mushroom",
            category: "Woodland Enchanter", typicalSize: "~15 cm cap",
            entry: "The classic red toadstool with white flecks, a fairy-tale icon of birch and pine woods that is beautiful but poisonous.\n\n• Forms a partnership with tree roots\n• Its red cap fades to orange as it ages\n• Never to be eaten, though it features in folklore",
            photoResource: "sample-fly-agaric"),
        StarterSpecies(
            id: "anemone", speciesId: "gbif:3033263", commonName: "Wood Anemone",
            scientificName: "Anemone nemorosa", realm: .plants, tag: "Wildflower",
            category: "Spring Carpet", typicalSize: "~15 cm tall",
            entry: "A delicate white woodland flower that carpets the forest floor each spring before the trees above come into leaf.\n\n• Flowers close at night and in dull weather\n• Spreads very slowly through creeping roots\n• A sign of ancient, undisturbed woodland",
            photoResource: "sample-wood-anemone"),
    ]
}

/// Mints the starter as a normal first catch: the bundled photo, the curated field entry, the
/// rarity the Worker confirmed (or Common until it is reachable), XP and the first streak day.
/// No identification call, no credit, no consent needed — nothing leaves the device.
struct StarterCatch: Sendable {
    let imageStore: any CaptureImageStoring
    let sightingStore: any SightingPersisting
    let progress: any ProgressRecording
    let clock: @Sendable () -> Date

    struct Outcome: Sendable {
        let sighting: Sighting
        let image: UIImage
        let isNew: Bool
        let progress: ProgressEvent?
    }

    init(
        imageStore: any CaptureImageStoring = DefaultCaptureImageStore(),
        sightingStore: any SightingPersisting = CollectionStore.shared,
        progress: any ProgressRecording = ProgressStore.shared,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.imageStore = imageStore
        self.sightingStore = sightingStore
        self.progress = progress
        self.clock = clock
    }

    /// Saves the starter, or returns nil when its photo or the database write fails (nothing
    /// is left behind in that case).
    func mint(_ starter: StarterSpecies, enrichment: SpeciesEnrichment?) -> Outcome? {
        guard let image = starter.image else { return nil }
        let id = UUID().uuidString
        guard let path = imageStore.save(image, id: id) else { return nil }
        let now = clock()
        let sighting = Sighting(
            id: id, speciesId: starter.speciesId,
            commonName: enrichment?.adoptedCommonName(current: starter.commonName, scientificName: starter.scientificName)
                ?? starter.commonName,
            scientificName: starter.scientificName, realm: starter.realm,
            rarity: enrichment?.rarity ?? .common, confidence: 1, capturedAt: now,
            latitude: nil, longitude: nil, elevationMeters: nil, imagePath: path,
            pokedexEntry: starter.entry, category: starter.category, typicalSize: starter.typicalSize,
            enriched: enrichment != nil)
        let isNew: Bool
        do {
            isNew = try sightingStore.save(sighting)
        } catch {
            imageStore.delete(path)
            MidgarLog.error("starter save failed: \(error)", category: .persistence)
            return nil
        }
        let event = try? progress.record(rarity: sighting.rarity, isNew: isNew, now: now)
        MidgarLog.info("starter minted \(sighting.commonName)", category: .capture)
        return Outcome(sighting: sighting, image: image, isNew: isNew, progress: event)
    }
}
