import Foundation
import SystemConfiguration

/// A track that has been downloaded, with where it lives and how big it is.
struct DownloadedTrack: Codable {
    var track: Track
    var fileName: String
    var byteSize: Int64
    var qualityLabel: String
    var downloadedAt: Date
}

/// What the download setting means for the file that gets fetched.
///
/// The Android app keeps a separate ceiling for downloads; here it maps onto the
/// renditions JioSaavn actually serves, which tops out at 320 kbps.
enum DownloadQuality: String {
    case lossless = "Lossless"
    case high = "High"
    case normal = "Normal"
    case dataSaver = "Data saver"

    static let all: [String] = [lossless.rawValue, high.rawValue, normal.rawValue, dataSaver.rawValue]

    init(setting: String) {
        self = DownloadQuality(rawValue: setting) ?? .high
    }

    var kbps: Int? {
        switch self {
        case .lossless, .high: return 320
        case .normal: return 160
        case .dataSaver: return 96
        }
    }
}

extension Notification.Name {
    /// Posted on the main queue whenever the saved set, a progress figure or a
    /// failure changes, so every surface showing download state can refresh.
    static let downloadsDidChange = Notification.Name("BitChordDownloadsDidChange")
}

/// The download queue and the record of what exists on disk.
///
/// Two kinds of state, deliberately separate, as upstream splits them:
///  - `saved` is what survives a relaunch — an index written to Application
///    Support, with one audio file beside it per track.
///  - `active` / `failed` is what is happening now — in memory, because a
///    download interrupted by the process dying did not happen.
///
/// Downloads are fetched from the same JioSaavn CDN the player already resolves,
/// so a downloaded track is the exact bytes AVPlayer would have streamed.
final class DownloadStore: NSObject {
    static let shared = DownloadStore()

    private(set) var saved: [DownloadedTrack] = []
    /// videoID -> 0…1 while running.
    private(set) var active: [String: Double] = [:]
    /// videoID -> reason, for a download that stopped.
    private(set) var failed: [String: String] = [:]

    private var session: URLSession!
    private var tasks: [Int: String] = [:]
    private var completions: [String: (Bool, String) -> Void] = [:]
    private var lastReported: [String: Double] = [:]

    private let directory: URL
    private let indexURL: URL

    private override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("BitChordDownloads", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        super.init()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        load()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Queries

    var totalBytes: Int64 {
        return saved.reduce(0) { $0 + $1.byteSize }
    }

    var isEmpty: Bool {
        return saved.isEmpty && active.isEmpty
    }

    func isDownloaded(_ videoID: String) -> Bool {
        return localURL(for: videoID) != nil
    }

    func isDownloading(_ videoID: String) -> Bool {
        return active[videoID] != nil
    }

    func progress(for videoID: String) -> Double? {
        return active[videoID]
    }

    func failure(for videoID: String) -> String? {
        return failed[videoID]
    }

    func savedItem(for videoID: String) -> DownloadedTrack? {
        return saved.first(where: { $0.track.videoID == videoID })
    }

    /// The file, but only if it is really there — an index entry can outlive the
    /// bytes it names if the container is cleaned out underneath the app.
    func localURL(for videoID: String) -> URL? {
        guard let item = saved.first(where: { $0.track.videoID == videoID }) else { return nil }
        let url = directory.appendingPathComponent(item.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return (size ?? 0) > 0 ? url : nil
    }

    func storageText() -> String {
        if saved.isEmpty { return "No downloads" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let size = formatter.string(fromByteCount: totalBytes)
        return "\(saved.count) song\(saved.count == 1 ? "" : "s") · \(size)"
    }

    // MARK: - Downloading

    /// Starts a download, or answers at once when the track is already here.
    ///
    /// `Wi-Fi only` is enforced here rather than at the call sites so every entry
    /// point obeys the same rule.
    func download(_ track: Track, completion: ((Bool, String) -> Void)? = nil) {
        if isDownloaded(track.videoID) {
            completion?(true, "Already downloaded")
            return
        }
        if isDownloading(track.videoID) {
            completion?(false, "Already downloading")
            return
        }
        if SettingsStore.shared.bool("BitChord.Download.WifiOnly", true), !isOnWiFi() {
            failed[track.videoID] = "Downloads are limited to Wi-Fi."
            postChange()
            completion?(false, "Downloads are limited to Wi-Fi. Turn that off in Settings to use mobile data.")
            return
        }

        failed.removeValue(forKey: track.videoID)
        active[track.videoID] = 0
        lastReported[track.videoID] = 0
        postChange()

        let quality = DownloadQuality(setting: SettingsStore.shared.string("BitChord.Download.Quality",
                                                                          DownloadQuality.high.rawValue))
        JioSaavnService.shared.resolve(title: track.title,
                                       artist: track.artist,
                                       durationSeconds: track.durationSeconds,
                                       preferredKbps: quality.kbps) { [weak self] url, reason in
            guard let self = self else { return }
            guard let url = url, let scheme = url.scheme, scheme.hasPrefix("http") else {
                self.finish(track: track, error: reason.isEmpty ? "No stream URL was returned." : reason)
                completion?(false, reason)
                return
            }
            let task = self.session.downloadTask(with: url)
            self.tasks[task.taskIdentifier] = track.videoID
            self.completions[track.videoID] = completion
            self.pendingTracks[track.videoID] = track
            if !self.activeOrder.contains(track.videoID) { self.activeOrder.append(track.videoID) }
            self.pendingQuality[track.videoID] = JioSaavnService.shared.lastQualityLabel
            task.resume()
        }
    }

    func cancel(_ videoID: String) {
        guard let pair = tasks.first(where: { $0.value == videoID }) else {
            active.removeValue(forKey: videoID)
            postChange()
            return
        }
        session.getTasksWithCompletionHandler { [weak self] _, _, downloadTasks in
            for task in downloadTasks where task.taskIdentifier == pair.key {
                task.cancel()
            }
            DispatchQueue.main.async {
                self?.active.removeValue(forKey: videoID)
                self?.tasks.removeValue(forKey: pair.key)
                self?.activeOrder.removeAll(where: { $0 == videoID })
                self?.pendingTracks.removeValue(forKey: videoID)
                self?.pendingQuality.removeValue(forKey: videoID)
                self?.completions.removeValue(forKey: videoID)
                self?.postChange()
            }
        }
    }

    /// Removes the index entry and the file it names.
    func remove(_ videoID: String) {
        if isDownloading(videoID) {
            cancel(videoID)
        }
        guard let index = saved.firstIndex(where: { $0.track.videoID == videoID }) else { return }
        let item = saved.remove(at: index)
        let url = directory.appendingPathComponent(item.fileName)
        try? FileManager.default.removeItem(at: url)
        save()
        postChange()
    }

    func removeAll() {
        for item in saved {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.fileName))
        }
        saved.removeAll()
        save()
        postChange()
    }

    private var pendingTracks: [String: Track] = [:]
    private var pendingQuality: [String: String] = [:]
    /// Insertion order for the in-flight downloads, so the screen lists them the
    /// way they were started rather than in dictionary order.
    private var activeOrder: [String] = []

    /// The downloads in flight, in the order they were started.
    var activeItems: [Track] {
        return activeOrder.compactMap { pendingTracks[$0] }
    }

    private func finish(track: Track, error: String) {
        active.removeValue(forKey: track.videoID)
        failed[track.videoID] = error
        activeOrder.removeAll(where: { $0 == track.videoID })
        pendingTracks.removeValue(forKey: track.videoID)
        pendingQuality.removeValue(forKey: track.videoID)
        let completion = completions.removeValue(forKey: track.videoID)
        postChange()
        completion?(false, error)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode([DownloadedTrack].self, from: data) else { return }
        // Drop entries whose file vanished, so the list never advertises a track
        // it cannot play.
        saved = stored.filter { item in
            let url = directory.appendingPathComponent(item.fileName)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            return (size ?? 0) > 0
        }
        if saved.count != stored.count {
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func postChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
            }
        }
    }

    // MARK: - Wi-Fi check

    /// Whether the active interface is Wi-Fi. Returns true when reachability
    /// cannot be read, because refusing a download on a broken probe is worse
    /// than allowing one.
    private func isOnWiFi() -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        guard let reach = withUnsafePointer(to: &address, { pointer -> SCNetworkReachability? in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                SCNetworkReachabilityCreateWithAddress(nil, rebound)
            }
        }) else { return true }
        var flags = SCNetworkReachabilityFlags()
        guard SCNetworkReachabilityGetFlags(reach, &flags) else { return true }
        return !flags.contains(.isWWAN)
    }
}

extension DownloadStore: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let videoID = tasks[downloadTask.taskIdentifier] else { return }
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        // Report in whole percent: the UI only ever prints an integer, and this
        // keeps the notification stream from waking every row on each packet.
        let rounded = (fraction * 100).rounded() / 100
        guard rounded != lastReported[videoID] else { return }
        lastReported[videoID] = rounded
        active[videoID] = rounded
        postChange()
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let videoID = tasks[downloadTask.taskIdentifier],
              let track = pendingTracks[videoID] else { return }

        let fileName = videoID.replacingOccurrences(of: "/", with: "_") + ".m4a"
        let destination = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            finish(track: track, error: "Could not save the file.")
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            try? FileManager.default.removeItem(at: destination)
            finish(track: track, error: "The download was empty.")
            return
        }
        let quality = pendingQuality[videoID] ?? ""
        saved.removeAll(where: { $0.track.videoID == videoID })
        saved.insert(DownloadedTrack(track: track,
                                     fileName: fileName,
                                     byteSize: size,
                                     qualityLabel: quality,
                                     downloadedAt: Date()), at: 0)
        save()
        active.removeValue(forKey: videoID)
        failed.removeValue(forKey: videoID)
        activeOrder.removeAll(where: { $0 == videoID })
        pendingTracks.removeValue(forKey: videoID)
        pendingQuality.removeValue(forKey: videoID)
        tasks.removeValue(forKey: downloadTask.taskIdentifier)
        let completion = completions.removeValue(forKey: videoID)
        postChange()
        completion?(true, "Downloaded")
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error = error,
              let videoID = tasks[task.taskIdentifier],
              let track = pendingTracks[videoID] else { return }
        let message = (error as NSError).code == NSURLErrorCancelled
            ? "Download cancelled."
            : error.localizedDescription
        tasks.removeValue(forKey: task.taskIdentifier)
        finish(track: track, error: message)
    }
}
