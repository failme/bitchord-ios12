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

Latest full run: commit `eb13fcc` (`43666892167`, attempt 1). The build,
simulator and screenshots jobs are green, including the simulated Google
handoff, relaunch, sign-out and signed-out relaunch. It captured 125 PNGs: 59
settled screenshots, 46 origin/mid/settled motion frames, 8 screens at
320x568 and 12 Google-account handoff/restore/sign-out frames, plus their
reports, under `_ci_tmp/run-eb13/extract/shots/`. Both root IPAs are that
build: 17,369,394 bytes, sha256
`0fa3c7b1712af19aecd6da77915294824273135cced2116ae18ffe57efa3062a`, bundle
`com.bitchord.ios12v2` 2.0.0, `MinimumOSVersion 12.0`, `UIDeviceFamily [1,2]`,
a thin `arm64` executable (Mach-O) and a registered `bitchord` URL scheme -
verified on the packaged file, with all three copies byte-identical.

## UI parity pass

The screens were measured against the running Android app in the emulator
(1080x2400, mapped to 402x874) rather than compared by eye alone. Header
heights, banner and card origins, list rows, settings rows, player transport
and footer were moved onto the reference bounds; `home.png`, `library.png`, `explore.png`, `search.png`,
`settings.png`, `downloads-empty.png`, `local-music.png` and `now-playing.png`
in `_ci_tmp/run-eb13/extract/shots/` are the resulting captures. Home's account button is 36pt, the Top Picks card is
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

The white page after a successful Google login is treated as what it is: the
YouTube Music shell failing to paint, not a failed Google sign-in. The login
watches the cookie store while navigation reaches any YouTube host, captures a
complete session as soon as an API SID exists, and — if the shell stays blank —
fetches `music.youtube.com` itself and reads the same `LOGGED_IN`,
`SESSION_INDEX`, `DATASYNC_ID`, `DELEGATED_SESSION_ID` and `VISITOR_DATA`
values from `ytcfg`. The captured cookie carries the Google identity cookies
only when the YouTube jar has no API SID of its own. The manual **Done** path
remains as a fallback.

The account surface follows the Android app rather than inventing an OAuth
client. **Sign in with Google** opens `accounts.google.com/ServiceLogin` in a
`WKWebView` with a Safari user agent, continues to `music.youtube.com`, and
captures the resulting YouTube/Google cookies. The app validates an API SID
(`SAPISID`, `__Secure-3PAPISID` or `__Secure-1PAPISID`), stores the session,
and signs InnerTube browsing requests with `SAPISIDHASH` plus the captured auth
user. Playback stays on the anonymous clients. The banner, all five header
avatars, Settings' **Account & integrations** row and History's sign-in prompt
share one `GoogleAccountStore`.

`-BCSignInStage` now proves the handoff without a Google account. It seeds the
web view's own cookie store with a YouTube `SAPISID` and visibility marker plus
a Google-only marker, loads a Google-origin page that redirects to
`music.youtube.com`, and runs the real sign-in controller, cookie capture and
`ytcfg`/document parsers:

- Rendered shell: `handoff-report-rendered.txt` has
  `probe.shellOrigin=https://music.youtube.com`, `probe.ytcfg=true`,
  `networkFallback=false`, `document.youtubeCookie=true`,
  `document.googleCookie=false`, `signedIn=true`, `homeVisible=true`.
- Blank shell: `handoff-report-blank.txt` has `shellBlank=true`, `ytcfg=false`,
  `networkFallback=true`, and `networkCookie=true`, proving the fallback
  request carried the captured signing cookie. It also reaches
  `signedIn=true`, `homeVisible=true`.
- Both paths write `dataSync=fixture-account` (the normalized `page||account`
  value), dismiss the browser, and capture `signed-in-home-rendered.png` and
  `signed-in-home-blank.png`.
- The next launch restores the same session, headers and visible Home
  (`restore.signedIn=true`, `restore.homeVisible=true`). Sign-out clears the
  session and shows the account page's **Sign in with Google** state, the Home
  prompt returns, and a further launch stays signed out.

The unsigned simulator has no keychain entitlement (`SecItemAdd` returns
`-34018`), so the harness records `persistence=simulator-fallback` and keeps
the session in a simulator-only durable fallback. A signed device still uses
the keychain alone; that device path and a real Google password/2FA login
remain device checks.

## Motion evidence

A separate `-BCMotion` launch drives every transition through the real control
(`MotionHarness`). It writes an origin frame, at least one mid frame and the
settled frame, and records presentation-layer values in
`_ci_tmp/run-eb13/extract/shots/motion-report.txt`. CI fails if any flag is
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
| `MusicLink.kt`, `PlayerDeepLink.kt`, intent filters | `DeepLink`, `DeepLinkRouter`, `CFBundleURLTypes` | Asserted - six `bitchord://` routes from `deeplinks.txt`, all `cold=1`; the shared parser also accepts YouTube watch/short/playlist/search URLs (`web-links-report.txt`). Universal-link association itself needs a controlled domain/AASA (blocked below) |

## Screens

| Upstream | Port | State |
| --- | --- | --- |
| `sharedUi/HomeScreen.kt` | `HomeViewController`, `ShelfRowView`, `TopPicksShelf`, `SignInBannerView` | Asserted - `home.png`; signed in, Top Picks and the collection shelf read `FEmusic_home` |
| `sharedUi/ExploreScreen.kt` | `ExploreViewController`, `MoodTileView` | Asserted - `moods.png`, `moods.tracks=20` |
| `sharedUi/SearchScreen.kt` | `SearchViewController`, `InnerTube`, `CatalogueSearch` | Asserted - `search.png` |
| `sharedUi/LibraryScreen.kt`, `LibraryPhoneParts.kt` | `LibraryViewController`, `LibraryStore`, `SavedLibraryViewController` | Asserted - `library.png`, `library-synced.png`; signed in, rows open Liked Music, History and the saved playlist/album/artist feeds |
| `ui/screens/HistoryScreen.kt` | `HistoryViewController` | Asserted - `history.png`, `history-empty.png`, `historyPage.*` |
| `AccountAndScrobblingScreen.kt` | `AccountViewController`, `GoogleAccountStore`, `GoogleSignInViewController`, `ScrobbleService` | Asserted signed out - `small-account.png`, `auth.accountSheet=true`; the deterministic handoff asserts a signed-in Home, identity, restore and sign-out. Settings configures Last.fm/ListenBrainz; a real Google password/2FA login still needs the device |
| `ui/screens/LocalFolder.kt` | `LocalMusicViewController`, `LocalMusicStore` | Asserted - `local-music.png`, `local-songs.png`, `local.playing=true` |
| `ui/screens/DetailScreen.kt` | `CollectionViewController`, `ArtistPage` | Asserted - `artist.png`, `artist.loaded=5` |
| `ui/replay/*` | `ReplayViewController` | Asserted - `replay.png`, `replay.entries`, `replay.plays` |
| `SettingsSheet.kt`, `SettingsView` | `SettingsViewController`, `SettingsStore` | Asserted - `settings*.png`; 82 rows, all 73 keys |
| `ui/screens/EqualizerScreen.kt` | Disabled row with reason | Blocked - the native path is `AVPlayer`; an `AVAudioEngine` graph is required for a 10-band tap |
| `ListenTogetherScreen.kt`, `PartySync.kt` | Disabled row | Blocked - needs a deployed party server and shared account |
| `DiscordScreen.kt`, `data/discord` | Disabled row | Blocked - Discord RPC's local IPC transport is Android-only |
| `SpotifyLibraryScreen.kt`, `SpotifyCanvasAuthScreen.kt` | `SpotifyImporter`, Library's **Import Spotify** card; sync by public YT Music link | Public playlist import is ported (embed page, matching, 100-row continuation). Authenticated Spotify library and Canvas need an OAuth client this build does not ship |
| `SourcesScreen.kt`, `data/sources`, `data/webdav`, `data/remote` | `AddonService`, `WebDAVClient`, `WebDAVStore`, `JellyfinClient`, `JellyfinStore`, `JellyfinViewController`, `SourcesViewController` | Asserted - WebDAV: `webdav-tree.png`, `webdav-playing.png`, `webdav-error.png`; PROPFIND list, folder browse, streamed `track.m4a`, bad-password message. Jellyfin: native API sign-in, library/folder/album browse, streamed `track.m4a` with `isPlaying=true`, expired/wrong-password/unreachable messages, `jellyfin-tree/playing/error/small.png`. SMB is blocked on the missing protocol client; see **Blocked surfaces** |
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
| `MusicLink.kt`, `PlayerDeepLink.kt` | `DeepLink`, `DeepLinkRouter` | Ported - six `bitchord://` routes asserted in `deeplinks.txt`; YouTube web forms asserted through the same parser. The OS-level universal-link association remains blocked by domain ownership/AASA |

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

All 73 upstream keys are present. Wired: playback speed, sleep timer,
download quality, storage limit, Wi-Fi-only, autoplay, show queue history,
addon URL, cache limit, storage used, local-music filter, the Google account
row, Last.fm (toggle, now-playing, primary artist, username, API key, secret,
session key, endpoint) and ListenBrainz (toggle, token, primary artist).

The settings that used to be rows without a consequence now drive their
surfaces: **Theme** persists System/Light/Dark and rebuilds the root so UIKit
views resolve the new palette (the light status bar is set from the same
value); **Font** is read by every `Theme.font` call; **App icon** switches the
shipped `AppIcon-Monochrome` asset through `setAlternateIconName`; **Lyrics →
Show full lyrics** switches between the lyric column and the one line being
sung; **Blur unfocused lines** changes the unsung alpha; **Save lyrics
offline** stores and reuses provider results; **Lyrics source** selects
Automatic (lrc.red → LyricsPlus → Unison → LRCLIB) or LRCLIB alone; **Liquid
glass**, **Legacy mesh gradient** and **Reduce dynamic blur** change the real
player backdrop; **Keep downloads updated** refreshes remote playlists at
launch; **JioSaavn** switches the resolver and the search catalogue;
**Track length tolerance** changes artist/title corroboration; **Stats for
nerds** shows the live engine summary; **Swipe to play next** adds the real
swipe action; **On Wi-Fi/On mobile data** select the playback bitrate ceiling.

Rows that remain disabled, and the specific block behind each, are listed
under **Blocked surfaces** below; none is a silent “not ported” placeholder.

## Blocked surfaces

Each row names the concrete reason and the thing that would unblock it. These
are the only surfaces not implemented; buildable discrepancies found by the
folder pass were implemented rather than listed here.

| Surface | Concrete block | What would unblock it |
| --- | --- | --- |
| SMB source (`data/smb`) | iOS has no SMB client API. iOS 12 also has no Network.framework SMB transport; the only SMB2 framework in the reference tree is a headerless arm64-only binary that cannot be linked into a simulator build. | Vendor an SMB2/SMB3 library with an iOS 12 simulator slice and a public header, or a server-side bridge. |
| Universal-link association (`applinks:`) | An associated-domain entitlement can only be issued for a domain this project controls, and Apple must serve `apple-app-site-association` from it. The app cannot claim `youtube.com` or `music.youtube.com`. | A controlled domain with an AASA file and the `associated-domains` entitlement. The parser/router already accepts the same URLs, as `web-links-report.txt` asserts. |
| Listen Together / party / presence | The client protocol needs a deployed party server and a shared signed-in identity; no such server or credentials are part of this build. | A hosted party backend and account identity for every participant. |
| Authenticated Spotify library and Canvas | Spotify library sync and Canvas need an OAuth client/secret and a signed-in Spotify account; neither is shipped, and Canvas media is not in the public embed page. | A Spotify developer app with the library/Canvas scopes and a test account. |
| Discord presence | Discord RPC uses local IPC (a Unix socket to the desktop client) on Android; iOS has no equivalent local Discord transport and Discord has no iOS RPC endpoint used here. | A supported Discord iOS SDK/endpoint. |
| Google Cast | No Google Cast SDK or receiver application ID is linked; Cast discovery also needs the local-network multicast entitlement. | Add the Google Cast iOS SDK, a receiver ID and the multicast entitlement. |
| Crossfade, 10-band EQ, loudness, skip-silence, Automix, spatial audio | The native path is `AVPlayer` over progressive files; those processors need per-sample access and two overlapping players, which the current pipeline does not expose. (`AVAudioEngine`/`MTAudioProcessingTap` would be a new playback engine, not a setting.) | Replace the native engine with an `AVAudioEngine` graph and implement the processors. |
| Bit-perfect, USB-DAC preference, output routing, disable-on-speaker | iOS public audio APIs expose no exclusive/bit-perfect mode, no DAC selection and no route-by-route override for this player. | A private/entitled audio route API or a platform change; not shippable on iOS 12. |
| Translation / bilingual lyrics | iOS 12 has no on-device translation API (`Translation` is iOS 17.4+), and the project has no third-party translation key. | A translation service key and a server-side proxy. |
| Animated cover / Spotify Canvas | The catalogues used here return static artwork; Canvas is authenticated Spotify media (see above) and InnerTube's animated artwork is not exposed by the browsing response. | An animated-artwork provider and, for Canvas, Spotify auth. |
| Remote InnerTube rating/save/rename | Those endpoints require the signed-in account and write/feedback tokens; the app deliberately keeps browsing anonymous and only creates remote playlists with the captured session. (The YouTube search list does have a real **Load more** control and advances its continuation token; the JioSaavn catalogue is a single 30-row page.) | A signed-in account with write scopes. |
| `ui/festive`, `ui/performance` | Festive is a dated seasonal illustration/composition with no corresponding iOS asset; performance exposes Android per-app refresh-rate controls, which iOS does not provide to apps. | The seasonal artwork/spec and an iOS-supported frame-rate policy. |
| Widget, Wear OS, TV apps | These are separate Android application surfaces, not screens inside the phone app. | Separate iOS extensions/apps, outside this target. |

## Upstream folder coverage

A folder-by-folder pass over `_reference/BitChord`, not just the screens. The
port is a single iOS app; Android-only surfaces are named as such rather than
silently left out.

| Upstream folder | Contains | iOS port and remaining gap |
| --- | --- | --- |
| `app/.../auth` | Google web login, account sessions, Spotify/Discord sign-in | Google web login, session restore/sign-out, account identity and channel switching are ported and handoff-tested (keychain on device, simulator fallback in unsigned CI). Spotify uses public embed import without OAuth, so its authenticated OAuth sign-in is blocked on client credentials; Discord's local IPC transport has no iOS equivalent. |
| `app/.../data/innertube` | Search, browse, home, library, account, write actions | Search, browse, collection pages, home feed, liked music, history, saved playlists/albums/artists and channel enumeration are ported. YouTube search has a real **Load more** driven by the response continuation token. Remote playlist creation is ported; rating, save, feedback tokens and remote rename need a signed-in write account and remain blocked. |
| `app/.../data/jiosaavn`, `data/sources`, `data/webdav`, `data/remote` | Catalogue, addon, WebDAV, Jellyfin | Ported: JioSaavn search/streams, addon tiers, WebDAV and Jellyfin browsers. SMB has no client. |
| `app/.../data/scrobbling` | Last.fm, Libre.fm, ListenBrainz | Ported: now-playing, half-track scrobble with the four-minute cap, primary-artist option, configurable Last.fm endpoint. Last.fm needs the listener's own API key/secret/session key; ListenBrainz needs only a token. |
| `app/.../data/spotify` | Public embed import and authenticated library | Public playlist import is ported through the embed page, including its 100-row token continuation and YouTube matching. Authenticated Spotify library/canvas is blocked on a Spotify OAuth app and account; see **Blocked surfaces**. |
| `app/.../data/lyrics`, `data/stats` | Lyrics providers, Replay | Ported with live providers, karaoke and Replay. |
| `app/.../data/listentogether`, `data/presence`, `backend/` | Party protocol, presence, server | Blocked: needs a deployed party server and a shared signed-in identity on every device. |
| `app/.../data/canvas`, `data/discord` | Canvas clips, Discord RPC | Blocked: Canvas needs Spotify's authenticated media API/account; Discord RPC is local Android IPC. |
| `app/.../download` | Queue, background transfers, offline files, playlist sync | Ported with background `URLSession`, quality/Wi-Fi/cap rules and synced playlists. |
| `app/.../playback` | Queue, radio, crossfade/DSP, Cast, DSD, loop mix, smart transitions | Queue, autoplay/radio, sleep timer and speed are ported. Crossfade/EQ/loudness/skip-silence/Automix need an `AVAudioEngine` graph rather than `AVPlayer`; bit-perfect/USB-DAC/routing need APIs iOS does not expose; Cast needs the Cast SDK and a receiver ID; DSD has no public decoder/route. These are the block rows above, not hidden omissions. |
| `app/.../ui/screens`, `ui/player`, `ui/components`, `ui/replay`, `ui/onboarding`, `ui/theme` | The Android UI | Ported and asserted by the screen/motion runs, including Theme (System/Light/Dark), Font, the alternate monochrome icon, liquid-glass/mesh backdrop options and the lyric presentation settings. `ui/festive` is a dated seasonal composition with no iOS asset; `ui/performance` needs Android-only per-app refresh-rate control. |
| `app/.../widget`, `wear`, `wearos/`, `tv/` | Home-screen widget, watch and TV apps | Android-only surfaces; not part of the iPhone app. |
| `shared/src/commonMain` | Models, settings, party, smart playback | Models/settings are mirrored. Party and smart/Automix models are not used because their engines are absent. |
| `shared/src/jvmSharedMain` | InnerTube, Spotify, downloads on JVM | The API shapes informed the iOS clients; JVM-only HTTP/storage code is not shipped. |
| `sharedUi` | Compose screens and resources | Served as the visual reference; UIKit replacements are listed in the screen matrix. |
| `web/` | Browser client, extension, docs | A separate web product; not part of the iOS app. |
| `native/` | FFmpeg decoder, analyzer, loop-mix native code | Not linked: the iOS player uses WebKit/AVPlayer rather than a native media3/FFmpeg pipeline. Linking FFmpeg would unblock DSD/loop-mix but also require a new audio-graph/engine and licensing review. |

## What CI measured, and what it did not

Measured in the simulator (`_ci_tmp/run-eb13/extract/shots/download-report.txt`
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

Not measured here: a real Google password/2FA login (the deterministic handoff
uses a seeded session), the signed-device keychain path, lock-screen controls,
`SCNetworkReachability`, the real background transfer daemon, audio routing and
DAC behaviour, and a real addon server over a network - all physical-device
checks. The web view, cookie extraction, `ytcfg` and document parsing,
`SAPISIDHASH` headers, restore, sign-out and the signed-out boundary are now
exercised in the simulator.
