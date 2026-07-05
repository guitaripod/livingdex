import UIKit

/// Persists captured images to the app sandbox and returns a stable relative
/// path stored on the sighting. Files live under Application Support/images.
enum ImageStore {
    private static let directoryName = "images"

    private static func directory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ image: UIImage, id: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            let name = "\(id).jpg"
            let url = try directory().appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return "\(directoryName)/\(name)"
        } catch {
            AppLogger.shared.error("image save failed: \(error)", category: .persistence)
            return nil
        }
    }

    static func load(_ relativePath: String) -> UIImage? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        let url = support.appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: url.path)
    }
}
