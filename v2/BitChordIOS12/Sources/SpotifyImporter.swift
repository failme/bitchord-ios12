import Foundation

/// One Spotify row, before it is matched to a YouTube Music song.
struct SpotifyImportTrack {
    let title: String
    let artist: String
}

/// A public Spotify playlist read from the embed page, as upstream's
/// `SpotifyImporter` does. No Spotify account or OAuth token is involved: the
/// embed page's `__NEXT_DATA__` carries the title and the first hundred rows,
/// and its anonymous web-player token pages through the rest.
enum SpotifyImporter {
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private static let embedTrackLimit = 100
    private static let pageSize = 100
    private static let pathfinderURL = "https://api-partner.spotify.com/pathfinder/v1/query"
    private static let fetchPlaylistHash = "19ff1327c29e99c208c86d7a9d8f1929cfdf3d3202a0ff4253c821f1901aa94d"

    /// A Spotify playlist id is 22 base-62 characters.
    private static let playlistIDPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9]{22}$")

    // MARK: - Link parsing

    /// Parses a raw link, URI or bare id into a playlist id.
    static func extractPlaylistID(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("spotify:playlist:") {
            var id = String(trimmed.dropFirst("spotify:playlist:".count))
            id = id.components(separatedBy: "?").first ?? id
            id = id.components(separatedBy: "/").first ?? id
            return isValidID(id) ? id : nil
        }

        // A bare id is convenient for users pasting one from the desktop app.
        if isValidID(trimmed) { return trimmed }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              host == "spotify.com" || host.hasSuffix(".spotify.com") else {
            return nil
        }
        let segments = components.path.split(separator: "/").map(String.init)
        guard let index = segments.firstIndex(of: "playlist"),
              index + 1 < segments.count else { return nil }
        let id = segments[index + 1]
        return isValidID(id) ? id : nil
    }

    private static func isValidID(_ id: String) -> Bool {
        let range = NSRange(location: 0, length: id.utf16.count)
        return playlistIDPattern.firstMatch(in: id, options: [], range: range) != nil
    }

    // MARK: - Playlist fetch

    static func fetchPlaylist(id: String,
                              completion: @escaping (String?, [SpotifyImportTrack], String?) -> Void) {
        guard let url = URL(string: "https://open.spotify.com/embed/playlist/\(id)") else {
            completion(nil, [], "That playlist link is not valid.")
            return
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(nil, [], "Could not reach Spotify: \(error.localizedDescription)")
                }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    completion(nil, [], "Could not load that Spotify playlist (HTTP \(status)).")
                }
                return
            }

            guard let script = nextDataScript(in: html),
                  let rootData = script.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: rootData)) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(nil, [], "Could not read the Spotify playlist. Make sure it is public.")
                }
                return
            }

            let props = (root["props"] as? [String: Any])?["pageProps"] as? [String: Any]
            let state = props?["state"] as? [String: Any]
            let entity = (state?["data"] as? [String: Any])?["entity"] as? [String: Any]
                ?? props?["entity"] as? [String: Any]
            guard let entity = entity else {
                DispatchQueue.main.async {
                    completion(nil, [], "That Spotify playlist is missing or private.")
                }
                return
            }

            let title = (entity["name"] as? String)
                ?? (entity["title"] as? String)
                ?? "Imported Spotify Playlist"
            let rows = (entity["trackList"] as? [[String: Any]])
                ?? (entity["tracks"] as? [[String: Any]])
                ?? []

            var tracks: [SpotifyImportTrack] = []
            for row in rows {
                guard let name = (row["title"] as? String) ?? (row["name"] as? String) else { continue }
                var artist = row["subtitle"] as? String ?? ""
                if artist.isEmpty, let artists = row["artists"] as? [[String: Any]] {
                    artist = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                }
                let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanName.isEmpty {
                    tracks.append(SpotifyImportTrack(title: cleanName,
                                                     artist: artist.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            guard !tracks.isEmpty else {
                DispatchQueue.main.async {
                    completion(nil, [], "No tracks were found in that public Spotify playlist.")
                }
                return
            }

            // The embed page stops at its first hundred rows. Its anonymous
            // token can page through the rest through the web player's own
            // pathfinder query; if that fails the first page still stands.
            if tracks.count >= embedTrackLimit,
               let token = (state?["settings"] as? [String: Any])
                    .flatMap({ $0["session"] as? [String: Any] })
                    .flatMap({ $0["accessToken"] as? String }) {
                fetchRemainingTracks(playlistID: id, token: token, start: tracks.count) { remaining in
                    var all = tracks
                    all.append(contentsOf: remaining)
                    DispatchQueue.main.async { completion(title, all, nil) }
                }
            } else {
                DispatchQueue.main.async { completion(title, tracks, nil) }
            }
        }.resume()
    }

    private static func nextDataScript(in html: String) -> String? {
        guard let open = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">") else {
            return nil
        }
        let rest = html[open.upperBound...]
        guard let close = rest.range(of: "</script>") else { return nil }
        return String(rest[..<close.lowerBound])
    }

    private static func fetchRemainingTracks(playlistID: String,
                                             token: String,
                                             start: Int,
                                             completion: @escaping ([SpotifyImportTrack]) -> Void) {
        var collected: [SpotifyImportTrack] = []
        var offset = start

        func page() {
            let variables = "{\"uri\":\"spotify:playlist:\(playlistID)\",\"offset\":\(offset),\"limit\":\(pageSize),\"enableWatchFeedEntrypoint\":false}"
            let extensions = "{\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"\(fetchPlaylistHash)\"}}"
            var components = URLComponents(string: pathfinderURL)!
            components.queryItems = [
                URLQueryItem(name: "operationName", value: "fetchPlaylist"),
                URLQueryItem(name: "variables", value: variables),
                URLQueryItem(name: "extensions", value: extensions)
            ]
            guard let url = components.url else {
                completion(collected)
                return
            }
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("WebPlayer", forHTTPHeaderField: "App-platform")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            URLSession.shared.dataTask(with: request) { data, _, _ in
                guard let data = data,
                      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let content = ((root["data"] as? [String: Any])?["playlistV2"] as? [String: Any])?["content"] as? [String: Any],
                      let items = content["items"] as? [[String: Any]] else {
                    completion(collected)
                    return
                }
                for item in items {
                    guard let data = (item["itemV2"] as? [String: Any])?["data"] as? [String: Any],
                          let name = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !name.isEmpty else { continue }
                    var artist = ""
                    if let artists = (data["artists"] as? [String: Any])?["items"] as? [[String: Any]] {
                        artist = artists.compactMap { ($0["profile"] as? [String: Any])?["name"] as? String }
                            .joined(separator: ", ")
                    }
                    collected.append(SpotifyImportTrack(title: name, artist: artist))
                }
                let total = Int((content["totalCount"] as? String) ?? "") ?? 0
                offset += items.count
                if items.isEmpty || offset >= total {
                    completion(collected)
                } else {
                    page()
                }
            }.resume()
        }
        page()
    }

    // MARK: - YouTube Music matching

    /// Resolves rows to YouTube Music songs with a small search window per row.
    /// Unmatched rows are returned so the import can report them honestly.
    static func resolve(_ tracks: [SpotifyImportTrack],
                        progress: ((Int, Int) -> Void)? = nil,
                        completion: @escaping ([Track], [SpotifyImportTrack]) -> Void) {
        guard !tracks.isEmpty else {
            completion([], [])
            return
        }
        let lock = NSLock()
        var matched = [Track?](repeating: nil, count: tracks.count)
        var completed = 0
        let queue = DispatchQueue(label: "BitChord.SpotifyImport", qos: .userInitiated, attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: 4)
        let group = DispatchGroup()

        for (index, row) in tracks.enumerated() {
            group.enter()
            queue.async {
                semaphore.wait()
                let query = [row.title, row.artist].filter { !$0.isEmpty }.joined(separator: " ")
                InnerTube.shared.search(query, filter: .songs) { results, _ in
                    let best = bestMatch(in: results ?? [], title: row.title, artist: row.artist)
                    lock.lock()
                    matched[index] = best ?? results?.first
                    completed += 1
                    let done = completed
                    lock.unlock()
                    DispatchQueue.main.async { progress?(done, tracks.count) }
                    semaphore.signal()
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            var songs: [Track] = []
            var unmatched: [SpotifyImportTrack] = []
            var seen = Set<String>()
            for (index, song) in matched.enumerated() {
                if let song = song {
                    if seen.insert(song.videoID).inserted { songs.append(song) }
                } else {
                    unmatched.append(tracks[index])
                }
            }
            completion(songs, unmatched)
        }
    }

    private static func bestMatch(in candidates: [Track], title: String, artist: String) -> Track? {
        var best: Track?
        var bestScore = 0
        for candidate in candidates.prefix(8) {
            let candidateTitle = normalize(candidate.title)
            let candidateArtist = normalize(candidate.artist)
            let targetTitle = normalize(title)
            let targetArtist = normalize(artist)
            guard !candidateTitle.isEmpty else { continue }

            var score = 0
            if candidateTitle == targetTitle { score += 100 }
            else if candidateTitle.hasPrefix(targetTitle) || targetTitle.hasPrefix(candidateTitle) { score += 65 }
            else if candidateTitle.contains(targetTitle) || targetTitle.contains(candidateTitle) { score += 45 }

            if !targetArtist.isEmpty {
                if candidateArtist == targetArtist { score += 40 }
                else if candidateArtist.contains(targetArtist) || targetArtist.contains(candidateArtist) { score += 25 }
            }
            // A title-only match is still useful, but never beats a title and
            // artist match when both are present.
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return bestScore >= 45 ? best : nil
    }

    /// Lowercased, accent-folded, punctuation-free text for matching the
    /// different ways Spotify and YouTube Music spell the same song.
    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let allowed = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return " "
        }
        return String(allowed).split(separator: " ").joined(separator: " ")
    }
}
