# BitChord for iOS 12.5.8

A UIKit port of [rzrinanda/bitchord-ios](https://github.com/rzrinanda/bitchord-ios) targeting
**iOS 12.0** — the last release that runs on iPhone 5s/6/6 Plus, iPad Air, iPad mini 2–3 and
iPod touch 6. Upstream targets iOS 17 with SwiftUI; this rebuilds the same app on UIKit with no
API newer than iOS 12.

Licensed **GPL-3.0**, because it is derived from GPL-3.0 work. See `LICENSE`.

## The part that makes sound

Upstream does not resolve audio through InnerTube. It plays YouTube's embed player inside a
`WKWebView` and defeats the player's background suspension:

- page-visibility APIs are forced to report `visible`, and `visibilitychange` / `pagehide` /
  `freeze` listeners are neutralised, both in the host page and in YouTube's iframes;
- a silent WebAudio oscillator keeps WebKit's audio thread alive;
- a listening/unMute/play watchdog re-issues commands until playback actually starts;
- seeks are posted, then verified, then forced by reloading the embed with `&start=`;
- a 250 ms ticker interpolates position between player updates so the scrubber stays smooth.

Anonymous InnerTube `player` requests are rejected (`LOGIN_REQUIRED`, `FAILED_PRECONDITION`,
"no longer supported in this application") — I measured that across five client configs. The
embed bridge is the mechanism that works, and all of it is iOS 12 API.

## What exists today

| Area | State |
| --- | --- |
| Search (InnerTube `WEB_REMIX`) | Working |
| Playback (WKWebView embed bridge) | Ported |
| Queue, next/previous, repeat, shuffle | Ported |
| Lock screen / control centre | Ported |
| Synced lyrics (LRCLIB + LRC parser) | Working |
| Now Playing (artwork/lyrics toggle, badge, shuffle, repeat, queue sheet) | Ported |
| Mini player | Working |
| Home tab | Ported: local shelves + live quick picks |
| Explore tab | Ported: trending songs, new albums, top charts, moods |
| Library tab (liked, playlists, recents, recent searches) | Ported |
| Settings (50+ keys) | Not ported |
| Addon sources, downloads, scrobbling, EQ, crossfade | Not ported |

## Build

No committed `.xcodeproj` — it is generated, so there is nothing stale to merge. Building needs
macOS with Xcode, or the bundled workflow.

### GitHub Actions (no Mac needed)

1. Push this repository to GitHub.
2. **Actions → Build iOS 12 IPA → Run workflow**.
3. Download the `BitChordIOS12-unsigned-ipa` artifact.

The workflow installs XcodeGen, builds with code signing off, and publishes the resulting
`MinimumOSVersion`, `LC_BUILD_VERSION minos` and architectures as check annotations, so the iOS 12
target is verifiable from outside. Build errors are also emitted as annotations, because Actions
logs now require a signed-in viewer.

### On a Mac

```
brew install xcodegen
xcodegen generate
open BitChordIOS12.xcodeproj
```

## Install

The artifact is unsigned. Sign it with [Sideloadly](https://sideloadly.io) — the only mainstream
free signer supporting iOS 12 (AltStore needs 14.0+, SideStore 14+/15+, TrollStore 14.0b2–16.6.1).
A free Apple ID allows 3 apps and expires after 7 days.

## Layout

```
project.yml                            XcodeGen spec, deployment target 12.0, scheme
BitChordIOS12/Info.plist               AppDelegate app, no scene manifest, audio background mode
BitChordIOS12/Sources/
  YouTubeBridge.swift                  WKWebView embed player + visibility spoof + JS protocol
  PlayerService.swift                  queue, transport, remote commands, now playing info
  InnerTube.swift                      search + player endpoints
  LyricsService.swift                  LRCLIB client + LRC parser
  SearchViewController.swift           debounced search
  NowPlayingViewController.swift       artwork, scrubber, transport, lyrics list
  MiniPlayerBar.swift                  floating mini player
  RootViewController.swift             container; hosts the bridge web view
  TrackCell.swift                      result row
  Track.swift                          model (mirrors upstream shape)
  ArtworkLoader.swift, Theme.swift, AppDelegate.swift, LaunchScreen.storyboard
.github/workflows/ios12.yml            unsigned IPA build + self-diagnosing annotations
```

## iOS 12 discipline

Avoided, because each would raise the floor: `SwiftUI`, `Combine`, `async`/`await`,
`@MainActor`, `@Observable`, `UIImage(systemName:)`, `UIColor.systemBackground`,
`UIActivityIndicatorView(style:)`, `UIMenu`, `UIButton.Configuration`,
`UISheetPresentationController`, `UIWindowScene`.

Used and safe on 12: `WKWebView`, `WKUserScript`, `WKScriptMessageHandler`,
`UINavigationController`, `UISearchController`, `UITableView`, `MPRemoteCommandCenter`,
`MPNowPlayingInfoCenter`, `AVAudioSession`, `URLSession`, `JSONSerialization`.
