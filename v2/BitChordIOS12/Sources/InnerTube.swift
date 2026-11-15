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

    /// The next page token from the last `search` response, when YouTube Music
    /// supplied one. Cleared by a new query.
    private(set) var searchContinuation: String?

    /// The current query and the web client's continuation, used when the
    /// WEB_REMIX search response carries no token of its own. YouTube's web
    /// results page still paginates, so Load more stays real instead of
    /// silently stopping after the first 20 rows.
    private var webQuery: String?
    private var webContinuation: String?
    private var webClientVersion = "2.20261112.10.00"

    /// Whether the current search has another page, including the web fallback
    /// when WEB_REMIX itself returns no token.
    var canLoadMoreSearch: Bool {
        return (searchContinuation?.isEmpty == false) || (webQuery != nil)
    }

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
        searchContinuation = nil
        webContinuation = nil
        webQuery = trimmed
        post(path: "search", body: body, userAgent: InnerTube.browserUserAgent) { json, error in
            guard let json = json else {
                completion(nil, error ?? "Search failed.")
                return
            }
            let tracks = self.parseSearch(json)
            self.searchContinuation = self.continuationToken(in: json)
            if tracks.isEmpty {
                completion(nil, "No results for \"\(trimmed)\".")
            } else {
                completion(tracks, nil)
            }
        }
    }

    /// The next page of the current search. The caller appends the rows; this
    /// only advances the token so a repeated call cannot loop on the same page.
    func searchNext(completion: @escaping ([Track]?, Bool, String?) -> Void) {
        guard let token = searchContinuation, !token.isEmpty else {
            if let query = webQuery {
                fetchWebSearchNext(query: query, completion: completion)
            } else {
                completion([], false, nil)
            }
            return
        }
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20241011.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "continuation": token
        ]
        post(path: "search", body: body, userAgent: InnerTube.browserUserAgent) { [weak self] json, error in
            guard let self = self else { return }
            guard let json = json else {
                completion(nil, self.searchContinuation != nil, error ?? "Search page failed.")
                return
            }
            let tracks = self.parseSearch(json)
            self.searchContinuation = self.continuationToken(in: json)
            completion(tracks, self.searchContinuation != nil, nil)
        }
    }

    private func continuationToken(in node: Any) -> String? {
        // Filter chips also carry a continuationCommand. Only the explicit
        // continuationItemRenderer belongs to the result shelf; using a chip's
        // token asks for a filter page and returns no rows.
        for item in renderers(named: "continuationItemRenderer", in: node) {
            if let command = item["continuationEndpoint"] as? [String: Any],
               let continuation = command["continuationCommand"] as? [String: Any],
               let token = continuation["token"] as? String, !token.isEmpty {
                return token
            }
        }
        return nil
    }

    /// First token anywhere in a web results document, where filter chips and
    /// the result shelf both expose one.
    private func anyContinuationToken(in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let command = dict["continuationCommand"] as? [String: Any],
               let token = command["token"] as? String, !token.isEmpty {
                return token
            }
            for (_, child) in dict {
                if let found = anyContinuationToken(in: child) { return found }
            }
        } else if let array = node as? [Any] {
            for child in array {
                if let found = anyContinuationToken(in: child) { return found }
            }
        }
        return nil
    }

    /// WEB_REMIX search currently returns a single shelf and no continuation.
    /// The regular YouTube results page still exposes a real continuation
    /// token; this fetches that page once, then asks the web search endpoint
    /// for the next page and maps its `videoRenderer` rows to tracks.
    private func fetchWebSearchNext(query: String,
                                    completion: @escaping ([Track]?, Bool, String?) -> Void) {
        if let token = webContinuation, !token.isEmpty {
            postWebContinuation(token, completion: completion)
            return
        }
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        var request = URLRequest(url: components.url!)
        request.setValue(InnerTube.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion(nil, false, error?.localizedDescription ?? "Search page failed.") }
                return
            }
            if let range = html.range(of: "INNERTUBE_CLIENT_VERSION\":\"") {
                let tail = html[range.upperBound...]
                if let end = tail.range(of: "\"") {
                    self.webClientVersion = String(tail[..<end.lowerBound])
                }
            }
            guard let start = html.range(of: "var ytInitialData = ")?.upperBound,
                  let end = html.range(of: ";</script>", range: start..<html.endIndex)?.lowerBound,
                  let jsonData = String(html[start..<end]).data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
                  let token = self.continuationToken(in: json) ?? self.anyContinuationToken(in: json) else {
                DispatchQueue.main.async { completion([], false, "No more search results.") }
                return
            }
            self.postWebContinuation(token, completion: completion)
        }.resume()
    }

    private func postWebContinuation(_ token: String,
                                     completion: @escaping ([Track]?, Bool, String?) -> Void) {
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": webClientVersion,
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "continuation": token
        ]
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(InnerTube.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            guard let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                DispatchQueue.main.async { completion(nil, self.webContinuation != nil, error?.localizedDescription ?? "Search page failed.") }
                return
            }
            let tracks = self.parseWebSearch(json)
            self.webContinuation = self.continuationToken(in: json)
            if self.webContinuation == nil { self.webQuery = nil }
            DispatchQueue.main.async {
                completion(tracks, self.webContinuation != nil, nil)
            }
        }.resume()
    }

    private func parseWebSearch(_ json: [String: Any]) -> [Track] {
        var output: [Track] = []
        var seen = Set<String>()
        for renderer in renderers(named: "videoRenderer", in: json) {
            guard let id = renderer["videoId"] as? String, id.count == 11,
                  !seen.contains(id) else { continue }
            let title = text(in: renderer["title"]) ?? ""
            guard !title.isEmpty else { continue }
            let artist = text(in: renderer["ownerText"])
                ?? text(in: renderer["longBylineText"])
                ?? "YouTube"
            let length = text(in: renderer["lengthText"])
            let thumbnails = value(renderer, ["thumbnail", "thumbnails"]) as? [[String: Any]]
            let artwork = (thumbnails?.last?["url"] as? String).flatMap(URL.init(string:))
            seen.insert(id)
            output.append(Track(videoID: id,
                                title: title,
                                artist: artist,
                                durationSeconds: length.flatMap(InnerTube.parseDuration),
                                artwork: artwork?.absoluteString))
        }
        return output
    }

    private func text(in node: Any?) -> String? {
        if let text = node as? String { return text }
        guard let dict = node as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
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
