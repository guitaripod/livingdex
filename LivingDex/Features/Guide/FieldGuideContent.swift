import Foundation

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

    static let introTitle = "Field Guide"
    static let introSubtitle = "How Living Dex works, and the real science behind every catch."

    static let steps: [Step] = [
        .init(
            symbol: "camera.viewfinder", title: "Point & catch",
            body: "Aim your camera at any living thing — a bird, a wildflower, a mushroom, a bug — and tap to catch. That's the whole action."),
        .init(
            symbol: "iphone", title: "Identified on your device",
            body: "An on-device AI names the species instantly, for free, and works offline. Nothing leaves your phone."),
        .init(
            symbol: "cloud", title: "Cloud ID for tricky ones",
            body: "If the on-device model isn't sure, Living Dex can ask a more powerful cloud AI for a confident answer. That uses one credit — and Pro members get unlimited cloud IDs."),
        .init(
            symbol: "square.grid.2x2", title: "Build your Dex",
            body: "Every confirmed catch is saved to your collection, sorted by realm — animals, plants, fungi, protists, and more — each with a rarity tier drawn from real ecological data."),
        .init(
            symbol: "location", title: "Explore your Nearby dex",
            body: "The Nearby tab is your regional Dex: every species that plausibly lives around you, shown as locked silhouettes. Catch one in the wild to reveal it."),
        .init(
            symbol: "book", title: "Earn a real field entry",
            body: "Each catch unlocks a full field entry — photos, calls, facts, and a written description — so your collection reads like a living field guide of what you've found."),
    ]

    static let realms: [RealmInfo] = [
        .init(
            realm: .animals, name: "Animals", tagline: "They move, eat, sense.",
            whatIsIt: "Animals are multicellular life that survives by eating other living things and, almost always, moving to find it. Unlike plants, they can't make food from sunlight, and unlike fungi, they digest meals inside their bodies. If it actively moves and responds fast to what's around it, it's very likely an animal — including insects, spiders, worms, and you.",
            examples: [
                "A pigeon, sparrow, or crow on the street",
                "A dog, cat, or squirrel in the neighborhood",
                "A honeybee or butterfly on a flower",
                "A ladybug, ant, or spider on a wall",
                "A snail, frog, or fish near water",
            ],
            catchTip: "Animals move, so be patient and steady — approach slowly, hold the frame on a resting bird or a working bee, and tap the moment it pauses."),
        .init(
            realm: .plants, name: "Plants", tagline: "They drink sunlight.",
            whatIsIt: "Plants make their own food out of thin air and light — photosynthesis, which pulls in sunlight, water, and carbon dioxide and turns them into sugar (giving off the oxygen we breathe). They're rooted in place, and their green comes from chlorophyll, the pigment doing that solar chemistry. Trees, mosses, ferns, and window-box flowers are all plants.",
            examples: [
                "A dandelion, daisy, or rose",
                "An oak, maple, or pine tree",
                "Grass, clover, or moss underfoot",
                "A fern or a houseplant on the sill",
                "A tomato, oak leaf, or pinecone",
            ],
            catchTip: "Plants hold still, so get close and fill the frame with one clear feature — a single flower, a distinct leaf, or bark — in good daylight for the sharpest ID."),
        .init(
            realm: .fungi, name: "Fungi", tagline: "Nature's hidden recyclers.",
            whatIsIt: "Fungi aren't plants — they can't photosynthesize, and they're actually closer cousins to animals than to anything green. A fungus digests food outside its body, releasing chemicals into dead wood, soil, or leaves and drinking the nutrients back in. The mushroom you see is just the fruiting body of a vast, thread-like network — the mycelium — hidden beneath.",
            examples: [
                "A mushroom or toadstool on the forest floor",
                "Bracket (shelf) fungi on a tree trunk",
                "Mold on old bread or fruit",
                "Lichen crusting a rock (a fungus-and-alga team)",
                "A puffball or a ring of mushrooms in grass",
            ],
            catchTip: "Look low and in the damp — after rain, check shady soil, rotting logs, and tree bases, and shoot from the side to capture cap, stem, and gills together."),
        .init(
            realm: .protists, name: "Protists", tagline: "The microscopic everything-else.",
            whatIsIt: "Protists are the grab-bag category — a catch-all for tiny, often single-celled life that isn't quite an animal, plant, or fungus. They're not one tidy family tree but many unrelated lineages lumped together for convenience. Living in any water, some swim and hunt like animals, some photosynthesize like plants, and some do a bit of both.",
            examples: [
                "Green pond scum or algae on still water",
                "Seaweed on the beach (large algae — some closer to plants)",
                "A slimy film on a fish tank or birdbath",
                "\"Sea sparkle\" or a colored algal bloom",
                "Slime mold creeping across a damp log",
            ],
            catchTip: "Most protists are too small to shoot alone, so aim for the crowd — a green scummy pond edge, a mat of seaweed, or a slime mold — where millions gather into something your camera can see."),
        .init(
            realm: .other, name: "Other", tagline: "Life beyond the big four.",
            whatIsIt: "This realm holds life that doesn't fit the others — chiefly bacteria and archaea, single cells so simple they don't even keep their DNA in a nucleus, yet the most abundant and ancient life on Earth. It also gathers the oddballs, like viruses, which sit right on the blurry border of \"alive.\" You mostly meet these as colonies or their handiwork.",
            examples: [
                "Slimy biofilm or \"scum\" on wet rocks and pipes",
                "Colorful bacterial mats around a hot spring",
                "Dental-plaque or pond-surface films",
                "Yogurt, cheese, or a sourdough starter",
                "A rust-colored or iridescent sheen on still water",
            ],
            catchTip: "You can't catch a single microbe, so photograph the visible evidence — a bacterial mat, a biofilm slick, or a fermented food — where countless cells add up to something you can see."),
    ]

    static let rarityIntro = "Every rarity badge in Living Dex is earned, never rolled — it's calculated from real biodiversity data: how densely a species actually shows up near you in the GBIF occurrence record, plus its official IUCN Red List conservation status. A creature's tier reflects how genuinely scarce it is in your corner of the world, so a rare badge means you found something honestly, verifiably hard to find."

    static let rarityTiers: [RarityInfo] = [
        .init(rarity: .common, meaning: "Backed by 1,000 or more local records, a Common is a neighbor you share your patch of Earth with daily — abundant, thriving, the friendly backbone of your local ecosystem."),
        .init(rarity: .uncommon, meaning: "With 200-plus local records, an Uncommon is a familiar-but-not-guaranteed find — present in your area, yet one you have to go looking for rather than stumble upon."),
        .init(rarity: .rare, meaning: "Earned when a species has only around 20-plus local records, a Rare is a genuine local scarcity — a sighting most people in your region will go a long time without making."),
        .init(rarity: .epic, meaning: "Reserved for species with fewer than 20 local records — or a vagrant that has wandered clear outside its normal range — an Epic is an ecological surprise, the right creature in a place it has almost no business being."),
        .init(rarity: .legendary, meaning: "Unlocked only by species the IUCN flags as threatened — Vulnerable, Endangered, or Critically Endangered — or the even graver Extinct in the Wild: a precious encounter with a life form the world has already nearly lost, or is at risk of losing forever."),
    ]

    static let concepts: [Concept] = [
        .init(
            title: "On-device ID vs Cloud ID",
            body: "On-device ID runs a compact AI model right on your phone: free, private, offline, instant. Cloud ID is a heavier vision model (Claude, via our backend) we fall back to only when the on-device model isn't confident — more accurate on hard cases, but it needs a connection and costs one credit."),
        .init(
            title: "Credits & Pro",
            body: "A cloud ID costs one credit. Free users get a metered allowance and can buy consumable credit packs; a Pro subscription removes the meter entirely — unlimited cloud IDs. On-device IDs are always free and never touch your credits."),
        .init(
            title: "Regional (Nearby) Dex",
            body: "Your personal checklist of species that realistically occur near your location, built from real occurrence records. Uncaught species appear as locked silhouettes; catching one in the wild reveals its full entry. It's a map of what you could find, not just what you have."),
        .init(
            title: "Confidence",
            body: "Every identification carries a confidence level — how sure the model is about the match. High-confidence catches straight away; low confidence is what triggers the optional cloud-ID fallback, so you get a reliable answer instead of a guess."),
        .init(
            title: "Where the data comes from",
            body: "Living Dex is built on real science, not invented facts. Species lists, ranges, and fact-sheets come from GBIF. Animal calls and photos come from Wikimedia Commons and Xeno-canto. The entry text is AI-written but grounded in those real fact-sheets — the AI phrases the story; the facts underneath are sourced."),
    ]
}
