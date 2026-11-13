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

    /// Playlist sync: the same browse call, keeping the playlist's own title so
    /// the saved copy reads like the remote one.
    func fetchPlaylist(identifier: String,
                       completion: @escaping (String?, [Track]?, String?) -> Void) {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(nil, nil, "Missing playlist id.")
            return
        }
        let browseID = trimmed.hasPrefix("VL") ? trimmed : "VL\(trimmed)"
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
                completion(nil, nil, error ?? "Could not reach the catalogue.")
                return
            }
            let tracks = self.parseSearch(json)
            guard !tracks.isEmpty else {
                completion(nil, nil, "This playlist has no playable songs.")
                return
            }
            completion(self.playlistTitle(in: json), tracks, nil)
        }
    }

    /// The playlist's own name, wherever this response puts it: the plain
    /// metadata renderer on older responses, the header renderers on newer ones.
    private func playlistTitle(in json: [String: Any]) -> String? {
        let keys = ["playlistMetadataRenderer", "musicDetailHeaderRenderer",
                    "musicEditablePlaylistDetailHeaderRenderer", "musicResponsiveHeaderRenderer"]
        func text(in meta: [String: Any]) -> String? {
            if let title = meta["title"] as? String, !title.isEmpty { return title }
            if let title = meta["title"] as? [String: Any] {
                if let text = title["text"] as? String, !text.isEmpty { return text }
                if let runs = title["runs"] as? [[String: Any]],
                   let text = runs.first?["text"] as? String, !text.isEmpty { return text }
            }
            return nil
        }
        func find(_ node: Any, depth: Int) -> String? {
            guard depth < 9 else { return nil }
            if let dict = node as? [String: Any] {
                for key in keys {
                    if let meta = dict[key] as? [String: Any], let title = text(in: meta) {
                        return title
                    }
                }
                for value in dict.values {
                    if let found = find(value, depth: depth + 1) { return found }
                }
            } else if let array = node as? [Any] {
                for value in array {
                    if let found = find(value, depth: depth + 1) { return found }
                }
            }
            return nil
        }
        return find(json, depth: 0)
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

    /// Upstream's radio: `next` with the seed's mix id returns a panel of songs
    /// built around it, which is what the queue becomes.
    func radio(seedVideoID: String, completion: @escaping ([Track]?, String?) -> Void) {
        guard !seedVideoID.isEmpty, !seedVideoID.hasPrefix(LocalMusicStore.idPrefix) else {
            completion(nil, "This song is on the device, so it has no radio.")
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
            "videoId": seedVideoID,
            "playlistId": "RDAMVM\(seedVideoID)",
            "isAudioOnly": true,
            // Without this the web client answers an ordinary watch-next page,
            // whose rows are not in a playlist panel, so the mix looked empty.
            "params": "wAEB"
        ]
        post(path: "next", body: body, userAgent: InnerTube.browserUserAgent) { json, error in
            guard let json = json else {
                completion(nil, error ?? "Could not reach the radio.")
                return
            }
            let tracks = InnerTube.parseRadioTracks(json)
            if tracks.isEmpty {
                completion(nil, "This track has no radio.")
            } else {
                completion(tracks, nil)
            }
        }
    }

    /// Picks the songs out of a `next` response, in the panel's order.
    static func parseRadioTracks(_ json: [String: Any]) -> [Track] {
        var panels: [[String: Any]] = []
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let panel = dict["playlistPanelVideoRenderer"] as? [String: Any] {
                    panels.append(panel)
                }
                for (_, child) in dict { walk(child) }
            } else if let array = node as? [Any] {
                for child in array { walk(child) }
            }
        }
        walk(json)

        var tracks: [Track] = []
        var seen = Set<String>()
        for panel in panels {
            guard let identifier = panel["videoId"] as? String, !identifier.isEmpty else { continue }
            guard !seen.contains(identifier) else { continue }
            guard let title = radioText(panel["title"]), !title.isEmpty else { continue }
            seen.insert(identifier)
            let artist = radioText(panel["longBylineText"]) ?? ""
            let length = radioText(panel["lengthText"]) ?? ""
            var artwork: String?
            if let thumbnail = panel["thumbnail"] as? [String: Any],
               let thumbs = thumbnail["thumbnails"] as? [[String: Any]] {
                artwork = thumbs.last?["url"] as? String
            }
            tracks.append(Track(videoID: identifier,
                                title: title,
                                artist: artist,
                                durationSeconds: RadioServiceSupport.seconds(length),
                                source: .youtube,
                                artwork: artwork))
        }
        return tracks
    }

    private static func radioText(_ node: Any?) -> String? {
        guard let node = node else { return nil }
        if let text = node as? String { return text }
        guard let dict = node as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
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
