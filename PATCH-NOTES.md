# BitChord IPA — iOS 12.5.8 compatibility patch

Source: `BitChord-1.0.2-9.ipa` (build 9, released 2026-11-10) from <https://ipa.hero154.com/BitChord-1.0.2-9.ipa>
Output: `BitChord-1.0.2-9-ios12-patched.ipa`

**Status: installs-and-launches is NOT expected to work.** See "Will it run?" below.

## What was changed

| Item | Before | After |
| --- | --- | --- |
| `Info.plist` → `MinimumOSVersion` (app) | `17.0` | `12.5` |
| `Info.plist` → `MinimumOSVersion` (Automix bundle) | `17.0` | `12.5` |
| `Info.plist` → `MinimumOSVersion` (AMSMB2 framework) | `15.0` | `12.5` |
| `Info.plist` → `MinimumOSVersion` (onnxruntime framework) | `15.1` | `12.5` |
| Mach-O `LC_BUILD_VERSION` minos — `BitChord` (@0x1410) | `0x110000` (17.0) | `0xC0500` (12.5) |
| Mach-O `LC_BUILD_VERSION` minos — `AMSMB2` (@0x11b0) | `0xF0000` (15.0) | `0xC0500` (12.5) |
| Mach-O `LC_BUILD_VERSION` minos — `onnxruntime` (@0x41e8) | `0x110000` (17.0) | `0xC0500` (12.5) |
| `Payload/BitChord.app/PlugIns/` (widget + share extension) | present, both iOS 17.0 | removed (WidgetKit/AppIntents do not exist on iOS 12) |
| `_CodeSignature/` (app + both frameworks) | present, signature now invalid | removed — must be re-signed anyway |

`LC_BUILD_VERSION` SDK (`0x1B0000`, iOS 27.0 SDK) was intentionally left alone; it is informational and does not gate installation.

Everything else — the 81 MB `BitChord` executable, `Assets.car`, localization bundles, ONNX models — is byte-for-byte the original.

## Will it run? No.

Lowering `MinimumOSVersion` only removes the version *gate*. It does not supply the frameworks the binary actually links against. `llvm-objdump --macho --dylibs-used` shows the executable requires:

- `SwiftUI.framework` — iOS 13+
- `AppIntents.framework` — iOS 16+
- `WidgetKit.framework` — iOS 14+
- `CryptoKit.framework` — iOS 13+
- `Symbols.framework` — iOS 13+
- `CoreTransferable.framework` — iOS 16+
- `AVFAudio.framework` — iOS 13+
- `libswiftObservation.dylib` — iOS 17+
- `libswift_StringProcessing.dylib` — iOS 16+
- `libswiftSpatial.dylib` — iOS 18+

None of these exist in the iOS 12.5.8 dyld shared cache, so `dyld` aborts at launch with a "Library not loaded" error before any app code runs. Beyond that, the app is Swift 6 / SwiftUI 8 source compiled against the iOS 27 SDK; it uses Swift concurrency, `@Observable`, `UIApplicationSceneManifest`, App Intents and the iOS 26-era `Assets.car` format. None of that is back-deployable by editing a binary.

A real iOS 12 build would require the app's source, a rewrite of the SwiftUI layer to UIKit, removal of App Intents / widgets / Observation, and replacing the modern Swift libraries — i.e. a separate port, not a patch.

## Installing anyway (for reference)

The IPA is unsigned. On iOS 12.5.8:

- **Sideloadly** (Windows/macOS) — supports iOS 7+, this is the only mainstream free signer that works on iOS 12.
- **AltStore** — requires iOS 14.0+.
- **SideStore** — requires iOS 14+ (current prerequisites say iOS 15+).
- **TrollStore** — supports 14.0b2–16.6.1 only.

Sideloadly will re-sign and install the patched IPA, and will report a launch crash on first open.
