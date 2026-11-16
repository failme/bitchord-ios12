# BitChord on iOS 12 — re-derived parity audit

This audit was rebuilt from the reference tree at
`_reference/BitChord` (`acf219a`), not from the previous audit's prose. It
walks the top-level folders, then every source folder and screen, then the
settings catalog, assets and motion surfaces. Each surface below is in exactly
one state:

- **Verified** — implemented in the iOS port and reproduced by a CI assertion
  (a report key, a real interaction, or a screenshot).
- **Deliberately equal** — a different implementation with the same user
  outcome, named explicitly rather than claimed as pixel-identical.
- **Blocked** — cannot be built for this target without a named platform,
  credential or infrastructure dependency, and the unblocker is stated.

The port is a native UIKit app for iOS 12, bundle `com.bitchord.ios12v2`
2.0.0, `MinimumOSVersion 12.0`, `UIDeviceFamily [1,2]`, arm64.

## Final evidence

Last complete v2 run: commit `798a28e` (`43779144080`, attempt 2). The `build`,
`simulator` and `screenshots` jobs are green. The screenshots artifact contains
**129 PNGs**: 60 settled screens (including `animated-cover.png` and the new
artist profile), 46 motion frames, 12 Google handoff/restore/sign-out frames, 3
light-palette screens and 8 screens at 320x568, plus their reports. The
packaged IPA from that run is **30,317,692 bytes**, sha256
`76187a3d7dcc321cafabc4dd134732acf4476d959c909a1447ff2cc0726f0517`,
bundle `com.bitchord.ios12v2` 2.0.0, `MinimumOSVersion 12.0`,
`UIDeviceFamily [1,2]`, a thin arm64 executable and a registered `bitchord`
URL scheme.

The first attempt failed only on the background-download index probe
(`background.indexed=false` after a simulated interruption); the retried job
passed with the same IPA. Earlier green runs after the Google fix:
`43679379002` (`5cd0428`).

## Top-level folder coverage

| Reference folder | What it contains | iOS outcome |
| --- | --- | --- |
| `app/src/main/java/com/music/bitchord/auth` | Google web login, account sessions, channel switching | **Verified** — `GoogleAccountStore`, `GoogleSignInViewController`, `-BCSignInStage`; keychain on device, deterministic simulator fallback |
| `app/.../data/innertube` | Search/browse/home/library/account, continuations, write actions | **Verified** — search, home, library, history, collection pages and real search continuation. Remote rating/save/feedback remain **Blocked** on signed-in write tokens |
| `app/.../data/jiosaavn` | Catalogue and streams | **Verified** — resolver and search catalogue, quality renditions |
| `app/.../data/sources`, `data/remote`, `data/webdav` | Addon, Jellyfin, WebDAV | **Verified** — addon tiers, WebDAV PROPFIND/stream, Jellyfin API/stream/errors |
| `app/.../data/smb` | SMB2 browser | **Blocked** — no SMB client API on iOS; needs a vendored SMB2/SMB3 client with an iOS 12 simulator slice |
| `app/.../data/scrobbling` | Last.fm, Libre.fm, ListenBrainz | **Verified** — now-playing, scrobble threshold, primary artist, token/secret settings |
| `app/.../data/spotify` | Public playlist import; authenticated library/canvas | Public import **Verified** (embed page, 100-row continuation, YouTube matching). Authenticated library/Canvas **Blocked** on a Spotify OAuth app, account and Canvas media |
| `app/.../data/lyrics`, `data/stats` | Lyrics providers, Replay | **Verified** — four lyric providers, karaoke, Replay stats and share |
| `app/.../data/listentogether`, `data/presence`, `backend/` | Party protocol/server | **Blocked** — needs a deployed party server and shared signed-in identity |
| `app/.../data/canvas`, `data/discord` | Canvas clips, Discord RPC | **Blocked** — Canvas is authenticated Spotify media; Discord uses local IPC that iOS does not provide |
| `app/.../download` | Queue, background transfers, offline files, playlist sync | **Verified** — background `URLSession`, quality/Wi-Fi/cap rules, force-quit recovery, 100-row playlist sync |
| `app/.../playback` | Queue, radio, DSP, Cast, DSD, loop mix, smart transitions | Queue/radio/autoplay/sleep/speed **Verified**. Crossfade/Automix, seven-band EQ + 16 reference presets, loudness (including speaker-only), spatial widening and skip-silence are **Verified** through an `MTAudioProcessingTap`; next-source prefetch is **Verified**. Cast, DSD and bit-perfect remain **Blocked** below |
| `app/.../ui/screens` | 16 screen files | Every screen is in the screen matrix below |
| `app/.../ui/player`, `ui/components`, `ui/onboarding`, `ui/theme`, `ui/icons`, `ui/navigation`, `ui/utils` | Player, components, onboarding, palette, icons, root navigation | **Verified / deliberately equal** — native UIKit equivalents and motion frames; see motion and screen sections |
| `app/.../ui/festive` | Date-gated Diwali greeting | **Ported** — `DiwaliGate` + `DiwaliGreetingViewController` with the reference illustration, shown only on 8 Nov 2026 in an Indian timezone and once; not date-triggered by today's CI |
| `app/.../ui/performance` | Per-app refresh-rate controls | **Verified** — the setting paces a real `CADisplayLink` (`preferredFramesPerSecond` 60/30); probe reports requested and measured rates |
| `app/.../ui/replay` | Replay model, screen, stories, poster, share | Replay stats and system share **Verified**; the multi-page story carousel is **deliberately equal** to one stats screen plus a rendered share card, not a hidden omission |
| `app/.../widget`, `wear`, `wearos/`, `tv/` | Widget, watch and TV apps | **Blocked/Android-only** — separate application targets; this project has no watchOS/widget/TV extension |
| `shared/src/commonMain` | Models, settings, party, smart playback | Models/settings mirrored; Automix curves and transitions are implemented on the native fade engine. Party protocols remain **Blocked** on a server |
| `shared/src/jvmSharedMain`, `commonTest`, `jvmTest` | JVM clients and tests | Reference only; API shapes informed the native clients, JVM code is not shipped |
| `sharedUi` | Compose screens/resources | Visual reference; UIKit replacements are the screen matrix |
| `web/` | Browser client, extension, docs | Separate web product, outside this iOS target |
| `native/` | FFmpeg decoder/analyzer/loop mix | **Blocked** — the iOS player is AVPlayer/WebKit; FFmpeg would need a new audio graph and licensing review |
| `docs/`, `.github/`, `gradle/` | Docs, CI, build config | Reference only |

## Screens

| Reference screen | iOS implementation | State and proof |
| --- | --- | --- |
| `sharedUi/HomeScreen.kt` | `HomeViewController`, shelves, sign-in banner | **Verified** — `home.png`; `settings.homeHideRecents=shown=true hidden=true`; signed-in handoff renders Home |
| `sharedUi/ExploreScreen.kt` | `ExploreViewController`, mood tiles | **Verified** — `moods.png`, `moods.tracks=20` |
| `sharedUi/SearchScreen.kt` | `SearchViewController`, `InnerTube` | **Verified** — `search.png`; `settings.searchPage2>0`, `settings.searchFresh>0` |
| `sharedUi/LibraryScreen.kt`, `LibraryPhoneParts.kt` | `LibraryViewController`, `SavedLibraryViewController` | **Verified** — `library.png`, `library-synced.png`, saved playlist/album/artist feeds |
| `ui/screens/HistoryScreen.kt` | `HistoryViewController` | **Verified** — `history.png`, `history-empty.png`, `historyPage.*` |
| `ui/screens/AccountAndScrobblingScreen.kt` | `AccountViewController`, `ScrobbleService`, Google flow | **Verified** — signed-out account capture; rendered/blank handoff, restore, sign-out; Last.fm/ListenBrainz settings |
| `ui/screens/LocalFolder.kt` | `LocalMusicViewController`, `LocalMusicStore` | **Verified** — `local-music.png`, `local-songs.png`, all-folders scan root probe |
| `ui/screens/DetailScreen.kt` | `ArtistViewController`, `CollectionViewController` | **Verified** — `artist.png`; `artist.summary=loaded=true songs=10 albums=12 related=6 bio=true` for Taylor Swift |
| `ui/screens/SettingsSheet.kt` | `SettingsViewController`, `SettingsCatalog` | **Verified** — `settings*.png`, `SettingsProbe` report below |
| `ui/screens/SourcesScreen.kt` | `SourcesViewController`, WebDAV/Jellyfin | **Verified** — tree/play/error captures for both |
| `ui/screens/LocalFolder.kt` + `PartyServerEditor.kt` | Local folder page; party editor absent | Local **Verified**; party editor **Blocked** with Listen Together |
| `ui/screens/ListenTogetherScreen.kt`, `ListenTogetherSheets.kt` | Disabled Settings row with explanation | **Blocked** — deployed party server + shared identity |
| `ui/screens/DiscordScreen.kt` | Disabled Settings row | **Blocked** — Discord RPC local IPC is Android-only |
| `ui/screens/EqualizerScreen.kt` | `EqualizerViewController`, manual bands + presets | **Verified** — seven draggable bands, 16 preset curves, balance and preamp all write the tap config; `settings.manualEq=changed=true bands=7 balance=-0.4` and `settings.dspProcessed=dry=false wet=true` |
| `ui/screens/SpotifyLibraryScreen.kt` | Library's public **Import Spotify** card, `SpotifyImporter` | Public playlist import **Verified**; authenticated library **Blocked** on OAuth app/account |
| `ui/screens/SpotifyCanvasAuthScreen.kt` | Disabled Canvas row | **Blocked** — authenticated Spotify media |
| `ui/screens/SignatureApiEditor.kt` | Disabled Artist signatures row | **Blocked** — signature service deployed with party backend; no endpoint |
| `ui/screens/WearOsSettings.kt` | Absent | **Blocked/Android-only** — separate Wear OS app |
| `ui/player/AndroidPlayerHost.kt` | `NowPlayingViewController` | **Verified** — `now-playing.png`, `lyrics.png`, `lyrics-karaoke.png`; 23 icons, theme and player appearance rows |
| `ui/onboarding/OnboardingScreen.kt` | `OnboardingViewController` | **Verified** — four step captures, 320x568 pass, rerun from Settings |
| `ui/replay/ReplayScreen.kt` | `ReplayViewController` | **Verified** — `replay.png`, `replay.entries`, `replay.plays`; share action |
| `ui/replay/ReplayStories.kt`, `ReplayPoster.kt`, `ReplayShareSheet.kt` | Single Replay screen plus `UIActivityViewController` | **Deliberately equal** — the same stats are presented once and shared as a rendered card; the Android story carousel/poster compositor is not reproduced |
| `ui/player/MusicVideoPlayer.kt` | Audio-only player | **Deliberately equal** — this target is audio-first; `Prefer music only` filters non-music instead of showing video |

## Google handoff (original bug)

The white page after a successful Google login was the YouTube Music shell
failing to paint, not a failed credential exchange. `GoogleSignInViewController`
now watches the cookie store while navigation reaches any YouTube host,
captures a session as soon as an API SID exists, and if the shell stays blank
fetches `music.youtube.com` itself and reads `LOGGED_IN`, `SESSION_INDEX`,
`DATASYNC_ID`, `DELEGATED_SESSION_ID` and `VISITOR_DATA` from `ytcfg`.

`-BCSignInStage` reproduces every path without a real Google password:

- rendered shell: `handoff-report-rendered.txt` has
  `probe.shellOrigin=https://music.youtube.com`, `probe.ytcfg=true`,
  `networkFallback=false`, `document.youtubeCookie=true`,
  `document.googleCookie=false`, `signedIn=true`, `homeVisible=true`;
- blank shell: `handoff-report-blank.txt` has `shellBlank=true`, `ytcfg=false`,
  `networkFallback=true`, `networkCookie=true`, then `signedIn=true`,
  `homeVisible=true`;
- both write `dataSync=fixture-account` and capture a signed-in Home;
- relaunch restores the session (`restore.signedIn=true`,
  `restore.homeVisible=true`);
- sign-out clears the session and shows **Sign in with Google**; another
  launch stays signed out (`signout-report-rendered.txt`).

The unsigned simulator has no keychain entitlement (`SecItemAdd -34018`), so
the harness records `persistence=simulator-fallback`; a signed device uses the
keychain alone. A real Google password/2FA login remains a device check.

## Settings

The reference `AppSettings.kt` at `acf219a` contains **131 persisted keys**
(`private const val KEY_*`), not the 73 the previous audit claimed.
`SettingsCatalog` now has **118 rows** (10 sections). The probe reports that
number directly, so it cannot drift with a source comment.

The catalog is not a 1:1 key dump; the 131 keys underlie 118 rows plus internal
state. The rows comprise:

- **75 stateful rows** (toggle/choice/stepper) round-trip through
  `SettingsStore` with `settings.roundTripFailures=none`;
- **20 disabled rows** name the exact missing input (probe:
  `settings.unavailable=20`), each also listed under **Blocked surfaces**;
- **text/action/page/account rows** for credentials, the addon URL, backup and
  export, cache actions, WebDAV sources, onboarding rerun, and so on. Theme and
  app icon are exercised separately by the probe's palette and asset checks.

Keys without their own row are internal state — onboarding completion, last
player screen/version code, Diwali seen, lyrics-sources seen, pinned playlists
— or per-surface sort/view modes controlled from their own screens. Discord's
detail fields sit behind the one blocked Discord row. No internal key is
presented as a working settings row, and no action row is counted as a
persisted preference.

Behavior groups asserted by `SettingsProbe`, using the same code paths as the
UI rather than grep:

| Group | Probe assertion |
| --- | --- |
| Theme palette | `settings.themeLight=true`, `settings.themeDark=true` |
| Icons | `settings.appIcons=23`, `appIconsUnique=23`, `appIconAlternates=22`, `appIconDeclared=22`; build job's `assetutil` finds all variants in compiled `Assets.car` |
| Backup/export | `settings.backupRestored=true`; `settings.downloadExport=saved=1 exported>=1` |
| Local roots | `settings.localRoots=LocalMusic->Documents` |
| Lyrics | `settings.lyrics=synced=1 shifted=0 unsynced=-2` (offset and synced toggle move the active line) |
| Render quality | `settings.renderQuality=high=42 cheap=12 low=12` |
| Autoplay filter | `settings.autoplay=noRepeat=c allowed=b,c` |
| Home shelves | `settings.homeHideRecents=shown=true hidden=true` |
| Speaker guard | `settings.speakerGuard=speakerBlocked=true headphonesAllowed=true` |
| Search continuation | `settings.searchPage1=20`, `settings.searchPage2=16`, `settings.searchFresh=16` |
| Native DSP dry/wet | `settings.dspProcessed=dry=false wet=true`; `settings.dspWet` carries the processed RMS/gain; `dsp-playback.txt` reports `tapAttached=true`, `processedFrames=438364`, `lastRMS=0.46766683` from the playing AVPlayer item |
| Manual equalizer | `settings.manualEq=changed=true bands=7 balance=-0.4`; the planar renderer now writes the equalised samples back to the output buffer |
| Settings search | `settings.search=equalizer=1 empty=0`; the field filters titles, details and keys through `SettingsCatalog.filtered` |
| Interface languages | `settings.languages=14`; every language has a shell table and the Settings choice lists all fourteen |
| Crossfade / Automix | `settings.crossfade=explicit=5 offAutomix=0 automix=3.0 fast=1.5` |
| Animated sleeve | `settings.animatedCover=enabled=true cellularOff=false reduced=false`; `animated-cover.txt` records `active=true` from the presented layer |
| Language resources | `settings.localization=language=Español home=Inicio search=Buscar settings=Ajustes`; `settings.languages=14` includes German, Polish, Portuguese, Indonesian, Japanese, Russian, both Chinese scripts, Hebrew and Italian |
| Translation provider | `settings.translation=targets=en,hi,es,fr cache=0` |
| Refresh rate | `settings.refreshModes=auto=60 sixty=60 thirty=30`; live `settings.refreshRate=requested=60 effective=36 running=true` under the loaded simulator |
| Direct Source Stream | `settings.prefetch=enabled=true requests=0 ready=0 failed=0 held=0` |

Rows that now have observable behavior include Theme, Font, App icon, player
theme (Cover/Solid/Legacy), crossfade, Automix + performance mode, the manual
equalizer (bands, balance, preamp and presets), loudness/speaker loudness,
spatial audio, skip silence, animated cover + cellular gate, app language,
bilingual lyrics/translation language,
Direct Source Stream, refresh rate, full-bleed artwork/detail, liquid glass, legacy
mesh, progressive/reduced blur, render quality, high-performance mode, hide
recents/videos/top picks/moods, show queue history, swipe-to-play-next,
don't-repeat, stop-on-close, prefer-music, square thumbnails, hide volume/status,
sleep timer, playback speed, Wi-Fi/cellular/download quality, storage limit,
Wi-Fi-only, keep-updated, export-compatible, scrobble minimum/percentage/cap,
local all-folders/filter, lyrics sync/full/blur/offset/syllable priority/save
offline/source, and the Google account row.

The **artist page** is no longer a generic track list. It loads the profile
photograph, listener count, biography, popular songs, an albums & singles
shelf and a fans-also-like shelf, with Play and Shuffle actions. The capture
for Taylor Swift reports `artist.summary=loaded=true songs=10 albums=12
related=6 bio=true`.

The **alternate icon** surface is 23 variants: Default plus 22 alternates,
including Monochrome. `AppIconChoice` maps every upstream name, `Info.plist`
declares all 22 alternates and the asset catalog contains 23 sets. The
simulator advertises support and then cancels `setAlternateIconName`
(“The operation was cancelled”), so CI asserts support and the attempt; the
compiled `Assets.car` check proves the assets exist. A signed device performs
the actual SpringBoard switch.

## Headline claims reproduced

| Claim | Executable check |
| --- | --- |
| Settings keys wired, not dead rows | `SettingsProbe` round-trips 75 rows and exercises every behavior group above; workflow greps each result |
| Artist pages carry the full profile | `artist.summary=loaded=true songs=10 albums=12 related=6 bio=true`; the screenshot is the same `ArtistViewController` the search row opens |
| Manual equalizer reaches the audio | `settings.manualEq=changed=true bands=7 balance=-0.4`; the tap writes the filtered samples back to the planar output buffer |
| Settings search is real | `settings.search=equalizer=1 empty=0` through `SettingsCatalog.filtered(by:)` |
| Fourteen interface languages | `settings.languages=14` with a shell table for every entry |
| Continuation-backed **Load more** | real `InnerTube.searchNext` after `search`; `settings.searchPage1=20`, `searchPage2=16`, `searchFresh=16`, `searchMore=true` |
| Six `bitchord://` routes | `deeplinks.txt`: track, album, artist, playlist, radio, home, every `cold=1` |
| YouTube watch/short/playlist/search URLs | shared `MusicLink` parser; `web-links-report.txt` resolves all four forms |
| `+` means space in search | parser replaces `+` before querying; `search` captures use multi-word titles |
| Alternate Monochrome in compiled `Assets.car` | build job runs `assetutil --info`, asserts `AppIcon`, Monochrome, LiquidGlass, NeonViolet, SamsungGlassClearDark and PixelNeonCyan, then prints `compiled icon variants present` |
| Light-palette screenshots | `theme-report.txt`; `theme-home-light.png`, `theme-settings-light.png`, `theme-account-light.png` |
| Background download retry after relaunch | `background-resumed.txt` and `background-killed.txt` each have `indexed=true`, `pendingAfter=0`, `phantom=false`, `ok=true`; the keep-mode transfer starts live and is backgrounded |

## Motion

`-BCMotion` drives each transition through the real control and writes an
origin, mid and settled frame plus presentation-layer values. The workflow
fails if any flag is false or a frame is missing. Captured transitions: tab
pill spring (0.42s, damping 0.82), tab crossfade (0.22s), mini-player expand
(0.30s spring), player open (0.46s spring), dismiss (0.26s ease-in), play/pause
glyph crossfade (0.18s), artwork change (0.25s/0.40s), card/tile press
(0.16s down, 0.24s spring back), stats paging snap (0.30s) and onboarding step
fade (0.22s). `home.png` and `explore.png` also assert the live geometry
(`home.firstArtwork.y=320`, `explore.firstTile.y=167`) inside a four-point
window.

## Implemented since the previous audit

These were the previous blocked audio/rendering/language rows. Each now changes
real behavior, and the probe assertion is the same code path the UI uses.

| Surface | Implementation | Probe / capture evidence |
| --- | --- | --- |
| Crossfade | `PlayerService` fades the current item over the configured seconds before `advance()`; the next track starts at full volume | `settings.crossfade=explicit=5 offAutomix=0 automix=3.0 fast=1.5`; real path in `maybeCrossfade` |
| Equalizer | `MTAudioProcessingTap` + ten biquad slots; seven draggable bands use the reference 60/150/400/1k/2.5k/6k/14k centres, all 16 named curves are presets, and balance/preamp trim the output | `settings.dspProcessed=dry=false wet=true`; `settings.manualEq=changed=true bands=7 balance=-0.4`; the player capture reports a live attached tap with 438,364 processed frames |
| Loudness normalisation | Per-buffer RMS → smoothed gain capped at 0.55–2.0 | wet `dspWet` gain differs from dry; `settings.dspProcessed` |
| Loudness on speaker | The same gain is enabled only when `AVAudioSession` reports the built-in speaker | `settings.speakerGuard=speakerBlocked=true headphonesAllowed=true`; tap config reads the route |
| Spatial audio | Mid/side widening (1.45× side) in both interleaved and planar tap paths | `settings.dspProcessed=dry=false wet=true`; stereo path in `renderStereo` |
| Skip silence | The tap flags 1.2 s of sub-0.0025 RMS; `PlayerService` seeks +1.5 s once | `AudioDSP.takeSkipSilenceRequest` consumed in `onTimeUpdated`; probe asserts the tap renderer |
| Automix / performance mode | Automix supplies a 3.0 s (Balanced) or 1.5 s (Fast) transition when Crossfade is zero | `settings.crossfade=… automix=3.0 fast=1.5` |
| Animated cover | Real `CABasicAnimation`s: scale 1.0→1.055 and ±3 pt pan over 9 s, gated by Reduce Animation and the cellular toggle | `settings.animatedCover=…`; `animated-cover.png` + `animated-cover.txt` (`active=true`) |
| App language | `L10n` string tables for all 14 reference languages; tab bar and Settings header read them at launch | `settings.localization=language=Español home=Inicio search=Buscar settings=Ajustes`; `settings.languages=14` |
| Bilingual lyrics / translation | Cached MyMemory `langpair` requests; translated line appended under the original with line timings retained | `settings.translation=targets=en,hi,es,fr`; translation path in `refresh()` |
| Per-app refresh rate | `DisplayRefreshController` drives a `CADisplayLink` at `preferredFramesPerSecond` 60 or 30 | `settings.refreshModes=auto=60 sixty=60 thirty=30`; live `settings.refreshRate=requested=60 effective=36 running=true` |
| Direct Source Stream | Resolves the next queue item and opens its `AVURLAsset` before the transition | `settings.prefetch=enabled=true`; `StreamPrefetcher.report` |

## Blocked surfaces

The rows below are the only remaining disabled surfaces. Each names the exact
input that is absent and what ships as soon as it is supplied; none of them can
be completed with on-device code already in this project.

| Surface | Concrete reason | Unblocker |
| --- | --- | --- |
| SMB (`data/smb`) | No SMB2/SMB3 client library with an iOS 12 slice; iOS has no SMB API | Add that signed dependency; the browser/stream UI ships immediately after |
| Universal links (`applinks:`) | No controlled domain + Apple-served AASA + associated-domain entitlement | Those three inputs; the URL parser and routes already ship |
| Listen Together, party, presence, signature editor | No hosted party server or participant identity | Deploy the reference party backend; the button, editor, synchronized queue and signatures ship with it |
| Authenticated Spotify library / Canvas | No Spotify OAuth client ID/secret, redirect URI, test account or Canvas media entitlement | Those credentials and scope approval; profile rows, library sync and Canvas player ship with them |
| Discord presence | Discord RPC uses local Unix-socket IPC; iOS has no equivalent endpoint | A supported Discord iOS SDK/endpoint |
| Google Cast | No Cast iOS SDK, receiver ID or local-network multicast entitlement | SDK + receiver ID + entitlement; the route button and session UI ship with them |
| Dolby Atmos | No Atmos-capable output/render path and no E-AC-3/Atmos stream for this catalogue | Atmos hardware/OS plus such a stream; the row and renderer selection ship together |
| Bit-perfect, USB-DAC preference, output precision, DAC volume, fixed volume, USB conversion | No exclusive integer-output API, route-pinning API, selectable bit-depth API or DAC volume endpoint; no attached DAC | A platform/DAC exposing those APIs plus the physical DAC; all six rows and the bit-perfect graph ship together |
| DSD, FFmpeg loop mix | No public DSD decoder/route; FFmpeg is not linked | A licensed FFmpeg/DSD pipeline and a new audio graph; the decoder/loop-mix surfaces ship with it |
| Spotify Canvas | Canvas is authenticated Spotify media with no public track endpoint | Spotify OAuth token and Canvas media entitlement; the player ships with them |
| Remote InnerTube rating/save/rename | Requires signed-in account write/feedback tokens; browsing is deliberately anonymous | Signed-in account with write scopes; the write actions ship with those tokens |
| Custom lyric sources | No signed provider-JSON proxy/schema; the four built-in providers are the only signed sources | Deploy the proxy and schema; the JSON editor and provider loader ship with it |
| Smart audio alignment | Requires a second synchronized stream/device and an offset analyzer | A second participant stream/device plus alignment transport; the control ships with it |
| Wear OS / watchOS | Separate application targets; this project has no watch target or paired watch | A watchOS companion target and a paired Apple Watch; the handoff UI ships with it |
| Widget, TV | Separate application surfaces, not phone-app screens | Separate iOS extensions/apps |

## What CI did not measure

No real Google password/2FA login, no signed-device keychain path, no physical
audio routing/DAC, no real Cast receiver, no real background transfer daemon,
no SMB server and no real Spotify OAuth account. The MyMemory translation
request itself is not exercised in CI; the harness verifies its target mapping
and the bilingual lyric path. The simulator *does* attach the audio tap to a
playing item (438,364 frames), but there is no listening/room-acoustic check.
Those are device or third-party-account checks; the simulator proves the code
paths listed above.
