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
        get(call: "search.getResults", params: ["q": query, "p": "1", "n": "30"]) { json in
            let rows = (json?["results"] as? [[String: Any]]) ?? []
            let tracks = rows.compactMap { self.track(from: $0) }
            completion(tracks)
        }
    }

    func artists(_ query: String, completion: @escaping ([CatalogueArtist]) -> Void) {
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
        get(call: "artist.getArtistPageDetails", params: ["artistId": artistID]) { json in
            guard let json = json else {
                completion([])
                return
            }
            var rows = (json["topSongs"] as? [[String: Any]]) ?? []
            if rows.isEmpty {
                // Older responses put the list under `songs`, sometimes in a map.
                rows = (json["songs"] as? [[String: Any]]) ?? []
            }
            if rows.isEmpty {
                for value in json.values {
                    if let artist = value as? [String: Any],
                       let list = artist["topSongs"] as? [[String: Any]], !list.isEmpty {
                        rows = list
                        break
                    }
                }
            }
            completion(rows.compactMap { self.track(from: $0) })
        }
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
