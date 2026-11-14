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

Latest full run: commit `60d569d` (`43649376117`). The build, simulator and
screenshots jobs are green; the screenshots job was rerun once after its
background-transfer fixture found no fresh transfer, and the rerun passed every
screen, motion, geometry, compact-layout and background assertion. It captured
59 settled screenshots, 46 origin/mid/settled motion frames and 8 screens at
320x568, plus their reports, in `_ci_tmp/run-60d569d/green/shots/`. Both root
IPAs are that build: 17,244,148 bytes, sha256
`7cfb58587243fbc18f1bf896212ad37ce5d53039a875ed9e4e788391c23e6c3a`, bundle
`com.bitchord.ios12v2` 2.0.0, `MinimumOSVersion 12.0`, `UIDeviceFamily [1,2]`,
a thin `arm64` executable (Mach-O) and a registered `bitchord` URL scheme -
verified on the committed file, with both copies byte-identical.

## UI parity pass

The screens were measured against the running Android app in the emulator
(1080x2400, mapped to 402x874) rather than compared by eye alone. Header
heights, banner and card origins, list rows, settings rows, player transport
and footer were moved onto the reference bounds; `home.png`, `library.png`, `explore.png`, `search.png`,
`settings.png`, `downloads-empty.png`, `local-music.png` and `now-playing.png`
in `_ci_tmp/run-60d569d/green/shots/` are the resulting captures. Home's account button is 36pt, the Top Picks card is
240x320pt (upstream's `min(width * 0.60, 280)` at 402pt by its 0.75 aspect),
and the album shelf follows the card row at 16pt rather than the feed's 28pt
rhythm. Explore keeps the 1.72:1 mood card and 18pt radius from
`MOOD_CARD_ASPECT` / `MOOD_CARD_SHAPE`. The song menu now names **Open album**
and **Open artist**, with the album sleeve glyph; the Song Info dialog waits
for its live payload (or its five-second cap) before the screenshot is taken.
Those measurements only held at the 402pt reference width. On a 320x568
launch the Explore grid kept a fixed 104pt row, which turned the 1.72:1 sleeve
into a squat 0.58 tile, and Now Playing's fixed artwork and footer stack pushed
the transport into the volume and output rows. Explore now derives the row
height from the measured width (138x80.3 at 320), and Now Playing reads the
actual view height before choosing compact metrics: 0.47 artwork, 18/16pt
title/artist, a 64pt transport, a tighter footer and the output label above the
safe-area edge. The compact report asserts the tile ratio and checks that the
transport, volume and footer do not overlap.

The Now Playing and lyrics surfaces were then rebuilt from the
Compose constants: 20pt medium artist over a 20pt semibold title, the 20dp
artwork-to-title gap, the 54dp collapsed header, a 7pt/12pt thumbless scrubber,
74dp transport glyphs at upstream's centres, and 34sp/41sp extra-bold lyrics
(30sp/38sp unsynced) at the 0.45 unsung alpha inside 30pt gutters. The backdrop
is the sleeve itself, pre-blurred with a saturation lift and drawn under
`FullArtworkScrim`; the old dark live blur that flattened it has been removed.
The panel's quote-mark, dotted queue and rounded transport vectors come from
`BitChordIcons`/`ic_player_*`, not generic placeholders. Motion is ported as well: the tab pill springs while the pages
crossfade, the mini player expands and collapses, Now Playing rises and slides
away with the play/pause glyph crossfading, artwork fades between tracks, cards
scale on press, the stats carousel snaps and onboarding steps fade.

## Google account

The account surface follows the Android app rather than inventing an OAuth
client. **Sign in with Google** opens `accounts.google.com/ServiceLogin` in a
`WKWebView` with a Safari user agent, continues to `music.youtube.com`, and
captures the resulting YouTube/Google cookies. The app validates an API SID
(`SAPISID`, `__Secure-3PAPISID` or `__Secure-1PAPISID`), stores the session in
the keychain, and signs InnerTube browsing requests with `SAPISIDHASH` plus the
captured auth user. Playback stays on the anonymous clients. The banner, all
five header avatars, Settings' **Account & integrations** row and History's
sign-in prompt share one `GoogleAccountStore`; the account page can sign out
and clears the browser cookies. No client ID or secret is committed, and CI
only exercises the signed-out state, so the first real login still needs the
listener to enter their own Google password/2FA on the device.

## Motion evidence

A separate `-BCMotion` launch drives every transition through the real control
(`MotionHarness`). It writes an origin frame, at least one mid frame and the
settled frame, and records presentation-layer values in
`_ci_tmp/run-60d569d/green/shots/motion-report.txt`. CI fails if any flag is
false or any of the 46
frames is missing, so a transition that snapped cannot pass as animated. The
tab pill's 0.42s spring was checked against an emulator screen recording of the
Android bar, which settles in roughly 0.4s; the remaining durations follow the
same Android motion vocabulary at 60fps.

| Transition | Timing | Frames | Mid-state captured |
| --- | --- | --- | --- |
| Tab pill slide | 0.42s spring, damping 0.82 | `motion-tab-0..3` | pill x 4.0 -> 34.5 -> 93.1 -> 94.7pt |
| Tab page crossfade | 0.22s ease-out | same frames | outgoing page alpha 1.00 -> 0.66 -> 1.00; incoming 0.34 at the same mid-frame |
| Mini-player expand | 0.30s spring, damping 0.90 | `motion-mini-0..3` | bar height 0 -> 25.3 -> 55.1 -> 56pt, alpha 0 -> 0.45 -> 0.98 -> 1; clipped while growing |
| Mini-player to Now Playing | standard modal + 0.46s spring, damping 0.86, 0.02s delay | `motion-player-open-0..5`, `-4a`, `-4b` | `open-2` shows the panel partway over Home; cover scale 0.941 -> 0.969 -> 0.991 -> 1.000 |
| Now Playing dismiss | 0.26s ease-in | `motion-close-0..3` | panel alpha 1.00 -> 0.94 -> 0.54 -> 0; translation 0 -> 52.4 -> 405.9 -> 874pt |
| Play/pause glyph | 0.18s cross-dissolve | `motion-play-0..3` | `play-1`/`play-2` capture the blend, and CI asserts playback state changed |
| Artwork change | 0.25s cover cross-dissolve (0.40s backdrop) | `motion-artwork-0..3` | track ID changes between frame 0 and frame 1; frame 1/2 catch the cover blend |
| Card press scale | 0.16s down, 0.24s spring back (damping 0.70) | `motion-card-0..4`, `motion-tile-0..4` | presentation scale sampled between 0.90 and 0.99 while held |
| Stats paging snap | 0.30s paging scroll | `motion-stats-0..3` | drag target 200pt snapped to 312pt; offset is partial at frame 1/2 and exactly 312 at frame 3 |
| Onboarding step fade | 0.22s ease-out | `motion-onboarding-0..3` | title/body/features alpha partway between 0 and 1 at frame 1/2 |

The live-frame report also sets the two residual geometries: Home's first
artwork is at y320 against the reference y320 (height-mapped), and Explore's
first tile is at y167 against the reference y167.5 (below the rasterization
tolerance). CI now fails explicitly when either falls outside a four-point
window, rather than leaving a failed `test` as the last command in a chain.
`home.png` and `explore.png` carry the same measurements in the settled set.

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
| `AccountAndScrobblingScreen.kt` | `AccountViewController`, `GoogleAccountStore`, `GoogleSignInViewController` | Asserted signed out - `small-account.png`, `auth.accountSheet=true`. A real Google login needs the listener's password/2FA on the device |
| `ui/screens/LocalFolder.kt` | `LocalMusicViewController`, `LocalMusicStore` | Asserted - `local-music.png`, `local-songs.png`, `local.playing=true` |
| `ui/screens/DetailScreen.kt` | `CollectionViewController`, `ArtistPage` | Asserted - `artist.png`, `artist.loaded=5` |
| `ui/replay/*` | `ReplayViewController` | Asserted - `replay.png`, `replay.entries`, `replay.plays` |
| `SettingsSheet.kt`, `SettingsView` | `SettingsViewController`, `SettingsStore` | Asserted - `settings*.png`; 82 rows, all 73 keys |
| `ui/screens/EqualizerScreen.kt` | Disabled row with reason | iOS 12 block - `AVPlayer` has no EQ tap |
| `ListenTogetherScreen.kt`, `PartySync.kt` | Absent | Account/credential - needs a party server |
| `DiscordScreen.kt`, `data/discord` | Disabled row | Android-only - Discord RPC uses local Android IPC |
| `SpotifyLibraryScreen.kt`, `SpotifyCanvasAuthScreen.kt` | Disabled row; sync by public YT Music link | Account/credential - Spotify OAuth client |
| `SourcesScreen.kt`, `data/sources`, `data/webdav`, `data/remote` | `AddonService`, `WebDAVClient`, `WebDAVStore`, `JellyfinClient`, `JellyfinStore`, `JellyfinViewController`, `SourcesViewController` | Asserted - WebDAV: `webdav-tree.png`, `webdav-playing.png`, `webdav-error.png`; PROPFIND list, folder browse, streamed `track.m4a`, bad-password message. Jellyfin: native API sign-in, library/folder/album browse, streamed `track.m4a` with `isPlaying=true`, expired/wrong-password/unreachable messages, `jellyfin-tree/playing/error/small.png`. SMB not shipped (see Remaining) |
| `WearOsSettings.kt`, `ui/widget`, `wearos/`, `tv/` | Absent | Android-only - separate apps/surfaces |

## Song menu and library actions

| Upstream | Port | State |
| --- | --- | --- |
| `SongActionsMenu.kt` | `TrackActions` | Asserted - `song-actions.png`; quick Like/Share, add to playlist, radio, play next, queue, saved-to-downloads, open album, open artist, info |
| `PlaylistPickerSheet.kt` | `PlaylistPicker`, `LibraryStore` | Asserted - `add-to-playlist.png`, `menu.playlistGrew=true` |
| `SongInfoDialog.kt` | `SongInfoViewController` | Asserted - `song-info.png`, `info.rows=5` |
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
cache limit, storage used, local-music filter, and the Google account row.
Disabled rows state what is missing: DSP, DAC, Last.fm/ListenBrainz keys,
Spotify, Cast, Discord.

## Remaining differences (iOS permits them; not built in this pass)

Named rather than hidden:

| Item | Why it is not here | What exists instead |
| --- | --- | --- |
| SMB source (`data/smb`) | Needs its own protocol client; WebDAV and Jellyfin were the two built in this pass | WebDAV and Jellyfin browsers plus the addon stream and local locker |
| Universal links (`applinks:`) | Associated-domains entitlement and iOS 13-era handling | The `bitchord://` scheme is the iOS 12 substitute; SpringBoard confirms it before opening |
| Listen Together, Spotify import, scrobbling, Discord, Cast | Accounts, OAuth clients or servers this build does not ship | Disabled rows naming the missing piece |

## What CI measured, and what it did not

Measured in the simulator (`_ci_tmp/run-60d569d/green/shots/download-report.txt`
and the background reports), with the run above:

- Song menu: `menu.items=Play next|Add to queue|Add to playlist|Like|Open
  album|Open artist|Saved to downloads|Start radio|Share|Song info`, every
  row asserted; `menu.hasAlbum=true`, `menu.playlistGrew=true` after adding
  into a new playlist.
- Queue: `queue.before=2`, `afterAdd=3`, `afterRemove=2`, `playNext=true`,
  `afterMove=3`, `moved=true`.
- History screen: `historyPage.rows=4`, `afterClear=0`, `restored=1`; Replay:
  `replay.entries=6`, `replay.plays=6`.
- Song info: `info.rows=5`, `info.title=Blinding Lights`, `info.album=After
  Hours`; the four live counts remain em dashes when YouTube's watch page
  cannot be reached from the simulator.
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

Also measured: the 320x568 pass reports `small.window=320x568`,
`explore.ratioOk=true`, `player.noOverlap=true`, `player.outputFits=true`,
`auth.accountSheet=true`, `small.done=true`, and writes the seven tab/player/
account/settings captures. The account page is the signed-out state;
`auth.browserFlow=google-web-session` and `auth.hasCookie=false` show CI did
not inject or fabricate a session.

Not measured here: a real Google sign-in (CI has no Google account and cannot
type a password or 2FA code), lock-screen controls, `SCNetworkReachability`,
the real background transfer daemon, audio routing and DAC behaviour, and a
real addon server over a network - all physical-device checks. The web view,
cookie extraction, keychain write, SAPISIDHASH headers and account parsing are
compiled and exercised up to the signed-out boundary; the first real login and
profile fetch need the listener's device.
