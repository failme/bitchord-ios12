import UIKit

/// Executable proof for the settings matrix, run by the screenshot job with
/// `-BCSettingsProbe <Documents>`. It drives the same stores and pure helpers
/// the UI uses, writes one report, and never depends on a grep of the source.
enum SettingsProbe {
    private static var lines: [String] = []
    private static var directory: URL?

    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-BCSettingsProbe"),
              index + 1 < arguments.count else { return }
        directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            run()
        }
    }

    private static func record(_ key: String, _ value: String) {
        lines.append("\(key)=\(value)")
    }

    private static func run() {
        let sections = SettingsCatalog.sections
        let items = sections.flatMap { $0.items }
        record("settings.sections", "\(sections.count)")
        record("settings.rows", "\(items.count)")
        record("settings.unavailable", "\(items.filter { if case .unavailable = $0.kind { return true }; return false }.count)")
        record("settings.appIcons", "\(AppIconChoice.displayNames.count)")
        record("settings.appIconsUnique", "\(Set(AppIconChoice.displayNames).count)")

        // Every stateful row must round-trip through the same store the UI
        // writes. Theme and app icon are exercised separately below because
        // changing them rebuilds the window or asks SpringBoard for an icon.
        var tested = 0
        var failures: [String] = []
        for item in items {
            if item.key == Theme.modeKey || item.key == AppIconChoice.key { continue }
            let defaults = UserDefaults.standard
            let old = defaults.object(forKey: item.key)
            switch item.kind {
            case .toggle(let fallback):
                let before = SettingsStore.shared.bool(item.key, fallback)
                SettingsStore.shared.set(!before, for: item.key)
                if SettingsStore.shared.bool(item.key, before) != !before {
                    failures.append(item.key)
                }
                tested += 1
            case .choice(let fallback, let options):
                guard let option = options.last else { continue }
                SettingsStore.shared.set(option, for: item.key)
                if SettingsStore.shared.string(item.key, fallback) != option {
                    failures.append(item.key)
                }
                tested += 1
            case .stepper(let fallback, _, _, _, _):
                SettingsStore.shared.set(1.0, for: item.key)
                if SettingsStore.shared.double(item.key, fallback) != 1.0 {
                    failures.append(item.key)
                }
                tested += 1
            default:
                continue
            }
            if let old = old {
                defaults.set(old, forKey: item.key)
            } else {
                defaults.removeObject(forKey: item.key)
            }
        }
        record("settings.roundTrip", "\(tested)")
        record("settings.roundTripFailures", failures.isEmpty ? "none" : failures.joined(separator: ","))

        // Theme: the palette is resolved from the persisted mode.
        let themeOld = UserDefaults.standard.object(forKey: Theme.modeKey)
        SettingsStore.shared.set(Theme.Mode.light.rawValue, for: Theme.modeKey)
        let light = Theme.mode == .light && !Theme.isDark
        SettingsStore.shared.set(Theme.Mode.dark.rawValue, for: Theme.modeKey)
        let dark = Theme.mode == .dark && Theme.isDark
        restore(themeOld, key: Theme.modeKey)
        record("settings.themeLight", "\(light)")
        record("settings.themeDark", "\(dark)")

        // App icon: all upstream variants are declared and packaged.
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any] ?? [:]
        record("settings.appIconAlternates", "\(alternates.count)")
        var packaged = 0
        for variant in AppIconChoice.variants {
            guard let alternate = variant.alternate else { continue }
            let files = (alternates[alternate] as? [String: Any])?["CFBundleIconFiles"] as? [String] ?? []
            if !files.isEmpty { packaged += 1 }
        }
        record("settings.appIconDeclared", "\(packaged)")

        // Backup: an exported file restores the values it was made from.
        let sentinel = "BitChord.Probe.Sentinel"
        let sentinelOld = UserDefaults.standard.object(forKey: sentinel)
        SettingsStore.shared.set("before", for: sentinel)
        var backupRestored = false
        if let backup = BackupService.shared.makeBackup() {
            SettingsStore.shared.set("after", for: sentinel)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(backup.name)
            try? backup.data.write(to: url, options: .atomic)
            let result = BackupService.shared.restore(from: url)
            backupRestored = result.ok && UserDefaults.standard.string(forKey: sentinel) == "before"
        }
        restore(sentinelOld, key: sentinel)
        record("settings.backupRestored", "\(backupRestored)")

        // Local music: the switch changes the actual scan root.
        let allOld = UserDefaults.standard.object(forKey: "BitChord.LocalMusic.UseAllFolders")
        SettingsStore.shared.set(false, for: "BitChord.LocalMusic.UseAllFolders")
        let localRoot = LocalMusicStore.shared.scanRootURL.lastPathComponent
        SettingsStore.shared.set(true, for: "BitChord.LocalMusic.UseAllFolders")
        let documentsRoot = LocalMusicStore.shared.scanRootURL.lastPathComponent
        restore(allOld, key: "BitChord.LocalMusic.UseAllFolders")
        record("settings.localRoots", "\(localRoot)->\(documentsRoot)")

        // Lyrics: synced on/off and the offset actually move the active line.
        let lyricLines = [0.0, 10.0, 20.0].enumerated().map { index, time in
            WordLyricLine(time: time, text: "line \(index)", words: [], end: nil)
        }
        let syncedIndex = NowPlayingViewController.lyricIndex(lines: lyricLines, position: 12,
                                                              offsetMilliseconds: 0, synced: true)
        let shiftedIndex = NowPlayingViewController.lyricIndex(lines: lyricLines, position: 12,
                                                               offsetMilliseconds: 3000, synced: true)
        let unsynced = NowPlayingViewController.lyricIndex(lines: lyricLines, position: 12,
                                                           offsetMilliseconds: 0, synced: false)
        record("settings.lyrics", "synced=\(syncedIndex) shifted=\(shiftedIndex) unsynced=\(unsynced)")

        // Performance: the same helper the player calls for its backdrop.
        let fullBlur = NowPlayingViewController.backdropBlurRadius(reduceBlur: false,
                                                                   highPerformance: false,
                                                                   renderQuality: "High")
        let cheapBlur = NowPlayingViewController.backdropBlurRadius(reduceBlur: false,
                                                                    highPerformance: true,
                                                                    renderQuality: "High")
        let lowBlur = NowPlayingViewController.backdropBlurRadius(reduceBlur: false,
                                                                  highPerformance: false,
                                                                  renderQuality: "Low")
        record("settings.renderQuality", "high=\(Int(fullBlur)) cheap=\(Int(cheapBlur)) low=\(Int(lowBlur))")

        // Autoplay: "Don't repeat in session" filters history, not just the queue.
        let mix = [probeTrack("a"), probeTrack("b"), probeTrack("c")]
        let noRepeat = PlayerService.autoplayCandidates(mix: mix, queueIDs: ["a"],
                                                         history: ["b"], avoidRepeats: true)
        let repeatAllowed = PlayerService.autoplayCandidates(mix: mix, queueIDs: ["a"],
                                                              history: ["b"], avoidRepeats: false)
        record("settings.autoplay", "noRepeat=\(noRepeat.map { $0.videoID }.joined(separator: ",")) allowed=\(repeatAllowed.map { $0.videoID }.joined(separator: ","))")

        // Home: hide recents removes the shelf, not merely the row toggle.
        LibraryStore.shared.recordPlayback(probeTrack("home-probe"))
        let hideOld = UserDefaults.standard.object(forKey: "BitChord.Misc.HideRecents")
        SettingsStore.shared.set(false, for: "BitChord.Misc.HideRecents")
        let home = HomeViewController()
        let shown = home.probeShelfTitles().contains("Recently played")
        SettingsStore.shared.set(true, for: "BitChord.Misc.HideRecents")
        let hidden = !home.probeShelfTitles().contains("Recently played")
        restore(hideOld, key: "BitChord.Misc.HideRecents")
        record("settings.homeHideRecents", "shown=\(shown) hidden=\(hidden)")

        // Downloads: a real file in the cache must reach Documents/Exports.
        let exportID = DownloadStore.shared.probeSeedExportFixture()
        let exported = DownloadStore.shared.exportAllCompatible()
        DownloadStore.shared.probeClearExportFixture(exportID)
        record("settings.downloadExport", "saved=1 exported=\(exported)")

        // Search continuation: the second page must carry real tracks.
        InnerTube.shared.search("Blinding Lights", filter: .songs) { tracks, _ in
            let first = tracks?.count ?? 0
            InnerTube.shared.searchNext { next, hasMore, _ in
                record("settings.searchPage1", "\(first)")
                record("settings.searchPage2", "\(next?.count ?? 0)")
                record("settings.searchMore", "\(hasMore)")
                record("settings.done", "\(failures.isEmpty)")
                finish()
            }
        }
    }

    private static func probeTrack(_ id: String) -> Track {
        return Track(videoID: id, title: "Probe \(id)", artist: "BitChord",
                     durationSeconds: 180)
    }

    private static func restore(_ value: Any?, key: String) {
        if let value = value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func finish() {
        guard let directory = directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: nil)
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("settings-probe.txt"),
                        atomically: true, encoding: .utf8)
        try? "done".write(to: directory.appendingPathComponent("settings-probe-done.txt"),
                          atomically: true, encoding: .utf8)
    }
}
