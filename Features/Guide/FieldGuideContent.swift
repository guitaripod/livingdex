import Foundation
import LivingDexCore

/// The static, science-vetted copy behind the in-app Field Guide. Kept as plain
/// data so `FieldGuideViewController` is pure layout. Realm art lives in the
/// asset catalog as `realm-<key>` (Gemini-generated, one cohesive set).
enum FieldGuide {
    struct Step {
        let symbol: String
        let title: String
        let body: String
    }

    struct RealmInfo {
        let realm: Realm
        let name: String
        let tagline: String
        let whatIsIt: String
        let examples: [String]
        let catchTip: String
        var assetName: String { "realm-\(realm.rawValue)" }
    }

    struct RarityInfo {
        let rarity: Rarity
        let meaning: String
    }

    struct Concept {
        let title: String
        let body: String
    }

    static let introTitle = String(localized: "Field Guide")
    static let introSubtitle = String(localized: "How Living Dex works, and the real science behind every catch.")

    static let steps: [Step] = [
        .init(
            symbol: "camera.viewfinder", title: String(localized: "Point & catch"),
            body: String(localized: "Aim your camera at any living thing — a bird, a wildflower, a mushroom, a bug — and tap to catch. No creature in reach? Identify a photo from your library instead.")),
        .init(
            symbol: "sparkle.magnifyingglass", title: String(localized: "Named by cloud AI"),
            body: String(localized: "Your photo is sent over an encrypted connection to a vision AI that names the species and says how sure it is. You start with 30 free identifications; each one uses a credit.")),
        .init(
            symbol: "checkmark.seal", title: String(localized: "Checked against real science"),
            body: String(localized: "The name is verified against GBIF, the world's biodiversity database. A misspelled or invented species never reaches your Dex — and Pro members identify without limits.")),
        .init(
            symbol: "square.grid.2x2", title: String(localized: "Build your Dex"),
            body: String(localized: "Every confirmed catch is saved to your collection, sorted by realm — animals, plants, fungi, protists, and more — each with a rarity tier drawn from real ecological data.")),
        .init(
            symbol: "location", title: String(localized: "Explore your Nearby dex"),
            body: String(localized: "The Nearby tab is your regional Dex: every species that plausibly lives around you, shown as locked silhouettes. Catch one in the wild to reveal it.")),
        .init(
            symbol: "book", title: String(localized: "Earn a real field entry"),
            body: String(localized: "Each catch unlocks a full field entry — photos, calls, facts, and a written description — so your collection reads like a living field guide of what you've found.")),
    ]

    static let realms: [RealmInfo] = [
        .init(
            realm: .animals, name: String(localized: "Animals"), tagline: String(localized: "They move, eat, sense."),
            whatIsIt: String(localized: "Animals are multicellular life that survives by eating other living things and, almost always, moving to find it. Unlike plants, they can't make food from sunlight, and unlike fungi, they digest meals inside their bodies. If it actively moves and responds fast to what's around it, it's very likely an animal — including insects, spiders, worms, and you."),
            examples: [
                String(localized: "A pigeon, sparrow, or crow on the street"),
                String(localized: "A dog, cat, or squirrel in the neighborhood"),
                String(localized: "A honeybee or butterfly on a flower"),
                String(localized: "A ladybug, ant, or spider on a wall"),
                String(localized: "A snail, frog, or fish near water"),
            ],
            catchTip: String(localized: "Animals move, so be patient and steady — approach slowly, hold the frame on a resting bird or a working bee, and tap the moment it pauses.")),
        .init(
            realm: .plants, name: String(localized: "Plants"), tagline: String(localized: "They drink sunlight."),
            whatIsIt: String(localized: "Plants make their own food out of thin air and light — photosynthesis, which pulls in sunlight, water, and carbon dioxide and turns them into sugar (giving off the oxygen we breathe). They're rooted in place, and their green comes from chlorophyll, the pigment doing that solar chemistry. Trees, mosses, ferns, and window-box flowers are all plants."),
            examples: [
                String(localized: "A dandelion, daisy, or rose"),
                String(localized: "An oak, maple, or pine tree"),
                String(localized: "Grass, clover, or moss underfoot"),
                String(localized: "A fern or a houseplant on the sill"),
                String(localized: "A tomato, oak leaf, or pinecone"),
            ],
            catchTip: String(localized: "Plants hold still, so get close and fill the frame with one clear feature — a single flower, a distinct leaf, or bark — in good daylight for the sharpest ID.")),
        .init(
            realm: .fungi, name: String(localized: "Fungi"), tagline: String(localized: "Nature's hidden recyclers."),
            whatIsIt: String(localized: "Fungi aren't plants — they can't photosynthesize, and they're actually closer cousins to animals than to anything green. A fungus digests food outside its body, releasing chemicals into dead wood, soil, or leaves and drinking the nutrients back in. The mushroom you see is just the fruiting body of a vast, thread-like network — the mycelium — hidden beneath."),
            examples: [
                String(localized: "A mushroom or toadstool on the forest floor"),
                String(localized: "Bracket (shelf) fungi on a tree trunk"),
                String(localized: "Mold on old bread or fruit"),
                String(localized: "Lichen crusting a rock (a fungus-and-alga team)"),
                String(localized: "A puffball or a ring of mushrooms in grass"),
            ],
            catchTip: String(localized: "Look low and in the damp — after rain, check shady soil, rotting logs, and tree bases, and shoot from the side to capture cap, stem, and gills together.")),
        .init(
            realm: .protists, name: String(localized: "Protists"), tagline: String(localized: "The microscopic everything-else."),
            whatIsIt: String(localized: "Protists are the grab-bag category — a catch-all for tiny, often single-celled life that isn't quite an animal, plant, or fungus. They're not one tidy family tree but many unrelated lineages lumped together for convenience. Living in any water, some swim and hunt like animals, some photosynthesize like plants, and some do a bit of both."),
            examples: [
                String(localized: "Green pond scum or algae on still water"),
                String(localized: "Seaweed on the beach (large algae — some closer to plants)"),
                String(localized: "A slimy film on a fish tank or birdbath"),
                String(localized: "\"Sea sparkle\" or a colored algal bloom"),
                String(localized: "Slime mold creeping across a damp log"),
            ],
            catchTip: String(localized: "Most protists are too small to shoot alone, so aim for the crowd — a green scummy pond edge, a mat of seaweed, or a slime mold — where millions gather into something your camera can see.")),
        .init(
            realm: .other, name: String(localized: "Other"), tagline: String(localized: "Life beyond the big four."),
            whatIsIt: String(localized: "This realm holds life that doesn't fit the others — chiefly bacteria and archaea, single cells so simple they don't even keep their DNA in a nucleus, yet the most abundant and ancient life on Earth. It also gathers the oddballs, like viruses, which sit right on the blurry border of \"alive.\" You mostly meet these as colonies or their handiwork."),
            examples: [
                String(localized: "Slimy biofilm or \"scum\" on wet rocks and pipes"),
                String(localized: "Colorful bacterial mats around a hot spring"),
                String(localized: "Dental-plaque or pond-surface films"),
                String(localized: "Yogurt, cheese, or a sourdough starter"),
                String(localized: "A rust-colored or iridescent sheen on still water"),
            ],
            catchTip: String(localized: "You can't catch a single microbe, so photograph the visible evidence — a bacterial mat, a biofilm slick, or a fermented food — where countless cells add up to something you can see.")),
    ]

    static let rarityIntro = String(localized: "Every rarity badge in Living Dex is earned, never rolled — it's calculated from real biodiversity data: how densely a species actually shows up near you in the GBIF occurrence record, plus its official IUCN Red List conservation status. A creature's tier reflects how genuinely scarce it is in your corner of the world, so a rare badge means you found something honestly, verifiably hard to find.")

    static let rarityTiers: [RarityInfo] = [
        .init(rarity: .common, meaning: String(localized: "Backed by 1,000 or more local records, a Common is a neighbor you share your patch of Earth with daily — abundant, thriving, the friendly backbone of your local ecosystem.")),
        .init(rarity: .uncommon, meaning: String(localized: "With 200-plus local records, an Uncommon is a familiar-but-not-guaranteed find — present in your area, yet one you have to go looking for rather than stumble upon.")),
        .init(rarity: .rare, meaning: String(localized: "Earned when a species has only around 20-plus local records, a Rare is a genuine local scarcity — a sighting most people in your region will go a long time without making.")),
        .init(rarity: .epic, meaning: String(localized: "Reserved for species with fewer than 20 local records — or a vagrant that has wandered clear outside its normal range — an Epic is an ecological surprise, the right creature in a place it has almost no business being.")),
        .init(rarity: .legendary, meaning: String(localized: "Unlocked only by species the IUCN flags as threatened — Vulnerable, Endangered, or Critically Endangered — or the even graver Extinct in the Wild: a precious encounter with a life form the world has already nearly lost, or is at risk of losing forever.")),
    ]

    static let concepts: [Concept] = [
        .init(
            title: String(localized: "How identification works"),
            body: String(localized: "A vision AI looks at your photo and proposes a species with a confidence score. Living Dex then verifies that name against GBIF and rejects anything that isn't a real, accepted species. The photo is sent only when you identify, over an encrypted connection, and is used only for that — it needs a connection.")),
        .init(
            title: String(localized: "Credits & Pro"),
            body: String(localized: "Each identification costs one credit, even when the AI finds nothing clear. Every device starts with 30 free; after that you can buy a credit pack or go Pro for unlimited identifications. Browsing your Dex, Nearby and field entries is always free.")),
        .init(
            title: String(localized: "Regional (Nearby) Dex"),
            body: String(localized: "Your personal checklist of species that realistically occur near your location, built from real occurrence records. Uncaught species appear as locked silhouettes; catching one in the wild reveals its full entry. It's a map of what you could find, not just what you have.")),
        .init(
            title: String(localized: "Confidence"),
            body: String(localized: "Every identification carries a confidence level — how sure the model is about the match. A low-confidence result isn't added to your Dex: you'll be asked for a clearer, closer shot, so your collection holds answers rather than guesses.")),
        .init(
            title: String(localized: "Where the data comes from"),
            body: String(localized: "Living Dex is built on real science, not invented facts. Species lists, ranges, and fact-sheets come from GBIF. Animal calls and photos come from Wikimedia Commons and Xeno-canto. Field entries are written by on-device AI where your phone supports it (by cloud AI for Pro members), otherwise they quote the sourced Wikipedia summary — the facts underneath are always sourced.")),
    ]
}
