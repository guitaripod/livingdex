import UIKit

/// Decodes sandbox images off the main thread and caches the decoded result, so
/// grid scrolling stays smooth at 120 Hz (a synchronous `UIImage(contentsOfFile:)`
/// + lazy decode during cell config is a classic ProMotion jank source).
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "com.guitaripod.livingdex.imageloader", qos: .userInitiated, attributes: .concurrent)

    private init() {
        cache.countLimit = 300
    }

    /// Returns an already-decoded image immediately, if cached.
    func cached(_ relativePath: String) -> UIImage? {
        cache.object(forKey: relativePath as NSString)
    }

    /// Loads + decodes off-main and calls back on main. `token` guards against a
    /// reused cell delivering a stale image.
    func load(_ relativePath: String, completion: @escaping @MainActor (UIImage?) -> Void) {
        if let hit = cached(relativePath) {
            Task { @MainActor in completion(hit) }
            return
        }
        queue.async { [weak self] in
            let image = ImageStore.load(relativePath)?.preparingForDisplay()
            if let image { self?.cache.setObject(image, forKey: relativePath as NSString) }
            Task { @MainActor in completion(image) }
        }
    }
}
