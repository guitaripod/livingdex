import LivingDexCore
import UIKit

/// The bundled wildlife photos (CC0) behind "Try a sample photo": the four starter species, so a
/// sample always knows what it shows. It is answered on the device and never reaches the cloud,
/// spends a free identification or needs the cloud consent, so it works for anyone at any time.
enum SampleLibrary {
    static let names = ["sample-robin", "sample-red-fox", "sample-fly-agaric", "sample-wood-anemone"]

    /// A sample photo with the species it shows.
    struct Sample {
        let image: UIImage
        let species: StarterSpecies
    }

    /// The sample at `index`, wrapping around the rotation.
    static func image(at index: Int, bundle: Bundle = .main) -> UIImage? {
        image(named: name(at: index), bundle: bundle)
    }

    /// A bundled photo by resource name.
    static func image(named name: String, bundle: Bundle = .main) -> UIImage? {
        guard let url = bundle.url(forResource: name, withExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// The sample at `index` with its species, wrapping around the rotation.
    static func sample(at index: Int, bundle: Bundle = .main) -> Sample? {
        let name = name(at: index)
        guard let species = StarterCatalog.all.first(where: { $0.photoResource == name }),
              let image = image(named: name, bundle: bundle) else { return nil }
        return Sample(image: image, species: species)
    }

    /// The next sample in the rotation, advancing it so repeat taps show new species.
    static func next() -> Sample? {
        let sample = sample(at: AppSettings.sampleCursor)
        AppSettings.sampleCursor += 1
        return sample
    }

    private static func name(at index: Int) -> String {
        names[((index % names.count) + names.count) % names.count]
    }
}

/// The identifier of a photo whose species is already known: a bundled sample.
struct KnownSpeciesIdentifier: SpeciesIdentifier {
    let candidate: SpeciesCandidate

    func identify(_ image: UIImage, context: CaptureContext) async -> IdentificationResult {
        IdentificationResult(candidates: [candidate])
    }
}
