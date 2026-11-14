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
    /// A row that clears one of the app's caches: "song" or "image".
    case cache(String)
    /// Row is shown for parity but has no effect here; the reason is surfaced to the user.
    case unavailable(String)
    /// Re-opens the first-run flow.
    case onboarding
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
                        kind: .toggle(false)),
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
                        kind: .unavailable("Route control needs the AVPlayer pipeline."))
        ]),

        SettingSection(title: "Lyrics", items: [
            SettingItem(key: "BitChord.Lyrics.Synced", title: "Synced lyrics",
                        detail: "Highlight the current line", kind: .toggle(true)),
            SettingItem(key: "BitChord.Lyrics.ShowFullLyrics", title: "Show full lyrics",
                        kind: .toggle(true)),
            SettingItem(key: "BitChord.Lyrics.BlurUnfocused", title: "Blur unfocused lines",
                        kind: .unavailable("Karaoke styling arrives with the syllable port.")),
            SettingItem(key: "BitChord.Lyrics.ShowBilingual", title: "Bilingual lyrics",
                        kind: .unavailable("Translation is not ported.")),
            SettingItem(key: "BitChord.Lyrics.TranslationLanguage", title: "Translation language",
                        kind: .unavailable("Translation is not ported.")),
            SettingItem(key: "BitChord.Lyrics.AutoDownloadToStorage", title: "Save lyrics offline",
                        kind: .unavailable("Lyrics storage manager is not ported.")),
            SettingItem(key: "BitChord.Lyrics.ArtistSignatures", title: "Artist signatures",
                        kind: .unavailable("Not ported.")),
            SettingItem(key: "BitChord.Lyrics.ActiveSource", title: "Lyrics source",
                        kind: .choice("LRCLIB", ["LRCLIB", "Embedded tags"])),
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
                        kind: .unavailable("Playlist sync is not ported.")),
            SettingItem(key: "BitChord.Download.ExportCompatible", title: "Export compatible files",
                        kind: .unavailable("Download manager is not ported.")),
            SettingItem(key: "BitChord.LocalMusic.SelectedFolder", title: "Local music folder",
                        detail: "Audio files in this app folder appear in Library \u{2192} Local Music",
                        kind: .page("Put audio files in the app's LocalMusic folder, through the Files app or iTunes File Sharing. Library \u{2192} Local Music lists them by folder, with the title, artist and length read from each file.")),
            SettingItem(key: "BitChord.LocalMusic.FilterNonMusic", title: "Filter non-music",
                        detail: "Hide clips shorter than 30 seconds",
                        kind: .toggle(true)),
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
            SettingItem(key: "BitChord.Source.JioSaavn", title: "JioSaavn",
                        kind: .unavailable("Addon sources are not ported.")),
            SettingItem(key: "BitChord.Source.TrackLengthTolerance", title: "Track length tolerance",
                        kind: .unavailable("Addon sources are not ported."))
        ]),

        SettingSection(title: "Integrations", items: [
            SettingItem(key: "BitChord.LastFm.Enabled", title: "Last.fm scrobbling",
                        kind: .unavailable("Scrobbler is not ported.")),
            SettingItem(key: "BitChord.LastFm.Username", title: "Last.fm username",
                        kind: .unavailable("Scrobbler is not ported.")),
            SettingItem(key: "BitChord.LastFm.SessionKey", title: "Last.fm session",
                        kind: .unavailable("Scrobbler is not ported.")),
            SettingItem(key: "BitChord.ListenBrainz.Enabled", title: "ListenBrainz",
                        kind: .unavailable("Scrobbler is not ported.")),
            SettingItem(key: "BitChord.ListenBrainz.Token", title: "ListenBrainz token",
                        kind: .unavailable("Scrobbler is not ported.")),
            SettingItem(key: "BitChord.Spotify.Connected", title: "Spotify",
                        kind: .unavailable("Spotify import is not ported.")),
            SettingItem(key: "BitChord.Spotify.Username", title: "Spotify username",
                        kind: .unavailable("Spotify import is not ported.")),
            SettingItem(key: "BitChord.Spotify.DisplayName", title: "Spotify display name",
                        kind: .unavailable("Spotify import is not ported.")),
            SettingItem(key: "BitChord.Spotify.AvatarURL", title: "Spotify avatar",
                        kind: .unavailable("Spotify import is not ported.")),
            SettingItem(key: "BitChord.Spotify.AccessToken", title: "Spotify token",
                        kind: .unavailable("Spotify import is not ported.")),
            SettingItem(key: "BitChord.Spotify.CookieSPDC", title: "Spotify cookie",
                        kind: .unavailable("Spotify import is not ported.")),
            SettingItem(key: "BitChord.Discord.Enabled", title: "Discord presence",
                        kind: .unavailable("Discord is not ported."))
        ]),

        SettingSection(title: "Appearance", items: [
            SettingItem(key: "BitChord.Appearance.Theme", title: "Theme",
                        kind: .choice("Midnight", ["Midnight", "System"])),
            SettingItem(key: "BitChord.Appearance.Font", title: "Font",
                        kind: .choice("System", ["System", "Rounded", "Serif"])),
            SettingItem(key: "BitChord.Appearance.AppIcon", title: "App icon",
                        kind: .unavailable("Alternate icons need an asset catalog port.")),
            SettingItem(key: "BitChord.Appearance.AnimatedCover", title: "Animated cover",
                        kind: .unavailable("Animated artwork is not ported.")),
            SettingItem(key: "BitChord.Appearance.AnimatedCoverCellular", title: "Animated cover on cellular",
                        kind: .unavailable("Animated artwork is not ported.")),
            SettingItem(key: "BitChord.Appearance.SpotifyCanvas", title: "Spotify Canvas",
                        kind: .unavailable("Not ported.")),
            SettingItem(key: "BitChord.Appearance.LiquidGlass", title: "Liquid glass",
                        kind: .unavailable("Materials ported as flat colour; no blur stack.")),
            SettingItem(key: "BitChord.Appearance.LegacyMesh", title: "Legacy mesh gradient",
                        kind: .unavailable("Mesh gradient is not ported.")),
            SettingItem(key: "BitChord.Appearance.ReduceAnimation", title: "Reduce animation",
                        kind: .unavailable("Depends on the mesh/motion work.")),
            SettingItem(key: "BitChord.Appearance.ReduceDynamicBlur", title: "Reduce dynamic blur",
                        kind: .unavailable("Depends on the mesh/motion work."))
        ]),

        SettingSection(title: "Misc", items: [
            SettingItem(key: "BitChord.Misc.HideVolumeSlider", title: "Hide volume slider",
                        kind: .unavailable("No volume slider in this player yet.")),
            SettingItem(key: "BitChord.Misc.HideStatusBarInPlayer", title: "Hide status bar in player",
                        kind: .unavailable("Not ported.")),
            SettingItem(key: "BitChord.Misc.HideSongStatus", title: "Hide song status",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.ShowQueueHistory", title: "Show queue history",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.PlayNextOnSwipe", title: "Swipe to play next",
                        kind: .unavailable("Mini player gestures are not ported.")),
            SettingItem(key: "BitChord.Misc.DontRepeatInSession", title: "Don't repeat in session",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.StopOnCloseRecents", title: "Stop when recents close",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Misc.ShowListenTogetherButton", title: "Listen together button",
                        kind: .unavailable("Listen Together is not ported.")),
            SettingItem(key: "BitChord.Misc.SmartAudioAlignment", title: "Smart audio alignment",
                        kind: .unavailable("Needs the DSP pipeline.")),
            SettingItem(key: "BitChord.Misc.WorkOutGenres", title: "Workout genres",
                        kind: .unavailable("Workout mode is not ported.")),
            SettingItem(key: "BitChord.Misc.AppLanguage", title: "Language",
                        kind: .choice("System", ["System", "English", "Indonesian"])),
            SettingItem(key: "BitChord.Misc.ShowOnboarding", title: "Show onboarding again",
                        detail: "Welcome, tour and library choice",
                        kind: .onboarding)
        ]),

        SettingSection(title: "Performance & advanced", items: [
            SettingItem(key: "BitChord.Misc.ShowDebugInfo", title: "Show debug info",
                        detail: "Stream source, quality and engine counters",
                        kind: .toggle(false)),
            SettingItem(key: "BitChord.Advanced.StatsForNerds", title: "Stats for nerds",
                        kind: .unavailable("Telemetry overlay is not ported.")),
            SettingItem(key: "BitChord.Performance.HighPerformanceMode", title: "High performance mode",
                        kind: .unavailable("Not ported.")),
            SettingItem(key: "BitChord.Performance.RefreshRate", title: "Refresh rate",
                        kind: .unavailable("Not ported.")),
            SettingItem(key: "BitChord.Performance.RenderQuality", title: "Render quality",
                        kind: .unavailable("Not ported."))
        ])
    ]

    static var keyCount: Int {
        return sections.reduce(0) { $0 + $1.items.count }
    }
}
