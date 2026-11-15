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
/// `lossless` asks a configured addon for its lossless tier first and falls back
/// to the best the standard catalogue has; the rest map onto the renditions
/// JioSaavn actually serves, which tops out at 320 kbps.
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

/// The download storage limit, kept as the text the row shows. `0` is
/// "Unlimited"; anything else is a byte ceiling for the downloaded set only —
/// it never touches files that are already there.
enum DownloadLimit {
    static let options = ["512 MB", "1 GB", "2 GB", "5 GB", "Unlimited"]
    static let fallback = "2 GB"

    static func bytes(for text: String) -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "unlimited" { return 0 }
        let number = Double(trimmed.split(separator: " ").first.map(String.init) ?? "") ?? 0
        if trimmed.contains("gb") { return Int64(number * 1024 * 1024 * 1024) }
        if trimmed.contains("mb") { return Int64(number * 1024 * 1024) }
        if trimmed.contains("kb") { return Int64(number * 1024) }
        return Int64(number)
    }

    static func text(for bytes: Int64) -> String {
        if bytes <= 0 { return "Unlimited" }
        let megabytes = bytes / (1024 * 1024)
        if megabytes >= 1024 {
            let gigabytes = Double(megabytes) / 1024
            return gigabytes == gigabytes.rounded()
                ? "\(Int(gigabytes)) GB"
                : String(format: "%.1f GB", gigabytes)
        }
        return "\(megabytes) MB"
    }
}

/// A download handed to the system and not finished yet. Written to disk so a
/// relaunch can pick the task back up: a background transfer outlives the
/// process, and its delegate callbacks arrive in the next one.
struct PendingDownload: Codable {
    var track: Track
    var qualityLabel: String
    var startedAt: Date
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
///  - `active` / `failed` is what is happening now, with pending transfers
///    mirrored to `pending.json` so a background task can be adopted again.
///
/// Transfers run in a background `URLSession`, so a download continues while the
/// app is suspended or killed and lands on the next launch. The harness can ask
/// for a paced foreground transport when it needs a transfer slow enough to
/// watch; the resolve, destination, index entry and completion are shared.
final class DownloadStore: NSObject {
    static let shared = DownloadStore()
    static let storageLimitKey = "BitChord.Download.StorageLimit"

    private(set) var saved: [DownloadedTrack] = []
    /// videoID -> 0…1 while running.
    private(set) var active: [String: Double] = [:]
    /// videoID -> reason, for a download that stopped.
    private(set) var failed: [String: String] = [:]

    /// The completion iOS hands us when a background session has events to
    /// deliver; released once the session says it is done.
    var backgroundEventsCompletion: (() -> Void)?

    private var session: URLSession!       // background transfers
    private var pacedSession: URLSession!  // foreground, capture harness only
    private var tasks: [Int: String] = [:]
    private var urls: [String: URL] = [:]
    private var attempts: [String: Int] = [:]
    /// Which session actually carried each track: "background", or
    /// "foreground" when the background one was refused and retried.
    private(set) var transport: [String: String] = [:]
    private var completions: [String: (Bool, String) -> Void] = [:]
    private var lastReported: [String: Double] = [:]

    private var pendingTracks: [String: Track] = [:]
    private var pendingQuality: [String: String] = [:]
    private var failedTracks: [String: Track] = [:]
    private var failedOrder: [String] = []
    private var activeOrder: [String] = []
    /// Tracks the user stopped on purpose. A cancel is not a failure, so it
    /// leaves no row behind; only an actual download error does.
    private var cancelledByUser: Set<String> = []

    /// Replaces the system reachability check. Only the capture harness sets it,
    /// to stand on a metered connection a CI mac never has; the decision it feeds
    /// is the same `isOnWiFi()` branch the app runs on a phone.
    var connectivityOverride: (() -> Bool)?

    /// Seconds to pause per 32 KB chunk. Only the capture harness sets it: the
    /// transfer then runs through a data task that consumes the body at human
    /// speed, so a genuine mid-transfer frame exists to photograph.
    var progressPace: TimeInterval = 0

    private struct PacedTransfer {
        let videoID: String
        let track: Track
        let handle: FileHandle
        let partURL: URL
        var received: Int64
        /// The catalogue CDN does not always send Content-Length; without a
        /// denominator the paced transport would report 0% for the whole file.
        let expectedBytes: Int64
    }
    private var paced: [Int: PacedTransfer] = [:]

    /// Where the files and the index live; the cache screen needs it to find
    /// partial downloads.
    var directoryURL: URL { return directory }

    private let directory: URL
    private let indexURL: URL
    private let pendingURL: URL

    private override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("BitChordDownloads", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        pendingURL = directory.appendingPathComponent("pending.json")
        super.init()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        load()
        loadPending()

        let background = URLSessionConfiguration.background(withIdentifier: "com.bitchord.ios12v2.downloads")
        background.sessionSendsLaunchEvents = true
        background.isDiscretionary = false
        background.timeoutIntervalForResource = 600
        session = URLSession(configuration: background, delegate: self, delegateQueue: nil)

        let foreground = URLSessionConfiguration.default
        foreground.timeoutIntervalForRequest = 30
        foreground.timeoutIntervalForResource = 300
        pacedSession = URLSession(configuration: foreground, delegate: self, delegateQueue: nil)

        // A background task started before the last launch may already be done
        // or still running; give the reconnect a moment, then settle anything the
        // system no longer knows about.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.reconcilePending()
        }
    }

    // MARK: - Queries

    var totalBytes: Int64 {
        return saved.reduce(0) { $0 + $1.byteSize }
    }

    var isEmpty: Bool {
        return saved.isEmpty && active.isEmpty
    }

    /// Downloads started but not yet finished, in the order they were started.
    var activeItems: [Track] {
        return activeOrder.compactMap { pendingTracks[$0] }
    }

    /// Downloads that were refused or stopped, with the reason to show on screen.
    var failedItems: [(track: Track, reason: String)] {
        var items: [(track: Track, reason: String)] = []
        for id in failedOrder {
            guard let track = failedTracks[id] else { continue }
            items.append((track, failed[id] ?? "Download failed."))
        }
        return items
    }

    var pendingCount: Int {
        return pendingTracks.count
    }

    var storageLimitBytes: Int64 {
        return DownloadLimit.bytes(for: SettingsStore.shared.string(DownloadStore.storageLimitKey,
                                                                   DownloadLimit.fallback))
    }

    var storageLimitText: String {
        return DownloadLimit.text(for: storageLimitBytes)
    }

    /// Roughly how big a track will be at this quality, from its duration. Used
    /// for the cap, where exactness does not matter and waiting for the file
    /// would defeat the point of refusing early.
    func estimatedBytes(for track: Track, quality: DownloadQuality) -> Int64 {
        let duration = track.durationSeconds ?? 0
        let seconds = duration > 0 ? duration : 210
        let kbps = Double(quality.kbps ?? 320)
        return Int64((kbps * 1000 / 8) * seconds) + 96 * 1024
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

    /// "1 song · 2.5 MB of 10 MB", the line both the Downloads header and the
    /// Settings row show.
    func storageText() -> String {
        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let limit = storageLimitText
        if saved.isEmpty {
            return limit == "Unlimited" ? "No downloads" : "No downloads · limit \(limit)"
        }
        let songs = "\(saved.count) song\(saved.count == 1 ? "" : "s")"
        return limit == "Unlimited" ? "\(songs) · \(size)" : "\(songs) · \(size) of \(limit)"
    }

    /// Copies completed downloads into Documents/Exports, where iOS File
    /// Sharing and the Files app can reach them. The original cache copy stays
    /// so offline playback keeps working.
    @discardableResult
    func exportAllCompatible() -> Int {
        guard let documents = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else { return 0 }
        let exports = documents.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exports,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        var copied = 0
        for item in saved {
            let source = directory.appendingPathComponent(item.fileName)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let safe = item.track.title.replacingOccurrences(of: "/", with: "-")
            let name = "\(item.track.artist) - \(safe).\(item.fileName.split(separator: ".").last ?? "m4a")"
            let target = exports.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) { copied += 1; continue }
            do {
                try FileManager.default.copyItem(at: source, to: target)
                copied += 1
            } catch {
                continue
            }
        }
        return copied
    }

    /// A tiny on-disk fixture for the settings probe, so the export row is
    /// exercised even when the screenshot run deleted its download.
    func probeSeedExportFixture() -> String {
        let id = "probe-export"
        let name = "\(id).m4a"
        let url = directory.appendingPathComponent(name)
        try? Data(repeating: 1, count: 64).write(to: url, options: .atomic)
        saved.removeAll(where: { $0.track.videoID == id })
        saved.append(DownloadedTrack(track: Track(videoID: id, title: "Probe export",
                                                  artist: "BitChord", durationSeconds: 120),
                                     fileName: name, byteSize: 64, qualityLabel: "High",
                                     downloadedAt: Date()))
        save()
        return id
    }

    func probeClearExportFixture(_ id: String) {
        if let item = saved.first(where: { $0.track.videoID == id }) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.fileName))
        }
        saved.removeAll(where: { $0.track.videoID == id })
        save()
    }

    // MARK: - Downloading

    /// Starts a download, or answers at once when the track is already here.
    ///
    /// The storage limit and `Wi-Fi only` are enforced here rather than at the
    /// call sites so every entry point obeys the same rules.
    func download(_ track: Track, completion: ((Bool, String) -> Void)? = nil) {
        if isDownloaded(track.videoID) {
            completion?(true, "Already downloaded")
            return
        }
        if isDownloading(track.videoID) {
            completion?(false, "Already downloading")
            return
        }

        let quality = DownloadQuality(setting: SettingsStore.shared.string("BitChord.Download.Quality",
                                                                         DownloadQuality.high.rawValue))
        let limit = storageLimitBytes
        if limit > 0 {
            let estimate = estimatedBytes(for: track, quality: quality)
            if totalBytes + estimate > limit {
                let reason = "Storage limit reached. \(storageText()) — free space or raise the limit in Settings."
                failed[track.videoID] = "Storage limit reached."
                failedTracks[track.videoID] = track
                if !failedOrder.contains(track.videoID) { failedOrder.append(track.videoID) }
                postChange()
                completion?(false, reason)
                return
            }
        }

        if SettingsStore.shared.bool("BitChord.Download.WifiOnly", true), !isOnWiFi() {
            // Held rather than silently skipped: the row stays on the screen
            // with the reason (the fuller instruction goes to the alert), which
            // is the only way the user learns why nothing downloaded.
            failed[track.videoID] = "Downloads are limited to Wi-Fi."
            failedTracks[track.videoID] = track
            if !failedOrder.contains(track.videoID) { failedOrder.append(track.videoID) }
            postChange()
            completion?(false, "Downloads are limited to Wi-Fi. Turn that off in Settings to use mobile data.")
            return
        }

        failed.removeValue(forKey: track.videoID)
        failedTracks.removeValue(forKey: track.videoID)
        failedOrder.removeAll(where: { $0 == track.videoID })
        cancelledByUser.remove(track.videoID)
        active[track.videoID] = 0
        lastReported[track.videoID] = 0
        postChange()

        // Lossless asks the addon first. No addon, or nothing for this track,
        // falls through to the standard catalogue without mentioning it.
        if quality == .lossless, AddonService.shared.isConfigured {
            AddonService.shared.stream(for: track) { [weak self] stream in
                DispatchQueue.main.async {
                    guard let self = self, self.active[track.videoID] != nil else { return }
                    if let stream = stream {
                        self.startTransfer(track: track, url: stream.url,
                                           qualityLabel: stream.label, completion: completion)
                    } else {
                        self.resolveAndStart(track: track, quality: quality, completion: completion)
                    }
                }
            }
            return
        }

        resolveAndStart(track: track, quality: quality, completion: completion)
    }

    private func resolveAndStart(track: Track,
                                 quality: DownloadQuality,
                                 completion: ((Bool, String) -> Void)?) {
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
            DispatchQueue.main.async {
                // Cancelled while the resolve was in flight.
                guard self.active[track.videoID] != nil else { return }
                self.startTransfer(track: track, url: url,
                                   qualityLabel: JioSaavnService.shared.lastQualityLabel,
                                   completion: completion)
            }
        }
    }

    private func startTransfer(track: Track,
                               url: URL,
                               qualityLabel: String,
                               completion: ((Bool, String) -> Void)?) {
        completions[track.videoID] = completion
        pendingTracks[track.videoID] = track
        pendingQuality[track.videoID] = qualityLabel
        urls[track.videoID] = url
        attempts[track.videoID] = 1
        if !activeOrder.contains(track.videoID) { activeOrder.append(track.videoID) }
        savePending()
        if progressPace > 0 {
            transport[track.videoID] = "paced"
            startPacedTransfer(track: track, url: url)
        } else {
            transport[track.videoID] = "background"
            let task = session.downloadTask(with: url)
            task.taskDescription = track.videoID
            tasks[task.taskIdentifier] = track.videoID
            task.resume()
        }
    }

    /// The simulator's background session occasionally reports an unclassified
    /// failure (-1) before a single byte arrives, while the same URL works in a
    /// foreground session. One retry keeps a download from dying for that, and
    /// the transport is recorded so the capture can say which one carried it.
    private func retryInForeground(videoID: String, track: Track) {
        guard let url = urls[videoID], attempts[videoID] == 2 else { return }
        attempts[videoID] = 3
        transport[videoID] = "foreground"
        let task = pacedSession.downloadTask(with: url)
        task.taskDescription = videoID
        tasks[task.taskIdentifier] = videoID
        task.resume()
    }

    /// A background task can fail before its first byte on the simulator. Try
    /// the same transport once more before falling back to a foreground task;
    /// the retry is what keeps a keep-mode capture genuinely backgrounded.
    private func retryInBackground(videoID: String, track: Track) {
        guard let url = urls[videoID], attempts[videoID] == 1 else { return }
        attempts[videoID] = 2
        transport[videoID] = "background"
        let task = session.downloadTask(with: url)
        task.taskDescription = videoID
        tasks[task.taskIdentifier] = videoID
        task.resume()
    }

    /// Data-task transport used only when the capture harness asks for a paced
    /// transfer: same resolve, same file, same index entry, consumed by hand.
    private func startPacedTransfer(track: Track, url: URL) {
        let partURL = directory.appendingPathComponent(".part-\(track.videoID)")
        try? FileManager.default.removeItem(at: partURL)
        FileManager.default.createFile(atPath: partURL.path, contents: nil, attributes: nil)
        guard let handle = try? FileHandle(forWritingTo: partURL) else {
            finish(track: track, error: "Could not open a file for the download.")
            return
        }
        let task = pacedSession.dataTask(with: url)
        task.taskDescription = track.videoID
        let quality = DownloadQuality(setting: SettingsStore.shared.string("BitChord.Download.Quality",
                                                                         DownloadQuality.high.rawValue))
        paced[task.taskIdentifier] = PacedTransfer(videoID: track.videoID, track: track,
                                                  handle: handle, partURL: partURL, received: 0,
                                                  expectedBytes: estimatedBytes(for: track, quality: quality))
        tasks[task.taskIdentifier] = track.videoID
        task.resume()
    }

    func cancel(_ videoID: String) {
        cancelledByUser.insert(videoID)
        guard let pair = tasks.first(where: { $0.value == videoID }) else {
            active.removeValue(forKey: videoID)
            cancelledByUser.remove(videoID)
            clearPending(videoID)
            postChange()
            return
        }
        let session: URLSession = self.session
        let pacedSession: URLSession = self.pacedSession
        let find: (URLSession) -> Void = { target in
            target.getTasksWithCompletionHandler { dataTasks, _, downloadTasks in
                // Paced transfers are data tasks; ordinary downloads are download
                // tasks, so both lists have to be searched.
                let all: [URLSessionTask] = dataTasks.map { $0 } + downloadTasks.map { $0 }
                for task in all where task.taskIdentifier == pair.key {
                    task.cancel()
                }
            }
        }
        find(session)
        find(pacedSession)
        DispatchQueue.main.async { [weak self] in
            self?.active.removeValue(forKey: videoID)
            self?.tasks.removeValue(forKey: pair.key)
            self?.activeOrder.removeAll(where: { $0 == videoID })
            self?.pendingTracks.removeValue(forKey: videoID)
            self?.pendingQuality.removeValue(forKey: videoID)
            self?.completions.removeValue(forKey: videoID)
            self?.clearPending(videoID)
            self?.postChange()
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

    private func finish(track: Track, error: String) {
        let userStopped = cancelledByUser.remove(track.videoID) != nil
        active.removeValue(forKey: track.videoID)
        if !userStopped {
            failed[track.videoID] = error
            failedTracks[track.videoID] = track
            if !failedOrder.contains(track.videoID) { failedOrder.append(track.videoID) }
        }
        activeOrder.removeAll(where: { $0 == track.videoID })
        pendingTracks.removeValue(forKey: track.videoID)
        pendingQuality.removeValue(forKey: track.videoID)
        clearPending(track.videoID)
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

    private func loadPending() {
        guard let data = try? Data(contentsOf: pendingURL),
              let stored = try? JSONDecoder().decode([String: PendingDownload].self, from: data),
              !stored.isEmpty else { return }
        for (videoID, item) in stored {
            pendingTracks[videoID] = item.track
            pendingQuality[videoID] = item.qualityLabel
            active[videoID] = 0
            activeOrder.append(videoID)
        }
    }

    private func savePending() {
        var stored: [String: PendingDownload] = [:]
        for (videoID, track) in pendingTracks {
            stored[videoID] = PendingDownload(track: track,
                                              qualityLabel: pendingQuality[videoID] ?? "",
                                              startedAt: Date())
        }
        guard !stored.isEmpty else {
            try? FileManager.default.removeItem(at: pendingURL)
            return
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: pendingURL, options: .atomic)
    }

    private func clearPending(_ videoID: String) {
        pendingTracks.removeValue(forKey: videoID)
        pendingQuality.removeValue(forKey: videoID)
        savePending()
    }

    /// Whatever the system no longer knows about after a relaunch is settled
    /// here: a file that landed is adopted, anything else is reported rather
    /// than left spinning forever.
    private func reconcilePending() {
        guard !pendingTracks.isEmpty else { return }
        session.getAllTasks { [weak self] tasks in
            let live = Set(tasks.compactMap { $0.taskDescription })
            DispatchQueue.main.async {
                guard let self = self else { return }
                for (videoID, track) in self.pendingTracks {
                    if live.contains(videoID) { continue }
                    if let item = self.adoptFinishedFile(videoID: videoID, track: track) {
                        self.saved.removeAll(where: { $0.track.videoID == videoID })
                        self.saved.insert(item, at: 0)
                        self.save()
                        self.active.removeValue(forKey: videoID)
                        self.activeOrder.removeAll(where: { $0 == videoID })
                        self.clearPending(videoID)
                        continue
                    }
                    self.active.removeValue(forKey: videoID)
                    let userStopped = self.cancelledByUser.remove(videoID) != nil
                    if !userStopped {
                        self.failed[videoID] = "Download interrupted. Tap to try again."
                        self.failedTracks[videoID] = track
                        if !self.failedOrder.contains(videoID) { self.failedOrder.append(videoID) }
                    }
                    self.activeOrder.removeAll(where: { $0 == videoID })
                    self.clearPending(videoID)
                }
                self.postChange()
            }
        }
    }

    /// A background transfer can finish while the app is dead; its file is moved
    /// into place by the delegate on relaunch, but if only the bytes survive,
    /// this turns them back into an index entry.
    private func adoptFinishedFile(videoID: String, track: Track) -> DownloadedTrack? {
        let fileName = videoID.replacingOccurrences(of: "/", with: "_") + ".m4a"
        let destination = directory.appendingPathComponent(fileName)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value,
              size > 0 else { return nil }
        return DownloadedTrack(track: track,
                               fileName: fileName,
                               byteSize: size,
                               qualityLabel: pendingQuality[videoID] ?? "",
                               downloadedAt: Date())
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
        if let override = connectivityOverride { return override() }
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

    /// The track a task belongs to, across relaunches: the system persists the
    /// task description, so it can be adopted before any in-memory map exists.
    private func videoID(for task: URLSessionTask) -> String? {
        if let known = tasks[task.taskIdentifier] { return known }
        if let described = task.taskDescription, pendingTracks[described] != nil {
            tasks[task.taskIdentifier] = described
            return described
        }
        return nil
    }
}

extension DownloadStore: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let videoID = videoID(for: downloadTask) else { return }
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        // Report in whole percent: the UI only ever prints an integer, and this
        // keeps the notification stream from waking every row on each packet.
        let rounded = (fraction * 100).rounded() / 100
        DispatchQueue.main.async {
            guard self.active[videoID] != nil, rounded != self.lastReported[videoID] else { return }
            self.lastReported[videoID] = rounded
            self.active[videoID] = rounded
            self.postChange()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let videoID = videoID(for: downloadTask),
              let track = pendingTracks[videoID] else { return }
        storeCompletedFile(videoID: videoID, track: track, from: location,
                           clearing: downloadTask.taskIdentifier)
    }

    /// Moves a finished download into place and records it. Shared by the normal
    /// download task and the paced data task the capture harness uses.
    private func storeCompletedFile(videoID: String, track: Track, from location: URL,
                                    clearing identifier: Int?) {
        let fileName = videoID.replacingOccurrences(of: "/", with: "_") + ".m4a"
        let destination = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            DispatchQueue.main.async { self.finish(track: track, error: "Could not save the file.") }
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            try? FileManager.default.removeItem(at: destination)
            DispatchQueue.main.async { self.finish(track: track, error: "The download was empty.") }
            return
        }
        DispatchQueue.main.async {
            let quality = self.pendingQuality[videoID] ?? ""
            self.saved.removeAll(where: { $0.track.videoID == videoID })
            self.saved.insert(DownloadedTrack(track: track,
                                              fileName: fileName,
                                              byteSize: size,
                                              qualityLabel: quality,
                                              downloadedAt: Date()), at: 0)
            self.save()
            if SettingsStore.shared.exportCompatibleDownloads {
                self.exportAllCompatible()
            }
            self.active.removeValue(forKey: videoID)
            self.failed.removeValue(forKey: videoID)
            self.failedTracks.removeValue(forKey: videoID)
            self.failedOrder.removeAll(where: { $0 == videoID })
            self.cancelledByUser.remove(videoID)
            self.activeOrder.removeAll(where: { $0 == videoID })
            self.clearPending(videoID)
            if let identifier = identifier { self.tasks.removeValue(forKey: identifier) }
            let completion = self.completions.removeValue(forKey: videoID)
            self.postChange()
            completion?(true, "Downloaded")
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        // A paced transfer writes its own file, so it is finished here rather
        // than in the download-task callback.
        if let transfer = paced.removeValue(forKey: task.taskIdentifier) {
            // closeFile(), not close(): the latter is iOS 13 and up.
            transfer.handle.closeFile()
            if error == nil {
                storeCompletedFile(videoID: transfer.videoID, track: transfer.track,
                                   from: transfer.partURL, clearing: task.taskIdentifier)
            } else {
                try? FileManager.default.removeItem(at: transfer.partURL)
                var cancelled = false
                if let error = error {
                    cancelled = (error as NSError).code == NSURLErrorCancelled
                }
                let message = cancelled ? "Download cancelled."
                                        : (error?.localizedDescription ?? "Download failed.")
                DispatchQueue.main.async {
                    self.tasks.removeValue(forKey: task.taskIdentifier)
                    self.finish(track: transfer.track, error: message)
                }
            }
            return
        }
        guard let error = error,
              let videoID = videoID(for: task),
              let track = pendingTracks[videoID] else { return }
        let ns = error as NSError
        let retryableCodes: Set<Int> = [
            NSURLErrorUnknown,
            NSURLErrorCancelled,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNotConnectedToInternet
        ]
        // The simulator hands a background task back with a transport error
        // when the app is relaunched; a real phone can do the same after a
        // network hand-off. One foreground retry turns that into a completed
        // download instead of an interrupted row, while a deliberate cancel
        // still remains a cancel.
        if ns.domain == NSURLErrorDomain, retryableCodes.contains(ns.code),
           transport[videoID] == "background",
           !cancelledByUser.contains(videoID) {
            DispatchQueue.main.async {
                self.tasks.removeValue(forKey: task.taskIdentifier)
                if self.attempts[videoID] == 1 {
                    self.retryInBackground(videoID: videoID, track: track)
                } else if self.attempts[videoID] == 2 {
                    self.retryInForeground(videoID: videoID, track: track)
                }
            }
            return
        }
        let message = ns.code == NSURLErrorCancelled
            ? "Download cancelled."
            : "\(ns.localizedDescription) [\(ns.domain) \(ns.code)]"
        DispatchQueue.main.async {
            self.tasks.removeValue(forKey: task.taskIdentifier)
            self.finish(track: track, error: message)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            let completion = self.backgroundEventsCompletion
            self.backgroundEventsCompletion = nil
            completion?()
        }
    }
}

extension DownloadStore: URLSessionDataDelegate {
    /// Consumes a paced download by hand, 32 KB at a time, so the transfer can
    /// be watched and photographed. It is the harness's transport only.
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard var transfer = paced[dataTask.taskIdentifier] else { return }
        let chunkSize = 32 * 1024
        let expected = dataTask.countOfBytesExpectedToReceive > 0
            ? dataTask.countOfBytesExpectedToReceive
            : transfer.expectedBytes
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            if progressPace > 0 { Thread.sleep(forTimeInterval: progressPace) }
            transfer.handle.write(data.subdata(in: offset..<end))
            transfer.received += Int64(end - offset)
            offset = end
            paced[dataTask.taskIdentifier] = transfer
            let fraction = expected > 0 ? min(0.99, Double(transfer.received) / Double(expected)) : 0
            DispatchQueue.main.async {
                guard self.active[transfer.videoID] != nil else { return }
                self.active[transfer.videoID] = fraction
                self.postChange()
            }
        }
    }
}
