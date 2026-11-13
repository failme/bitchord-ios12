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
        // Background transfers get their own launch pair: start one and quit,
        // then launch again and see what the system delivered.
        if let start = arguments.firstIndex(of: "-BCBackgroundStart"), start + 1 < arguments.count {
            backgroundStart(directory: URL(fileURLWithPath: arguments[start + 1], isDirectory: true))
            return
        }
        if let verify = arguments.firstIndex(of: "-BCBackgroundVerify"), verify + 1 < arguments.count {
            backgroundVerify(directory: URL(fileURLWithPath: arguments[verify + 1], isDirectory: true))
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

    /// Waits for a percentage that is clearly mid-transfer, then shoots it. The
    /// last real partial value is kept, so a transfer that outruns the camera
    /// still gets the best frame it produced rather than a 0% one.
    private static func snapProgress(_ capture: DownloadCapture, track: Track, attempt: Int,
                                     best: Double = 0, then: @escaping () -> Void) {
        let fraction = capture.store.progress(for: track.videoID) ?? 0
        let partial = fraction > 0 && fraction < 0.98 ? fraction : 0
        let bestNow = max(best, partial)
        if bestNow >= 0.2 || attempt >= 12 {
            let percent = Int((bestNow * 100).rounded())
            capture.report.append("progress.captured=\(percent)")
            capture.shot("download-progress")
            then()
            return
        }
        after(0.6) {
            snapProgress(capture, track: track, attempt: attempt + 1, best: bestNow, then: then)
        }
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
            capture.spareTrack = others.dropFirst(2).first
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
                        storageCapProbe(capture, host: downloads)
                    }
                }
            }
        }
    }

    // MARK: - Storage cap

    /// With a 10 MB limit and 2.5 MB already saved, a ~8 MB track must be held
    /// with a reason, and the existing file must be untouched; then the limit is
    /// dropped below the usage to prove nothing is deleted behind the user's back.
    private static func storageCapProbe(_ capture: DownloadCapture, host: UIViewController) {
        guard let track = capture.spareTrack else {
            capture.report.append("cap.missing=true")
            playlistSyncProbe(capture, host: host)
            return
        }
        let beforeCount = capture.store.saved.count
        let beforeBytes = capture.store.totalBytes
        SettingsStore.shared.set("10 MB", for: DownloadStore.storageLimitKey)
        capture.report.append("cap.setting=\(SettingsStore.shared.string(DownloadStore.storageLimitKey, ""))")
        capture.report.append("cap.usage=\(capture.store.storageText())")
        capture.report.append("cap.estimate=\(capture.store.estimatedBytes(for: track, quality: .high))")
        capture.store.download(track) { ok, message in
            capture.report.append("cap.blocked=\(!ok)")
            capture.report.append("cap.reason=\(capture.store.failure(for: track.videoID) ?? "")")
            capture.report.append("cap.message=\(message)")
        }
        after(1) {
            capture.report.append("cap.savedUnchanged=\(capture.store.saved.count == beforeCount && capture.store.totalBytes == beforeBytes)")
            capture.checkpoint()
            host.dismiss(animated: false) {
                let downloads = DownloadsViewController()
                downloads.modalPresentationStyle = .fullScreen
                capture.root.present(downloads, animated: false) {
                    after(1) {
                        capture.shot("storage-cap")
                        // Lowering the limit under the current usage keeps every file.
                        SettingsStore.shared.set("1 MB", for: DownloadStore.storageLimitKey)
                        let filesKept = capture.store.saved.allSatisfy {
                            capture.store.localURL(for: $0.track.videoID) != nil
                        }
                        capture.report.append("cap.lowLimitFiles=\(filesKept)")
                        capture.report.append("cap.lowLimitCount=\(capture.store.saved.count)")
                        capture.checkpoint()
                        let settings = SettingsViewController()
                        settings.modalPresentationStyle = .fullScreen
                        downloads.present(settings, animated: false) {
                            after(0.8) {
                                settings.scrollToDownloadSection()
                                after(0.8) {
                                    capture.shot("settings-storage")
                                    capture.report.append("settings.cap=\(SettingsStore.shared.string(DownloadStore.storageLimitKey, ""))")
                                    capture.report.append("settings.usage=\(capture.store.storageText())")
                                    settings.dismiss(animated: false) {
                                        // Back to a workable limit for the addon run.
                                        SettingsStore.shared.set("Unlimited", for: DownloadStore.storageLimitKey)
                                        playlistSyncProbe(capture, host: downloads)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Playlist sync

    private static func playlistSyncProbe(_ capture: DownloadCapture, host: UIViewController) {
        InnerTube.shared.searchCollections("Top songs", filter: .playlists) { items in
            guard let item = items.first else {
                capture.report.append("sync.target=false")
                capture.finish()
                return
            }
            capture.report.append("sync.target=\(item.browseID)")
            LibraryStore.shared.syncPlaylist(remoteID: item.browseID) { ok, message in
                capture.report.append("sync.ok=\(ok)")
                capture.report.append("sync.message=\(message)")
                capture.report.append("sync.playlists=\(LibraryStore.shared.playlists.count)")
                if let playlist = LibraryStore.shared.playlists.first(where: { $0.id.hasPrefix("remote:") }) {
                    capture.report.append("sync.title=\(playlist.title)")
                    capture.report.append("sync.tracks=\(playlist.tracks.count)")
                    capture.report.append("sync.first=\(playlist.tracks.first?.title ?? "")")
                    capture.report.append("sync.last=\(playlist.tracks.last?.title ?? "")")
                    capture.syncedTitle = playlist.title
                    capture.syncedTracks = playlist.tracks
                }
                capture.checkpoint()
                host.dismiss(animated: false) {
                    capture.root.showTab(2)
                    after(1.5) {
                        capture.shot("library-synced")
                        let list = TrackListViewController()
                        list.tracks = capture.syncedTracks
                        list.title = capture.syncedTitle
                        list.emptyText = "This playlist is empty."
                        list.modalPresentationStyle = .fullScreen
                        capture.root.present(list, animated: false) {
                            after(1) {
                                capture.shot("playlist-synced")
                                list.dismiss(animated: false) {
                                    playlistFailureProbe(capture, host: capture.root)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The remote side refusing: the UI shows the failure instead of pretending
    /// the playlist synced, and the saved set stays as it was.
    private static func playlistFailureProbe(_ capture: DownloadCapture, host: UIViewController) {
        let before = LibraryStore.shared.playlists.count
        LibraryStore.shared.syncPlaylist(remoteID: "this-is-not-a-playlist") { ok, message in
            capture.report.append("sync.failure.ok=\(!ok)")
            capture.report.append("sync.failure.message=\(message)")
            capture.report.append("sync.failure.unchanged=\(LibraryStore.shared.playlists.count == before)")
            guard !ok else {
                capture.finish()
                return
            }
            PlaylistSync.presentFailure(on: host, message: message)
            after(0.8) {
                capture.shot("sync-failed")
                PlaylistSync.dismissFailure(on: host)
                after(0.5) { addonProbe(capture, host: host) }
            }
        }
    }

    // MARK: - Lossless addon

    /// The addon serves one track and answers 404 for the other, so the same
    /// quality setting has to take the addon when it has something and the
    /// standard catalogue when it does not.
    private static func addonProbe(_ capture: DownloadCapture, host: UIViewController) {
        guard let addonURL = URL(string: ProcessInfo.processInfo.environment["BC_ADDON_URL"] ?? "http://127.0.0.1:8765") else {
            capture.report.append("addon.missing=true")
            capture.finish()
            return
        }
        CatalogueSearch.shared.songs("Levitating Dua Lipa") { tracks in
            guard tracks.count >= 2 else {
                capture.report.append("addon.tracks=false")
                capture.finish()
                return
            }
            capture.checkpoint()
            let fresh = tracks.filter { !DownloadStore.shared.isDownloaded($0.videoID) }
            guard fresh.count >= 2 else {
                capture.report.append("addon.tracks=false")
                capture.checkpoint()
                capture.finish()
                return
            }
            let losslessTrack = fresh[0]
            let fallbackTrack = fresh[1]
            capture.report.append("addon.track=\(losslessTrack.videoID)")
            capture.report.append("addon.fallbackTrack=\(fallbackTrack.videoID)")
            SettingsStore.shared.set(addonURL.absoluteString, for: AddonService.urlKey)
            SettingsStore.shared.set(DownloadQuality.lossless.rawValue, for: "BitChord.Download.Quality")
            // Tell the test server which id it should be able to serve.
            var request = URLRequest(url: addonURL.appendingPathComponent("__serve/\(losslessTrack.videoID)"))
            request.timeoutInterval = 5
            URLSession.shared.dataTask(with: request) { _, _, _ in
                DispatchQueue.main.async {
                    capture.store.download(losslessTrack) { ok, message in
                        capture.report.append("addon.ok=\(ok)")
                        if !ok { capture.report.append("addon.message=\(message)") }
                    }
                    waitUntil({ capture.store.isDownloaded(losslessTrack.videoID)
                                || capture.store.failure(for: losslessTrack.videoID) != nil },
                              timeout: 120) { finished in
                        if let item = capture.store.savedItem(for: losslessTrack.videoID),
                           let url = capture.store.localURL(for: losslessTrack.videoID) {
                            capture.report.append("addon.bytes=\(item.byteSize)")
                            capture.report.append("addon.label=\(item.qualityLabel)")
                            copy(url, to: capture.directory.appendingPathComponent("quality-lossless.m4a"))
                        } else {
                            capture.report.append("addon.bytes=0")
                            capture.report.append("addon.failed=\(finished)")
                        }
                        capture.checkpoint()
                        capture.store.download(fallbackTrack) { ok, message in
                            capture.report.append("addon.fallback.ok=\(ok)")
                            if !ok { capture.report.append("addon.fallback.message=\(message)") }
                        }
                        waitUntil({ capture.store.isDownloaded(fallbackTrack.videoID)
                                    || capture.store.failure(for: fallbackTrack.videoID) != nil },
                                  timeout: 120) { _ in
                            if let item = capture.store.savedItem(for: fallbackTrack.videoID),
                               let url = capture.store.localURL(for: fallbackTrack.videoID) {
                                capture.report.append("addon.fallback.bytes=\(item.byteSize)")
                                capture.report.append("addon.fallback.label=\(item.qualityLabel)")
                                copy(url, to: capture.directory.appendingPathComponent("quality-fallback.m4a"))
                            } else {
                                capture.report.append("addon.fallback.bytes=0")
                            }
                            capture.checkpoint()
                            SettingsStore.shared.set(DownloadQuality.high.rawValue, for: "BitChord.Download.Quality")
                            host.dismiss(animated: false) {
                                let downloads = DownloadsViewController()
                                downloads.modalPresentationStyle = .fullScreen
                                capture.root.present(downloads, animated: false) {
                                    after(1.5) {
                                        capture.shot("downloads-addon")
                                        capture.finish()
                                    }
                                }
                            }
                        }
                    }
                }
            }.resume()
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

    // MARK: - Background transfer launches

    /// Starts a real background download and leaves the process while it is
    /// still transferring: the next launch has to adopt it.
    private static func backgroundStart(directory: URL) {
        var report = ["background.started=true"]
        CatalogueSearch.shared.songs("Save Your Tears The Weeknd") { tracks in
            // Anything already on disk would short-circuit, so take a fresh one.
            guard let track = tracks.first(where: { !DownloadStore.shared.isDownloaded($0.videoID) }) else {
                report.append("background.track=false")
                writeText(report.joined(separator: "\n"), name: "background-report.txt", directory: directory)
                exit(0)
            }
            report.append("background.track=\(track.videoID)")
            report.append("background.title=\(track.title)")
            DownloadStore.shared.download(track) { ok, message in
                report.append("background.download=\(ok) \(message)")
            }
            waitUntil({ DownloadStore.shared.isDownloading(track.videoID) }, timeout: 25) { started in
                after(0.8) {
                    report.append("background.live=\(started)")
                    report.append("background.pending=\(DownloadStore.shared.pendingCount)")
                    report.append("background.progress=\(DownloadStore.shared.progress(for: track.videoID) ?? 0)")
                    writeText(report.joined(separator: "\n"), name: "background-report.txt", directory: directory)
                    // Leave without finishing: the transfer belongs to the system now.
                    exit(0)
                }
            }
        }
    }

    /// Relaunched after the process died: adopt whatever the system delivered
    /// and say plainly whether the track ended up in the library.
    private static func backgroundVerify(directory: URL) {
        var report: [String] = []
        let started = readBackgroundReport(directory: directory)
        let videoID = started.first(where: { $0.hasPrefix("background.track=") })?
            .replacingOccurrences(of: "background.track=", with: "")
        report.append("verify.pendingAtLaunch=\(DownloadStore.shared.pendingCount)")
        report.append("verify.savedAtLaunch=\(DownloadStore.shared.saved.count)")
        // Read-back of the playlist the previous process synced: a fresh launch
        // reads it off disk, so this is the relaunch proof, not memory.
        report.append("verify.playlists=\(LibraryStore.shared.playlists.count)")
        if let playlist = LibraryStore.shared.playlists.first(where: { $0.id.hasPrefix("remote:") }) {
            report.append("verify.playlistTitle=\(playlist.title)")
            report.append("verify.playlistTracks=\(playlist.tracks.count)")
            report.append("verify.playlistFirst=\(playlist.tracks.first?.title ?? "")")
            report.append("verify.playlistLast=\(playlist.tracks.last?.title ?? "")")
        }
        guard let id = videoID, !id.isEmpty else {
            report.append("background.ok=false")
            report.append("background.reason=no-track-in-start-report")
            writeText(report.joined(separator: "\n"), name: "background-verify.txt", directory: directory)
            try? "done".write(to: directory.appendingPathComponent("background-done.txt"),
                              atomically: true, encoding: .utf8)
            exit(0)
        }
        report.append("verify.track=\(id)")
        if DownloadStore.shared.isDownloaded(id) {
            report.append("background.deliveredBeforeCheck=true")
        }
        waitUntil({ DownloadStore.shared.pendingCount == 0 }, timeout: 150) { _ in
            report.append("background.indexed=\(DownloadStore.shared.isDownloaded(id))")
            report.append("background.pendingAfter=\(DownloadStore.shared.pendingCount)")
            report.append("background.saved=\(DownloadStore.shared.saved.count)")
            report.append("background.bytes=\(DownloadStore.shared.totalBytes)")
            report.append("background.failed=\(DownloadStore.shared.failedItems.count)")
            report.append("background.ok=\(DownloadStore.shared.isDownloaded(id))")
            writeText(report.joined(separator: "\n"), name: "background-verify.txt", directory: directory)
            try? "done".write(to: directory.appendingPathComponent("background-done.txt"),
                              atomically: true, encoding: .utf8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
        }
    }

    private static func readBackgroundReport(directory: URL) -> [String] {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("background-report.txt"),
                                     encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    fileprivate static func writeReport(_ text: String, directory: URL) {
        writeText(text, name: "download-report.txt", directory: directory)
    }

    fileprivate static func writeText(_ text: String, name: String, directory: URL) {
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        try? text.write(to: directory.appendingPathComponent(name),
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
    var spareTrack: Track?
    var highBytes: Int64 = 0
    var saverBytes: Int64 = 0
    var syncedTitle = ""
    var syncedTracks: [Track] = []

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
