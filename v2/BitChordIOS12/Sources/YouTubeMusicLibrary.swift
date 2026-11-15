import Foundation

/// A card from YouTube Music's home feed: either a playable song or a
/// collection page opened by its browse id.
struct YouTubeHomeItem {
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let browseID: String?
    let videoID: String?
}

/// The signed-in YouTube Music library, read through the same InnerTube browse
/// endpoint upstream's `YtMusicRepository.library()` uses.
extension InnerTube {
    /// Liked Music is YouTube Music's `LM` auto-playlist, addressed as `VLLM`.
    /// It is the account's thumbs-up collection, not the local liked list.
    func fetchLikedMusic(completion: @escaping ([Track], String?) -> Void) {
        fetchPersonalBrowse(id: "VLLM", completion: completion)
    }

    /// The account's listening history, newest first.
    func fetchRemoteHistory(completion: @escaping ([Track], String?) -> Void) {
        fetchPersonalBrowse(id: "FEmusic_history", completion: completion)
    }

    /// Songs explicitly added to the library, distinct from Liked Music.
    func fetchLibrarySongs(completion: @escaping ([Track], String?) -> Void) {
        fetchPersonalBrowse(id: "FEmusic_liked_videos", completion: completion)
    }

    /// The personalised home feed. Songs become Top Picks; albums, playlists
    /// and mixes become cards that open their own page.
    func fetchHome(completion: @escaping ([Track], [YouTubeHomeItem]) -> Void) {
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20241011.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "browseId": "FEmusic_home"
        ]
        post(path: "browse", body: body, userAgent: InnerTube.browserUserAgent) { [weak self] json, _ in
            guard let self = self, let json = json else {
                completion([], [])
                return
            }
            let renderers = self.renderers(named: "musicTwoRowItemRenderer", in: json)
            var songs: [Track] = []
            var collections: [YouTubeHomeItem] = []
            var seenSongs = Set<String>()
            var seenCollections = Set<String>()

            for renderer in renderers {
                let title = self.homeText(renderer["title"]) ?? ""
                guard !title.isEmpty else { continue }
                let subtitle = self.homeText(renderer["subtitle"]) ?? ""
                let artwork = self.homeArtwork(in: renderer)
                let watch = self.homeEndpoint(named: "watchEndpoint", in: renderer)?["videoId"] as? String
                let browse = self.homeEndpoint(named: "browseEndpoint", in: renderer)?["browseId"] as? String

                if let videoID = watch, !videoID.isEmpty {
                    if seenSongs.insert(videoID).inserted {
                        let artist = subtitle.components(separatedBy: " \u{2022} ").first ?? subtitle
                        songs.append(Track(videoID: videoID, title: title, artist: artist))
                    }
                } else if let browseID = browse, !browseID.isEmpty {
                    if seenCollections.insert(browseID).inserted {
                        collections.append(YouTubeHomeItem(title: title,
                                                           subtitle: subtitle,
                                                           artworkURL: artwork,
                                                           browseID: browseID,
                                                           videoID: nil))
                    }
                }
            }
            completion(songs, collections)
        }
    }

    private func homeText(_ node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String, !simple.isEmpty { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private func homeEndpoint(named name: String, in node: Any) -> [String: Any]? {
        if let dict = node as? [String: Any] {
            if let endpoint = dict[name] as? [String: Any] { return endpoint }
            if let navigation = dict["navigationEndpoint"] as? [String: Any],
               let endpoint = navigation[name] as? [String: Any] { return endpoint }
            for value in dict.values {
                if let found = homeEndpoint(named: name, in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = homeEndpoint(named: name, in: value) { return found }
            }
        }
        return nil
    }

    private func homeArtwork(in node: Any) -> URL? {
        var best: URL?
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let thumbnails = dict["thumbnails"] as? [[String: Any]] {
                    for thumbnail in thumbnails {
                        if let raw = thumbnail["url"] as? String,
                           let url = URL(string: raw.hasPrefix("//") ? "https:" + raw : raw) {
                            best = url
                        }
                    }
                }
                for value in dict.values { walk(value) }
            } else if let array = node as? [Any] {
                for value in array { walk(value) }
            }
        }
        walk(node)
        return best
    }

    private func fetchPersonalBrowse(id: String,
                                     completion: @escaping ([Track], String?) -> Void) {
        guard GoogleAccountStore.shared.isSignedIn else {
            completion([], "Sign in with Google to load your YouTube Music library.")
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
            "browseId": id
        ]
        post(path: "browse", body: body, userAgent: InnerTube.browserUserAgent) { [weak self] json, error in
            guard let self = self, let json = json else {
                completion([], error ?? "Could not reach YouTube Music.")
                return
            }
            let tracks = self.parseSearch(json)
            if tracks.isEmpty {
                completion([], "This list is empty on the signed-in account.")
            } else {
                completion(tracks, nil)
            }
        }
    }
}
