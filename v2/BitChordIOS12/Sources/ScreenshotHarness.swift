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
    /// local path rather than a stream.
    private static func captureDownloads(window: UIWindow, root: RootViewController, directory: URL) {
        var report: [String] = []
        let store = DownloadStore.shared
        report.append("saved=\(store.saved.count)")
        report.append("totalBytes=\(store.totalBytes)")
        if let item = store.saved.first {
            let url = store.localURL(for: item.track.videoID)
            report.append("first=\(item.track.title)")
            report.append("fileExists=\(url != nil)")
            report.append("fileBytes=\(item.byteSize)")
        }

        root.dismiss(animated: false) {
            let downloads = DownloadsViewController()
            downloads.modalPresentationStyle = .fullScreen
            root.present(downloads, animated: false) {
                // The row's cover is fetched asynchronously; give it a beat so the
                // shot shows the finished row rather than a placeholder tile.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    write(window: window, name: "downloads", directory: directory)
                }
                guard let item = store.saved.first else {
                    writeReport(report.joined(separator: "\n"), directory: directory)
                    exit(0)
                }
                PlayerService.shared.play(tracks: [item.track], startingAt: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                    report.append("localPlayback=\(AudioEngine.shared.currentIsLocal)")
                    report.append("source=\(AudioEngine.shared.currentSourceLabel)")
                    report.append(String(format: "position=%.1f", PlayerService.shared.currentTime))
                    report.append("duration=\(Int(PlayerService.shared.duration))")
                    writeReport(report.joined(separator: "\n"), directory: directory)
                    downloads.dismiss(animated: false) { root.presentNowPlaying() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        write(window: window, name: "offline", directory: directory)
                        // Delete the download and check the row and the bytes
                        // both go, then photograph the empty destination.
                        let fileURL = store.localURL(for: item.track.videoID)
                        store.remove(item.track.videoID)
                        let gone = fileURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
                        report.append("deletedRows=\(store.saved.count)")
                        report.append("fileRemoved=\(gone)")
                        root.dismiss(animated: false) {
                            let after = DownloadsViewController()
                            after.modalPresentationStyle = .fullScreen
                            root.present(after, animated: false) {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    write(window: window, name: "downloads-empty", directory: directory)
                                    writeReport(report.joined(separator: "\n"), directory: directory)
                                    exit(0)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func writeReport(_ text: String, directory: URL) {
        try? text.write(to: directory.appendingPathComponent("download-report.txt"),
                        atomically: true, encoding: .utf8)
    }

    private static func write(window: UIWindow, name: String, directory: URL) {
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
