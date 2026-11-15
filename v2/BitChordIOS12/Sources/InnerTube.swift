import Foundation

/// Thin client for the YouTube Music InnerTube endpoints.
///
/// The `search` request shape here was verified against the live API: a POST to
/// `/youtubei/v1/search` with the WEB_REMIX client returns `musicResponsiveListItemRenderer`
/// nodes that carry the video id, title, artist and duration.
final class InnerTube {
    static let shared = InnerTube()

    static let browserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    private let session: URLSession
    private let endpoint = URL(string: "https://music.youtube.com/youtubei/v1/")!

    private struct ClientConfig {
        let name: String
        let version: String
        let userAgent: String
        let extras: [String: Any]
    }

    /// Tried in order when resolving a playable audio URL. YouTube gates most anonymous
    /// clients behind a sign-in/bot check, so several are attempted before giving up.
    private let clients: [ClientConfig] = [
        // Measured against the live endpoint: this client is the one that still returns direct
        // stream URLs without a cipher or a PO token, and it offers AAC in MP4 — the format
        // AVPlayer decodes natively on iOS 12. The ordinary Android and iOS clients answer
        // HTTP 400 and the web clients answer UNPLAYABLE, so this is tried first.
        ClientConfig(
            name: "ANDROID_VR",
            version: "1.60.19",
            userAgent: "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
            extras: [
                "androidSdkVersion": 32,
                "deviceMake": "Oculus",
                "deviceModel": "Quest 3",
                "osName": "Android",
                "osVersion": "12L"
            ]
        ),
        ClientConfig(
            name: "ANDROID_MUSIC",
            version: "6.42.55",
            userAgent: "com.google.android.apps.youtube.music/6.42.55 (Linux; U; Android 11; en_US)",
            extras: ["androidSdkVersion": 30]
        ),
        ClientConfig(
            name: "IOS",
            version: "19.45.4",
            userAgent: "com.google.ios.youtube/19.45.4 (iPhone14,3; U; CPU iOS 17_0 like Mac OS X)",
            extras: [
                "deviceMake": "Apple",
                "deviceModel": "iPhone14,3",
                "osName": "iPhone",
                "osVersion": "17.0.0.20A362"
            ]
        ),
        ClientConfig(
            name: "WEB_REMIX",
            version: "1.20241011.01.00",
            userAgent: InnerTube.browserUserAgent,
            extras: [:]
        )
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        session = URLSession(configuration: config)
    }

    // MARK: - Search

    func search(_ query: String,
                filter: SearchFilter? = nil,
                completion: @escaping ([Track]?, String?) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion([], nil)
            return
        }
        var body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20241011.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "query": trimmed
        ]
        if let params = filter?.params {
            body["params"] = params
        }
        post(path: "search", body: body, userAgent: InnerTube.browserUserAgent) { json, error in
            guard let json = json else {
                completion(nil, error ?? "Search failed.")
                return
            }
            let tracks = self.parseSearch(json)
            if tracks.isEmpty {
                completion(nil, "No results for \"\(trimmed)\".")
            } else {
                completion(tracks, nil)
            }
        }
    }

    // MARK: - Stream resolution

    func resolveStreamURL(videoID: String, completion: @escaping (URL?, String) -> Void) {
        attempt(index: 0, videoID: videoID, lastReason: "No audio source available.", completion: completion)
    }

    private func attempt(index: Int,
                         videoID: String,
                         lastReason: String,
                         completion: @escaping (URL?, String) -> Void) {
        guard index < clients.count else {
            completion(nil, lastReason)
            return
        }
        let client = clients[index]
        var clientContext: [String: Any] = [
            "clientName": client.name,
            "clientVersion": client.version,
            "hl": "en",
            "gl": "US"
        ]
        for (key, value) in client.extras {
            clientContext[key] = value
        }
        let body: [String: Any] = [
            "context": ["client": clientContext],
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        post(path: "player", body: body, userAgent: client.userAgent) { [weak self] json, error in
            guard let self = self else { return }
            guard let json = json else {
                self.attempt(index: index + 1,
                             videoID: videoID,
                             lastReason: error ?? lastReason,
                             completion: completion)
                return
            }
            if let url = self.bestAudioURL(in: json) {
                completion(url, "")
                return
            }
            let status = (self.value(json, ["playabilityStatus", "status"]) as? String) ?? ""
            let reason = (self.value(json, ["playabilityStatus", "reason"]) as? String) ?? ""
            let detail: String
            if status == "LOGIN_REQUIRED" || status == "UNPLAYABLE" {
                detail = "YouTube is blocking anonymous playback (\(client.name)). Add a source in Settings."
            } else if !reason.isEmpty {
                detail = "\(reason) (\(client.name))"
            } else {
                detail = "No audio stream returned (\(client.name))."
            }
            self.attempt(index: index + 1,
                         videoID: videoID,
                         lastReason: detail,
                         completion: completion)
        }
    }

    private func bestAudioURL(in json: [String: Any]) -> URL? {
        guard let streaming = json["streamingData"] as? [String: Any] else { return nil }
        var formats: [[String: Any]] = []
        if let adaptive = streaming["adaptiveFormats"] as? [[String: Any]] {
            formats.append(contentsOf: adaptive)
        }
        if let progressive = streaming["formats"] as? [[String: Any]] {
            formats.append(contentsOf: progressive)
        }
        var bestScore = Int.min
        var bestURL: URL?
        for format in formats {
            guard let mime = format["mimeType"] as? String, mime.hasPrefix("audio/") else { continue }
            guard let raw = format["url"] as? String, let url = URL(string: raw) else { continue }
            let bitrate = (format["bitrate"] as? Int) ?? 0
            // AVFoundation plays AAC in MP4 far more reliably than Opus in WebM on iOS 12.
            let score = bitrate + (mime.contains("mp4") ? 10_000_000 : 0)
            if score > bestScore {
                bestScore = score
                bestURL = url
            }
        }
        return bestURL
    }

    // MARK: - Transport

    /// The signed-in profile: display name, email/handle and avatar.
    func accountMenu(completion: @escaping ([String: Any]?) -> Void) {
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20241011.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ]
        ]
        post(path: "account/account_menu", body: body, userAgent: InnerTube.browserUserAgent) { json, _ in
            completion(json)
        }
    }

    func post(path: String,
                      body: [String: Any],
                      userAgent: String,
                      completion: @escaping ([String: Any]?, String?) -> Void) {
        var payload = body
        if path != "player", let dataSyncId = GoogleAccountStore.shared.dataSyncId {
            var context = (payload["context"] as? [String: Any]) ?? [:]
            var user = (context["user"] as? [String: Any]) ?? ["lockedSafetyMode": false]
            user["onBehalfOfUser"] = dataSyncId
            context["user"] = user
            payload["context"] = context
        }
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        // Signed-in browsing is what makes the personal library and
        // age-restricted catalogue answer as this listener. Playback stays on
        // the anonymous clients, whose direct audio URLs are the ones that
        // work here; signing those changed the player response shape.
        if path != "player" {
            for (name, value) in GoogleAccountStore.shared.requestHeaders() {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            completion(nil, "Could not encode the request.")
            return
        }
        request.httpBody = data
        session.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(nil, error.localizedDescription)
                }
                return
            }
            guard let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(nil, "Unexpected response from YouTube Music.")
                }
                return
            }
            DispatchQueue.main.async {
                completion(json, nil)
            }
        }.resume()
    }

    // MARK: - Search response parsing

    func parseSearch(_ json: [String: Any]) -> [Track] {
        var songs: [Track] = []
        var others: [Track] = []
        var seen = Set<String>()
        for renderer in renderers(named: "musicResponsiveListItemRenderer", in: json) {
            guard let track = track(from: renderer) else { continue }
            if seen.contains(track.videoID) { continue }
            seen.insert(track.videoID)
            // A result's type is its own token in the metadata column: "Song",
            // "Video", "Episode", "Artist". Only Song rows are catalogue
            // recordings; the user-uploaded videos next to them have no match in
            // any streaming catalogue, so playing one is a guaranteed silence.
            if isSongRow(renderer) {
                songs.append(track)
            } else {
                others.append(track)
            }
        }
        return songs.isEmpty ? others : songs
    }

    private func isSongRow(_ renderer: [String: Any]) -> Bool {
        guard let columns = renderer["flexColumns"] as? [[String: Any]] else { return false }
        for column in columns {
            if columnSegments([column], index: 0).contains(where: { $0.lowercased() == "song" }) {
                return true
            }
        }
        return false
    }

    private func track(from renderer: [String: Any]) -> Track? {
        guard let videoID = videoID(in: renderer) else { return nil }
        let columns = (renderer["flexColumns"] as? [[String: Any]]) ?? []
        guard let title = columnText(columns, index: 0), !title.isEmpty else { return nil }
        let segments = columnSegments(columns, index: 1)
        // Song rows carry a play count where the video rows carry a length, so
        // the duration is often simply absent — left nil, and the row shows no
        // time rather than a wrong 0:00.
        return Track(
            videoID: videoID,
            title: title,
            artist: artistName(from: segments),
            durationSeconds: durationSeconds(from: segments) ?? fixedDuration(in: renderer)
        )
    }

    /// Some result layouts state the length in a right-hand fixed column.
    private func fixedDuration(in renderer: [String: Any]) -> Double? {
        guard let columns = renderer["fixedColumns"] as? [[String: Any]] else { return nil }
        for column in columns {
            guard let renderer = column["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
                  let text = renderer["text"] as? [String: Any] else { continue }
            let raw: String
            if let simple = text["simpleText"] as? String {
                raw = simple
            } else {
                raw = ((text["runs"] as? [[String: Any]]) ?? [])
                    .compactMap { $0["text"] as? String }.joined()
            }
            if let seconds = InnerTube.parseDuration(raw.trimmingCharacters(in: .whitespaces)) {
                return seconds
            }
        }
        return nil
    }

    private func videoID(in renderer: [String: Any]) -> String? {
        let direct = value(renderer, [
            "overlay", "musicItemThumbnailOverlayRenderer", "content",
            "musicPlayButtonRenderer", "playNavigationEndpoint", "watchEndpoint", "videoId"
        ]) as? String
        if let direct = direct, direct.count == 11 { return direct }

        var found: String?
        func walk(_ node: Any) {
            if found != nil { return }
            if let dict = node as? [String: Any] {
                if let watch = dict["watchEndpoint"] as? [String: Any],
                   let id = watch["videoId"] as? String, id.count == 11 {
                    found = id
                    return
                }
                for (_, child) in dict {
                    walk(child)
                }
            } else if let array = node as? [Any] {
                for child in array {
                    walk(child)
                }
            }
        }
        walk(renderer)
        return found
    }

    func columnText(_ columns: [[String: Any]], index: Int) -> String? {
        guard index < columns.count else { return nil }
        guard let text = value(columns[index], ["musicResponsiveListItemFlexColumnRenderer", "text"]) as? [String: Any] else {
            return nil
        }
        if let simple = text["simpleText"] as? String {
            let trimmed = simple.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let runs = (text["runs"] as? [[String: Any]]) ?? []
        let joined = runs.compactMap { $0["text"] as? String }.joined()
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func columnSegments(_ columns: [[String: Any]], index: Int) -> [String] {
        guard index < columns.count else { return [] }
        guard let text = value(columns[index], ["musicResponsiveListItemFlexColumnRenderer", "text"]) as? [String: Any] else {
            return []
        }
        var segments: [String] = []
        if let simple = text["simpleText"] as? String {
            segments.append(simple)
        }
        let runs = (text["runs"] as? [[String: Any]]) ?? []
        for run in runs {
            guard let raw = run["text"] as? String else { continue }
            for piece in raw.components(separatedBy: "\u{2022}") {
                let clean = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    segments.append(clean)
                }
            }
        }
        return segments
    }

    private func durationSeconds(from segments: [String]) -> Double? {
        for segment in segments {
            if let seconds = InnerTube.parseDuration(segment) {
                return seconds
            }
        }
        return nil
    }

    private func artistName(from segments: [String]) -> String {
        let noise: Set<String> = ["song", "video", "album", "playlist", "single", "ep", "mixtape", "podcast"]
        for segment in segments {
            let lower = segment.lowercased()
            if InnerTube.parseDuration(segment) != nil { continue }
            if lower.contains("view") || lower.contains("play") || lower.contains("like") { continue }
            if noise.contains(lower) { continue }
            if lower.range(of: "^\\d{4}$", options: .regularExpression) != nil { continue }
            if lower.contains("subscriber") { continue }
            return segment
        }
        return ""
    }

    private static func parseDuration(_ text: String) -> Double? {
        let pieces = text.split(separator: ":")
        guard pieces.count == 2 || pieces.count == 3 else { return nil }
        var total = 0.0
        for piece in pieces {
            guard let value = Double(String(piece)), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total > 0 ? total : nil
    }

    // MARK: - Generic JSON helpers

    func renderers(named name: String, in node: Any) -> [[String: Any]] {
        var output: [[String: Any]] = []
        func walk(_ current: Any) {
            if let dict = current as? [String: Any] {
                if let renderer = dict[name] as? [String: Any] {
                    output.append(renderer)
                }
                for (_, child) in dict {
                    walk(child)
                }
            } else if let array = current as? [Any] {
                for child in array {
                    walk(child)
                }
            }
        }
        walk(node)
        return output
    }

    private func value(_ node: Any?, _ path: [String]) -> Any? {
        var current: Any? = node
        for key in path {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[key]
        }
        return current
    }
}
