# Port audit — what is actually ported

Verdict: **not a 1:1 recreation.** 12,120 lines exist against 23,705 upstream (51%).
26 upstream files have no direct counterpart: their behaviour is either replaced by a smaller
iOS-native implementation or listed under "Remaining gaps" at the end, with the API that rules
it out where one does.

The settings surface exists: all 73 upstream keys are present with their key names and
defaults. Playback speed, sleep timer, download quality, Wi-Fi-only, the download storage
limit, the addon URL and the live storage figure are wired to real behaviour; the rest are
rendered but disabled, each stating why the machinery behind it is missing. A switch that
silently does nothing would be worse than an absent one.

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

## The 73 settings keys: which are wired

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
| Entry point | `v2/BitChordIOS12/Sources/TrackCell.swift`, `TrackActions.swift` | Long-press a song → Download / Cancel download / Delete download, whichever the row is in (iOS 12 has no context-menu API) |
| Library route | `v2/BitChordIOS12/Sources/LibraryViewController.swift` | The Downloads row pushes the new screen, with the download glyph |
| Offline playback | `v2/BitChordIOS12/Sources/NativeAudioPlayer.swift`, `AudioEngine.swift` | A downloaded track plays through the same AVPlayer path, queue, now-playing and lock screen; no further request is made |
| Settings | `SettingsStore.swift`, `SettingsViewController.swift` | Download quality (Lossless/High/Normal/Data saver), Download storage limit, Storage used (live, against the limit), Download over Wi-Fi only, Lossless addon URL |
| Proof | `ScreenshotHarness.swift`, `.github/workflows/ios12-v2.yml` | First launch downloads a track and exits; second launch captures Downloads and offline playback and writes `download-report.txt`, which the job asserts |

Files live in `Application Support/BitChordDownloads/`, one `.m4a` per track plus
`index.json`. The index is pruned on load of any entry whose file is gone.

### Demonstrated in CI (commit `ce080cd`, simulator, all three jobs green)

The screenshots job launches once with `-BCSeedDownload` (a 320 kbps download),
quits, then relaunches with `-BCScreenshots`, which reads the index back off disk
and runs the whole feature. `download-report.txt` from the second process, with
the job failing if any line is wrong:

- **Relaunch**: `resume.saved=1`, `resume.totalBytes=8197355` — the index and the
  file survived a process restart.
- **Offline playback**: `localPlayback=true`, `source=Downloaded` — the player
  took the local-file branch, with no resolve.
- **Quality changes the rendition**: same track, two settings.
  `quality.high.label=JioSaavn 320kbps`, `quality.high.bytes=8197355`;
  `quality.setting=Data saver`, `quality.saver.label=JioSaavn 96kbps`,
  `quality.saver.bytes=2489491`, `quality.saverSmaller=true`. The job measures
  both stored files with `afinfo`: **326337 bps vs 98124 bps**, **8197355 B vs
  2489491 B** — a 3.3x smaller file at the lower setting.
- **Settings reflect it**: `settings.storage=1 song · 2.5 MB` while Download
  quality reads "Data saver".
- **Wi-Fi-only holds the download**: with the setting on and the connection
  reported as metered, `wifi.blocked=true`, `wifi.failedRows=1`,
  `wifi.message=Downloads are limited to Wi-Fi...`, and the row shows "HELD"
  with that reason.
- **Menus**: `sheet.delete.downloaded=true`, `sheet.cancel.downloading=true`,
  `sheet.download.idle=true`, each opened from a real `TrackCell` in a real list.
- **Delete**: `deletedRows=0`, `fileRemoved=true`.
- **Progress**: `progress.captured=23` — the shot was taken with the transfer at
  23% and the bar filled to match.

Screens in `shots-v2/`: `downloads.png` (saved row), `download-progress.png`
(Downloading... 23% plus bar), `downloads-saver.png` (JioSaavn 96kbps · 2.5 MB),
`settings-downloads.png` (Data saver, Wi-Fi-only on, Storage used 1 song ·
2.5 MB), `wifi-blocked.png` (HELD row), `sheet-download.png`,
`sheet-cancel.png`, `sheet-delete.png`, `offline.png`, `downloads-empty.png`,
`library.png`.

Mechanism note: the mid-transfer frame exists because the harness sets
`progressPace`, which switches the store to a data-task transport that consumes
the body 32 KB at a time; the resolve, destination, index entry and completion
are shared with the normal download-task path. The Wi-Fi decision is likewise the
real branch with a harness-supplied connection answer
(`connectivityOverride`), because CI has no metered link.

The IPA is now inspected inside CI too: the packaged `.ipa` is unzipped,
`MinimumOSVersion` read from its `Info.plist` (12.0), and `lipo -archs` run on
its binary (arm64), so a green build cannot hide a wrong deployment target.

## Storage cap, background transfers, addon tiers, playlist sync

These four were the last items the audit listed as unbuilt. They are now real
behaviour in the app, driven by the capture harness and asserted in CI (run
`43365794289` on commit `add1ae1`, all three jobs green).

| Piece | Files | What it does |
| --- | --- | --- |
| Storage cap | `DownloadStore.swift`, `SettingsStore.swift`, `SettingsViewController.swift` | `BitChord.Download.StorageLimit` (512 MB / 1 GB / 2 GB / 5 GB / Unlimited); a new download whose estimate would pass the cap is refused, the row shows "Storage limit reached." the same way a HELD row shows its reason, and the alert carries the fuller sentence with the current usage |
| Background transfers | `DownloadStore.swift`, `AppDelegate.swift` | `URLSessionConfiguration.background(withIdentifier:)`, `sessionSendsLaunchEvents`, `application:handleEventsForBackgroundURLSession:`, a `pending.json` mirror with `taskDescription` as the join key, and a 12 s post-launch reconcile |
| Addon tiers | `AddonService.swift`, `DownloadStore.swift`, Settings | `GET <base>/manifest` and `GET <base>/stream/<videoID>`; Lossless asks the addon first and falls through to the standard catalogue when it answers 404 or nothing usable |
| Playlist sync | `PlaylistSync.swift`, `LibraryStore.swift`, `InnerTubeBrowse.swift`, `LibraryViewController.swift` | Sync button in the Library heading; a public YouTube Music playlist link or id is pulled through the same `browse` call, saved under a `remote:` id with its tracks in order, and re-syncing replaces it in place |

Measured in that run (reports are committed under `shots-v2/`):

- **Cap**: with `10 MB` set and one 2.5 MB song saved, the estimate
  `9338304` bytes crossed the limit, so `cap.blocked=true`,
  `cap.reason=Storage limit reached.`, `cap.savedUnchanged=true`. Lowering the
  limit to `1 MB` left `cap.lowLimitCount=1` and `cap.lowLimitFiles=true`, and
  Settings reads `1 song · 2.5 MB of 1 MB`.
- **Background, resumed**: a download started, the app was sent to the
  background, and on return `background.indexed=true`,
  `background.pendingAfter=0`, `background.phantom=false` (no index entry
  without a file).
- **Background, force-quit**: `verify.pendingAtLaunch=1`, then
  `background.indexed=false`, `background.reported=true`,
  `background.reason=Download interrupted. Tap to try again.`,
  `background.pendingAfter=0`, `background.phantom=false` — the index is
  consistent either way.
- **Addon vs standard**: `addon.label=Lossless · 1411 kbps` on the ALAC the
  addon served, `775186 bps / 3883053 B` measured by `afinfo`, against
  `addon.fallback.label=JioSaavn 320kbps`, `320353 bps / 8198941 B` for a track
  the addon does not serve. Both files are fetched by the app in the same run.
- **Playlist sync**: `sync.ok=true`, 100 songs, first `Die With A Smile`, last
  `Another You (feat. Sadie Jean)`; a fresh process then read back
  `verify.playlistTracks=100` with the same first and last titles. The failure
  path (`sync.failure.ok=true`, message "This playlist has no playable songs.")
  leaves `sync.playlists` unchanged and shows the alert captured in
  `sync-failed.png`.

Screens added: `storage-cap.png`, `settings-storage.png`, `library-synced.png`,
`playlist-synced.png`, `sync-failed.png`, `downloads-addon.png`.

Substitutions worth naming:

- **Playlist sync** replaces upstream's signed-in account sync (`AccountManager`
  is an Android/credential feature with no counterpart here) with a public
  YouTube Music playlist by link. No account, no tokens, same browse call.
- **Background transfers** use the real iOS 12 background session. On the
  simulator that daemon refuses the transfer with `NSURLErrorUnknown (-1)`
  before a byte arrives, so the store retries once in a foreground session and
  records which session carried the file (`transport`). On a device the first
  session is the one that runs. `simctl terminate` is a force-quit, which
  cancels background transfers by design on any device — that is exactly why
  the killed scenario asserts the *report* path rather than a completed file.
- **The addon in CI** is `v2/tools/addon_server.py`, a local server speaking the
  same two calls. It serves a generated 40 s ALAC file, so the two files differ
  in duration as well as tier: the **bitrate** comparison (775 kbps against
  320 kbps) is the tier proof, and the byte sizes differ measurably too.

### Not verified here
- Anything on a real iOS 12 device: all of this is the simulator build of the
  same source. AVPlayer local-file playback, the lock screen,
  `SCNetworkReachability`, the background transfer daemon and tapping the real
  addon are unexercised on device.
- A physically metered connection: the block path runs, but the reachability
  answer is injected by the harness.
- The paced transport is capture-only; users get the download-task transport.
  Everything after resolve is the same code.

## Remaining gaps

Items iOS 12 itself rules out, with the API that does it and what ships instead:

| Item | Ruled out by | Shipped instead |
| --- | --- | --- |
| Bit-perfect output, USB DAC preference, output precision | iOS 12 exposes no route-selection or exclusive-mode API for app audio; `AVAudioSession` offers only categories and ports | `AVPlayer` playback; the rows are disabled and say so |
| Crossfade, gapless, equalizer, loudness normalisation, AudioProcessing tap | `AVPlayer` has no per-sample tap or second-player crossfade; doing it needs the whole pipeline rebuilt on `AVAudioEngine` with the streaming bridge removed | speed and sleep timer are wired; the DSP rows state the missing pipeline |
| Account sign-in and cloud library sync | Upstream's `AccountManager` is Android-only; this port has no credentials or server | public playlist sync plus local storage |
| Last.fm / ListenBrainz scrobbling | requires per-user API keys this port has no way to obtain | rows disabled with that reason |
| Spotify import | needs a Spotify OAuth client and Web API credentials, neither shipped | playlist sync by public YouTube Music link |

Still unported with no iOS 12 blocker (scope, not platform): local music scan
(`MPMediaLibrary` exists on iOS 12), artist pages, radio and mood sections, the
queue history sheet, syllable-level karaoke, a downloaded badge outside the
Downloads screen, and cache eviction.
