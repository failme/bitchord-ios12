import Foundation

/// InnerTube search filters. Values are the exact `params` blobs the upstream iOS client sends
/// for each BitChord Android SearchFilter, so results match the reference app's catalog slices.
enum SearchFilter: String {
    case songs
    case videos
    case albums
    case artists
    case playlists

    var params: String {
        switch self {
        case .songs: return "EgWKAQIIAWoKEAkQChAFEAMQBA=="
        case .videos: return "EgWKAQIQAWoKEAkQChAFEAMQBA=="
        case .albums: return "EgWKAQIYAWoKEAkQChAFEAMQBA=="
        case .artists: return "EgWKAQIgAWoKEAkQChAFEAMQBA=="
        case .playlists: return "EgWKAQIoAWoKEAkQChAFEAMQBA=="
        }
    }
}

/// An album, playlist or artist tile: something to open rather than play directly.
struct CollectionItem {
    let browseID: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
}

extension InnerTube {
    func searchCollections(_ query: String,
                           filter: SearchFilter,
                           completion: @escaping ([CollectionItem]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion([])
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
            "query": trimmed,
            "params": filter.params
        ]
        post(path: "search", body: body, userAgent: InnerTube.browserUserAgent) { json, _ in
            guard let json = json else {
                completion([])
                return
            }
            completion(self.parseCollections(json))
        }
    }

    /// Loads an album or playlist by browse id. Web browse ids are prefixed (`VL` for playlists,
    /// `MPRE` for albums); bare ids get the playlist prefix like upstream does.
    func fetchCollection(_ identifier: String,
                         completion: @escaping ([Track]?, String?) -> Void) {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(nil, "Missing collection id.")
            return
        }
        let browseID = (trimmed.hasPrefix("VL") || trimmed.hasPrefix("MPRE") || trimmed.hasPrefix("UC"))
            ? trimmed
            : "VL\(trimmed)"
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20241011.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "browseId": browseID
        ]
        post(path: "browse", body: body, userAgent: InnerTube.browserUserAgent) { json, error in
            guard let json = json else {
                completion(nil, error ?? "Could not load this collection.")
                return
            }
            let tracks = self.parseSearch(json)
            if tracks.isEmpty {
                completion(nil, "Nothing playable in this collection.")
            } else {
                completion(tracks, nil)
            }
        }
    }

    func parseCollections(_ json: [String: Any]) -> [CollectionItem] {
        var items: [CollectionItem] = []
        var seen = Set<String>()
        for renderer in renderers(named: "musicResponsiveListItemRenderer", in: json) {
            guard let identifier = collectionID(in: renderer), !identifier.isEmpty else { continue }
            guard !seen.contains(identifier) else { continue }
            let columns = (renderer["flexColumns"] as? [[String: Any]]) ?? []
            guard let title = columnText(columns, index: 0), !title.isEmpty else { continue }
            let subtitle = columnSegments(columns, index: 1).joined(separator: " \u{2022} ")
            items.append(CollectionItem(browseID: identifier,
                                        title: title,
                                        subtitle: subtitle,
                                        artworkURL: thumbnailURL(in: renderer)))
            seen.insert(identifier)
        }
        return items
    }

    private func collectionID(in renderer: [String: Any]) -> String? {
        var found: String?
        func walk(_ node: Any) {
            if found != nil { return }
            if let dict = node as? [String: Any] {
                if let browse = dict["browseEndpoint"] as? [String: Any],
                   let identifier = browse["browseId"] as? String,
                   !identifier.isEmpty {
                    found = identifier
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

    private func thumbnailURL(in renderer: [String: Any]) -> URL? {
        var found: URL?
        func walk(_ node: Any) {
            if found != nil { return }
            if let dict = node as? [String: Any] {
                if let thumbnails = dict["thumbnails"] as? [[String: Any]] {
                    for thumb in thumbnails.reversed() {
                        if let raw = thumb["url"] as? String, let url = URL(string: raw) {
                            found = url
                            return
                        }
                    }
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
}
