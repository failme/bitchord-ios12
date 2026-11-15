import Foundation

/// An artist row from the catalogue.
struct CatalogueArtist {
    let id: String
    let name: String
    let artwork: URL?
}

/// An album row from the catalogue.
struct CatalogueAlbum {
    let id: String
    let title: String
    let artist: String
    let year: String
    let artwork: URL?
    let songCount: Int
}

/// Everything the artist page draws: the photograph, the counts, the
/// biography, the popular songs and the release/related-artist shelves.
struct ArtistProfile {
    let name: String
    let artwork: URL?
    let listenerText: String?
    let bio: String?
    let topSongs: [Track]
    let albums: [CatalogueAlbum]
    let related: [CatalogueArtist]
}

/// Searching JioSaavn instead of YouTube.
///
/// YouTube Music's search only ever answered with recordings — artists and albums
/// have no video id, so every one of them was dropped, and the Song-only filter
/// meant a query that returned anything else looked empty. The catalogue behind
/// playback answers all three kinds directly, and the rows it returns carry the
/// artwork and length that playback already needs, so a result list and the queue
/// it builds come from the same place.
final class CatalogueSearch {
    static let shared = CatalogueSearch()

    private let session: URLSession
    private let endpoint = URL(string: "https://www.jiosaavn.com/api.php")!

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
            "X-Forwarded-For": "49.36.0.1",
            "X-Real-IP": "49.36.0.1",
            "Accept-Language": "en-IN,en;q=0.9",
            "Cookie": "explicit_content=1",
            "Accept": "application/json"
        ]
        session = URLSession(configuration: config)
    }

    // MARK: - Search

    /// Recordings matching `query`, ready to queue.
    func songs(_ query: String, completion: @escaping ([Track]) -> Void) {
        guard SettingsStore.shared.jioSaavnEnabled else {
            InnerTube.shared.search(query, filter: .songs) { tracks, _ in
                completion(tracks ?? [])
            }
            return
        }
        get(call: "search.getResults", params: ["q": query, "p": "1", "n": "30"]) { json in
            let rows = (json?["results"] as? [[String: Any]]) ?? []
            let tracks = rows.compactMap { self.track(from: $0) }
            completion(tracks)
        }
    }

    func artists(_ query: String, completion: @escaping ([CatalogueArtist]) -> Void) {
        guard SettingsStore.shared.jioSaavnEnabled else {
            InnerTube.shared.searchCollections(query, filter: .artists) { rows in
                completion(rows.map { CatalogueArtist(id: $0.browseID, name: $0.title, artwork: $0.artworkURL) })
            }
            return
        }
        get(call: "search.getArtistResults", params: ["q": query, "p": "1", "n": "20"]) { json in
            let rows = (json?["results"] as? [[String: Any]]) ?? []
            let artists = rows.compactMap { row -> CatalogueArtist? in
                guard let id = row["id"] as? String, !id.isEmpty else { return nil }
                let name = self.decode((row["name"] as? String) ?? (row["title"] as? String) ?? "")
                guard !name.isEmpty else { return nil }
                return CatalogueArtist(id: id, name: name, artwork: self.artwork(row["image"] as? String))
            }
            completion(artists)
        }
    }

    func albums(_ query: String, completion: @escaping ([CatalogueAlbum]) -> Void) {
        guard SettingsStore.shared.jioSaavnEnabled else {
            InnerTube.shared.searchCollections(query, filter: .albums) { rows in
                completion(rows.map {
                    CatalogueAlbum(id: $0.browseID, title: $0.title, artist: $0.subtitle,
                                   year: "", artwork: $0.artworkURL, songCount: 0)
                })
            }
            return
        }
        get(call: "search.getAlbumResults", params: ["q": query, "p": "1", "n": "20"]) { json in
            let rows = (json?["results"] as? [[String: Any]]) ?? []
            let albums = rows.compactMap { row -> CatalogueAlbum? in
                guard let id = row["id"] as? String, !id.isEmpty else { return nil }
                let title = self.decode((row["title"] as? String) ?? "")
                guard !title.isEmpty else { return nil }
                let info = row["more_info"] as? [String: Any] ?? [:]
                let count = Int((info["song_count"] as? String) ?? "") ?? 0
                return CatalogueAlbum(id: id,
                                      title: title,
                                      artist: self.primaryArtist(in: info),
                                      year: (row["year"] as? String) ?? "",
                                      artwork: self.artwork(row["image"] as? String),
                                      songCount: count)
            }
            completion(albums)
        }
    }

    // MARK: - Collections

    /// The songs on an album, in track order.
    ///
    /// `album.getAlbumDetails` was retired by the catalogue and now answers
    /// `INPUT_INVALID / operation is not supported`, which is why every album
    /// page came up saying there was nothing to see. `content.getAlbumDetails`
    /// is the operation that still returns the tracklist, and it puts the songs
    /// under `list`.
    func songs(inAlbum albumID: String, completion: @escaping ([Track]) -> Void) {
        guard SettingsStore.shared.jioSaavnEnabled else {
            InnerTube.shared.fetchCollection(albumID) { tracks, _ in completion(tracks ?? []) }
            return
        }
        get(call: "content.getAlbumDetails", params: ["albumid": albumID]) { json in
            guard let json = json else {
                completion([])
                return
            }
            var rows = (json["songs"] as? [[String: Any]]) ?? []
            if rows.isEmpty {
                rows = (json["list"] as? [[String: Any]]) ?? []
            }
            // Some responses wrap the album in a map keyed by its own id.
            if rows.isEmpty {
                for value in json.values {
                    if let album = value as? [String: Any],
                       let list = album["songs"] as? [[String: Any]], !list.isEmpty {
                        rows = list
                        break
                    }
                }
            }
            completion(rows.compactMap { self.track(from: $0) })
        }
    }

    /// An artist's best-known songs.
    func songs(byArtist artistID: String, completion: @escaping ([Track]) -> Void) {
        guard SettingsStore.shared.jioSaavnEnabled else {
            InnerTube.shared.fetchCollection(artistID) { tracks, _ in completion(tracks ?? []) }
            return
        }
        get(call: "artist.getArtistPageDetails", params: ["artistId": artistID]) { json in
            guard let json = json else {
                completion([])
                return
            }
            var rows = self.rows(in: json["topSongs"], key: "songs")
            if rows.isEmpty {
                rows = self.rows(in: json["songs"], key: "songs")
            }
            completion(rows.compactMap { self.track(from: $0) })
        }
    }

    /// The full artist page. JioSaavn's current payload nests the popular songs
    /// and albums in maps (`topSongs.songs`, `topAlbums.albums`); the old parser
    /// only accepted arrays, which is why artist pages opened empty. Older and
    /// newer shapes are both accepted here.
    func artistProfile(id: String,
                       name: String,
                       artwork: URL?,
                       completion: @escaping (ArtistProfile) -> Void) {
        guard SettingsStore.shared.jioSaavnEnabled else {
            youTubeArtistProfile(id: id, name: name, artwork: artwork, completion: completion)
            return
        }
        get(call: "artist.getArtistPageDetails", params: ["artistId": id]) { json in
            guard let json = json else {
                self.youTubeArtistProfile(id: id, name: name, artwork: artwork,
                                          completion: completion)
                return
            }
            let profileName = self.decode((json["name"] as? String) ?? name)
            let songs = self.rows(in: json["topSongs"], key: "songs")
                .compactMap { self.track(from: $0) }
            let albums = self.rows(in: json["topAlbums"], key: "albums")
                .compactMap { self.album(from: $0) }
            if songs.isEmpty && albums.isEmpty {
                self.youTubeArtistProfile(id: id, name: name, artwork: artwork,
                                          completion: completion)
                return
            }
            let relatedRows = (json["similarArtists"] as? [[String: Any]]) ?? []
            let related = relatedRows.compactMap { row -> CatalogueArtist? in
                guard let identifier = (row["id"] as? String) ?? (row["_id"] as? String),
                      !identifier.isEmpty else { return nil }
                let title = self.decode((row["name"] as? String) ?? "")
                guard !title.isEmpty else { return nil }
                let raw = (row["image_url"] as? String) ?? (row["image"] as? String)
                return CatalogueArtist(id: identifier, name: title, artwork: self.artwork(raw))
            }
            let artworkURL = self.artwork((json["image"] as? String)) ?? artwork
            completion(ArtistProfile(name: profileName,
                                     artwork: artworkURL,
                                     listenerText: self.listenerText(in: json),
                                     bio: self.artistBio(json["bio"] ?? json["artistBio"]),
                                     topSongs: songs,
                                     albums: albums,
                                     related: related))
        }
    }

    private func youTubeArtistProfile(id: String,
                                      name: String,
                                      artwork: URL?,
                                      completion: @escaping (ArtistProfile) -> Void) {
        InnerTube.shared.fetchCollection(id) { tracks, _ in
            completion(ArtistProfile(name: name,
                                     artwork: artwork,
                                     listenerText: "Artist",
                                     bio: nil,
                                     topSongs: tracks ?? [],
                                     albums: [],
                                     related: []))
        }
    }

    private func rows(in value: Any?, key: String) -> [[String: Any]] {
        if let rows = value as? [[String: Any]] { return rows }
        if let map = value as? [String: Any],
           let rows = map[key] as? [[String: Any]] { return rows }
        return []
    }

    private func album(from row: [String: Any]) -> CatalogueAlbum? {
        guard let identifier = row["id"] as? String, !identifier.isEmpty else { return nil }
        let title = decode((row["title"] as? String) ?? "")
        guard !title.isEmpty else { return nil }
        let info = row["more_info"] as? [String: Any] ?? [:]
        let count = Int((info["song_count"] as? String) ?? "") ?? 0
        return CatalogueAlbum(id: identifier,
                              title: title,
                              artist: primaryArtist(in: info),
                              year: (row["year"] as? String) ?? "",
                              artwork: artwork(row["image"] as? String),
                              songCount: count)
    }

    private func listenerText(in json: [String: Any]) -> String? {
        let subtitle = decode((json["subtitle"] as? String) ?? "")
        if !subtitle.isEmpty { return subtitle }
        let raw = (json["fan_count"] as? String) ?? (json["follower_count"] as? String) ?? ""
        guard let count = Int(raw), count > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        let number = formatter.string(from: NSNumber(value: count)) ?? raw
        return "\(number) listeners"
    }

    /// `bio` is either a plain string, a JSON-encoded string, or a list of
    /// objects with a `text` field. Empty `[]` is common and means no copy.
    private func artistBio(_ value: Any?) -> String? {
        if let text = value as? String {
            let decoded = decode(text)
            if decoded.hasPrefix("[") {
                if let data = decoded.data(using: .utf8),
                   let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                    let joined = list.compactMap { $0["text"] as? String }
                        .map { decode($0) }
                        .joined(separator: "\n")
                    return joined.isEmpty ? nil : joined
                }
                return nil
            }
            return decoded.isEmpty ? nil : decoded
        }
        if let list = value as? [[String: Any]] {
            let joined = list.compactMap { $0["text"] as? String }
                .map { decode($0) }
                .joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    // MARK: - Row mapping

    /// A catalogue row as a `Track`, keeping the catalogue's own artwork so the
    /// list does not point at a YouTube thumbnail that will never exist for it.
    private func track(from row: [String: Any]) -> Track? {
        guard let id = row["id"] as? String, !id.isEmpty else { return nil }
        let title = decode((row["title"] as? String) ?? "")
        guard !title.isEmpty else { return nil }
        let info = row["more_info"] as? [String: Any] ?? [:]
        let seconds = Double((info["duration"] as? String) ?? "")
        let album = decode((info["album"] as? String) ?? "")
        let flag = (row["explicit_content"] as? String ?? "").lowercased()
        return Track(videoID: "saavn:" + id,
                     title: title,
                     artist: primaryArtist(in: info),
                     album: album,
                     durationSeconds: (seconds ?? 0) > 0 ? seconds : nil,
                     isExplicit: flag == "1" || flag == "true",
                     artwork: artwork(row["image"] as? String)?.absoluteString)
    }

    private func primaryArtist(in info: [String: Any]) -> String {
        if let map = info["artistMap"] as? [String: Any],
           let primary = map["primary_artists"] as? [[String: Any]] {
            let names = primary.compactMap { $0["name"] as? String }.map { decode($0) }
            if !names.isEmpty {
                return names.joined(separator: ", ")
            }
        }
        if let subtitle = info["music"] as? String, !subtitle.isEmpty {
            return decode(subtitle)
        }
        return decode((info["artist"] as? String) ?? "")
    }

    /// The catalogue serves 50x50 art by default; the list wants something that
    /// survives a 2x screen.
    private func artwork(_ raw: String?) -> URL? {
        guard var text = raw, !text.isEmpty else { return nil }
        for size in ["50x50", "150x150"] {
            text = text.replacingOccurrences(of: size, with: "500x500")
        }
        return URL(string: text)
    }

    private func decode(_ text: String) -> String {
        var out = text
        let entities = [("&quot;", "\""), ("&amp;", "&"), ("&#039;", "'"),
                        ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">")]
        for (entity, value) in entities {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Transport

    private func get(call: String,
                     params: [String: String],
                     completion: @escaping ([String: Any]?) -> Void) {
        var items = [
            URLQueryItem(name: "__call", value: call),
            URLQueryItem(name: "_format", value: "json"),
            URLQueryItem(name: "_marker", value: "0"),
            URLQueryItem(name: "api_version", value: "4"),
            URLQueryItem(name: "ctx", value: "android")
        ]
        for (name, value) in params {
            items.append(URLQueryItem(name: name, value: value))
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        guard let url = components?.url else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        session.dataTask(with: url) { data, _, _ in
            var json: [String: Any]?
            if let data = data {
                json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            DispatchQueue.main.async { completion(json) }
        }.resume()
    }
}
