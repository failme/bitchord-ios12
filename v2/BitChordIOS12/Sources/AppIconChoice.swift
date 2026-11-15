import UIKit

/// The home-screen icon variants upstream ships.
///
/// Android swaps launcher aliases; iOS 12 exposes `setAlternateIconName`, with
/// the same "never leave the app without an icon" guarantee because the system
/// keeps the primary icon until the alternate has been accepted. The setting is
/// stored as the displayed name and the row is re-read after the change.
enum AppIconChoice {
    static let key = "BitChord.Appearance.AppIcon"
    static let fallback = "Default"

    /// Display title and the asset-catalog suffix. The primary icon has no
    /// suffix; every other name is declared in `CFBundleAlternateIcons`.
    static let variants: [(title: String, alternate: String?)] = [
        ("Default", nil),
        ("Monochrome", "Monochrome"),
        ("Liquid Glass", "LiquidGlass"),
        ("Liquid Glass Dark", "LiquidGlassDark"),
        ("Liquid Glass Clear", "LiquidGlassClear"),
        ("Liquid Glass Clear Dark", "LiquidGlassClearDark"),
        ("Samsung Glass", "SamsungGlass"),
        ("Samsung Glass Dark", "SamsungGlassDark"),
        ("Samsung Glass Clear", "SamsungGlassClear"),
        ("Samsung Glass Clear Dark", "SamsungGlassClearDark"),
        ("Pixel Glass", "PixelGlass"),
        ("Pixel Glass Dark", "PixelGlassDark"),
        ("Pixel Glass Clear", "PixelGlassClear"),
        ("Pixel Glass Clear Dark", "PixelGlassClearDark"),
        ("Neon Silver", "NeonSilver"),
        ("Neon Cyan", "NeonCyan"),
        ("Neon Violet", "NeonViolet"),
        ("Samsung Neon Silver", "SamsungNeonSilver"),
        ("Samsung Neon Cyan", "SamsungNeonCyan"),
        ("Samsung Neon Violet", "SamsungNeonViolet"),
        ("Pixel Neon Silver", "PixelNeonSilver"),
        ("Pixel Neon Cyan", "PixelNeonCyan"),
        ("Pixel Neon Violet", "PixelNeonViolet")
    ]

    static var displayNames: [String] { return variants.map { $0.title } }

    static var current: String {
        return UserDefaults.standard.string(forKey: key) ?? fallback
    }

    static func apply(_ displayName: String, completion: @escaping (String?) -> Void) {
        let alternate = variants.first(where: { $0.title == displayName })?.alternate
        guard UIApplication.shared.supportsAlternateIcons else {
            completion("Alternate icons are not supported on this device.")
            return
        }
        UIApplication.shared.setAlternateIconName(alternate) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(error.localizedDescription)
                    return
                }
                UserDefaults.standard.set(displayName, forKey: key)
                NotificationCenter.default.post(name: .settingsDidChange, object: nil)
                completion(nil)
            }
        }
    }
}
