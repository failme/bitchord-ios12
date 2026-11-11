import UIKit

enum Theme {
    static let background = UIColor(red: 0.071, green: 0.075, blue: 0.086, alpha: 1)
    static let surface = UIColor(red: 0.122, green: 0.129, blue: 0.145, alpha: 1)
    static let primaryText = UIColor.white
    static let secondaryText = UIColor(white: 0.62, alpha: 1)
    static let accent = UIColor(red: 0.988, green: 0.329, blue: 0.424, alpha: 1)

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func monoDigits(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        return base
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
