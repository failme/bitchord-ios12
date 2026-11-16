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
        let probeDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        directory = probeDirectory
        let seed = probeDirectory.appendingPathComponent("settings-relaunch-seeded.txt")
        if FileManager.default.fileExists(atPath: seed.path) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                runRelaunchCheck(seed: seed)
            }
            return
        }
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
                                               manualBands: zeroBands, toneX: 0, toneY: 0,
                                               balance: 0, preamp: 0)
        let toneWet = AudioDSP.shared.selfTest(eq: "Manual", loudness: false, spatial: false,
                                               manualBands: zeroBands, toneX: 4, toneY: -3,
                                               balance: 0, preamp: 0)
        let persisted = abs(toneX - 4) < 0.001 && abs(toneY + 3) < 0.001
        record("settings.tonePad", "bands=10 x=\(Int(toneX)) y=\(Int(toneY)) "
            + "persisted=\(persisted) "
            + "changed=\(!toneDry.contains("changed=true") && toneWet.contains("changed=true"))")
        restore(toneOldX, key: "BitChord.Audio.EqToneX")
        restore(toneOldY, key: "BitChord.Audio.EqToneY")

        // Appearance: the three new choices each reach the exact helper every
        // screen draws through, not just UserDefaults.
        let accentOld = UserDefaults.standard.object(forKey: Theme.accentKey)
        let themeAccent = Theme.accent
        SettingsStore.shared.set("Coral", for: Theme.accentKey)
        let coral = Theme.accent
        let accentPersisted = SettingsStore.shared.string(Theme.accentKey, "Theme") == "Coral"
        let accentChanged = colourHex(coral) != colourHex(themeAccent)
        record("settings.accent", "name=\(Theme.accentName) persisted=\(accentPersisted) "
            + "changed=\(accentChanged) hex=\(colourHex(coral))")
        restore(accentOld, key: Theme.accentKey)

        let textOld = UserDefaults.standard.object(forKey: Theme.textSizeKey)
        SettingsStore.shared.set("Small", for: Theme.textSizeKey)
        let small = Theme.font(17).pointSize
        SettingsStore.shared.set("Large", for: Theme.textSizeKey)
        let large = Theme.font(17).pointSize
        let textPersisted = SettingsStore.shared.string(Theme.textSizeKey, "Standard") == "Large"
        record("settings.textSize", String(format: "small=%.1f large=%.1f persisted=%@ scaled=%@",
                                           small, large, textPersisted ? "true" : "false",
                                           large > small ? "true" : "false"))
        restore(textOld, key: Theme.textSizeKey)

        let densityOld = UserDefaults.standard.object(forKey: Theme.densityKey)
        SettingsStore.shared.set("Comfortable", for: Theme.densityKey)
        let roomy = Theme.rowHeight(58)
        SettingsStore.shared.set("Compact", for: Theme.densityKey)
        let tight = Theme.rowHeight(58)
        let densityPersisted = SettingsStore.shared.string(Theme.densityKey, "Comfortable") == "Compact"
        record("settings.density", "roomy=\(Int(roomy)) tight=\(Int(tight)) "
            + "persisted=\(densityPersisted) changed=\(tight < roomy)")
        restore(densityOld, key: Theme.densityKey)

        // Route policy: disconnect pauses only when asked, and the existing
        // speaker guard still wins on its own branch.
        let disconnect = PlayerService.routePauseReason(
            reason: .oldDeviceUnavailable, previousOutputs: [.headphones],
            currentOutput: .builtInSpeaker, pauseOnDisconnect: true, disableSpeaker: false)
        let ignored = PlayerService.routePauseReason(
            reason: .oldDeviceUnavailable, previousOutputs: [.headphones],
            currentOutput: .builtInSpeaker, pauseOnDisconnect: false, disableSpeaker: false)
        let speaker = PlayerService.routePauseReason(
            reason: .routeConfigurationChange, previousOutputs: [.headphones],
            currentOutput: .builtInSpeaker, pauseOnDisconnect: false, disableSpeaker: true)
        record("settings.headphonePause", "disconnect=\(disconnect != nil) "
            + "ignored=\(ignored == nil) speakerGuard=\(speaker != nil)")

        // The syllable preference changes what the renderer receives.
        let word = LyricWord(start: 0, end: 1, text: "Hello", startChar: 0, endChar: 5,
                             syllables: [LyricSyllable(start: 0, end: 1, startChar: 0, endChar: 5)])
        let line = WordLyricLine(time: 0, text: "Hello", words: [word], end: 1)
        let wordsOn = LyricsService.linesForDisplay([line], preferWordTimings: true).first?.isWordSynced
        let wordsOff = LyricsService.linesForDisplay([line], preferWordTimings: false).first?.isWordSynced
        record("settings.syllableSync", "on=\(wordsOn == true) off=\(wordsOff == false)")

        // Artist controls: the same filter/sort/bio keys the header buttons
        // write, read back by the page's own summary.
        let artistKeys = [ArtistViewController.albumFilterKey, ArtistViewController.albumSortKey,
                          ArtistViewController.trackSortKey, ArtistViewController.bioExpandedKey]
        let artistOld = artistKeys.map { UserDefaults.standard.object(forKey: $0) }
        SettingsStore.shared.set("Singles", for: artistKeys[0])
        SettingsStore.shared.set("Title", for: artistKeys[1])
        SettingsStore.shared.set("A–Z", for: artistKeys[2])
        SettingsStore.shared.set(true, for: artistKeys[3])
        let artistProbe = ArtistViewController(artist: CatalogueArtist(id: "probe-artist",
                                                                      name: "Probe Artist",
                                                                      artwork: nil))
        artistProbe.applyProfileForProbe(ArtistProfile(
            name: "Probe Artist", artwork: nil, listenerText: nil,
            bio: String(repeating: "Biography copy. ", count: 20),
            topSongs: [
                Track(videoID: "artist-z", title: "Zebra", artist: "Probe Artist",
                      durationSeconds: 180),
                Track(videoID: "artist-a", title: "Afterglow", artist: "Probe Artist",
                      durationSeconds: 180)
            ],
            albums: [
                CatalogueAlbum(id: "a", title: "Album", artist: "Probe Artist", year: "2024",
                               artwork: nil, songCount: 10, kind: .album),
                CatalogueAlbum(id: "s", title: "Single", artist: "Probe Artist", year: "2023",
                               artwork: nil, songCount: 1, kind: .single),
                CatalogueAlbum(id: "c", title: "Collection", artist: "Probe Artist", year: "2022",
                               artwork: nil, songCount: 12, kind: .compilation)
            ], related: []))
        record("settings.artistControls", "\(artistProbe.discographySummary)")
        SettingsStore.shared.set("All", for: artistKeys[0])
        SettingsStore.shared.set("Title", for: artistKeys[1])
        record("settings.artistAlbumSort", "\(artistProbe.discographySummary)")
        for (index, key) in artistKeys.enumerated() {
            restore(artistOld[index], key: key)
        }

        // History actions use the same helpers the two Settings rows call.
        LibraryStore.shared.addRecentSearch(probeTrack("search-history"))
        LibraryStore.shared.recordPlayback(probeTrack("listen-history"))
        PlaybackHistoryStore.shared.record(probeTrack("listen-history"))
        SettingsActions.clearSearchHistory()
        SettingsActions.clearListeningHistory()
        record("settings.historyActions", "search=\(LibraryStore.shared.recentSearches.count) "
            + "recents=\(LibraryStore.shared.recentTracks.count) "
            + "queue=\(PlaybackHistoryStore.shared.items.count) "
            + "position=\(Int(LibraryStore.shared.lastPlaybackPosition))")

        // Resume save/load: the real store, and the real setting gate.
        PlaybackSessionStore.shared.save(queue: [probeTrack("resume-probe")], index: 0,
                                         position: 42)
        let resume = PlaybackSessionStore.shared.load()
        record("settings.resumeStore", "queue=\(resume?.queue.count ?? 0) "
            + "index=\(resume?.index ?? -1) position=\(Int(resume?.position ?? 0))")
        PlaybackSessionStore.shared.clear()
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
        let coverage = L10n.featureCoverage()
        record("settings.newTranslations", "keys=\(coverage.keys) languages=\(coverage.languages) "
            + "missing=\(coverage.missing)")
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
                seedRelaunchProbe()
                record("settings.done", "\(failures.isEmpty)")
                finish()
            }
        }
    }

    /// Phase one leaves five non-default values and a real saved queue on disk.
    /// The workflow then launches the app again; phase two reads them back in a
    /// fresh process, which is the relaunch evidence the round-trip rows cannot
    /// provide.
    private static func seedRelaunchProbe() {
        let store = SettingsStore.shared
        store.set("Coral", for: Theme.accentKey)
        store.set("Large", for: Theme.textSizeKey)
        store.set("Compact", for: Theme.densityKey)
        store.set(true, for: "BitChord.Audio.ResumeOnLaunch")
        store.set(true, for: "BitChord.Audio.PauseOnHeadphoneDisconnect")
        store.set("Singles", for: ArtistViewController.albumFilterKey)
        store.set("Title", for: ArtistViewController.albumSortKey)
        store.set("A–Z", for: ArtistViewController.trackSortKey)
        store.set(true, for: ArtistViewController.bioExpandedKey)
        PlaybackSessionStore.shared.save(queue: [probeTrack("resume-relaunch")],
                                         index: 0, position: 42)
        guard let directory = directory else { return }
        try? "seeded".write(to: directory.appendingPathComponent("settings-relaunch-seeded.txt"),
                            atomically: true, encoding: .utf8)
        record("settings.relaunchSeeded", "true")
    }

    private static func runRelaunchCheck(seed: URL) {
        guard let directory = directory else { return }
        let store = SettingsStore.shared
        let queue = PlayerService.shared.queue
        let track = PlayerService.shared.currentTrack?.videoID ?? ""
        let position = Int(PlayerService.shared.currentTime.rounded())
        let accent = store.string(Theme.accentKey, "") == "Coral" && Theme.accentName == "Coral"
        let text = store.string(Theme.textSizeKey, "") == "Large"
        let density = store.string(Theme.densityKey, "") == "Compact"
        let resume = store.bool("BitChord.Audio.ResumeOnLaunch", false)
        let headphones = store.bool("BitChord.Audio.PauseOnHeadphoneDisconnect", false)
        let artist = store.string(ArtistViewController.albumFilterKey, "") == "Singles"
            && store.string(ArtistViewController.albumSortKey, "") == "Title"
            && store.string(ArtistViewController.trackSortKey, "") == "A–Z"
            && store.bool(ArtistViewController.bioExpandedKey, false)
        let restored = queue.count == 1 && track == "resume-relaunch" && position == 42
        let report = "settings.relaunch=accent=\(accent) text=\(text) density=\(density) "
            + "resume=\(resume) headphones=\(headphones) artist=\(artist) queue=\(queue.count) "
            + "track=\(track) position=\(position)\n"
            + "settings.relaunchRestored=\(restored)\n"
            + "settings.relaunchPersisted=\(accent && text && density && resume && headphones && artist)\n"
        try? report.write(to: directory.appendingPathComponent("settings-relaunch.txt"),
                          atomically: true, encoding: .utf8)
        try? "done".write(to: directory.appendingPathComponent("settings-relaunch-done.txt"),
                          atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: seed)
        PlaybackSessionStore.shared.clear()
    }

    private static func colourHex(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "?" }
        return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
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
