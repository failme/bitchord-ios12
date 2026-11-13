import Foundation

/// Upstream's cache settings, mapped onto what iOS actually exposes.
///
/// `URLCache` is the one disk cache an app can both bound and clear on iOS 12:
/// it holds the artwork and API responses every screen fetches. The rows that
/// upstream points at its song cache are wired here to the app's own partial
/// downloads and temp files, which is the audio the port can safely throw away
/// — completed downloads are the user's library, not a cache.
final class CacheStore {
    static let shared = CacheStore()
    static let limitKey = "BitChord.Storage.CacheLimitMB"
    static let options = ["100 MB", "250 MB", "500 MB", "1 GB"]
    static let fallback = "250 MB"

    var limitBytes: Int64 {
        let text = SettingsStore.shared.string(CacheStore.limitKey, CacheStore.fallback)
        return DownloadLimit.bytes(for: text)
    }

    var limitText: String {
        return DownloadLimit.text(for: limitBytes)
    }

    /// Applied at launch and whenever the limit changes.
    func configure() {
        let bytes = limitBytes
        guard bytes > 0 else { return }
        URLCache.shared.diskCapacity = Int(bytes)
        URLCache.shared.memoryCapacity = min(Int(bytes) / 4, 64 * 1024 * 1024)
    }

    /// Everything the app currently caches, in bytes.
    var sizeBytes: Int64 {
        var total = Int64(URLCache.shared.currentDiskUsage)
        let directory = scratchDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: [.fileSizeKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        for file in files {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
        return total
    }

    /// Artwork and API responses, plus whatever they left on disk.
    func clearImageCache() -> Int64 {
        let before = sizeBytes
        URLCache.shared.removeAllCachedResponses()
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: scratchDirectory,
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles])) ?? []
        for file in files {
            try? manager.removeItem(at: file)
        }
        return max(0, before - sizeBytes)
    }

    /// Partial downloads and scratch files; completed downloads stay.
    func clearSongCache() -> Int64 {
        let before = sizeBytes
        let manager = FileManager.default
        let directory = scratchDirectory
        let files = (try? manager.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles])) ?? []
        for file in files {
            try? manager.removeItem(at: file)
        }
        let downloads = DownloadStore.shared.directoryURL
        let partials = (try? manager.contentsOfDirectory(at: downloads,
                                                         includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles])) ?? []
        for file in partials where file.lastPathComponent.hasPrefix(".part-") {
            try? manager.removeItem(at: file)
        }
        return max(0, before - sizeBytes)
    }

    private var scratchDirectory: URL {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}
