# BitChord for iOS 12.5.8 (UIKit port)

A ground-up **iOS 12** UIKit client for YouTube Music, built because the official BitChord iOS
app cannot run below iOS 17. Swift 5, `IPHONEOS_DEPLOYMENT_TARGET = 12.0`, no SwiftUI, no
Combine, no Swift concurrency, no SF Symbols runtime API — every framework it touches exists on
iOS 12.

It is **not** the hero154 app: that one is closed-source and binary-only, and its interface is
SwiftUI, which does not exist on iOS 12. This is an independent implementation of the same core
job: search, play, synced lyrics.

## What works

| Area | Status |
| --- | --- |
| YouTube Music search (InnerTube `WEB_REMIX`) | Verified against the live API — request shape and response parsing tested |
| Synced lyrics (LRCLIB, no key) | Verified against the live API — LRC parsing with `[mm:ss.xx]` and multi-timestamp lines |
| Playback (`AVPlayer`), background audio, lock-screen controls | Implemented |
| Queue: next / previous / auto-advance | Implemented |
| Stream resolution from YouTube | **Blocked by YouTube** — see below |
| Stream resolution from a user source template | Implemented, untested against a real source |

## The honest part: audio needs a source

YouTube now refuses anonymous `player` requests from every client that used to return a direct
URL. Measured on 2026-11-11:

| Client | Result |
| --- | --- |
| `ANDROID_MUSIC` | `LOGIN_REQUIRED` — "Please sign in" |
| `ANDROID_VR` | `LOGIN_REQUIRED` — "Sign in to confirm you're not a bot" |
| `IOS` | HTTP 400 `FAILED_PRECONDITION` |
| `TVHTML5_SIMPLY_EMBEDDED_PLAYER` | `ERROR` — "YouTube is no longer supported in this application or device" |
| `MWEB` | `UNPLAYABLE` — "The page needs to be reloaded" |

So the app tries YouTube directly (it will start working again if a client opens up), and falls
back to a **source template** you set in the app: **Source** in the top-right of the search
screen. The contract is deliberately loose — point it at any URL that

- returns JSON `{"url": "https://…"}`, or
- returns a bare `https://…` URL as text, or
- serves audio bytes directly (`Content-Type: audio/*`).

`{videoId}` (or `{id}`) is substituted with the track's video id:

```
https://your-host.example/stream?id={videoId}
```

The app always tries the source first, then YouTube.

## Build it

The repo carries no `.xcodeproj`; it is generated, so there is nothing stale to merge. Building
needs macOS with Xcode (or the GitHub Actions workflow, which does it for you).

### GitHub Actions (no Mac needed)

1. Create an empty repository on GitHub.
2. Push this folder to it:
   ```
   git init
   git add .
   git commit -m "BitChord iOS 12 UIKit port"
   git branch -M main
   git remote add origin https://github.com/<you>/<repo>.git
   git push -u origin main
   ```
3. Open **Actions → Build iOS 12 IPA → Run workflow**.
4. When it finishes, download the `BitChordIOS12-unsigned-ipa` artifact.

The workflow installs XcodeGen, generates the project, builds for `iphoneos` with code signing
disabled, prints the resulting `MinimumOSVersion` and `LC_BUILD_VERSION` so the iOS 12 target is
verifiable, and packages `Payload/BitChordIOS12.app` into an unsigned `.ipa`.

### On a Mac

```
brew install xcodegen
xcodegen generate
open BitChordIOS12.xcodeproj
```

Set your team under *Signing & Capabilities*, pick your device, run.

## Install on the iPhone (iOS 12.5.8)

The artifact is **unsigned**, which is what you want here — Sideloadly signs it with your Apple ID
as it installs.

1. Install [Sideloadly](https://sideloadly.io) on Windows or macOS.
2. Connect the iPhone, drag `BitChordIOS12-unsigned.ipa` into Sideloadly, enter your Apple ID.
3. Install, then on the device trust the profile under *Settings → General → Profiles*.
4. Open BitChord, set your **Source** in the top-right, and search.

Sideloadly is the only mainstream free signer that supports iOS 12 — AltStore needs iOS 14.0+,
SideStore needs iOS 14+ (current docs say 15+), Scarlet needs 14+, TrollStore covers 14.0b2–16.6.1.

A free Apple ID allows 3 apps at a time and expires after 7 days.

## Layout

```
project.yml                          XcodeGen spec (deployment target, scheme, signing off)
BitChordIOS12/Info.plist             classic AppDelegate app, no scene manifest
BitChordIOS12/Sources/
  AppDelegate.swift                  window + appearance setup
  RootViewController.swift           nav stack + mini player container
  SearchViewController.swift         debounced search, source settings
  TrackCell.swift                    result row
  NowPlayingViewController.swift     artwork, scrubber, controls, lyrics list
  MiniPlayerBar.swift                bottom bar
  PlayerService.swift                AVPlayer, queue, lock screen, now playing info
  StreamResolver.swift               source template → InnerTube fallback
  InnerTube.swift                    search + player endpoints
  LyricsService.swift                LRCLIB client + LRC parser
  ArtworkLoader.swift                image cache
  Track.swift, Theme.swift, LaunchScreen.storyboard
.github/workflows/ios12.yml          unsigned IPA build
```

## iOS 12 API discipline

Deliberately avoided, because they would raise the floor: `SwiftUI`, `Combine`, `async`/`await`,
`@Observable`, `UIImage(systemName:)`, `UIColor.systemBackground`, `UIActivityIndicatorView(style:)`,
`UIMenu`/`UIAction`, `UIButton.Configuration`, `UISheetPresentationController`, `UIWindowScene`.

Used and safe on iOS 12: `UINavigationController`, `UISearchController`,
`UITableView`, `AVPlayer`, `MPRemoteCommandCenter`, `MPNowPlayingInfoCenter`, `AVAudioSession`,
`URLSession`, `JSONSerialization`, `NSRegularExpression`.
