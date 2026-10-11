import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Presents the system photo picker (no Photos permission needed — the player only
/// shares the one photo they choose) and hands back a bounded-size, correctly
/// oriented image.
@MainActor
final class PhotoImporter: NSObject, PHPickerViewControllerDelegate {
    private static let maxPixel: CGFloat = 2048

    private let onImage: @MainActor @Sendable (UIImage) -> Void
    private let onBegin: @MainActor @Sendable () -> Void
    private let onFailure: @MainActor @Sendable () -> Void

    init(
        onImage: @escaping @MainActor @Sendable (UIImage) -> Void,
        onBegin: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onImage = onImage
        self.onBegin = onBegin
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

    /// Dismisses the picker at once (so a slow iCloud original can't be picked twice), then
    /// loads the one chosen photo and hands it over only after the picker is gone.
    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        nonisolated(unsafe) let provider = results.first?.itemProvider
        MainActor.assumeIsolated {
            picker.dismiss(animated: true) { [self] in
                guard let provider else { return }
                onBegin()
                load(provider)
            }
        }
    }

    private func load(_ provider: NSItemProvider) {
        let onImage = onImage
        let onFailure = onFailure
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
            let image = url.flatMap { ImageDownsampler.image(at: $0, maxPixel: Self.maxPixel) }
            Task { @MainActor in
                if let image { onImage(image) } else { onFailure() }
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
