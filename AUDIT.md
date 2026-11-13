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

Latest full run: commit `2b7fd9e`, all three jobs green (`43380104251`). Both
root IPAs are that build: 16,947,648 bytes, sha256 `e6493578...`, bundle
`com.bitchord.ios12v2` 2.0.0, `MinimumOSVersion 12.0`, `UIDeviceFamily [1,2]`,
and a thin `arm64` executable (`cputype 0x100000c`) - verified inside CI by
unzipping the packaged IPA and again on the committed file, with both copies
byte-identical.

## Shell and navigation

| Upstream | Port | State |
| --- | --- | --- |
| `floatingtabbar/FloatingTabBar.kt`, `MainViewModel.kt` | `RootViewController`, `CapsuleTabBar` | Asserted - `home/explore/library/search` screenshots |
| `components/MiniPlayer.kt` | `MiniPlayerBar` | Asserted - in every captured screen |
| `ui/player/AndroidPlayerHost.kt` | `NowPlayingViewController` | Asserted - `lyrics.png`, `lyrics-karaoke.png` |
| `components/IosSwitch.kt`, `IosMenu.kt` | UIKit switches, action sheets | Ported - iOS 12 has no `UIMenu` |
| `FrostedTopBar`, `GlassNavBar`, `LiquidGlass` | `MeshGradientView`, `Theme`, native bars | Ported as an approximation |

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
| `SourcesScreen.kt`, `data/sources` | `AddonService` manifest/stream | Ported - asserted lossless tier; WebDAV/SMB/Jellyfin not shipped (see Remaining) |
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
| Deep links / intent filters (`MusicLink.kt`, `PlayerDeepLink.kt`) | Needs a registered URL scheme and link resolution | Links shared from the menu open in the browser |
| WebDAV / SMB / Jellyfin source modules (`data/webdav`, `data/smb`, `data/remote`) | Each needs its own client, auth and browser UI | Addon stream contract plus the local locker |
| Onboarding screen (`OnboardingScreen.kt`) | The first-run explanation is not drawn | The sign-in banner on Home explains the guest state |
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
  `verify.history=2` with `verify.historyTop=Blinding Lights`.

Also measured in the same run: relaunch, offline playback, deletion, two quality renditions measured
with `afinfo`, Wi-Fi HELD, storage cap, background resumed and force-quit, addon
versus standard, 100-song playlist sync read back by a fresh process, local
locker, queue history, History screen, Replay, song menu and add-to-playlist,
queue edits and reorder, autoplay past the queue end, radio and its failure,
artist page, moods, song info, karaoke syllables, downloaded badges, cache
freeing a created megabyte, and the packaged IPA's plist and architecture.

Not measured here: lock-screen controls, `SCNetworkReachability`, the real
background transfer daemon, audio routing and DAC behaviour, and a real addon
server over a network - all physical-device checks. The metered-link decision
and the download pacing are the real code paths with their inputs injected.
