import Foundation

struct Playlist: Codable, Hashable {
    var id: String
    var title: String
    var author: String = "You"
    var playlistDescription: String?
    var tracks: [Track] = []

    var coverURL: URL? { return tracks.first?.artworkURL }
}

extension Notification.Name {
    static let libraryDidChange = Notification.Name("BitChordLibraryDidChange")
}

/// Port of upstream `LibraryDatabase`: liked songs, playlists, recents, recent searches and the
/// listening clock, all persisted as JSON in UserDefaults. Upstream resolves missing artwork
/// asynchronously; that arrives with the artwork work, so this stores what it is given.
final class LibraryStore {
    static let shared = LibraryStore()

    private(set) var likedTracks: [Track] = []
    private(set) var playlists: [Playlist] = []
    private(set) var recentTracks: [Track] = []
    private(set) var recentSearches: [Track] = []
    private(set) var totalMinutesListened: Int = 0
    private(set) var lastPlayedAt: Date?
    private(set) var lastPlaybackPosition: TimeInterval = 0
    private(set) var lastPlaybackDuration: TimeInterval = 0

    private let likedKey = "BitChord.Library.LikedTracks"
    private let playlistsKey = "BitChord.Library.Playlists"
    private let recentsKey = "BitChord.Library.Recents"
    private let searchesKey = "BitChord.Library.RecentSearches"
    private let minutesKey = "BitChord.Library.MinutesListened"
    private let lastPlayedKey = "BitChord.Library.LastPlayedAt"
    private let positionKey = "BitChord.Library.LastPosition"
    private let durationKey = "BitChord.Library.LastDuration"

    private init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: likedKey),
           let tracks = try? decoder.decode([Track].self, from: data) {
            likedTracks = tracks
        }
        if let data = UserDefaults.standard.data(forKey: playlistsKey),
           let stored = try? decoder.decode([Playlist].self, from: data) {
            playlists = stored
        }
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let stored = try? decoder.decode([Track].self, from: data) {
            recentTracks = stored
        }
        if let data = UserDefaults.standard.data(forKey: searchesKey),
           let stored = try? decoder.decode([Track].self, from: data) {
            recentSearches = stored
        }
        totalMinutesListened = UserDefaults.standard.integer(forKey: minutesKey)
        lastPlayedAt = UserDefaults.standard.object(forKey: lastPlayedKey) as? Date
        lastPlaybackPosition = UserDefaults.standard.double(forKey: positionKey)
        lastPlaybackDuration = UserDefaults.standard.double(forKey: durationKey)
    }

    /// Re-reads every persisted record, for a backup restored over the current
    /// library. Notification observers redraw from these properties.
    func reloadFromDisk() {
        likedTracks = []
        playlists = []
        recentTracks = []
        recentSearches = []
        load()
        announce()
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func announce() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            }
        }
    }

    // MARK: - Liked

    func isLiked(_ track: Track) -> Bool {
        return likedTracks.contains(where: { $0.videoID == track.videoID })
    }

    func toggleLike(_ track: Track) {
        if let index = likedTracks.firstIndex(where: { $0.videoID == track.videoID }) {
            likedTracks.remove(at: index)
        } else {
            likedTracks.insert(track, at: 0)
        }
        save(likedTracks, key: likedKey)
        announce()
    }

    // MARK: - Playlists

    func createPlaylist(title: String, playlistDescription: String? = nil, remoteID: String? = nil) -> Playlist {
        let identifier = (remoteID?.isEmpty == false ? remoteID : nil) ?? UUID().uuidString
        let playlist = Playlist(id: identifier,
                                title: title,
                                author: "You",
                                playlistDescription: playlistDescription,
                                tracks: [])
        playlists.append(playlist)
        save(playlists, key: playlistsKey)
        announce()
        return playlist
    }

    func add(_ track: Track, toPlaylistWith id: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        guard !playlists[index].tracks.contains(where: { $0.videoID == track.videoID }) else { return }
        playlists[index].tracks.append(track)
        save(playlists, key: playlistsKey)
        announce()
    }

    func remove(_ track: Track, fromPlaylistWith id: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].tracks.removeAll(where: { $0.videoID == track.videoID })
        save(playlists, key: playlistsKey)
        announce()
    }

    /// Pulls a public YouTube Music playlist in and keeps it locally, tracks and
    /// order included. Syncing the same playlist again replaces its contents in
    /// place rather than adding a duplicate.
    func syncPlaylist(remoteID: String, completion: @escaping (Bool, String) -> Void) {
        let identifier = PlaylistSync.identifier(from: remoteID)
        guard !identifier.isEmpty else {
            completion(false, "That does not look like a playlist link.")
            return
        }
        InnerTube.shared.fetchPlaylist(identifier: identifier) { title, tracks, error in
            guard let tracks = tracks, !tracks.isEmpty else {
                let message = error ?? "This playlist has no playable songs."
                DispatchQueue.main.async { completion(false, message) }
                return
            }
            let key = "remote:\(identifier)"
            var playlist = self.playlists.first(where: { $0.id == key })
                ?? Playlist(id: key, title: title ?? "Playlist",
                            author: "YouTube Music", playlistDescription: nil, tracks: [])
            if let title = title, !title.isEmpty { playlist.title = title }
            playlist.tracks = tracks
            if let index = self.playlists.firstIndex(where: { $0.id == key }) {
                self.playlists[index] = playlist
            } else {
                self.playlists.append(playlist)
            }
            self.save(self.playlists, key: self.playlistsKey)
            self.announce()
            DispatchQueue.main.async {
                completion(true, "Synced \(tracks.count) song\(tracks.count == 1 ? "" : "s").")
            }
        }
    }

    func deletePlaylist(_ id: String) {
        playlists.removeAll(where: { $0.id == id })
        save(playlists, key: playlistsKey)
        announce()
    }

    // MARK: - Recents

    func recordPlayback(_ track: Track) {
        recentTracks.removeAll(where: { $0.videoID == track.videoID })
        recentTracks.insert(track, at: 0)
        if recentTracks.count > 30 {
            recentTracks.removeLast()
        }
        save(recentTracks, key: recentsKey)

        let now = Date()
        lastPlayedAt = now
        lastPlaybackDuration = track.durationSeconds ?? 0
        UserDefaults.standard.set(now, forKey: lastPlayedKey)
        UserDefaults.standard.set(lastPlaybackDuration, forKey: durationKey)

        totalMinutesListened += max(1, Int((track.durationSeconds ?? 0) / 60))
        UserDefaults.standard.set(totalMinutesListened, forKey: minutesKey)
        announce()
    }

    func updateProgress(position: TimeInterval, duration: TimeInterval) {
        lastPlaybackPosition = position
        if duration > 0 {
            lastPlaybackDuration = duration
            UserDefaults.standard.set(duration, forKey: durationKey)
        }
        UserDefaults.standard.set(position, forKey: positionKey)
        UserDefaults.standard.set(Date(), forKey: lastPlayedKey)
    }

    var continueListeningTrack: Track? {
        return recentTracks.first
    }

    // MARK: - Recent searches

    func addRecentSearch(_ track: Track) {
        recentSearches.removeAll(where: { $0.videoID == track.videoID || $0.title == track.title })
        recentSearches.insert(track, at: 0)
        if recentSearches.count > 20 {
            recentSearches.removeLast()
        }
        save(recentSearches, key: searchesKey)
        announce()
    }

    func removeRecentSearch(_ track: Track) {
        recentSearches.removeAll { $0.videoID == track.videoID }
        save(recentSearches, key: searchesKey)
        announce()
    }

    func clearRecentSearches() {
        recentSearches.removeAll()
        save(recentSearches, key: searchesKey)
        announce()
    }

    /// The listening-history action clears the rows Home draws and the resume
    /// position, so a later launch cannot resurrect either one.
    func clearListeningHistory() {
        recentTracks.removeAll()
        lastPlayedAt = nil
        lastPlaybackPosition = 0
        lastPlaybackDuration = 0
        save(recentTracks, key: recentsKey)
        UserDefaults.standard.removeObject(forKey: lastPlayedKey)
        UserDefaults.standard.removeObject(forKey: positionKey)
        UserDefaults.standard.removeObject(forKey: durationKey)
        announce()
    }

    /// Tracks the user is most likely to want next: liked songs first, then recents.
    var quickPicks: [Track] {
        var seen = Set<String>()
        var picks: [Track] = []
        for track in likedTracks + recentTracks {
            if seen.contains(track.videoID) { continue }
            seen.insert(track.videoID)
            picks.append(track)
        }
        return picks
    }
}
