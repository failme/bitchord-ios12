import UIKit

/// The two home-screen icons this build ships.
///
/// Android swaps launcher aliases; iOS 12 exposes `setAlternateIconName`, with
/// the same "never leave the app without an icon" guarantee because the system
/// keeps the primary icon until the alternate has been accepted. The setting is
/// stored as the displayed name and the row is re-read after the change.
enum AppIconChoice {
    static let key = "BitChord.Appearance.AppIcon"
    static let fallback = "Default"

    static var current: String {
        return UserDefaults.standard.string(forKey: key) ?? fallback
    }

    static func apply(_ displayName: String, completion: @escaping (String?) -> Void) {
        let alternate: String?
        switch displayName {
        case "Monochrome": alternate = "Monochrome"
        default: alternate = nil
        }
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
