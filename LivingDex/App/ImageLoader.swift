import ImageIO
import UIKit

/// Decodes sandbox images off the main thread as *downscaled* thumbnails and
/// caches the result, so grid scrolling stays smooth at 120 Hz and memory stays
/// bounded. Captures are stored at full camera resolution (~12MP ≈ 46MB decoded);
/// the Dex grid only ever needs a small tile, so we thumbnail via ImageIO rather
/// than resident-decoding the full bitmap, and cap the cache by byte cost.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "com.guitaripod.livingdex.imageloader", qos: .userInitiated, attributes: .concurrent)

    /// Long-edge pixel budget for a grid tile — a third-of-screen cell at 3× on
    /// the largest current iPhone, with headroom for aspect-fill cropping.
    private let thumbnailMaxPixel: CGFloat = 600

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// Returns an already-decoded thumbnail immediately, if cached.
    func cached(_ relativePath: String) -> UIImage? {
        cache.object(forKey: cacheKey(relativePath))
    }

    /// Loads + downsamples off-main and calls back on main. `token` (caller side)
    /// guards against a reused cell delivering a stale image.
    func load(_ relativePath: String, completion: @escaping @MainActor (UIImage?) -> Void) {
        if let hit = cached(relativePath) {
            Task { @MainActor in completion(hit) }
            return
        }
        queue.async { [weak self] in
            guard let self else {
                Task { @MainActor in completion(nil) }
                return
            }
            let image = self.decodeThumbnail(relativePath)
            if let image { self.store(image, for: relativePath) }
            Task { @MainActor in completion(image) }
        }
    }

    private func cacheKey(_ relativePath: String) -> NSString {
        "\(relativePath)@\(Int(thumbnailMaxPixel))" as NSString
    }

    private func store(_ image: UIImage, for relativePath: String) {
        let cost = image.cgImage.map { $0.width * $0.height * 4 }
            ?? Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: cacheKey(relativePath), cost: cost)
    }

    /// Decodes a downscaled thumbnail (≈`thumbnailMaxPixel` on the long edge)
    /// straight from the file via ImageIO, so a grid cell never holds a full-
    /// resolution bitmap and the decode cost scales with the tile, not the capture.
    private func decodeThumbnail(_ relativePath: String) -> UIImage? {
        guard let url = fileURL(relativePath),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func fileURL(_ relativePath: String) -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        return support.appendingPathComponent(relativePath)
    }
}
