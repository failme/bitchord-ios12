import UIKit

/// How a settings row behaves and whether this port can honour it.
enum SettingKind {
    case toggle(Bool)
    case stepper(Double, Double, Double, Double, String)
    case choice(String, [String])
    /// Row opens something that is not in this build; the text says what it
    /// would need, and tapping explains rather than pretending to navigate.
    case page(String)
    /// A row that reports live state (how much disk downloads use) and opens the
    /// screen where that state can be changed.
    case storage
    /// A row that prompts for the addon server that supplies lossless tiers.
    case addon
    /// A free-text setting: explanation, placeholder, and whether the stored
    /// value is a credential that should only read back as Set / Not set.
    case text(String, String, Bool)
    /// A row that clears one of the app's caches: "song" or "image".
    case cache(String)
    /// Row is shown for parity but has no effect here; the reason is surfaced to the user.
    case unavailable(String)
    /// Re-opens the first-run flow.
    case onboarding
    /// Runs a screen action (backup export/import, reveal cache).
    case action(String)
    /// Opens the WebDAV source browser.
    case sources
    /// Opens the Google / YouTube Music account page.
    case account
}

struct SettingItem {
    let key: String
    let title: String
    var detail: String? = nil
    /// Leading glyph, for the rows the real app draws with an icon.
    var icon: Icons.Kind? = nil
    /// A capsule after the title, as in the real "IN USE" marker.
    var badge: String? = nil
    let kind: SettingKind
}

struct SettingSection {
    let title: String
    let items: [SettingItem]
}

extension Notification.Name {
    static let settingsDidChange = Notification.Name("BitChordSettingsDidChange")
}

/// Persists every key upstream persists. Keys are the upstream `@AppStorage` names verbatim, so
/// defaults and any future import stay compatible.
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private init() {}

    func bool(_ key: String, _ fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    func data(_ key: String) -> Data? {
        return defaults.data(forKey: key)
    }

    func double(_ key: String, _ fallback: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    func string(_ key: String, _ fallback: String) -> String {
        return defaults.string(forKey: key) ?? fallback
    }

    func set(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        }
    }

    func set(_ value: Bool, for key: String) { set(value as Any, for: key) }
    func set(_ value: Double, for key: String) { set(value as Any, for: key) }
    func set(_ value: String, for key: String) { set(value as Any, for: key) }

    // MARK: - Working settings

    var playbackRate: Double {
        get { return double("BitChord.Audio.PlaybackRate", 1.0) }
        set { set(newValue, for: "BitChord.Audio.PlaybackRate") }
    }

    var sleepTimerMinutes: Double {
        get { return double("BitChord.Misc.SleepTimerMinutes", 0) }
        set { set(newValue, for: "BitChord.Misc.SleepTimerMinutes") }
    }

    var showSyncedLyrics: Bool {
        get { return bool("BitChord.Lyrics.Synced", true) }
        set { set(newValue, for: "BitChord.Lyrics.Synced") }
    }

    var autoPlayNext: Bool {
        get { return bool("BitChord.Audio.AutoPlay", true) }
        set { set(newValue, for: "BitChord.Audio.AutoPlay") }
    }

    /// Whether the player prints its own diagnostics: stream source, quality
    /// and engine counters. Off unless asked for — that is a developer view,
    /// not chrome the listener should have to read on every track.
    var showDebugInfo: Bool {
        get { return bool("BitChord.Misc.ShowDebugInfo", false) }
        set { set(newValue, for: "BitChord.Misc.ShowDebugInfo") }
    }

    /// Upstream's "Stats for nerds" row; it is the same live engine summary the
    /// debug row turns on, so a track's source, rate and stale counter can be
    /// read from the player without opening Settings first.
    var showNerdStats: Bool {
        get { return bool("BitChord.Advanced.StatsForNerds", false) || showDebugInfo }
        set {
            set(newValue, for: "BitChord.Advanced.StatsForNerds")
            if !newValue { set(false, for: "BitChord.Misc.ShowDebugInfo") }
        }
    }

    /// JioSaavn is the primary playable catalogue on iOS 12; turning it off
    /// leaves YouTube/InnerTube as the only resolver, exactly as upstream's
    /// source switch does.
    var jioSaavnEnabled: Bool {
        get { return bool("BitChord.Source.JioSaavn", true) }
        set { set(newValue, for: "BitChord.Source.JioSaavn") }
    }

    /// How far a JioSaavn result may differ from the requested track length.
    /// Zero means "don't use duration as corroboration".
    var trackLengthTolerance: Double {
        let raw = string("BitChord.Source.TrackLengthTolerance", "8 s")
        if raw.lowercased().hasPrefix("any") { return 0 }
        return Double(String(raw.split(separator: " ").first ?? "8")) ?? 8
    }

    var keepDownloadsUpdated: Bool {
        get { return bool("BitChord.Download.KeepUpdated", false) }
        set { set(newValue, for: "BitChord.Download.KeepUpdated") }
    }

    var playNextOnSwipe: Bool {
        get { return bool("BitChord.Misc.PlayNextOnSwipe", false) }
        set { set(newValue, for: "BitChord.Misc.PlayNextOnSwipe") }
    }

    var syncedLyrics: Bool {
        get { return bool("BitChord.Lyrics.Synced", true) }
        set { set(newValue, for: "BitChord.Lyrics.Synced") }
    }

    var lyricsOffsetMilliseconds: Double {
        get { return double("BitChord.Lyrics.OffsetSeconds", 0) * 1000 }
        set { set(newValue / 1000, for: "BitChord.Lyrics.OffsetSeconds") }
    }

    var hideRecents: Bool { return bool("BitChord.Misc.HideRecents", false) }
    var hideHomeVideos: Bool { return bool("BitChord.Misc.HideHomeVideos", false) }
    var hideTopPicks: Bool { return bool("BitChord.Misc.HideTopPicks", false) }
    var hideHomeMoods: Bool { return bool("BitChord.Misc.HideHomeMoods", false) }
    var useAllAudioFolders: Bool { return bool("BitChord.LocalMusic.UseAllFolders", false) }
    var exportCompatibleDownloads: Bool { return bool("BitChord.Download.ExportCompatible", false) }
    var replayGenres: Bool { return bool("BitChord.Replay.WorkoutGenres", true) }
    var fullBleedArtwork: Bool { return bool("BitChord.Appearance.FullBleedArtwork", true) }
    var fullBleedDetailArtwork: Bool { return bool("BitChord.Appearance.FullBleedDetailArtwork", false) }
    var prioritizeSyllableSync: Bool { return bool("BitChord.Lyrics.PrioritizeSyllableSync", false) }
    var highPerformanceMode: Bool { return bool("BitChord.Performance.HighPerformanceMode", false) }
    var renderQuality: String { return string("BitChord.Performance.RenderQuality", "High") }
}

/// The upstream sections and keys, with an honest availability verdict for each.
///
/// Rows backed by the embed player work. Rows belonging to the AVPlayer DSP pipeline
/// (crossfade, EQ, bit-perfect, USB DAC, loudness), to storage that does not exist here yet
/// (downloads, lyrics cache), or to integrations that are not ported (Last.fm, ListenBrainz,
/// Spotify, Discord, accounts) are present but disabled with the reason, instead of pretending.
enum SettingsCatalog {
    static let sections: [SettingSection] = [
        // The real page opens with these two, above any section label: the
        // account state and the party invitation.
        SettingSection(title: "", items: [
            SettingItem(key: "BitChord.Account.Integrations", title: "Account & integrations",
                        detail: "Not signed in",
                        icon: .personOutline,
                        kind: .account),
            SettingItem(key: "BitChord.Misc.ListenTogether", title: "Listen together",
                        detail: "Share a code and play the same music, in time",
                        icon: .peopleOutline,
                        kind: .page("Listening together needs a signed-in account on every device, so the party can tell who is in it."))
        ]),

        // AUDIO QUALITY sits above Playback on the real screen, with the
        // active Wi-Fi ceiling marked IN USE.
        SettingSection(title: "Audio quality", items: [
            SettingItem(key: "BitChord.Audio.Sources", title: "Sources",
                        detail: "Where audio comes from and the order used",
                        icon: .plug,
                        kind: .page("Streams come from YouTube Music and JioSaavn. A lossless addon can be pointed at below.")),
            SettingItem(key: "BitChord.Audio.DirectSourceStream", title: "Direct Source Stream",
                        detail: "Pre-opens the next source during a transition",
                        kind: .unavailable("Needs the crossfade/prefetch gate; this player has no overlapping transition to open a source in.")),
            SettingItem(key: "BitChord.Audio.WifiQuality", title: "On Wi-Fi",
                        icon: .wifi,
                        badge: "IN USE",
                        kind: .choice("Lossless", ["Lossless", "High", "Normal", "Data saver"])),
            SettingItem(key: "BitChord.Audio.CellularQuality", title: "On mobile data",
                        icon: .mobileData,
                        kind: .choice("Lossless", ["Lossless", "High", "Normal", "Data saver"])),
            SettingItem(key: "BitChord.Audio.DolbyAtmos", title: "Dolby Atmos",
                        detail: "This device can't play Atmos, so these songs play in their usual version",
                        icon: .dolby,
                        kind: .unavailable(""))
        ]),

        SettingSection(title: "Playback", items: [
            SettingItem(key: "BitChord.Audio.PlaybackRate", title: "Playback speed",
                        detail: "0.5\u{00D7} to 2.0\u{00D7}",
                        kind: .stepper(1.0, 0.5, 2.0, 0.25, "\u{00D7}")),
            SettingItem(key: "BitChord.Misc.SleepTimerMinutes", title: "Sleep timer",
                        detail: "Pause after this long (0 = off)",
                        kind: .stepper(0, 0, 120, 15, " min")),
            SettingItem(key: "BitChord.Audio.AutoPlay", title: "Autoplay",
                        detail: "",
                        kind: .toggle(true)),
            SettingItem(key: "BitChord.Appearance.FullBleedArtwork", title: "Full-screen cover art",
                        detail: "Let the sleeve fill the player backdrop",
                        kind: .toggle(true)),
            SettingItem(key: "BitChord.Appearance.FullBleedDetailArtwork", title: "Full-screen detail cover",
                        detail: "Use the same edge-to-edge sleeve on album pages",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Lyrics.OffsetSeconds", title: "Lyrics offset",
                        detail: "Shift words against the audio, in milliseconds",
                        kind: .stepper(0, -2, 2, 0.1, " s")),
            SettingItem(key: "BitChord.Lyrics.PrioritizeSyllableSync", title: "Prefer syllable sync",
                        detail: "Use word timings before plain line timings",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Audio.Crossfade", title: "Crossfade",
                        detail: "Needs the AVPlayer pipeline",
                        kind: .unavailable("The embed player has no second stream to fade into.")),
            SettingItem(key: "BitChord.Audio.Equalizer", title: "Equalizer",
                        detail: "10-band presets",
                        kind: .unavailable("Requires an AVAudioEngine tap, which the embed player bypasses.")),
            SettingItem(key: "BitChord.Audio.BitPerfect", title: "Bit-perfect output",
                        detail: "Bypass OS resampling",
                        kind: .unavailable("Not possible through WebKit audio.")),
            SettingItem(key: "BitChord.Audio.PreferUSBDAC", title: "Prefer USB DAC",
                        kind: .unavailable("Not possible through WebKit audio.")),
            SettingItem(key: "BitChord.Audio.SkipSilence", title: "Skip silence",
                        kind: .unavailable("No sample-level access.")),
            SettingItem(key: "BitChord.Audio.LoudnessNormalization", title: "Loudness normalisation",
                        kind: .unavailable("No sample-level access.")),
            SettingItem(key: "BitChord.Audio.Automix", title: "Automix",
                        kind: .unavailable("Upstream beta; needs the DSP pipeline.")),
            SettingItem(key: "BitChord.Audio.AutomixPerf", title: "Automix performance mode",
                        kind: .unavailable("Depends on Automix.")),
            SettingItem(key: "BitChord.Audio.SpatialAudio", title: "Spatial audio",
                        kind: .unavailable("Not available for this stream.")),
            SettingItem(key: "BitChord.Audio.OutputPrecision", title: "Output precision",
                        kind: .unavailable("WebKit picks the output format.")),
            SettingItem(key: "BitChord.Audio.DisableOnPhoneSpeaker", title: "Disable on phone speaker",
                        detail: "Pause when the built-in speaker is the output",
                        kind: .toggle(false))
        ]),

        SettingSection(title: "Lyrics", items: [
            SettingItem(key: "BitChord.Lyrics.Synced", title: "Synced lyrics",
                        detail: "Highlight the current line", kind: .toggle(true)),
            SettingItem(key: "BitChord.Lyrics.ShowFullLyrics", title: "Show full lyrics",
                        kind: .toggle(true)),
            SettingItem(key: "BitChord.Lyrics.BlurUnfocused", title: "Blur unfocused lines",
                        detail: "Dim lines that are not being sung", kind: .toggle(true)),
            SettingItem(key: "BitChord.Lyrics.ShowBilingual", title: "Bilingual lyrics",
                        kind: .unavailable("Translation is not ported.")),
            SettingItem(key: "BitChord.Lyrics.TranslationLanguage", title: "Translation language",
                        kind: .unavailable("Translation is not ported.")),
            SettingItem(key: "BitChord.Lyrics.AutoDownloadToStorage", title: "Save lyrics offline",
                        detail: "Reuse fetched lyrics without a network", kind: .toggle(false)),
            SettingItem(key: "BitChord.Lyrics.ArtistSignatures", title: "Artist signatures",
                        kind: .unavailable("Not ported.")),
            SettingItem(key: "BitChord.Lyrics.ActiveSource", title: "Lyrics source",
                        detail: "Automatic asks lrc.red, LyricsPlus, Unison, then LRCLIB",
                        kind: .choice("Automatic", ["Automatic", "LRCLIB"])),
            SettingItem(key: "BitChord.Lyrics.SourcesJSON", title: "Custom lyric sources",
                        kind: .unavailable("Provider switching is not ported."))
        ]),

        SettingSection(title: "Library & downloads", items: [
            SettingItem(key: "BitChord.Download.Quality", title: "Download quality",
                        detail: "Per track, whatever the connection",
                        kind: .choice("High", DownloadQuality.all)),
            SettingItem(key: "BitChord.Download.WifiOnly", title: "Download over Wi-Fi only",
                        kind: .toggle(true)),
            SettingItem(key: "BitChord.Download.StorageLimit", title: "Download storage limit",
                        detail: "Downloads stop before passing this",
                        kind: .choice(DownloadLimit.fallback, DownloadLimit.options)),
            SettingItem(key: "BitChord.Download.Storage", title: "Storage used",
                        kind: .storage),
            SettingItem(key: "BitChord.Download.KeepUpdated", title: "Keep downloads updated",
                        detail: "Refresh synced playlists on launch",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Download.ExportCompatible", title: "Export compatible files",
                        detail: "Copies downloads to Documents/Exports for Files and iTunes",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Backup.Export", title: "Export data",
                        detail: "Playlists, likes, history and settings as JSON",
                        kind: .action("export")),
            SettingItem(key: "BitChord.Backup.Import", title: "Import data",
                        detail: "Restore a BitChord JSON backup",
                        kind: .action("import")),
            SettingItem(key: "BitChord.LocalMusic.SelectedFolder", title: "Local music folder",
                        detail: "Audio files in this app folder appear in Library \u{2192} Local Music",
                        kind: .page("Put audio files in the app's LocalMusic folder, through the Files app or iTunes File Sharing. Library \u{2192} Local Music lists them by folder, with the title, artist and length read from each file.")),
            SettingItem(key: "BitChord.LocalMusic.UseAllFolders", title: "Use all audio folders",
                        detail: "Also scan the rest of Documents for playable audio",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.LocalMusic.FilterNonMusic", title: "Filter non-music",
                        detail: "Hide clips shorter than 30 seconds",
                        kind: .toggle(true)),
            SettingItem(key: "BitChord.Storage.ShowCacheFolder", title: "Show cache folder",
                        detail: "Reveal the app's cache in Files",
                        kind: .action("cacheFolder")),
            SettingItem(key: "BitChord.Storage.CacheLimitMB", title: "Song cache limit",
                        detail: "Bound on the app's disk cache",
                        kind: .choice(CacheStore.fallback, CacheStore.options)),
            SettingItem(key: "BitChord.Storage.ClearSongCache", title: "Clear song cache",
                        detail: "Frees space used by downloaded audio",
                        kind: .cache("song")),
            SettingItem(key: "BitChord.Storage.ClearImageCache", title: "Clear image cache",
                        detail: "Frees space used by album artwork",
                        kind: .cache("image"))
        ]),

        SettingSection(title: "Sources & addons", items: [
            SettingItem(key: "BitChord.Sources.Addon", title: "Lossless addon",
                        detail: "FLAC and ALAC straight from a source you point at",
                        kind: .addon),
            SettingItem(key: "BitChord.Source.WebDAV", title: "Sources & folders",
                        detail: "WebDAV servers you can stream from",
                        kind: .sources),
            SettingItem(key: "BitChord.Source.SMB", title: "SMB",
                         kind: .unavailable("iOS has no SMB client API; a third-party SMB2/SMB3 library with an iOS 12 slice would be required.")),
            SettingItem(key: "BitChord.Source.JioSaavn", title: "JioSaavn",
                        detail: "Primary playable catalogue on this device",
                        kind: .toggle(true)),
            SettingItem(key: "BitChord.Source.TrackLengthTolerance", title: "Track length tolerance",
                        detail: "How closely a catalogue match may differ",
                        kind: .choice("8 s", ["4 s", "8 s", "12 s", "Any"]))
        ]),

        SettingSection(title: "Integrations", items: [
            SettingItem(key: "BitChord.LastFm.Enabled", title: "Last.fm scrobbling",
                        detail: "Needs an API key, secret and session key",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.LastFm.NowPlaying", title: "Last.fm now playing",
                        detail: "Show the current song on your Last.fm profile",
                        kind: .toggle(true)),
            SettingItem(key: "BitChord.LastFm.PrimaryArtistOnly", title: "Primary artist only",
                        detail: "Drop featured credits before scrobbling",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.LastFm.Username", title: "Last.fm username",
                        kind: .text("Your Last.fm name, for reference on this device.", "Username", false)),
            SettingItem(key: "BitChord.LastFm.ApiKey", title: "Last.fm API key",
                        kind: .text("The API key from your Last.fm API account.", "API key", true)),
            SettingItem(key: "BitChord.LastFm.Secret", title: "Last.fm shared secret",
                        kind: .text("The shared secret paired with the API key.", "Shared secret", true)),
            SettingItem(key: "BitChord.LastFm.SessionKey", title: "Last.fm session key",
                        detail: "From last.fm/api/auth with this API key",
                        kind: .text("Paste a session key created for this API key. BitChord signs scrobbles locally and never sends the secret anywhere else.", "Session key", true)),
            SettingItem(key: "BitChord.LastFm.Endpoint", title: "Last.fm endpoint",
                        detail: "libre.fm works too",
                        kind: .text("Leave empty for https://ws.audioscrobbler.com/2.0/. For Libre.fm use https://libre.fm/2.0/.", "https://ws.audioscrobbler.com/2.0/", false)),
            SettingItem(key: "BitChord.LastFm.MinDuration", title: "Minimum track length",
                        detail: "Tracks shorter than this are never scrobbled",
                        kind: .stepper(30, 10, 300, 10, "s")),
            SettingItem(key: "BitChord.LastFm.DelayPercent", title: "Scrobble point",
                        detail: "Percentage of the track before a scrobble is sent",
                        kind: .stepper(50, 10, 90, 5, "%")),
            SettingItem(key: "BitChord.LastFm.DelayCap", title: "Scrobble delay cap",
                        detail: "Longest wait before a scrobble is sent",
                        kind: .stepper(180, 30, 600, 30, "s")),
            SettingItem(key: "BitChord.ListenBrainz.Enabled", title: "ListenBrainz",
                        detail: "Submit plays as they happen",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.ListenBrainz.Token", title: "ListenBrainz token",
                        detail: "From listenbrainz.org/settings",
                        kind: .text("Your user token from ListenBrainz settings.", "Token", true)),
            SettingItem(key: "BitChord.ListenBrainz.PrimaryArtistOnly", title: "ListenBrainz primary artist only",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Spotify.Connected", title: "Spotify",
                        detail: "Public playlist import is in Library",
                        icon: .spotify,
                        kind: .page("Open Library → Import Spotify, paste a public playlist link, and BitChord matches its rows on YouTube Music. No Spotify sign-in is needed.")),
            SettingItem(key: "BitChord.Spotify.Username", title: "Spotify username",
                        kind: .unavailable("Only public playlists can be imported without a Spotify developer app.")),
            SettingItem(key: "BitChord.Spotify.DisplayName", title: "Spotify display name",
                        kind: .unavailable("Only public playlists can be imported without a Spotify developer app.")),
            SettingItem(key: "BitChord.Spotify.AvatarURL", title: "Spotify avatar",
                        kind: .unavailable("Only public playlists can be imported without a Spotify developer app.")),
            SettingItem(key: "BitChord.Spotify.AccessToken", title: "Spotify token",
                        kind: .unavailable("Authenticated Spotify library sync is not enabled in this build.")),
            SettingItem(key: "BitChord.Spotify.CookieSPDC", title: "Spotify cookie",
                        kind: .unavailable("Authenticated Spotify library sync is not enabled in this build.")),
            SettingItem(key: "BitChord.Discord.Enabled", title: "Discord presence",
                        kind: .unavailable("Discord's IPC transport does not exist on iOS."))
        ]),

        SettingSection(title: "Appearance", items: [
            SettingItem(key: "BitChord.Appearance.Theme", title: "Theme",
                        detail: "System, Light or Dark",
                        kind: .choice("Dark", ["System", "Light", "Dark"])),
            SettingItem(key: "BitChord.Appearance.Font", title: "Font",
                        kind: .choice("System", ["System", "Rounded", "Serif"])),
            SettingItem(key: "BitChord.Appearance.AppIcon", title: "App icon",
                        detail: "Default, glass, neon and monochrome",
                        kind: .choice(AppIconChoice.fallback, AppIconChoice.displayNames)),
            SettingItem(key: "BitChord.Appearance.AnimatedCover", title: "Animated cover",
                        kind: .unavailable("Animated artwork is not ported.")),
            SettingItem(key: "BitChord.Appearance.AnimatedCoverCellular", title: "Animated cover on cellular",
                        kind: .unavailable("Animated artwork is not ported.")),
            SettingItem(key: "BitChord.Appearance.SpotifyCanvas", title: "Spotify Canvas",
                        kind: .unavailable("Not ported.")),
            SettingItem(key: "BitChord.Appearance.LiquidGlass", title: "Liquid glass",
                        detail: "Blurred cover backdrop behind the player", kind: .toggle(true)),
            SettingItem(key: "BitChord.Appearance.LegacyMesh", title: "Legacy mesh gradient",
                        detail: "Use the stock mesh instead of cover colours", kind: .toggle(false)),
            SettingItem(key: "BitChord.Appearance.ReduceAnimation", title: "Reduce animation",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Appearance.ReduceDynamicBlur", title: "Reduce dynamic blur",
                        detail: "Uses a lighter backdrop blur", kind: .toggle(false)),
            SettingItem(key: "BitChord.Appearance.DisableBlendEffects", title: "Disable blend effects",
                        detail: "Remove the cover-colour glow and fades", kind: .toggle(false)),
            SettingItem(key: "BitChord.Appearance.GlassPerformance", title: "Glass performance",
                        detail: "Use the cheaper backdrop blur", kind: .toggle(false)),
            SettingItem(key: "BitChord.Appearance.ProgressiveBlur", title: "Progressive top blur",
                        detail: "Fade the cover into the status bar", kind: .toggle(true)),
            SettingItem(key: "BitChord.Appearance.PlayerTheme", title: "Player theme",
                        detail: "Cover, solid colour or the legacy mesh",
                        kind: .choice("Cover", ["Cover", "Solid", "Legacy"]))
        ]),

        SettingSection(title: "Misc", items: [
            SettingItem(key: "BitChord.Misc.HideVolumeSlider", title: "Hide volume slider",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.HideStatusBarInPlayer", title: "Hide status bar in player",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.HideSongStatus", title: "Hide song status",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.ShowQueueHistory", title: "Show queue history",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.PlayNextOnSwipe", title: "Swipe to play next",
                        detail: "Swipe a song row to put it after the current track",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.HideRecents", title: "Hide recents",
                        detail: "Keep recently played rows off Home",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.HideHomeVideos", title: "Hide home videos",
                        detail: "Drop video shelves from the YouTube Music feed",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.HideTopPicks", title: "Hide top picks",
                        detail: "Hide the large personalised cards",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.HideHomeMoods", title: "Hide home moods",
                        detail: "Hide mood and genre cards",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.SquareVideoThumbnails", title: "Square video thumbnails",
                        detail: "Crop video art to a square instead of 16:9",
                        kind: .toggle(true)),
            SettingItem(key: "BitChord.Misc.PreferMusicOnly", title: "Prefer music only",
                        detail: "Drop spoken-word and video results from search",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.DontRepeatInSession", title: "Don't repeat in session",
                        detail: "Radio will not suggest a song already played this session",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.StopOnCloseRecents", title: "Stop when recents close",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.ShowListenTogetherButton", title: "Listen together button",
                        kind: .unavailable("Listen Together is not ported.")),
            SettingItem(key: "BitChord.Misc.SmartAudioAlignment", title: "Smart audio alignment",
                        kind: .unavailable("Needs the DSP pipeline.")),
            SettingItem(key: "BitChord.Misc.WorkOutGenres", title: "Workout genres",
                        detail: "Show the upbeat genres card in Replay",
                        kind: .toggle(true)),
            SettingItem(key: "BitChord.Replay.Stats", title: "Replay",
                        detail: "Plays, top songs and minutes listened",
                        kind: .action("replay")),
            SettingItem(key: "BitChord.Misc.AppLanguage", title: "Language",
                        detail: "English only in this build",
                        kind: .unavailable("The iOS 12 port ships one English resource bundle; adding a language needs translated strings and a restart path.")),
            SettingItem(key: "BitChord.Misc.ShowOnboarding", title: "Show onboarding again",
                        detail: "Welcome, tour and library choice",
                        kind: .onboarding)
        ]),

        SettingSection(title: "Performance & advanced", items: [
            SettingItem(key: "BitChord.Misc.ShowDebugInfo", title: "Show debug info",
                        detail: "Stream source, quality and engine counters",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Advanced.StatsForNerds", title: "Stats for nerds",
                        detail: "Live source, rate and buffer counters on the player",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Performance.HighPerformanceMode", title: "High performance mode",
                        detail: "Freezes the mesh backdrop and disables depth blur",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Performance.RefreshRate", title: "Refresh rate",
                        detail: "This iOS version has no app-selected display rate",
                        kind: .unavailable("iOS 12 exposes no app-level display refresh-rate control; the system picks it.")),
            SettingItem(key: "BitChord.Performance.RenderQuality", title: "Render quality",
                        detail: "High keeps the full mesh; Low uses a static colour",
                        kind: .choice("High", ["High", "Low"])),
            SettingItem(key: "BitChord.Audio.LoudnessSpeaker", title: "Loudness on speaker",
                        kind: .unavailable("Needs the per-sample loudness processor; this player is AVPlayer-based.")),
            SettingItem(key: "BitChord.Audio.DacVolume", title: "DAC hardware volume",
                        kind: .unavailable("Needs a USB DAC with a volume endpoint; the simulator has no audio hardware.")),
            SettingItem(key: "BitChord.Audio.FixedVolume", title: "Fixed volume output",
                        kind: .unavailable("Needs exclusive bit-perfect output, which AVPlayer does not expose.")),
            SettingItem(key: "BitChord.Audio.Convert", title: "Convert on USB DAC",
                        kind: .unavailable("Needs the bit-perfect resampler and a connected DAC.")),
            SettingItem(key: "BitChord.WearOS", title: "Wear OS",
                        kind: .unavailable("Wear OS is a separate Android companion app; there is no watchOS target in this project."))
        ])
    ]

    static var keyCount: Int {
        return sections.reduce(0) { $0 + $1.items.count }
    }
}
