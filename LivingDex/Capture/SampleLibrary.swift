import UIKit

/// A handful of bundled wildlife photos (CC0) that run through the real
/// identification pipeline — so anyone can see a catch without a creature in reach.
enum SampleLibrary {
    static let names = ["sample-robin", "sample-red-fox", "sample-fly-agaric", "sample-wood-anemone"]

    /// The sample at `index`, wrapping around the rotation.
    static func image(at index: Int, bundle: Bundle = .main) -> UIImage? {
        let name = names[((index % names.count) + names.count) % names.count]
        guard let url = bundle.url(forResource: name, withExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// The next sample in the rotation, advancing it so repeat taps show new species.
    static func next() -> UIImage? {
        let image = image(at: AppSettings.sampleCursor)
        AppSettings.sampleCursor += 1
        return image
    }
}
