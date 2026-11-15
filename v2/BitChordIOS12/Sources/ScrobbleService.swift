import Foundation
import CommonCrypto

/// Last.fm and ListenBrainz scrobbling, ported from upstream's
/// `ScrobbleManager`, `LastFM` and `ListenBrainzManager`.
///
/// Upstream starts a wall-clock timer with a pause/resume budget. The web
/// player already reports playback position, so this port uses the position
/// directly: a song is scrobbled once it passes half its length, capped at
/// upstream's four-minute threshold. That is the same rule and it survives
/// seeking, buffering and background playback.
final class ScrobbleService {
    static let shared = ScrobbleService()

    private let settings = SettingsStore.shared
    private var currentTrack: Track?
    private var startedAt = Date()
    private var scrobbled = false

    private init() {}

    // MARK: - Playback hooks

    func trackDidStart(_ track: Track) {
        currentTrack = track
        startedAt = Date()
        scrobbled = false
        submitLastFMNowPlaying(track)
        submitListenBrainzNowPlaying(track)
    }

    func trackDidAdvance(position: Double, duration: Double) {
        guard let track = currentTrack, !scrobbled else { return }
        let length = duration > 0 ? duration : (track.durationSeconds ?? 0)
        let minimum = settings.double("BitChord.LastFm.MinDuration", 30)
        guard length >= minimum else { return }
        let percent = settings.double("BitChord.LastFm.DelayPercent", 50) / 100
        let cap = settings.double("BitChord.LastFm.DelayCap", 180)
        let threshold = min(length * percent, cap)
        guard position >= threshold else { return }
        scrobbled = true
        submitScrobble(track, position: position, duration: length)
    }

    func trackDidStop() {
        currentTrack = nil
        scrobbled = false
    }

    // MARK: - Settings

    private var lastFMEnabled: Bool {
        return settings.bool("BitChord.LastFm.Enabled", false)
    }

    private var lastFMNowPlaying: Bool {
        return settings.bool("BitChord.LastFm.NowPlaying", true)
    }

    private var lastFMPrimaryArtistOnly: Bool {
        return settings.bool("BitChord.LastFm.PrimaryArtistOnly", false)
    }

    private var lastFMKey: String {
        return settings.string("BitChord.LastFm.ApiKey", "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var lastFMSecret: String {
        return settings.string("BitChord.LastFm.Secret", "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var lastFMSession: String {
        return settings.string("BitChord.LastFm.SessionKey", "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var lastFMEndpoint: String {
        let value = settings.string("BitChord.LastFm.Endpoint", "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "https://ws.audioscrobbler.com/2.0/" : value
    }

    private var listenBrainzEnabled: Bool {
        return settings.bool("BitChord.ListenBrainz.Enabled", false)
    }

    private var listenBrainzToken: String {
        return settings.string("BitChord.ListenBrainz.Token", "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var listenBrainzPrimaryArtistOnly: Bool {
        return settings.bool("BitChord.ListenBrainz.PrimaryArtistOnly", false)
    }

    private func artist(for track: Track, primaryOnly: Bool) -> String {
        guard primaryOnly else { return track.artist }
        // YouTube Music credits are usually comma-separated. Upstream's
        // `primaryArtist()` takes the first credit, not the whole string.
        let separators = CharacterSet(charactersIn: ",&")
        let first = track.artist.components(separatedBy: separators).first ?? track.artist
        let featured = first.components(separatedBy: " feat.").first
            ?? first.components(separatedBy: " ft.").first
            ?? first
        return featured.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Last.fm

    private func submitLastFMNowPlaying(_ track: Track) {
        guard lastFMEnabled, lastFMNowPlaying,
              !lastFMKey.isEmpty, !lastFMSecret.isEmpty, !lastFMSession.isEmpty else { return }
        var extra: [String: String] = [
            "artist": artist(for: track, primaryOnly: lastFMPrimaryArtistOnly),
            "track": track.title
        ]
        if !track.album.isEmpty { extra["album"] = track.album }
        if let duration = track.durationSeconds, duration > 0 {
            extra["duration"] = String(Int(duration))
        }
        lastFMRequest(method: "track.updateNowPlaying", extra: extra) { _ in }
    }

    private func submitScrobble(_ track: Track, position: Double, duration: Double) {
        if lastFMEnabled, !lastFMKey.isEmpty, !lastFMSecret.isEmpty, !lastFMSession.isEmpty {
            let timestamp = String(Int(startedAt.timeIntervalSince1970))
            var extra: [String: String] = [
                "artist[0]": artist(for: track, primaryOnly: lastFMPrimaryArtistOnly),
                "track[0]": track.title,
                "timestamp[0]": timestamp,
                "duration[0]": String(Int(duration))
            ]
            if !track.album.isEmpty { extra["album[0]"] = track.album }
            lastFMRequest(method: "track.scrobble", extra: extra) { _ in }
        }
        submitListenBrainz(track, position: position, duration: duration)
    }

    private func lastFMRequest(method: String,
                               extra: [String: String],
                               completion: @escaping (Bool) -> Void) {
        var params: [String: String] = [
            "method": method,
            "api_key": lastFMKey,
            "sk": lastFMSession
        ]
        for (key, value) in extra { params[key] = value }

        let signature = params.sorted { $0.key < $1.key }
            .map { $0.key + $0.value }
            .joined() + lastFMSecret
        params["api_sig"] = md5(signature)
        params["format"] = "json"

        guard let url = URL(string: lastFMEndpoint) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("BitChord for iOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpBody = params.map { key, value in
            "\(percentEncode(key))=\(percentEncode(value))"
        }.joined(separator: "&").data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status >= 200, status < 300, let data = data else {
                completion(false)
                return
            }
            // Last.fm reports API failures inside a 200 response.
            if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               root["error"] != nil {
                completion(false)
                return
            }
            completion(true)
        }.resume()
    }

    private func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// CommonCrypto is present on iOS 12; CryptoKit is not.
    private func md5(_ value: String) -> String {
        let data = Data(value.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - ListenBrainz

    private func submitListenBrainzNowPlaying(_ track: Track) {
        guard listenBrainzEnabled, !listenBrainzToken.isEmpty else { return }
        var metadata: [String: Any] = [
            "artist_name": artist(for: track, primaryOnly: listenBrainzPrimaryArtistOnly),
            "track_name": track.title,
            "additional_info": [
                "submission_client": "BitChord",
                "position_ms": 0
            ]
        ]
        if !track.album.isEmpty { metadata["release_name"] = track.album }
        if let duration = track.durationSeconds, duration > 0 {
            var info = metadata["additional_info"] as? [String: Any] ?? [:]
            info["duration_ms"] = Int(duration * 1000)
            metadata["additional_info"] = info
        }
        let payload: [String: Any] = [
            "listen_type": "playing_now",
            "payload": [["track_metadata": metadata]]
        ]
        listenBrainzRequest(payload)
    }

    private func submitListenBrainz(_ track: Track, position: Double, duration: Double) {
        guard listenBrainzEnabled, !listenBrainzToken.isEmpty else { return }
        let started = Int(startedAt.timeIntervalSince1970)
        let durationMS = Int(duration * 1000)
        var metadata: [String: Any] = [
            "artist_name": artist(for: track, primaryOnly: listenBrainzPrimaryArtistOnly),
            "track_name": track.title,
            "additional_info": [
                "submission_client": "BitChord",
                "duration_ms": durationMS,
                "position_ms": Int(position * 1000)
            ]
        ]
        if !track.album.isEmpty { metadata["release_name"] = track.album }
        let payload: [String: Any] = [
            "listen_type": "single",
            "payload": [[
                "listened_at": started,
                "track_metadata": metadata
            ]]
        ]
        listenBrainzRequest(payload)
    }

    private func listenBrainzRequest(_ payload: [String: Any]) {
        guard let url = URL(string: "https://api.listenbrainz.org/1/submit-listens"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Token \(listenBrainzToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
}
