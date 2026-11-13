import Foundation

extension Notification.Name {
    static let playbackHistoryDidChange = Notification.Name("BitChordPlaybackHistoryDidChange")
}

/// Upstream's `QueueHistory`: the last few songs that actually played, so the
/// queue sheet can show them above the upcoming list.
///
/// The setting `BitChord.Misc.ShowQueueHistory` controls whether they are
/// shown (off by default upstream too). The list is written to disk so it
/// survives relaunch, capped at the same 25 entries.
final class PlaybackHistoryStore {
    static let shared = PlaybackHistoryStore()
    static let limit = 25
    static let settingKey = "BitChord.Misc.ShowQueueHistory"

    private(set) var items: [Track] = []
    private let key = "BitChord.Player.QueueHistory"

    private init() {
        load()
    }

    var isEnabled: Bool {
        return SettingsStore.shared.bool(PlaybackHistoryStore.settingKey, false)
    }

    func record(_ track: Track) {
        // A song already in the list moves to the top instead of appearing twice.
        items.removeAll(where: { $0.videoID == track.videoID })
        items.insert(track, at: 0)
        if items.count > PlaybackHistoryStore.limit {
            items.removeLast(items.count - PlaybackHistoryStore.limit)
        }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode([Track].self, from: data) else { return }
        items = Array(stored.prefix(PlaybackHistoryStore.limit))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: .playbackHistoryDidChange, object: nil)
    }
}
