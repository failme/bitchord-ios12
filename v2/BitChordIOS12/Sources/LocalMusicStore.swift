import Foundation
import AVFoundation

/// One audio file found on the device, already shaped as a `Track` so the
/// player, rows and menus treat it like any other song.
struct LocalSong {
    var track: Track
    var relativePath: String
    var folder: String
    var byteSize: Int64
}

extension Notification.Name {
    static let localMusicDidChange = Notification.Name("BitChordLocalMusicDidChange")
}

/// Upstream's `LocalMediaRepository`: audio already on the device, grouped by
/// folder, read without the network.
///
/// iOS has no MediaStore, so the locker is the app's own `Documents/LocalMusic`
/// directory — the folder the Files app and iTunes File Sharing expose. Every
/// file in it (one level of folders deep) is read with AVFoundation for its
/// title, artist, album and length, and given a `local:` id that the player
/// resolves straight back to the file, so a scanned song plays, queues and
/// survives relaunch without a catalogue lookup.
final class LocalMusicStore {
    static let shared = LocalMusicStore()
    static let idPrefix = "local:"
    static let folderName = "LocalMusic"

    private(set) var songs: [LocalSong] = []
    private let scanQueue = DispatchQueue(label: "com.bitchord.localmusic.scan")
    private static let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aif", "aiff", "caf", "m4b"]

    var rootURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent(LocalMusicStore.folderName, isDirectory: true)
    }

    /// Reads the folder off the main queue, then publishes the result.
    func scan(completion: (([LocalSong]) -> Void)? = nil) {
        scanQueue.async {
            let found = LocalMusicStore.readSongs(root: self.rootURL)
            DispatchQueue.main.async {
                self.songs = found
                NotificationCenter.default.post(name: .localMusicDidChange, object: nil)
                completion?(found)
            }
        }
    }

    /// Folders in the order they were found, each with its songs.
    var folders: [(name: String, songs: [LocalSong])] {
        var order: [String] = []
        var grouped: [String: [LocalSong]] = [:]
        for song in songs {
            if grouped[song.folder] == nil {
                order.append(song.folder)
                grouped[song.folder] = []
            }
            grouped[song.folder]?.append(song)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    /// The file behind a `local:` id, or nil when it has been deleted.
    func localURL(for videoID: String) -> URL? {
        guard videoID.hasPrefix(LocalMusicStore.idPrefix) else { return nil }
        let relative = String(videoID.dropFirst(LocalMusicStore.idPrefix.count))
        let url = rootURL.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Reading

    private static func readSongs(root: URL) -> [LocalSong] {
        let manager = FileManager.default
        var found: [LocalSong] = []
        let folders = (try? manager.contentsOfDirectory(at: root,
                                                        includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles])) ?? []
        for entry in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                let files = (try? manager.contentsOfDirectory(at: entry,
                                                              includingPropertiesForKeys: [.fileSizeKey],
                                                              options: [.skipsHiddenFiles])) ?? []
                for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if let song = song(at: file,
                                       relative: "\(entry.lastPathComponent)/\(file.lastPathComponent)",
                                       folder: entry.lastPathComponent) {
                        found.append(song)
                    }
                }
            } else if let song = song(at: entry,
                                      relative: entry.lastPathComponent,
                                      folder: LocalMusicStore.folderName) {
                found.append(song)
            }
        }
        return found
    }

    private static func song(at url: URL, relative: String, folder: String) -> LocalSong? {
        guard audioExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        // Upstream's "Filter non-music": a ringtone or a voice memo is not a song.
        let filtering = SettingsStore.shared.bool("BitChord.LocalMusic.FilterNonMusic", true)
        if filtering && seconds < 30 { return nil }

        var title = ""
        var artist = ""
        var album = ""
        for item in asset.commonMetadata {
            guard let key = item.commonKey?.rawValue, let value = item.stringValue, !value.isEmpty else { continue }
            switch key {
            case "title": title = value
            case "artist": artist = value
            case "albumName": album = value
            default: break
            }
        }
        if title.isEmpty {
            title = url.deletingPathExtension().lastPathComponent
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let track = Track(videoID: LocalMusicStore.idPrefix + relative,
                          title: title,
                          artist: artist.isEmpty ? "Unknown Artist" : artist,
                          album: album.isEmpty ? folder : album,
                          durationSeconds: seconds,
                          source: .library)
        return LocalSong(track: track, relativePath: relative, folder: folder, byteSize: size)
    }
}
