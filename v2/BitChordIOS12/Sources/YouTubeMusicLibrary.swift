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

/// One Google account or brand channel the login can act as, as the account
/// switcher lists it. `pageId` and `dataSyncId` are the identity a request has
/// to carry to act as that channel.
struct YouTubeChannel {
    let name: String
    let subtitle: String
    let avatarURL: URL?
    let pageId: String?
    let dataSyncId: String?
    let isSelected: Bool

    var key: String { return pageId ?? dataSyncId ?? name }
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

    /// Creates a playlist on the signed-in YouTube Music account. The local
    /// card is only written after this returns an id, so it never claims a
    /// remote playlist that was refused.
    func createRemotePlaylist(title: String,
                              description: String?,
                              videoIDs: [String] = [],
                              completion: @escaping (String?, String?) -> Void) {
        guard GoogleAccountStore.shared.isSignedIn else {
            completion(nil, "Sign in with Google to create a YouTube Music playlist.")
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
            "title": title,
            "description": description ?? "",
            "privacyStatus": "PRIVATE"
        ]
        if !videoIDs.isEmpty { body["videoIds"] = videoIDs }
        post(path: "playlist/create", body: body, userAgent: InnerTube.browserUserAgent) { [weak self] json, error in
            guard let self = self, let json = json else {
                completion(nil, error ?? "YouTube Music did not create the playlist.")
                return
            }
            let identifier = (json["playlistId"] as? String) ?? self.findString("playlistId", in: json)
            if let identifier = identifier, !identifier.isEmpty {
                completion(identifier.hasPrefix("VL") ? identifier : "VL" + identifier, nil)
            } else {
                completion(nil, "YouTube Music created the playlist but returned no id.")
            }
        }
    }

    /// One saved-library feed: playlists, albums or artists. Each row keeps the
    /// browse id that opens it and the artwork the account already saved.
    func fetchLibraryCollections(feedID: String,
                                 completion: @escaping ([CollectionItem], String?) -> Void) {
        guard GoogleAccountStore.shared.isSignedIn else {
            completion([], "Sign in with Google to load your saved library.")
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
            "browseId": feedID
        ]
        post(path: "browse", body: body, userAgent: InnerTube.browserUserAgent) { [weak self] json, error in
            guard let self = self, let json = json else {
                completion([], error ?? "Could not reach YouTube Music.")
                return
            }
            var items: [CollectionItem] = []
            var seen = Set<String>()
            let renderers = self.renderers(named: "musicTwoRowItemRenderer", in: json)
                + self.renderers(named: "musicResponsiveListItemRenderer", in: json)
            for renderer in renderers {
                guard let browseID = self.libraryBrowseID(in: renderer),
                      !browseID.isEmpty, seen.insert(browseID).inserted else { continue }
                let title = self.channelText(renderer["title"])
                    ?? self.columnText((renderer["flexColumns"] as? [[String: Any]]) ?? [], index: 0)
                    ?? ""
                guard !title.isEmpty else { continue }
                let subtitle = self.channelText(renderer["subtitle"])
                    ?? self.columnSegments((renderer["flexColumns"] as? [[String: Any]]) ?? [], index: 1)
                        .joined(separator: " \u{2022} ")
                items.append(CollectionItem(browseID: browseID,
                                            title: title,
                                            subtitle: subtitle,
                                            artworkURL: self.homeArtwork(in: renderer)))
            }
            completion(items, items.isEmpty ? "Nothing saved in this section." : nil)
        }
    }

    private func libraryBrowseID(in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let browse = dict["browseEndpoint"] as? [String: Any],
               let identifier = browse["browseId"] as? String { return identifier }
            for value in dict.values {
                if let found = libraryBrowseID(in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = libraryBrowseID(in: value) { return found }
            }
        }
        return nil
    }

    /// The accounts and brand channels this Google login can act as.
    func fetchAccountChannels(completion: @escaping ([YouTubeChannel], String?) -> Void) {
        guard GoogleAccountStore.shared.isSignedIn else {
            completion([], "Sign in with Google first.")
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
            ]
        ]
        post(path: "account/accounts_list", body: body, userAgent: InnerTube.browserUserAgent) { [weak self] json, error in
            guard let self = self, let json = json else {
                completion([], error ?? "Could not load this account's channels.")
                return
            }
            var channels: [YouTubeChannel] = []
            var seen = Set<String>()
            for item in self.renderers(named: "accountItem", in: json) {
                let name = self.channelText(item["accountName"]) ?? ""
                guard !name.isEmpty else { continue }
                let pageID = self.findString("pageId", in: item)
                let dataSync = GoogleAccountStore.normalizeDataSyncID(self.findString("datasyncIdToken", in: item))
                guard pageID != nil || dataSync != nil else { continue }
                let subtitle = self.channelText(item["channelHandle"])
                    ?? self.channelText(item["accountByline"])
                    ?? ""
                let selected: Bool
                if let value = item["isSelected"] as? Bool {
                    selected = value
                } else {
                    selected = (item["isSelected"] as? String) == "true"
                }
                let channel = YouTubeChannel(name: name,
                                             subtitle: subtitle,
                                             avatarURL: self.avatarURL(in: item["accountPhoto"]),
                                             pageId: pageID,
                                             dataSyncId: dataSync,
                                             isSelected: selected)
                if seen.insert(channel.key).inserted { channels.append(channel) }
            }
            completion(channels, channels.isEmpty ? "This login lists no channels." : nil)
        }
    }

    private func channelText(_ node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String, !simple.isEmpty { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private func findString(_ key: String, in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let value = dict[key] as? String, !value.isEmpty { return value }
            for value in dict.values {
                if let found = findString(key, in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findString(key, in: value) { return found }
            }
        }
        return nil
    }

    private func avatarURL(in node: Any?) -> URL? {
        guard let dict = node as? [String: Any],
              let thumbnails = dict["thumbnails"] as? [[String: Any]] else { return nil }
        guard let raw = thumbnails.last?["url"] as? String else { return nil }
        return URL(string: raw.hasPrefix("//") ? "https:" + raw : raw)
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
