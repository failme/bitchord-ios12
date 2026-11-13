# BitChord on iOS 12 — what is ported, and how it is proven

This is a recreation of `kushagrasinghx/BitChord` (Kotlin/Compose, Android) as a
native UIKit app for iOS 12. Every feature below is exercised by the capture
harness in CI, on a simulator, from the app's own screens — not by a unit test
that pokes a model. What is left out is left out because iOS 12 has no API for
it, and each such row names the API and what ships in its place.

- App: `v2/BitChordIOS12`, ~17 MB unsigned IPA at the repo root.
- Deployment target `12.0`, thin `arm64`, `UIDeviceFamily [1,2]` (checked inside
  CI by unzipping the packaged IPA, reading its `Info.plist` and running
  `lipo -archs`), and again on the committed IPA.
- Language/frameworks: Swift + UIKit, `AVPlayer`, `URLSession` (background
  configuration), `URLCache`, `WKWebView` only where a web surface is the point.

## How it is proven

Every push runs three jobs (`.github/workflows/ios12-v2.yml`):

1. **build** — device build with `IPHONEOS_DEPLOYMENT_TARGET=12.0`, packages the
   unsigned IPA, unzips it and asserts `MinimumOSVersion`, `arm64` and the device
   family.
2. **simulator** — same sources for an iPhone SE (1st gen, 320 pt wide) and an
   iPhone 8, so the small-screen layout is what CI renders.
3. **screenshots** — boots the 320 pt simulator, seeds a download, launches the
   app with `-BCScreenshots`, drives ~20 phases through real screens, writes
   `download-report.txt`, asserts ~100 keys on it, then runs two more launches:
   a background transfer that is resumed, and one that is force-quit. The job
   fails if any assertion or any expected screenshot is missing.

Latest full run: commit `604452f`, all three jobs green (`43375904069`). The
committed IPA was built by that run and inspected again locally:
`MinimumOSVersion 12.0`, `UIDeviceFamily [1,2]`, executable `arm64`
(`cputype 0x100000c`), 16,906,942 bytes.

The harness (`Sources/ScreenshotHarness.swift`) touches the app the way a user
does: presents screens, taps table rows, opens the long-press sheet, plays
tracks, and photographs the result. Where a platform state cannot exist in CI
(a metered link, a background daemon that works in the simulator), the branch is
the real one and only its input is injected; those two are named below.

## What is implemented

| Area | Where | Proven by (report keys / screens) |
| --- | --- | --- |
| Tabs, capsule bar, mini player, Home/Explore/Library/Search | `RootViewController`, `HomeViewController`, `ExploreViewController`, `LibraryViewController`, `SearchViewController` | `home.png`, `explore.png`, `library.png`, `search.png` |
| Search with source bar, filters, artist and album rows | `SearchViewController`, `InnerTube`, `InnerTubeBrowse`, `CatalogueSearch` | live results in `search.png`; artist page below |
| Artist pages | `ArtistPage.swift` (YouTube Music browse, the same page upstream opens) | `artist.name=The Weeknd`, `artist.loaded=5`, `artist.png` |
| Moods | `ExploreViewController` tiles → `InnerTube.search("<mood> music")` | `moods.title=Chill`, `moods.tracks=20`, `moods.png` |
| Now Playing: artwork, lyrics/karaoke, scrubber, shuffle/repeat, like, queue | `NowPlayingViewController` | `lyrics.png`, `queue-history.png` |
| Queue history (last 25, `BitChord.Player.QueueHistory`) | `PlaybackHistoryStore`, `QueueViewController` | `history.count=2`, `history.top=Shape of You`, `history.limit=25`, `queue-history.png` |
| Syllable karaoke from enhanced LRC | `LyricsService.taggedLine` + `KaraokeLineView` | `lyrics.syllables=3`, `lyrics.text=Hello world`, `lyrics.revealAdvance=true`, `lyrics.liveWordLines=95`, `lyrics-karaoke.png` |
| Radio ("Start radio" in the song menu) | `TrackActions` → `RadioService` → `InnerTube.radio` | seed resolved on YouTube, mix loaded and playing, `radio.png`, failure alert `radio-failed.png` |
| Local Music (locker) | `LocalMusicStore`, `LocalMusicViewController` | `local.folders=1`, `local.tracks=1`, `local.playing=true`, engine `native Local Music`, `local-music.png`, `local-songs.png` |
| Downloaded mark on every row | `TrackCell` | `badge.downloaded=true` |
| Downloads: queue, progress, quality, delete, offline playback | `DownloadStore`, `DownloadsViewController`, `NativeAudioPlayer` | see the download section |
| Storage cap, Wi-Fi-only, background transfers | `DownloadStore`, `AppDelegate` | below |
| Playlist sync by public YouTube Music link | `PlaylistSync`, `LibraryStore` | `sync.tracks=100`, relaunch read-back, `playlist-synced.png` |
| Lossless addon | `AddonService`, Settings | `addon.label=Lossless · 1411 kbps` |
| Cache limit + clearing | `CacheStore`, Settings | `cache.limit=250 MB`, `cache.freed=11026432`, `settings-cache.png` |
| 73 settings keys, persistence | `SettingsStore`, `SettingsViewController` | `settings.png`, `settings-downloads.png` |

Screens are laid out for a 320 pt width (the SE) and verified at that size in CI;
nothing in the app assumes an iPhone X-class safe area.

## Downloads, offline, quality, cap, background, addon, sync

| Piece | File | What it does |
| --- | --- | --- |
| Download store | `DownloadStore.swift` | Queue, real progress, persisted index + files, delete, storage total, Wi-Fi-only and quality policy, storage cap |
| Downloads screen | `DownloadsViewController.swift` | Live rows with percentage and bar, saved rows with quality + size, swipe to delete, empty state |
| Entry point | `TrackCell.swift`, `TrackActions.swift` | Long-press → Download / Cancel / Delete (iOS 12 has no context-menu API) |
| Offline playback | `NativeAudioPlayer.swift`, `AudioEngine.swift` | A downloaded track plays through the same AVPlayer path, queue, now-playing and lock screen, with no request |
| Background | `DownloadStore.swift`, `AppDelegate.swift` | Background `URLSession`, launch events, `pending.json`, post-launch reconcile |
| Addon | `AddonService.swift` | `GET <base>/manifest`, `GET <base>/stream/<id>`; Lossless falls back to the catalogue on 404 |
| Sync | `PlaylistSync.swift` | Public playlist link/id → `browse` → saved as `remote:` |

Measured in CI (reports committed under `shots-v2/`):

- **Relaunch**: `resume.saved=1`, `resume.totalBytes=8182315` — the index and file
  survived a restart.
- **Offline**: `localPlayback=true`, `source=Downloaded`.
- **Quality changes the rendition**: `JioSaavn 320kbps` at 8182315 B against
  `Data saver` at 2489491 B; `afinfo` in CI measures 326337 bps vs 98124 bps.
- **Cap**: `cap.blocked=true`, `cap.reason=Storage limit reached.`,
  `cap.savedUnchanged=true`, and at a 1 MB limit `cap.lowLimitCount=1` with
  Settings reading `1 song · 2.5 MB of 1 MB`.
- **Wi-Fi-only**: `wifi.blocked=true`, the row shows HELD with the reason.
- **Background resumed**: `background.indexed=true`, `background.pendingAfter=0`,
  `background.phantom=false`.
- **Background force-quit**: `verify.pendingAtLaunch=1`,
  `background.reported=true`, `background.reason=Download interrupted. Tap to try
  again.`, `background.pendingAfter=0`, `background.failed=1`.
- **The same fresh process reads the locker and the history back**:
  `verify.localTracks=1`, `verify.localTitle=01 Levitating`, `verify.history=3`,
  `verify.historyTop=Blinding Lights` — three songs were played during the
  capture, and only the last 25 are kept by design.
- **Addon vs catalogue**: `Lossless · 1411 kbps` (775186 bps / 3883053 B) against
  `JioSaavn 320kbps` (320353 bps / 8198941 B), both fetched by the app.
- **Sync**: 100 songs, first and last titles recorded, read back after a fresh
  launch; the failure path leaves the saved set unchanged and shows
  `sync-failed.png`.
- **Local music**: `local.folders=1`, `local.tracks=1`,
  `local.title=01 Levitating`, `local.playing=true`, engine
  `native Local Music t=1.0/204`, and a fresh process still lists it.
- **Queue history**: `history.count=2`, `history.limit=25`,
  `history.top=Shape of You`, shown as its own section above the queue.
- **Karaoke**: enhanced-LRC tags parse into three timed syllables
  (`lyrics.words=3`, `lyrics.syllables=3`), the highlight advances with the
  clock (`lyrics.revealAdvance=true`), and live lyrics from the real source are
  word-synced when the file carries tags.
- **Radio**: `radio.seed=catalogue-resolved`, `radio.tracks=50`,
  `radio.first=Blinding Lights`, `radio.playing=true`, `radio.queued=50` — the
  catalogue seed was resolved to its YouTube recording, the mix replaced the
  queue and played. The refusal path is photographed as `radio-failed.png`.
- **Cache**: a known 1 MB file plus the app's own caches are cleared;
  `cache.freed` is the measured difference.
- **Menus**: `sheet.delete.downloaded=true`, `sheet.cancel.downloading=true`,
  `sheet.download.idle=true`, opened from a real row.

## What iOS 12 rules out, and what ships instead

| Item | Blocked by | Shipped instead |
| --- | --- | --- |
| Bit-perfect output, USB DAC preference, output precision | iOS 12 exposes no exclusive-mode or route-selection API for app audio; `AVAudioSession` offers categories and ports only | `AVPlayer`; the rows are disabled and say why |
| Crossfade, gapless, equaliser, loudness normalisation, AudioProcessing tap | `AVPlayer` has no per-sample tap and no second-player crossfade; those need the whole pipeline rebuilt on `AVAudioEngine`, which would drop the streaming bridge | Speed and sleep timer are wired; the DSP rows state the missing pipeline |
| System media-library scan (`MPMediaLibrary`) | iOS 12 gates the library behind `MPMediaLibrary.requestAuthorization`, and there is no library at all in the simulator, so a scan cannot be part of a reproducible build | The app scans its own `Documents/LocalMusic` folder (Files/iTunes sharing), ids `local:`, and plays it through the same engine |
| Per-file cache eviction | iOS 12 exposes no public API to enumerate or evict a URL cache's entries one by one | `URLCache.shared.diskCapacity` bounds it; "Clear image cache" drops all responses and the app's cache directory, and reports the bytes freed |
| Lyrics translation | No translation API exists before iOS 17.4 (`Translation`); third-party services need keys and network per line | Lyrics come synced from the source; the karaoke timeline is built from the file's own timings |
| Context menus, `UIMenu`, `UISearchToken`, large-title collapse, drag-and-drop between apps | All are iOS 13+ APIs | Long-press action sheet, a source bar, and a custom large-title header, all reachable by tap |

## What still needs something this build cannot ship

These are not iOS 12 limits; they are credentials or servers that do not exist in
this repository, and the app says so in Settings rather than pretending.

| Item | Why | Substitution |
| --- | --- | --- |
| Last.fm / ListenBrainz scrobbling | Needs the user's own API keys and a registered application | Rows disabled with that reason |
| Spotify import | Needs a Spotify OAuth client and Web API credentials | Playlist sync by public YouTube Music link |
| Account sign-in / cloud library sync | Upstream's `AccountManager` is an Android service with no server here | Local library, persisted; public playlist sync |

## Not verified here

- Anything on a real iOS 12 device: every run is the simulator build of the same
  source. The lock screen, `SCNetworkReachability`, the background transfer
  daemon and a real addon server are unexercised on device.
- A physically metered connection: the block path runs, with the reachability
  answer injected.
- The paced transfer used for the mid-progress screenshot is capture-only; users
  get the download-task transport. Everything after resolve is shared code.
- The simulator's background session refuses transfers with
  `NSURLErrorUnknown (-1)` before a byte arrives; the store retries once in a
  foreground session and records `transport`. On a device the first session is
  the one that runs.

## Commit log (this pass)

| Commit | Scope |
| --- | --- |
| `b9b7ab7` | Local locker, queue history, radio service, syllable LRC, downloaded badge, cache limit |
| `83d880f` | Radio seeds resolved onto YouTube; artist rows/pages from YouTube Music |
| `0745c81` | Mix endpoint asked for a radio (`params=wAEB`) |
| `3d50e7d` | Sync probe skips channel ids and retries the next real playlist |
| `01e2a0f` | Radio probe drives the menu path, seed resolution included |
| `ebb545a` | Play pill readable on the white accent; capture screens get their nav bars |
| `32af791` | Radio probe reports the mix the service loaded |
| `f935f34` | Local engine assertion matches the app; audit rewritten |
| `604452f` | Artist assertion matches the harness key — all three jobs green |

Earlier passes covered the download store and offline playback, the storage cap,
background transfers, addon tiers and playlist sync (`add1ae1`), and the four
tabs, search/browse, Now Playing and Settings before that.
