import UIKit

/// Renders the tabs to PNGs when the app is launched with `-BCScreenshots <dir>`.
///
/// There is no iOS 12 runtime to look at and no Mac in hand, but the deployment
/// target is 12.0, so the app runs unchanged on the simulator the build machine
/// already has. This writes the screens out for the CI job to collect — the only
/// way to judge the interface without a device.
enum ScreenshotHarness {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        // A first launch downloads one track and exits; CI then relaunches with
        // -BCScreenshots, so the capture proves the index survived a restart
        // rather than reading back this process's memory.
        if let seed = arguments.firstIndex(of: "-BCSeedDownload"), seed + 1 < arguments.count {
            seedDownload(directory: URL(fileURLWithPath: arguments[seed + 1], isDirectory: true))
            return
        }
        guard let flag = arguments.firstIndex(of: "-BCScreenshots"),
              flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        // Give Home and Explore a moment to make their network calls.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            capture(directory: directory)
        }
    }

    private static func capture(directory: URL) {
        guard let window = UIApplication.shared.keyWindow,
              let root = window.rootViewController as? RootViewController else { return }
        let names = ["home", "explore", "library", "search"]
        var index = 0
        var step: (() -> Void)?

        step = {
            guard index < names.count else {
                capturePlayer(window: window, root: root, directory: directory)
                return
            }
            let name = names[index]
            root.showTab(index)
            index += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                write(window: window, name: name, directory: directory)
                step?()
            }
        }
        step?()
    }

    /// Plays a track and photographs the lyrics panel, so the one screen whose
    /// look depends on a live provider is still judged from a capture.
    private static func capturePlayer(window: UIWindow, root: RootViewController, directory: URL) {
        CatalogueSearch.shared.songs("Blinding Lights The Weeknd") { tracks in
            guard let track = tracks.first else {
                exit(0)
            }
            PlayerService.shared.play(tracks: [track], startingAt: 0)
            root.presentNowPlayingFromRoot()
            // The vocal enters around half a minute in; seek there so the
            // capture shows the sweep mid-line instead of a silent intro.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                PlayerService.shared.seek(toFraction: 0.16)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if let player = root.presentedViewController as? NowPlayingViewController {
                    player.showLyricsForScreenshots()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    write(window: window, name: "lyrics", directory: directory)
                    guard let player = root.presentedViewController as? NowPlayingViewController else {
                        exit(0)
                    }
                    let settings = SettingsViewController()
                    settings.modalPresentationStyle = .fullScreen
                    player.present(settings, animated: false) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            write(window: window, name: "settings", directory: directory)
                            settings.scrollToDownloadSection()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                write(window: window, name: "settings-downloads", directory: directory)
                                captureDownloads(window: window, root: root, directory: directory)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Downloads

    /// Downloads one track and writes what happened beside the screenshots.
    private static func seedDownload(directory: URL) {
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        var report = ["seed: start"]
        CatalogueSearch.shared.songs("Blinding Lights The Weeknd") { tracks in
            guard let track = tracks.first else {
                report.append("seed: no search results")
                writeReport(report.joined(separator: "\n"), directory: directory)
                exit(0)
            }
            report.append("seed: track \(track.title) / \(track.artist)")
            if DownloadStore.shared.isDownloaded(track.videoID) {
                report.append("seed: already downloaded")
                writeReport(report.joined(separator: "\n"), directory: directory)
                exit(0)
            }
            DownloadStore.shared.download(track) { ok, message in
                report.append("seed: download ok=\(ok) message=\(message)")
                report.append("seed: saved=\(DownloadStore.shared.saved.count)")
                report.append("seed: bytes=\(DownloadStore.shared.totalBytes)")
                if let url = DownloadStore.shared.localURL(for: track.videoID) {
                    report.append("seed: file=\(url.lastPathComponent)")
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                    report.append("seed: fileBytes=\(size)")
                } else {
                    report.append("seed: no local file")
                }
                writeReport(report.joined(separator: "\n"), directory: directory)
                exit(0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            report.append("seed: timed out")
            writeReport(report.joined(separator: "\n"), directory: directory)
            exit(0)
        }
    }

    /// Photographs the Downloads screen, then plays the saved file and
    /// photographs the player — recording whether the engine really took the
    /// local path rather than a stream. The saved track here was written by the
    /// seed launch, so finding it is the relaunch proof.
    private static func captureDownloads(window: UIWindow, root: RootViewController, directory: URL) {
        let capture = DownloadCapture(window: window, root: root, directory: directory)
        root.dismiss(animated: false) {
            let downloads = DownloadsViewController()
            downloads.modalPresentationStyle = .fullScreen
            root.present(downloads, animated: false) {
                after(2) { captureResume(capture, downloads: downloads) }
            }
        }
    }

    /// The state the seed left behind, offline playback, then deletion.
    private static func captureResume(_ capture: DownloadCapture, downloads: DownloadsViewController) {
        let store = capture.store
        capture.report.append("resume.saved=\(store.saved.count)")
        capture.report.append("resume.totalBytes=\(store.totalBytes)")
        guard let item = store.saved.first,
              let fileURL = store.localURL(for: item.track.videoID) else {
            capture.report.append("resume.missing=true")
            capture.shot("downloads")
            capture.finish()
            return
        }
        capture.seedTrack = item.track
        capture.highBytes = item.byteSize
        capture.report.append("quality.high.bytes=\(item.byteSize)")
        capture.report.append("quality.high.label=\(item.qualityLabel)")
        capture.shot("downloads")
        // Keep the 320 file so the CI runner can measure it with afinfo.
        copy(fileURL, to: capture.directory.appendingPathComponent("quality-high.m4a"))
        capture.checkpoint()

        PlayerService.shared.play(tracks: [item.track], startingAt: 0)
        after(6) {
            capture.report.append("localPlayback=\(AudioEngine.shared.currentIsLocal)")
            capture.report.append("source=\(AudioEngine.shared.currentSourceLabel)")
            downloads.dismiss(animated: false) { capture.root.presentNowPlaying() }
            after(3) {
                capture.shot("offline")
                let path = store.localURL(for: item.track.videoID)
                store.remove(item.track.videoID)
                capture.report.append("deletedRows=\(store.saved.count)")
                capture.report.append("fileRemoved=\(path.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false)")
                capture.checkpoint()
                capture.root.dismiss(animated: false) {
                    let empty = DownloadsViewController()
                    empty.modalPresentationStyle = .fullScreen
                    capture.root.present(empty, animated: false) {
                        after(1) {
                            capture.shot("downloads-empty")
                            startQualityProbe(capture, host: empty)
                        }
                    }
                }
            }
        }
    }

    /// Downloads the same track again at Data saver, photographs the transfer
    /// mid-flight, then records what was stored.
    private static func startQualityProbe(_ capture: DownloadCapture, host: UIViewController) {
        guard let track = capture.seedTrack else {
            capture.finish()
            return
        }
        // The same key the Settings row writes, through the same store.
        SettingsStore.shared.set(DownloadQuality.dataSaver.rawValue,
                                 for: "BitChord.Download.Quality")
        capture.report.append("quality.setting=\(SettingsStore.shared.string("BitChord.Download.Quality", ""))")
        // ~75 chunks for a 2.4 MB file at 96 kbps, so the transfer lasts long
        // enough to photograph at a real percentage.
        capture.store.progressPace = 0.08
        capture.store.download(track) { ok, message in
            capture.report.append("quality.saver.ok=\(ok)")
            if !ok { capture.report.append("quality.saver.message=\(message)") }
        }
        after(1.2) {
            snapProgress(capture, track: track, attempt: 0) {
                waitUntil({ capture.store.isDownloaded(track.videoID)
                            || capture.store.failure(for: track.videoID) != nil },
                          timeout: 90) { finished in
                    capture.store.progressPace = 0
                    guard finished, let item = capture.store.savedItem(for: track.videoID),
                          let url = capture.store.localURL(for: track.videoID) else {
                        capture.report.append("quality.saver.missing=true")
                        capture.finish()
                        return
                    }
                    capture.saverBytes = item.byteSize
                    capture.report.append("quality.saver.bytes=\(item.byteSize)")
                    capture.report.append("quality.saver.label=\(item.qualityLabel)")
                    capture.report.append("quality.saverSmaller=\(item.byteSize < capture.highBytes)")
                    copy(url, to: capture.directory.appendingPathComponent("quality-saver.m4a"))
                    capture.shot("downloads-saver")
                    capture.checkpoint()
                    captureSettings(capture, host: host)
                }
            }
        }
    }

    /// Waits for a percentage that is genuinely mid-transfer, then shoots it.
    private static func snapProgress(_ capture: DownloadCapture, track: Track, attempt: Int,
                                     then: @escaping () -> Void) {
        let fraction = capture.store.progress(for: track.videoID) ?? 0
        if (fraction > 0.02 && fraction < 0.98) || attempt >= 8 {
            capture.report.append("progress.captured=\(Int((fraction * 100).rounded()))")
            capture.shot("download-progress")
            then()
            return
        }
        after(0.8) { snapProgress(capture, track: track, attempt: attempt + 1, then: then) }
    }

    private static func captureSettings(_ capture: DownloadCapture, host: UIViewController) {
        let settings = SettingsViewController()
        settings.modalPresentationStyle = .fullScreen
        host.present(settings, animated: false) {
            after(0.8) {
                settings.scrollToDownloadSection()
                after(0.8) {
                    capture.shot("settings-downloads")
                    capture.report.append("settings.storage=\(capture.store.storageText())")
                    capture.checkpoint()
                    settings.dismiss(animated: false) { captureSheets(capture, host: host) }
                }
            }
        }
    }

    /// Opens the real row menu in all three states on one real list, so the
    /// shots show the sheet a long press produces, not a mock of it.
    private static func captureSheets(_ capture: DownloadCapture, host: UIViewController) {
        guard let saved = capture.store.saved.first else {
            capture.report.append("sheets.noSaved=true")
            capture.finish()
            return
        }
        CatalogueSearch.shared.songs("Shape of You Ed Sheeran") { found in
            let others = found.filter { $0.videoID != saved.track.videoID }
            guard let downloading = others.first, let untouched = others.dropFirst().first else {
                capture.report.append("sheets.tracks=false")
                capture.finish()
                return
            }
            capture.extraTrack = untouched
            // Slow enough that the menu can be photographed while the row still
            // says it is downloading, then cancelled from that same menu.
            capture.store.progressPace = 0.1
            capture.store.download(downloading) { _, _ in }
            after(0.8) {
                host.dismiss(animated: false) {
                    let list = TrackListViewController()
                    list.tracks = [saved.track, downloading, untouched]
                    list.modalPresentationStyle = .fullScreen
                    capture.root.present(list, animated: false) {
                        after(1) {
                            let cells = trackCells(in: list.view)
                            guard cells.count >= 3 else {
                                capture.report.append("sheets.cells=\(cells.count)")
                                capture.finish()
                                return
                            }
                            cells[0].presentMenu()
                            after(0.7) {
                                capture.shot("sheet-delete")
                                capture.report.append("sheet.delete.downloaded=\(capture.store.isDownloaded(saved.track.videoID))")
                                TrackActions.topController()?.dismiss(animated: false) {
                                    cells[1].presentMenu()
                                    after(0.7) {
                                        capture.shot("sheet-cancel")
                                        capture.report.append("sheet.cancel.downloading=\(capture.store.isDownloading(downloading.videoID))")
                                        TrackActions.topController()?.dismiss(animated: false) {
                                            cells[2].presentMenu()
                                            after(0.7) {
                                                capture.shot("sheet-download")
                                                let idle = !capture.store.isDownloaded(untouched.videoID)
                                                    && !capture.store.isDownloading(untouched.videoID)
                                                capture.report.append("sheet.download.idle=\(idle)")
                                                capture.checkpoint()
                                                TrackActions.topController()?.dismiss(animated: false) {
                                                    capture.store.cancel(downloading.videoID)
                                                    capture.store.progressPace = 0
                                                    after(0.5) { wifiProbe(capture, host: list) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// With Wi-Fi-only on and the connection reported as metered, the store must
    /// hold the download and the row must say why.
    private static func wifiProbe(_ capture: DownloadCapture, host: UIViewController) {
        guard let track = capture.extraTrack else {
            capture.finish()
            return
        }
        SettingsStore.shared.set(true, for: "BitChord.Download.WifiOnly")
        capture.report.append("wifi.setting=\(SettingsStore.shared.bool("BitChord.Download.WifiOnly", false))")
        capture.store.connectivityOverride = { false }
        capture.store.download(track) { ok, message in
            capture.report.append("wifi.blocked=\(!ok)")
            capture.report.append("wifi.message=\(message)")
        }
        after(1) {
            host.dismiss(animated: false) {
                let downloads = DownloadsViewController()
                downloads.modalPresentationStyle = .fullScreen
                capture.root.present(downloads, animated: false) {
                    after(1.2) {
                        capture.shot("wifi-blocked")
                        capture.report.append("wifi.failedRows=\(capture.store.failedItems.count)")
                        capture.store.connectivityOverride = nil
                        capture.finish()
                    }
                }
            }
        }
    }

    private static func after(_ seconds: TimeInterval, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body)
    }

    private static func waitUntil(_ condition: @escaping () -> Bool,
                                  timeout: TimeInterval,
                                  then: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() { then(true); return }
            if Date() > deadline { then(false); return }
            after(0.5) { poll() }
        }
        poll()
    }

    private static func copy(_ from: URL, to: URL) {
        try? FileManager.default.removeItem(at: to)
        try? FileManager.default.copyItem(at: from, to: to)
    }

    private static func trackCells(in view: UIView) -> [TrackCell] {
        var found: [TrackCell] = []
        func walk(_ node: UIView) {
            if let cell = node as? TrackCell { found.append(cell) }
            node.subviews.forEach(walk)
        }
        walk(view)
        return found.sorted {
            $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY
        }
    }

    fileprivate static func writeReport(_ text: String, directory: URL) {
        try? text.write(to: directory.appendingPathComponent("download-report.txt"),
                        atomically: true, encoding: .utf8)
    }

    fileprivate static func write(window: UIWindow, name: String, directory: URL) {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { return }
        try? data.write(to: directory.appendingPathComponent(name + ".png"))
    }
}

/// Shared state for the download capture steps. It also writes the `done` marker
/// the CI job waits for instead of guessing how long the sequence takes.
private final class DownloadCapture {
    let window: UIWindow
    let root: RootViewController
    let directory: URL
    let store = DownloadStore.shared
    var report: [String] = []
    var seedTrack: Track?
    var extraTrack: Track?
    var highBytes: Int64 = 0
    var saverBytes: Int64 = 0

    init(window: UIWindow, root: RootViewController, directory: URL) {
        self.window = window
        self.root = root
        self.directory = directory
    }

    func shot(_ name: String) {
        ScreenshotHarness.write(window: window, name: name, directory: directory)
    }

    func checkpoint() {
        ScreenshotHarness.writeReport(report.joined(separator: "\n"), directory: directory)
    }

    func finish() {
        report.append("done=true")
        checkpoint()
        try? "done".write(to: directory.appendingPathComponent("done.txt"),
                          atomically: true, encoding: .utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
    }
}
