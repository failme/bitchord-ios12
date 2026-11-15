import AVFoundation
import Foundation

/// Direct Source Stream support: resolves the next queue item ahead of the
/// transition and lets AVFoundation open the media before it is needed.
/// Requests are deduplicated by video id; the report exposes how many were
/// started and how many assets became playable.
final class StreamPrefetcher {
    static let shared = StreamPrefetcher()

    private(set) var requests = 0
    private(set) var ready = 0
    private(set) var failures = 0
    private var inFlight: Set<String> = []
    private var assets: [String: AVURLAsset] = [:]
    private let lock = NSLock()

    private init() {}

    func prefetch(videoID: String) {
        guard !videoID.isEmpty, !videoID.hasPrefix("jellyfin:"),
              !videoID.hasPrefix("webdav:"), !videoID.hasPrefix("local:") else { return }
        lock.lock()
        if inFlight.contains(videoID) || assets[videoID] != nil {
            lock.unlock()
            return
        }
        inFlight.insert(videoID)
        requests += 1
        lock.unlock()
        InnerTube.shared.resolveStreamURL(videoID: videoID) { [weak self] url, _ in
            guard let self = self else { return }
            guard let url = url, let scheme = url.scheme, scheme.hasPrefix("http") else {
                self.lock.lock()
                self.inFlight.remove(videoID)
                self.failures += 1
                self.lock.unlock()
                return
            }
            let asset = AVURLAsset(url: url)
            asset.loadValuesAsynchronously(forKeys: ["playable", "tracks"]) {
                DispatchQueue.main.async {
                    self.lock.lock()
                    self.inFlight.remove(videoID)
                    self.assets[videoID] = asset
                    self.ready += 1
                    self.lock.unlock()
                }
            }
        }
    }

    func asset(for videoID: String) -> AVURLAsset? {
        lock.lock()
        defer { lock.unlock() }
        return assets[videoID]
    }

    var report: String {
        lock.lock()
        defer { lock.unlock() }
        return "requests=\(requests) ready=\(ready) failed=\(failures) held=\(assets.count)"
    }
}
