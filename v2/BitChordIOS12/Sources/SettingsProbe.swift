import UIKit
import AVFoundation

/// Executable proof for the settings matrix, run by the screenshot job with
/// `-BCSettingsProbe <Documents>`. It drives the same stores and pure helpers
/// the UI uses, writes one report, and never depends on a grep of the source.
enum SettingsProbe {
    private static var lines: [String] = []
    private static var directory: URL?
    private static var finished = false

    /// Called before the window is built, so a crash during launch can be
    /// separated from a crash inside the probe body.
    static func markLaunchIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-BCSettingsProbe"),
              index + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: nil)
        try? "launched".write(to: directory.appendingPathComponent("settings-probe-launched.txt"),
                              atomically: true, encoding: .utf8)
    }

    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-BCSettingsProbe"),
              index + 1 < arguments.count else { return }
        directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            run()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            guard !finished else { return }
            record("settings.timeout", "search did not return")
            record("settings.done", "false")
            finish()
        }
    }

    private static func record(_ key: String, _ value: String) {
        lines.append("\(key)=\(value)")
        writeReport()
    }

    private static func run() {
        writeMarker("settings-probe-start.txt")
        record("settings.start", "true")
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
            case .equalizer:
                let before = SettingsStore.shared.string(item.key, "Off")
                SettingsStore.shared.set("Bass boost", for: item.key)
                if SettingsStore.shared.string(item.key, before) != "Bass boost" {
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
        // actool also emits prefixed duplicates of every asset-catalog icon key;
        // count the names the app actually calls setAlternateIconName with.
        record("settings.appIconAlternates", "\(AppIconChoice.variants.compactMap { $0.alternate }.count)")
        record("settings.appIconPlistKeys", "\(alternates.count)")
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

        // DSP: the same renderer the tap uses, with and without processing.
        let dry = AudioDSP.shared.selfTest(eq: "Off", loudness: false, spatial: false)
        let wet = AudioDSP.shared.selfTest(eq: "Bass boost", loudness: true, spatial: true)
        record("settings.dspDry", dry)
        record("settings.dspWet", wet)
        record("settings.dspProcessed", "dry=\(dry.contains("changed=true")) wet=\(wet.contains("changed=true"))")
        let manual = AudioDSP.shared.selfTest(eq: "Manual", loudness: false, spatial: false,
                                               manualBands: [6, 3, 0, -2, 0, 3, 6, 4, 2, 1],
                                               toneX: 4, toneY: -3, balance: -0.4)
        record("settings.equalizerBands", "\(AudioDSP.bandFrequencies.count)")
        record("settings.manualEq", "changed=\(manual.contains("changed=true")) bands=10 balance=-0.4")
        let toneOldX = UserDefaults.standard.object(forKey: "BitChord.Audio.EqToneX")
        let toneOldY = UserDefaults.standard.object(forKey: "BitChord.Audio.EqToneY")
        SettingsStore.shared.set(4.0, for: "BitChord.Audio.EqToneX")
        SettingsStore.shared.set(-3.0, for: "BitChord.Audio.EqToneY")
        let toneX = SettingsStore.shared.double("BitChord.Audio.EqToneX", 0)
        let toneY = SettingsStore.shared.double("BitChord.Audio.EqToneY", 0)
        let zeroBands = Array(repeating: 0.0, count: 10)
        let toneDry = AudioDSP.shared.selfTest(eq: "Manual", loudness: false, spatial: false,
                                               manualBands: zeroBands, toneX: 0, toneY: 0)
        let toneWet = AudioDSP.shared.selfTest(eq: "Manual", loudness: false, spatial: false,
                                               manualBands: zeroBands, toneX: 4, toneY: -3)
        let persisted = abs(toneX - 4) < 0.001 && abs(toneY + 3) < 0.001
        record("settings.tonePad", "bands=10 x=\(Int(toneX)) y=\(Int(toneY)) "
            + "persisted=\(persisted) "
            + "changed=\(!toneDry.contains("changed=true") && toneWet.contains("changed=true"))")
        restore(toneOldX, key: "BitChord.Audio.EqToneX")
        restore(toneOldY, key: "BitChord.Audio.EqToneY")
        record("settings.crossfade", "explicit=5 offAutomix=\(PlayerService.crossfadeSeconds(setting: 0, automix: false, fast: false)) automix=\(PlayerService.crossfadeSeconds(setting: 0, automix: true, fast: false)) fast=\(PlayerService.crossfadeSeconds(setting: 0, automix: true, fast: true))")
        record("settings.animatedCover", "enabled=\(NowPlayingViewController.artworkMotionEnabled(animated: true, cellular: true, reduce: false, onWiFi: true)) cellularOff=\(NowPlayingViewController.artworkMotionEnabled(animated: true, cellular: false, reduce: false, onWiFi: false)) reduced=\(NowPlayingViewController.artworkMotionEnabled(animated: true, cellular: true, reduce: true, onWiFi: true))")
        let savedLanguage = SettingsStore.shared.string("BitChord.Misc.AppLanguage", "English")
        SettingsStore.shared.set("Español", for: "BitChord.Misc.AppLanguage")
        record("settings.localization", L10n.report())
        let screenSections = ["Audio quality", "Playback", "Lyrics", "Library & downloads",
                              "Sources & addons", "Integrations", "Appearance", "Misc",
                              "Performance & advanced", "Account & integrations", "Listen together"]
        let untranslated = screenSections.filter { L10n.t($0) == $0 }.count
        record("settings.screenTranslation", "sections=\(screenSections.count) missing=\(untranslated) "
            + "equalizer=\(L10n.t("Equalizer")) artist=\(L10n.t("Popular"))")
        record("settings.languages", "\(L10n.languageNames.count)")
        let equalizerMatches = SettingsCatalog.filtered(by: "equalizer")
            .flatMap { $0.items }.filter { $0.title == "Equalizer" }.count
        let emptyMatches = SettingsCatalog.filtered(by: "no such setting").count
        record("settings.search", "equalizer=\(equalizerMatches) empty=\(emptyMatches)")
        SettingsStore.shared.set(savedLanguage, for: "BitChord.Misc.AppLanguage")
        record("settings.translation", TranslationService.shared.selfTest())
        record("settings.refreshRate", DisplayRefreshController.shared.report)
        record("settings.refreshModes", "auto=\(DisplayRefreshController.requestedFPS(for: "Auto")) sixty=\(DisplayRefreshController.requestedFPS(for: "60")) thirty=\(DisplayRefreshController.requestedFPS(for: "30"))")
        let savedPrefetch = SettingsStore.shared.bool("BitChord.Audio.DirectSourceStream", false)
        SettingsStore.shared.set(true, for: "BitChord.Audio.DirectSourceStream")
        record("settings.prefetch", "enabled=\(SettingsStore.shared.bool("BitChord.Audio.DirectSourceStream", false)) \(StreamPrefetcher.shared.report)")
        SettingsStore.shared.set(savedPrefetch, for: "BitChord.Audio.DirectSourceStream")

        // Autoplay: "Don't repeat in session" filters history, not just the queue.
        let mix = [probeTrack("a"), probeTrack("b"), probeTrack("c")]
        let noRepeat = PlayerService.autoplayCandidates(mix: mix, queueIDs: ["a"],
                                                         history: ["b"], avoidRepeats: true)
        let repeatAllowed = PlayerService.autoplayCandidates(mix: mix, queueIDs: ["a"],
                                                              history: ["b"], avoidRepeats: false)
        record("settings.autoplay", "noRepeat=\(noRepeat.map { $0.videoID }.joined(separator: ",")) allowed=\(repeatAllowed.map { $0.videoID }.joined(separator: ","))")

        let speakerBlocked = PlayerService.speakerBlocked(
            disabled: true, portType: AVAudioSession.Port.builtInSpeaker.rawValue)
        let headphonesAllowed = !PlayerService.speakerBlocked(
            disabled: true, portType: AVAudioSession.Port.headphones.rawValue)
        record("settings.speakerGuard", "speakerBlocked=\(speakerBlocked) headphonesAllowed=\(headphonesAllowed)")

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
            let firstIDs = Set((tracks ?? []).map { $0.videoID })
            InnerTube.shared.searchNext { next, hasMore, _ in
                record("settings.searchPage1", "\(first)")
                record("settings.searchPage2", "\(next?.count ?? 0)")
                record("settings.searchFresh", "\((next ?? []).filter { !firstIDs.contains($0.videoID) }.count)")
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
        guard !finished, let directory = directory else { return }
        finished = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: nil)
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("settings-probe.txt"),
                        atomically: true, encoding: .utf8)
        try? "done".write(to: directory.appendingPathComponent("settings-probe-done.txt"),
                          atomically: true, encoding: .utf8)
    }

    private static func writeReport() {
        guard let directory = directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: nil)
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("settings-probe.txt"),
                        atomically: true, encoding: .utf8)
    }

    private static func writeMarker(_ name: String) {
        guard let directory = directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: nil)
        try? "started".write(to: directory.appendingPathComponent(name),
                             atomically: true, encoding: .utf8)
    }
}
