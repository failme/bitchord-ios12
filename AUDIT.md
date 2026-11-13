# Port audit — what is actually ported

Verdict: **not a 1:1 recreation.** 4,568 lines exist against 23,705 upstream (19.3%).
26 upstream files have **no counterpart at all** (6,048 lines).

The settings surface now exists: all 73 upstream keys are present with their key names and
defaults. Two are wired to real behaviour (playback speed, sleep timer); the rest are rendered
but disabled, each stating why the machinery behind it is missing. A switch that silently does
nothing would be worse than an absent one.

Measured by listing every upstream file and grepping this port for each subsystem symbol.

## Fully absent (26 files, 6,048 lines)

| Upstream file | Lines |
| --- | --- |
| BitChordCore/Network/StreamExtractor.swift | 1071 |
| BitChordCore/AudioEngine/CachingResourceLoader.swift | 564 |
| BitChordUI/Components/TrackContextMenuSheet.swift | 477 |
| BitChordUI/Components/AudioPipelineSheet.swift | 464 |
| BitChordUI/Components/AccountMenuSheet.swift | 438 |
| BitChordCore/Services/SpotifyImporter.swift | 347 |
| BitChordCore/Services/LocalMusicScanner.swift | 309 |
| BitChordUI/Components/DownloadSheetView.swift | 281 |
| BitChordUI/Components/BitChordLogoView.swift | 208 |
| BitChordCore/Lyrics/LyricsStorageManager.swift | 207 |
| BitChordCore/AudioEngine/AudioProtector.swift | 197 |
| BitChordCore/Services/DownloadManager.swift | 191 |
| BitChordCore/Models/SearchResultItem.swift | 170 |
| BitChordCore/Lyrics/LyricsManager.swift | 164 |
| BitChordCore/AudioEngine/AudioProcessingTapHelper.swift | 155 |
| BitChordCore/Services/AccountManager.swift | 152 |
| BitChordUI/Components/SongInfoDialog.swift | 122 |
| BitChordCore/Services/LastFmScrobbler.swift | 122 |
| BitChordUI/Components/ThinSlider.swift | 104 |
| BitChordCore/Models/Album.swift | 79 |
| BitChordCore/AudioEngine/EqualizerPreset.swift | 56 |
| BitChordCore/AudioEngine/SleepTimer.swift | 48 |
| BitChordUI/Components/DynamicBackgroundGradient.swift | 38 |
| BitChordCore/AudioEngine/CrossfadeManager.swift | 33 |
| BitChordUI/Components/FrostedGlass.swift | 28 |
| BitChordCore/Models/SongInfo.swift | 23 |

## Replaced rather than ported

| Upstream | Lines | This port | Consequence |
| --- | --- | --- | --- |
| AudioPlayerEngine | 2543 | PlayerService + YouTubeAudioBridge | no crossfade, gapless, EQ, speed, sleep timer, loudness, bit-perfect, USB DAC |
| YTMusicClient | 1636 | InnerTube + InnerTubeBrowse (~330) | search + filters + album/playlist browse only; no radio, artist pages, iTunes fallback, song info |
| LyricsManager | 164 | LyricsService | no provider switching, no translation, no cache |

## Partial — screen exists, details do not

| Upstream | Lines | Ported | Missing |
| --- | --- | --- | --- |
| HomeView | 1667 | quick picks, continue listening, recents, liked | mood chips, 4-row pick grid + Play All, station/listen-together, new releases, forgotten favourites, mixed for you, listen again |
| SearchView | 944 | query + results | source bar (YouTube/Library/Addons), category chips, recently searched grid, browse categories, addon prompt |
| LibraryView | 853 | liked, playlists, recents, recent searches | local music list, downloaded songs, Spotify import, create/rename flows |
| ExploreView | 825 | trending, new albums, top charts, moods | top category cards, ranked trending shelf, daily charts, artist charts |
| NowPlayingView | 1303 | artwork/lyrics toggle, badge, scrubber, shuffle/repeat, like, queue | stats-for-nerds telemetry, upgrade banner, volume slider, lyrics source picker, autoplay, queue history |
| Track | 620 | 10 fields | streamURL, lyricsId, isExplicit, TrackVersionMatcher, version classification, matching |
| LRCParser | 120 | line timestamps | **syllable tags are stripped, not parsed** — upstream does karaoke highlighting |
| MiniPlayerBar | 134 | tap-to-open | swipe-to-skip, drag-to-expand |
| LibraryDatabase | 329 | 8 collections | artwork resolution pass |
| Lyrics | 88 | LyricLine | Syllable model |
| AudioQuality | 26 | badge strings | quality policy and selection |
| PlaybackState | 20 | RepeatMode | shuffle/autoplay state machine |
| SettingsView | 3065 | 73 keys, sections, persistence, speed + sleep timer | every DSP, storage, integration and appearance row is disabled |
| BitChordSettings | 1110 | SettingsStore keys/defaults | no quality policy, no addon model, no credential storage |

## The 73 settings keys: 0 wired

Audio (15): Automix, AutomixPerf, BitPerfect, CellularQuality, Crossfade, DirectSourceStream,
DisableOnPhoneSpeaker, DolbyAtmos, Equalizer, LoudnessNormalization, OutputPrecision,
PreferUSBDAC, Quality, SkipSilence, SpatialAudio, WifiQuality.
Appearance (11), Lyrics (10), Misc (11), Download (4), LastFm (3), ListenBrainz (2),
Spotify (6), LocalMusic (3), Source (2), Storage (2), Performance (3), Discord (1), Advanced (1).

## What "every detail" requires

1. SettingsView + BitChordSettings (4,175 lines): 73 keys, sections, addon/source editors, account sheets.
2. Audio engine surface the embed can support: speed, sleep timer, autoplay, queue history,
   plus crossfade/EQ only if a real AVPlayer pipeline is built alongside the bridge.
3. Search and Home detail: source bar, category chips, recently-searched grid, 8 Home sections.
4. Lyrics: syllable-level karaoke, storage/cache, translation, provider switching.
5. Addons/downloads: StreamExtractor, DownloadManager, download sheet, offline storage.
6. Integrations: Last.fm, ListenBrainz, Spotify import, local music scan, account manager.
7. Components: context menu sheet, song info, thin slider, frosted glass, mesh gradient, logo.

## Port log

| Commit | Scope |
| --- | --- |
| 53a7dbf | WKWebView embed bridge; player rewritten around it |
| a357cda | Four tabs, capsule bar, library store |
| ee760aa | Search filters, album/playlist browse, live Home and Explore |
| d9fdbaa | Full Now Playing: artwork/lyrics toggle, badge, shuffle/repeat, queue sheet |
| 4fa9943 / 97699fd | Settings surface, 73 keys; speed and sleep timer wired |
| bbb64e8 | Playback self-healing (process-death recovery, stall watchdog) plus a drawn icon set replacing every glyph button |

Every build above was verified green with `MinimumOSVersion 12.0`, `LC_BUILD_VERSION minos 12.0`,
`arm64`. Nothing in this port has been run on a device.

## Downloads and offline playback (v2 port)

Status: **implemented and exercised in the simulator**; not verified on an iOS 12 device.

| Piece | File | What it does |
| --- | --- | --- |
| Download store | `v2/BitChordIOS12/Sources/DownloadStore.swift` | Queue, real progress, persisted index + files, delete, storage total, Wi-Fi-only and quality policy |
| Downloads screen | `v2/BitChordIOS12/Sources/DownloadsViewController.swift` | Live rows with percentage and progress bar, saved rows with quality + size, swipe to delete, empty state |
| Entry point | `v2/BitChordIOS12/Sources/TrackCell.swift` | Long-press a song → Download / Delete download (iOS 12 has no context-menu API) |
| Library route | `v2/BitChordIOS12/Sources/LibraryViewController.swift` | The Downloads row pushes the new screen, with the download glyph |
| Offline playback | `v2/BitChordIOS12/Sources/NativeAudioPlayer.swift`, `AudioEngine.swift` | A downloaded track plays through the same AVPlayer path, queue, now-playing and lock screen; no further request is made |
| Settings | `SettingsStore.swift`, `SettingsViewController.swift` | Download quality (Lossless/High/Normal/Data saver), Download over Wi-Fi only, Storage used (live) |
| Proof | `ScreenshotHarness.swift`, `.github/workflows/ios12-v2.yml` | First launch downloads a track and exits; second launch captures Downloads and offline playback and writes `download-report.txt`, which the job asserts |

Files live in `Application Support/BitChordDownloads/`, one `.m4a` per track plus
`index.json`. The index is pruned on load of any entry whose file is gone.

### Verified in CI (run 43351457240, simulator, all three jobs green)

The screenshots job launches the app once with `-BCSeedDownload`, terminates it,
then launches again with `-BCScreenshots`. From `download-report.txt` of that
second launch: `saved=1`, `totalBytes=8197355`, `fileExists=true`,
`localPlayback=true`, `source=Downloaded`, `position=6.5`, `deletedRows=0`,
`fileRemoved=true`. So the index and the file survived a process restart, the
player took the local branch (no resolve), and deleting removed both the row and
the bytes. The job fails if any of those four assertions does not hold.

Screens: `shots-v2/downloads.png` (saved row, cover, "JioSaavn 320kbps · 8.2 MB"),
`shots-v2/offline.png` (that file playing, 0:10 of 3:20),
`shots-v2/settings-downloads.png` (Download quality High, Wi-Fi-only on,
"Storage used — 1 song · 8.2 MB"), `shots-v2/downloads-empty.png` (empty state
after the delete), `shots-v2/library.png` (Downloads row with its glyph).

Not photographed: the in-flight progress bar and percentage (the seed run is
headless and the 8 MB file finished before any shot), and the long-press menu
itself — both are exercised by the code path but only the outcomes above are
visually confirmed.

Not done in this feature: background/suspended downloads (foreground URLSession
only, so a download stops if the app is killed), lossless or addon-source
downloads, playlist sync, cache eviction and a storage cap, and a per-row
downloaded badge outside the Downloads screen. Nothing here is verified on an
iOS 12 device — only the simulator, via CI.
