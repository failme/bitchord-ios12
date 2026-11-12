import UIKit

/// BitChord's visual language, measured off the upstream app.
///
/// Pure-black background, graphite surfaces, white ink, grey secondary text and
/// the signature red accent — dark only, as upstream ships it.
enum Theme {
    // MARK: - Palette

    static let background = UIColor.black
    static let surface = UIColor(red: 0x0D / 255.0, green: 0x0D / 255.0, blue: 0x0F / 255.0, alpha: 1)
    static let surfaceVariant = UIColor(red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1E / 255.0, alpha: 1)
    static let primaryText = UIColor.white
    static let secondaryText = UIColor(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x93 / 255.0, alpha: 1)
    static let outline = UIColor(red: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2E / 255.0, alpha: 1)
    /// Upstream's primary is white — playback controls, accents, the selected
    /// tab. The red is Replay's rank badge and nothing else.
    static let accent = UIColor.white
    static let replayRed = UIColor(red: 0xFA / 255.0, green: 0x2D / 255.0, blue: 0x48 / 255.0, alpha: 1)

    /// The page inset every screen shares.
    static let gutter: CGFloat = 16
    /// A row's thumbnail box.
    static let rowArtwork: CGFloat = 52

    // MARK: - Type

    /// Upstream's scale (`BitChordTypography`). Every weight there is asked for
    /// one cut bolder than it draws, because Apple Music's own screens came out
    /// lighter; the weights below are the cuts the real app actually paints.
    enum TextStyle {
        case displayLarge, headlineLarge, headlineMedium, titleLarge
        case titleMedium, bodyLarge, bodyMedium, labelMedium, labelSmall

        var size: CGFloat {
            switch self {
            case .displayLarge: return 34
            case .headlineLarge: return 30
            case .headlineMedium: return 22
            case .titleLarge: return 20
            case .titleMedium: return 16
            case .bodyLarge: return 16
            case .bodyMedium: return 14
            case .labelMedium: return 12
            case .labelSmall: return 11
            }
        }

        var weight: UIFont.Weight {
            switch self {
            case .displayLarge, .headlineLarge: return .bold
            case .headlineMedium, .titleLarge: return .semibold
            case .titleMedium, .labelMedium, .labelSmall: return .medium
            case .bodyLarge, .bodyMedium: return .regular
            }
        }

        /// Measured off Apple Music: small text opens up, large titles close.
        var kerning: CGFloat {
            switch self {
            case .displayLarge: return -0.5
            case .headlineLarge: return -0.4
            case .headlineMedium: return -0.25
            case .titleLarge: return -0.2
            case .titleMedium: return 0.05
            case .bodyLarge: return 0.2
            case .bodyMedium: return 0.3
            case .labelMedium: return 0.25
            case .labelSmall: return 0.3
            }
        }
    }

    static func font(_ style: TextStyle) -> UIFont {
        return UIFont.systemFont(ofSize: style.size, weight: style.weight)
    }

    static func kerning(_ style: TextStyle) -> CGFloat {
        return style.kerning
    }

    static func attributed(_ text: String, _ style: TextStyle, color: UIColor) -> NSAttributedString {
        return NSAttributedString(string: text,
                                   attributes: [.font: font(style),
                                                .foregroundColor: color,
                                                .kern: style.kerning])
    }

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func monoDigits(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        return UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Scrubber

    /// A 2pt track image: the thin-slider look in `UISlider` form (iOS 12-safe).
    static func trackImage(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 4, height: 2)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
        }
        return image.resizableImage(withCapInsets: .zero, resizingMode: .stretch)
    }

    /// A 12pt white thumb.
    static func thumbImage() -> UIImage {
        let diameter: CGFloat = 12
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(
            size: CGSize(width: diameter + 6, height: diameter + 6),
            format: format
        ).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: diameter, height: diameter)).fill()
        }
    }

    // MARK: - Explicit badge

    /// Apple's explicit tile, as upstream draws it: a filled rounded square with
    /// the E cut out of it, so the backdrop shows through the letter.
    static func explicitBadgeImage(side: CGFloat = 13, color: UIColor = .white) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: CGSize(width: side, height: side)),
                         cornerRadius: 2 * side / 13).fill()
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.setBlendMode(.destinationOut)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let font = UIFont.systemFont(ofSize: side * 9.5 / 13, weight: .bold)
            let text = NSAttributedString(string: "E",
                                          attributes: [.font: font, .paragraphStyle: paragraph])
            let height = text.size().height
            text.draw(in: CGRect(x: 0, y: (side - height) / 2 - 0.5, width: side, height: height))
        }
    }

    // MARK: - Artwork color

    /// The average color of the artwork's edges — the glow the cover fades into.
    static func edgeColor(of image: UIImage) -> UIColor? {
        guard let source = image.cgImage else { return nil }
        let dimension = 16
        guard let context = CGContext(data: nil, width: dimension, height: dimension,
                                      bitsPerComponent: 8, bytesPerRow: dimension * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .low
        context.draw(source, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: dimension * dimension * 4)
        var red = 0, green = 0, blue = 0, count = 0
        func take(_ x: Int, _ y: Int) {
            let offset = (y * dimension + x) * 4
            red += Int(pixels[offset])
            green += Int(pixels[offset + 1])
            blue += Int(pixels[offset + 2])
            count += 1
        }
        for x in 0..<dimension {
            take(x, 0)
            take(x, dimension - 1)
        }
        for y in 1..<(dimension - 1) {
            take(0, y)
            take(dimension - 1, y)
        }
        guard count > 0 else { return nil }
        return UIColor(red: CGFloat(red) / CGFloat(count) / 255,
                       green: CGFloat(green) / CGFloat(count) / 255,
                       blue: CGFloat(blue) / CGFloat(count) / 255,
                       alpha: 1)
    }
}
