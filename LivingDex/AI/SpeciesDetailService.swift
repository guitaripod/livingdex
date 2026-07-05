import AVFoundation
import Foundation

/// A playable, commercial-safe recording of a species' call ("cry").
struct SpeciesCall: Sendable {
    var url: URL
    var recordist: String?
    var license: String?
    var source: String

    var attribution: String {
        var parts = [source]
        if let recordist, !recordist.isEmpty { parts.append(recordist) }
        if let license, !license.isEmpty { parts.append(license) }
        return parts.joined(separator: " · ")
    }
}

/// Fetches card-detail extras (currently the species "call") from the domain
/// Worker's `/v1/detail`, and streams the audio on demand. Best-effort — most
/// species simply have no safe recording.
final class SpeciesDetailService: NSObject, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private var player: AVPlayer?

    init(baseURL: URL = Secrets.workerBaseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        self.session = URLSession(configuration: config)
    }

    func call(scientificName: String) async -> SpeciesCall? {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("v1/detail"), resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "name", value: scientificName)]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(DetailResponse.self, from: data)
            guard let c = decoded.call, let u = URL(string: c.url) else { return nil }
            return SpeciesCall(url: u, recordist: c.recordist, license: c.license, source: c.source)
        } catch {
            return nil
        }
    }

    /// Plays the call over the speaker even if the ring switch is silent — the
    /// user tapped play, so it's a deliberate, expected sound.
    @MainActor func play(_ call: SpeciesCall) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = AVPlayer(url: call.url)
        player?.play()
        AppLogger.shared.info("playing call from \(call.source)", category: .ai)
    }

    private struct DetailResponse: Decodable {
        var call: Call?
        struct Call: Decodable { var url: String; var recordist: String?; var license: String?; var source: String }
    }
}
