import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Presents the system photo picker (no Photos permission needed — the player only
/// shares the one photo they choose) and hands back a bounded-size, correctly
/// oriented image.
@MainActor
final class PhotoImporter: NSObject, PHPickerViewControllerDelegate {
    private static let maxPixel: CGFloat = 2048

    private let onImage: (UIImage) -> Void
    private let onFailure: () -> Void

    init(onImage: @escaping (UIImage) -> Void, onFailure: @escaping () -> Void) {
        self.onImage = onImage
        self.onFailure = onFailure
    }

    func present(from presenter: UIViewController) {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let provider = results.first?.itemProvider else {
            Task { @MainActor in picker.dismiss(animated: true) }
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
            let image = url.flatMap { ImageDownsampler.image(at: $0, maxPixel: Self.maxPixel) }
            Task { @MainActor in
                picker.dismiss(animated: true) {
                    if let image { self.onImage(image) } else { self.onFailure() }
                }
            }
        }
    }
}

/// The "identify a photo instead" choices, shared by the Field HUD and the camera
/// gate so both offer exactly the same two paths.
@MainActor
enum PhotoSourceMenu {
    static func make(onLibrary: @escaping @MainActor () -> Void, onSample: @escaping @MainActor () -> Void) -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Choose from Photos", image: UIImage(systemName: "photo.on.rectangle")) { _ in onLibrary() },
            UIAction(title: "Try a sample photo", image: UIImage(systemName: "sparkles")) { _ in onSample() },
        ])
    }
}
