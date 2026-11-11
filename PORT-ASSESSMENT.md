# BitChord → iOS 12.5.8 port feasibility

Assessment date: 2026-11-11

## Bottom line

A working BitChord app for iOS 12.5.8 cannot be produced from this machine. Two independent
blockers, either one of which is fatal on its own.

## Blocker 1 — no source to port

| Codebase | Availability | Target |
| --- | --- | --- |
| `hero154` iOS app (the one on bitlchord.hero154.com) | **binary only.** No public repo. `Payload/BitChord.app/README.md` documents internal Swift file paths (`Navigation/RootTabView.swift`, `Services/AppModel.swift`) but the sources are not shipped. | iOS 17.0, Swift 6, SwiftUI 8, iOS 27 SDK |
| `kushagrasinghx/BitChord` (upstream, GPL-3.0) | public | **Android only** — Kotlin, minSdk 26. Issue #388 ("iOS App Support / Cross-Platform Port") was closed completed, pointing at the third-party launches below. |
| `rzrinanda/bitchord-ios` (closest open Swift port) | public, GPL-3.0 | `Package.swift` declares `platforms: [.iOS(.v17)]`; `IPHONEOS_DEPLOYMENT_TARGET = 17.0`; `swift-tools-version: 6.0`. Uses `.ultraThinMaterial` (iOS 15+), mesh gradients (iOS 18), `@Observable`, Swift concurrency. |
| `OtosanX/OnlyMusic-iOS` | public | iOS 18+ per its own description. |
| `Spvteam/bitchord-ipados`, `Kaitoramac/BitChord-iOS`, `atlasoftimezz-coder/BitChord-iOS` | public | Kotlin-based "automated Xcode IPA builder" wrappers around the Android app; still not iOS 12 code. |

There is no iOS 12-era BitChord codebase anywhere in the chain. Every published version on
`ipa.hero154.com` (1.0.0-3, 1.0.1-4, 1.0.2-9) declares `minOSVersion: 17.0`, so there is no
older build to fall back to either.

## Blocker 2 — this machine cannot build or sign an iOS app

```
OS:            MINGW64_NT-10.0-26300 (Windows 11), x86_64
swift/swiftc:  not installed
xcodebuild:    not found
xcrun:         not found
ldid:          not found
codesign:      not found
Xcode.app:     NO
clang:         present (LLVM for Windows — no iOS SDK, no arm64-apple-ios sysroot)
```

Producing an installable `.ipa` needs, at minimum:

1. a Swift/Objective-C compiler with the iOS SDK (`iphoneos*.sdk`), shipped only inside Xcode;
2. the arm64 iOS standard library (`libswiftCore.dylib` slice for iOS) — no Linux/Windows toolchain
   provides an iOS Swift target;
3. `codesign` or `ldid` to pseudo-sign the bundle, and an Apple ID signing step (Sideloadly) before
   the device will accept it.

None of the three exists here. The iOS SDK itself is only distributable as part of Xcode and cannot
be installed on Windows.

## What a real port actually involves

Lowering a deployment target is not the work. Starting from `rzrinanda/bitchord-ios`, an iOS 12
build requires:

- **UI:** replace the entire SwiftUI layer with UIKit (`UIViewController`, `UITableView`,
  `UICollectionView`, Auto Layout). SwiftUI does not exist before iOS 13; there is no shim.
- **Concurrency:** replace `async/await`, `Task`, actors, `AsyncStream` with GCD + completion
  handlers. Swift concurrency back-deploys to iOS 13, not 12.
- **State:** replace `@Observable` / `@Environment(Type.self)` (Observation framework, iOS 17) with
  manual KVO, delegates or Combine-free observer patterns (Combine is iOS 13+ too).
- **Audio:** `AVAudioEngine` exists on iOS 12 (inside AVFoundation), but `AVAudioSession`
  spatial/Atmos APIs, `AVPlayer` HLS-DASH behaviours and MediaPlayer integration need rework.
  The app's Automix ONNX runtime (`onnxruntime` framework, min 15.1) has no iOS 12 build published.
- **Images/UI extras:** SF Symbols runtime (`UIImage(systemName:)`) is iOS 13+; `.ultraThinMaterial`,
  `MeshGradient`, `ContainerRelativeShape`, `ShareLink`, `WidgetKit`, App Intents — all absent.
- **Networking/storage:** `URLSession` is fine, but `CryptoKit` (iOS 13) used for cache keys and the
  modern `Assets.car` catalog need replacing.

That is a ground-up UIKit application, not a build-setting change — and the result still has to be
compiled on macOS or a GitHub Actions `macos-*` runner (a `.github/workflows/*-ios.yml` Xcode
build is the only Mac-free route, and it needs the code pushed to the user's own GitHub account).

## Practical conclusion

The device in question (iOS 12.5.8 = iPhone 5s / 6 / 6 Plus, iPad Air, iPad mini 2–3, iPod touch 6)
is on Apple's last supported release for that hardware. BitChord's feature set (Hi-Res lossless,
Atmos, word-level lyrics, ONNX Automix, widgets, App Intents) is built on APIs from iOS 15–18.
No amount of binary or build-setting work moves it to iOS 12.
