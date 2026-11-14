# BitChord on iOS 12 - coverage matrix

A native UIKit recreation of `kushagrasinghx/BitChord` (Kotlin/Compose, Android)
for iOS 12. The matrix below is derived from the upstream tree - every
user-facing surface in `ui/screens`, `ui/components`, `ui/player`, `playback`,
`download`, `data` and the shared UI module - and each row names the iOS code
that implements it and the CI proof, or names the iOS 12 API that blocks it and
what ships instead.

States: **Asserted** (CI drives the real screen/action and asserts a key or a
screenshot), **Ported** (implemented and reachable, exercised indirectly by the
flows CI asserts), **iOS 12 block**, **Account/credential** (needs an account or
third-party keys this build cannot ship), **Android-only**.

Latest full run: commit `32c0fee`, all three jobs green (`43536015686`). Both
root IPAs are that build: 17,060,582 bytes, sha256 `e146410d...`, bundle
`com.bitchord.ios12v2` 2.0.0, `MinimumOSVersion 12.0`, `UIDeviceFamily [1,2]`,
a thin `arm64` executable (`cputype 0x100000c`) and a registered `bitchord`
URL scheme - verified inside CI by unzipping the packaged IPA and again on the
committed file, with both copies byte-identical.

## Shell and navigation

| Upstream | Port | State |
| --- | --- | --- |
| `floatingtabbar/FloatingTabBar.kt`, `MainViewModel.kt` | `RootViewController`, `CapsuleTabBar` | Asserted - `home/explore/library/search` screenshots |
| `components/MiniPlayer.kt` | `MiniPlayerBar` | Asserted - in every captured screen |
| `ui/player/AndroidPlayerHost.kt` | `NowPlayingViewController` | Asserted - `lyrics.png`, `lyrics-karaoke.png` |
| `components/IosSwitch.kt`, `IosMenu.kt` | UIKit switches, action sheets | Ported - iOS 12 has no `UIMenu` |
| `FrostedTopBar`, `GlassNavBar`, `LiquidGlass` | `MeshGradientView`, `Theme`, native bars | Ported as an approximation |
| `OnboardingScreen.kt` | `OnboardingViewController` | Asserted - `onboarding-welcome/tour/library/ready.png`, `onboarding-report.txt`, 320x568 shots; re-runnable from Settings |
| `MusicLink.kt`, `PlayerDeepLink.kt`, intent filters | `DeepLink`, `DeepLinkRouter`, `CFBundleURLTypes` | Asserted - six routes from `deeplinks.txt`, all `cold=1`; scheme shown registered by SpringBoard's prompt |

## Screens

| Upstream | Port | State |
| --- | --- | --- |
| `sharedUi/HomeScreen.kt` | `HomeViewController`, `ShelfRowView`, `TopPicksShelf`, `SignInBannerView` | Asserted - `home.png` |
| `sharedUi/ExploreScreen.kt` | `ExploreViewController`, `MoodTileView` | Asserted - `moods.png`, `moods.tracks=20` |
| `sharedUi/SearchScreen.kt` | `SearchViewController`, `InnerTube`, `CatalogueSearch` | Asserted - `search.png` |
| `sharedUi/LibraryScreen.kt`, `LibraryPhoneParts.kt` | `LibraryViewController`, `LibraryStore` | Asserted - `library.png`, `library-synced.png` |
| `ui/screens/HistoryScreen.kt` | `HistoryViewController` | Asserted - `history.png`, `history-empty.png`, `historyPage.*` |
| `ui/screens/LocalFolder.kt` | `LocalMusicViewController`, `LocalMusicStore` | Asserted - `local-music.png`, `local-songs.png`, `local.playing=true` |
| `ui/screens/DetailScreen.kt` | `CollectionViewController`, `ArtistPage` | Asserted - `artist.png`, `artist.loaded=5` |
| `ui/replay/*` | `ReplayViewController` | Asserted - `replay.png`, `replay.entries`, `replay.plays` |
| `SettingsSheet.kt`, `SettingsView` | `SettingsViewController`, `SettingsStore` | Asserted - `settings*.png`; 82 rows, all 73 keys |
| `ui/screens/EqualizerScreen.kt` | Disabled row with reason | iOS 12 block - `AVPlayer` has no EQ tap |
| `AccountAndScrobblingScreen.kt` | Disabled rows | Account/credential - needs the user's Last.fm/ListenBrainz keys |
| `ListenTogetherScreen.kt`, `PartySync.kt` | Absent | Account/credential - needs a party server |
| `DiscordScreen.kt`, `data/discord` | Disabled row | Android-only - Discord RPC uses local Android IPC |
| `SpotifyLibraryScreen.kt`, `SpotifyCanvasAuthScreen.kt` | Disabled row; sync by public YT Music link | Account/credential - Spotify OAuth client |
| `SourcesScreen.kt`, `data/sources`, `data/webdav`, `data/remote` | `AddonService`, `WebDAVClient`, `WebDAVStore`, `JellyfinClient`, `JellyfinStore`, `JellyfinViewController`, `SourcesViewController` | Asserted - WebDAV: `webdav-tree.png`, `webdav-playing.png`, `webdav-error.png`; PROPFIND list, folder browse, streamed `track.m4a`, bad-password message. Jellyfin: native API sign-in, library/folder/album browse, streamed `track.m4a` with `isPlaying=true`, expired/wrong-password/unreachable messages, `jellyfin-tree/playing/error/small.png`. SMB not shipped (see Remaining) |
| `WearOsSettings.kt`, `ui/widget`, `wearos/`, `tv/` | Absent | Android-only - separate apps/surfaces |

## Song menu and library actions

| Upstream | Port | State |
| --- | --- | --- |
| `SongActionsMenu.kt` | `TrackActions` | Asserted - `song-actions.png`; play next, add to queue, add to playlist, like, artist, download, radio, share, info |
| `PlaylistPickerSheet.kt` | `PlaylistPicker`, `LibraryStore` | Asserted - `add-to-playlist.png`, `menu.playlistGrew=true` |
| `SongInfoDialog.kt` | `SongInfoViewController` | Asserted - `song-info.png`, `info.rows=7` |
| `LyricsShareCard.kt`, `AndroidLyricsShareSheet.kt` | `TrackActions.share` -> `UIActivityViewController` | Ported - title, artist and a playable link; the rendered card image is not drawn |
| `ReorderPlaylistPage.kt`, `BoundedQueueEdits.kt` | Queue edit mode, `moveInQueue` | Asserted - `queue-edit.png`, `queue.moved=true` |
| `QueueActionNotice.kt` | Queue sheet header | Ported |

## Playback

| Upstream | Port | State |
| --- | --- | --- |
| `QueueCoordinator.kt`, `QueueShuffle.kt` | `PlayerService` queue, shuffle, move, remove | Asserted - `queue.afterAdd/afterRemove/playNext/moved` |
| `Autoplay.kt`, `smart/*` | `extendWithAutoplay`, `RadioService.mix` | Asserted - `autoplay.started=true`, `autoplay.tracks>=5` |
| `QueueHistory.kt` | `PlaybackHistoryStore` | Asserted - `history.count/top/limit`, relaunch `verify.history` |
| `SleepTimer.kt` | `BitChord.Misc.SleepTimerMinutes` + timer | Ported |
| Playback rate | `BitChord.Audio.PlaybackRate`, `AudioEngine` | Ported |
| `CrossfadeController`, `EqualizerProcessor`, `LoudnessProcessor`, `SpatialAudioProcessor`, `TransitionFilterProcessor` | Disabled rows | iOS 12 block - no per-sample tap or second player on `AVPlayer` |
| `audio/bitperfect`, `AudioOutput`, `DacVolumeHud`, `AudioRouting` | Disabled rows | iOS 12 block - no exclusive-mode or route selection API |
| `PlaybackFallback`, `QualityUpgrade`, `StreamChoice` | `AudioEngine`, `JioSaavnService`, download quality | Asserted - quality and addon fallback proofs |
| `MusicOnlyPlayback.kt` | `LocalMusicStore` 30 s filter | Ported |
| `PartySync.kt` | Absent | Account/credential - party server |
| `MusicLink.kt`, `PlayerDeepLink.kt` | Absent | Remaining (see below) |

## Downloads and offline

| Upstream | Port | State |
| --- | --- | --- |
| `DownloadService.kt`, `DownloadStore.kt`, `Downloads.kt` | `DownloadStore`, `DownloadsViewController` | Asserted - `downloads.png`, progress, menus, delete |
| Quality, Wi-Fi-only, cap | `SettingsStore`, `DownloadStore` | Asserted - `quality.*`, `wifi.blocked`, `cap.*` |
| Background transfers | background `URLSession`, `AppDelegate` | Asserted - resumed and force-quit reports |
| `PlaylistSync.kt` | `PlaylistSync`, `LibraryStore` | Asserted - `sync.tracks=100`, relaunch read-back |
| `OfflineDash.kt`, `OfflineHls.kt`, taggers | complete `.m4a` downloads | Ported differently - no remuxing, files arrive tagged |
| Addon lossless | `AddonService` | Asserted - 1411 kbps vs 320 kbps |

## Lyrics

| Upstream | Port | State |
| --- | --- | --- |
| `data/lyrics` providers (lrc.red, LyricsPlus, LRCLIB) | `LyricsService`, same default order | Asserted - `lyrics.liveLines` |
| Enhanced-LRC syllable karaoke | `taggedLine`, `KaraokeLyricView` | Asserted - `lyrics.syllables=3`, `lyrics.revealAdvance=true`, `lyrics-karaoke.png` |
| `LyricsSourcesDialog.kt` | Source name in the lyrics header | Ported |
| `TranslationLanguageDialog.kt` | Absent | iOS 12 block - no translation API before iOS 17.4 |

## Settings

All 73 upstream keys, 82 rows. Wired: playback speed, sleep timer, download
quality, storage limit, Wi-Fi-only, autoplay, show queue history, addon URL,
cache limit, storage used, local-music filter. Disabled rows state what is
missing: DSP, DAC, accounts, scrobbling, Spotify, Cast, Discord.

## Remaining differences (iOS permits them; not built in this pass)

Named rather than hidden:

| Item | Why it is not here | What exists instead |
| --- | --- | --- |
| SMB source (`data/smb`) | Needs its own protocol client; WebDAV and Jellyfin were the two built in this pass | WebDAV and Jellyfin browsers plus the addon stream and local locker |
| Universal links (`applinks:`) | Associated-domains entitlement and iOS 13-era handling | The `bitchord://` scheme is the iOS 12 substitute; SpringBoard confirms it before opening |
| Listen Together, Spotify import, scrobbling, Discord, Cast | Accounts, OAuth clients or servers this build does not ship | Disabled rows naming the missing piece |

## What CI measured, and what it did not

Measured in the simulator (`shots-v2/download-report.txt` and the background
reports), with the run above:

- Song menu: `menu.items=Play next|Add to queue|Add to playlist|Like|Go to
  artist|Delete download|Start radio|Share|Song info`, every row asserted;
  `menu.playlistGrew=true` after adding into a new playlist.
- Queue: `queue.before=2`, `afterAdd=3`, `afterRemove=2`, `playNext=true`,
  `afterMove=3`, `moved=true`.
- History screen: `historyPage.rows=4`, `afterClear=0`, `restored=1`; Replay:
  `replay.entries=6`, `replay.plays=6`.
- Song info: `info.rows=7`, `info.title=Blinding Lights`, `info.source=Downloaded`.
- Autoplay: `autoplay.started=true`, `autoplay.tracks=51` from a one-song queue.
- A force-quit relaunch reads back `verify.localTracks=1` and
  `verify.history=2` with `verify.historyTop=Blinding Lights`, and
  `verify.onboardingCompleted=true`, `verify.onboardingPresented=false`.
- Onboarding: `onboarding-report.txt` has `shown=true`, the four step titles,
  `completed=true`, `dismissed=true`; `onboarding.rerun=true` from the Settings
  row; the 320x568 run reports `onboarding.window=320x568` with
  `primaryVisible=true` on all four steps.
- Deep links: `route=track ... screen=NowPlaying`, `album ... Album`, `artist ...
  Artist`, `playlist ... Playlist`, `radio ... Radio`, `home ... Home`, every
  line `cold=1`; `deeplink-prompt.png` shows SpringBoard offering to open the
  registered scheme.
- WebDAV: `webdav.listed=true`, `root=Music|readme.txt`,
  `folder=Nested|track.m4a`, `hasTrack=true`, `playing=true`,
  `title=track.m4a`, `isPlaying=true`, and `authError=Wrong username or
  password.` for the wrong-password request.
- Jellyfin: `listed=true`, `libraries=Music`, `folder=true` with
  `Album One|Loose Track.m4a`, `album=true` with `track.m4a`, `playing=true`,
  `title=track.m4a`, `isPlaying=true`; `expiredError=Your Jellyfin session
  expired. Sign in again.`, `authError=Wrong username or password.`, and
  `unreachable=Couldn't reach 127.0.0.1 (-1004).` The 320x568 launch reports
  `jellyfin.window=320x568`, `items=Music` and `tableVisible=true`; the fixture
  logged the real `AuthenticateByName` POST and the ranged `Audio/.../stream`
  GET.

Also measured in the same run: relaunch, offline playback, deletion, two quality renditions measured
with `afinfo`, Wi-Fi HELD, storage cap, background resumed and force-quit, addon
versus standard, 100-song playlist sync read back by a fresh process, local
locker, queue history, History screen, Replay, song menu and add-to-playlist,
queue edits and reorder, autoplay past the queue end, radio and its failure,
artist page, moods, song info, karaoke syllables, downloaded badges, cache
freeing a created megabyte, the first-run flow at full size and at 320x568, six
deep-link destinations from cold launches, a WebDAV listing/browse/stream with
its auth failure, the same browse/stream flow over Jellyfin's own API with its
three failure messages, and the packaged IPA's plist, scheme and architecture.

Not measured here: lock-screen controls, `SCNetworkReachability`, the real
background transfer daemon, audio routing and DAC behaviour, and a real addon
server over a network - all physical-device checks. The metered-link decision
and the download pacing are the real code paths with their inputs injected.
