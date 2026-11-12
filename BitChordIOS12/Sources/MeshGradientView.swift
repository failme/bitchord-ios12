import UIKit

/// Upstream's Now Playing backdrop: four luminous blobs sampled from the album
/// art, drawn as soft radial gradients and blurred into a mesh.
///
/// Measured off `MeshGradient.kt` — the same four anchors, the same 0.85 centre
/// alpha faded along a smootherstep curve, the same 0.12-lightness base and the
/// same vertical scrim — so the player reads as the same surface rather than a
/// black rectangle with a picture on it.
final class MeshGradientView: UIView {
    /// Four colours, in blob order. Setting a new palette re-renders.
    var palette: [UIColor] = Theme.meshFallbackPalette {
        didSet {
            guard palette.count == didSet.count || true else { return }
            render()
        }
    }

    private let imageView = UIImageView()
    private var renderKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        render()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(imageView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        render()
    }

    // MARK: - Rendering

    private static let anchors: [CGPoint] = [
        CGPoint(x: 0.20, y: 0.25),
        CGPoint(x: 0.80, y: 0.20),
        CGPoint(x: 0.75, y: 0.80),
        CGPoint(x: 0.25, y: 0.75)
    ]

    private func render() {
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let colors = (palette.isEmpty ? Theme.meshFallbackPalette : palette)
        if colors.count < 4 { return }
        let key = String(format: "%.0fx%.0f", size.width, size.height) + colors.map { $0.hexString }.joined()
        guard key != renderKey else { return }
        renderKey = key
        imageView.image = MeshGradientView.image(size: size, colors: colors)
    }

    /// Draws the four blobs and softens them once, at image scale, rather than
    /// re-blurring a live layer on every frame.
    static func image(size: CGSize, colors: [UIColor]) -> UIImage? {
        guard size.width > 1, size.height > 1, colors.count >= 4 else { return nil }
        // Overscan: the blur pulls colour in from outside the frame.
        let overscan: CGFloat = 1.3
        let canvas = CGSize(width: size.width * overscan, height: size.height * overscan)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            colors[0].dimmed(to: 0.12).setFill()
            UIRectFill(CGRect(origin: .zero, size: canvas))

            let radius = max(canvas.width, canvas.height) * 0.62
            for (index, colour) in colors.prefix(4).enumerated() {
                let anchor = anchors[index]
                let centre = CGPoint(x: anchor.x * canvas.width, y: anchor.y * canvas.height)
                let stops = 8
                var components: [CGFloat] = []
                for step in 0...stops {
                    let t = CGFloat(step) / CGFloat(stops)
                    let alpha = 0.85 * (1 - smootherStep(t))
                    let resolved = colour.withAlphaComponent(alpha)
                    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, whiteAlpha: CGFloat = 0
                    resolved.getRed(&red, green: &green, blue: &blue, alpha: &whiteAlpha)
                    components.append(contentsOf: [red, green, blue, whiteAlpha])
                }
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let colours = components.isEmpty ? nil : {
                          var list: [CGColor] = []
                          var index = 0
                          while index + 3 < components.count {
                              list.append(UIColor(red: components[index],
                                                  green: components[index + 1],
                                                  blue: components[index + 2],
                                                  alpha: components[index + 3]).cgColor)
                              index += 4
                          }
                          return list
                      }(),
                      let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: nil) else {
                    continue
                }
                context.cgContext.drawRadialGradient(gradient,
                                                     startCenter: centre, startRadius: 0,
                                                     endCenter: centre, endRadius: radius,
                                                     options: [.drawsAfterEndLocation])
            }

            // Scrim: white text has to stay readable over bright art.
            UIColor.black.withAlphaComponent(0.10).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height * 0.45))
            UIColor.black.withAlphaComponent(0.38).setFill()
            UIRectFill(CGRect(x: 0, y: canvas.height * 0.45,
                              width: canvas.width, height: canvas.height * 0.55))
        }

        // One blur for the whole backdrop, then crop back to the frame.
        guard let source = drawn.cgImage else { return drawn }
        guard let blurred = blur(source, radius: 42) else { return drawn }
        let crop = CGRect(x: (canvas.width - size.width) / 2,
                          y: (canvas.height - size.height) / 2,
                          width: size.width, height: size.height)
        guard let cropped = blurred.cropping(to: crop) else { return drawn }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    private static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        let input = CIImage(cgImage: image)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: input.extent)
    }

    private static func smootherStep(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(t, 1))
        return clamped * clamped * clamped * (clamped * (clamped * 6 - 15) + 10)
    }
}

// MARK: - Palette

extension Theme {
    /// Upstream's stock mesh, used when a cover yields nothing usable.
    static let meshFallbackPalette: [UIColor] = [
        UIColor(red: 0x3A / 255, green: 0x1C / 255, blue: 0x71 / 255, alpha: 1),
        UIColor(red: 0xD7 / 255, green: 0x6D / 255, blue: 0x77 / 255, alpha: 1),
        UIColor(red: 0x2B / 255, green: 0x58 / 255, blue: 0x76 / 255, alpha: 1),
        UIColor(red: 0xFF / 255, green: 0xAF / 255, blue: 0x7B / 255, alpha: 1)
    ]

    /// Four mesh colours from `image`, as `paletteOf` in `MeshGradient.kt` does
    /// it: quantise to a handful of swatches, drop near-duplicates, and fan the
    /// shortfall out of the art's own colours instead of borrowing stock purple.
    static func meshPalette(of image: UIImage?) -> [UIColor] {
        guard let image = image, let swatches = quantise(image), !swatches.isEmpty else {
            return meshFallbackPalette
        }
        var distinct: [UIColor] = []
        for colour in swatches {
            if !distinct.contains(where: { isClose($0, colour) }) {
                distinct.append(colour)
            }
        }
        if distinct.count >= 4 {
            return Array(distinct.prefix(4)).map { $0.tuned() }
        }
        if distinct.isEmpty {
            return meshFallbackPalette
        }
        var expanded = distinct
        var step: CGFloat = 1
        while expanded.count < 4 {
            let base = distinct[expanded.count % distinct.count]
            expanded.append(base.shifted(hue: 24 * step, lightness: 0.12 * step))
            step += 1
        }
        return expanded.map { $0.tuned() }
    }

    /// Buckets a 32×32 downsample by hue so the palette comes from the picture's
    /// dominant colour families rather than from whichever pixel came first.
    private static func quantise(_ image: UIImage) -> [UIColor]? {
        guard let source = image.cgImage else { return nil }
        let dimension = 32
        guard let context = CGContext(data: nil, width: dimension, height: dimension,
                                      bitsPerComponent: 8, bytesPerRow: dimension * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .low
        context.draw(source, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: dimension * dimension * 4)

        var buckets: [Int: (colour: UIColor, count: Int)] = [:]
        for index in 0..<(dimension * dimension) {
            let offset = index * 4
            let red = CGFloat(pixels[offset]) / 255
            let green = CGFloat(pixels[offset + 1]) / 255
            let blue = CGFloat(pixels[offset + 2]) / 255
            let light = 0.299 * red + 0.587 * green + 0.114 * blue
            // Near-black and near-white sleeves carry no hue worth a blob.
            guard light > 0.08, light < 0.94 else { continue }
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            UIColor(red: red, green: green, blue: blue, alpha: 1)
                .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let key = Int((hue * 360) / 24)
            if var existing = buckets[key] {
                existing.count += 1
                buckets[key] = existing
            } else {
                buckets[key] = (UIColor(red: red, green: green, blue: blue, alpha: 1), 1)
            }
        }
        return buckets.values.sorted { $0.count > $1.count }.map { $0.colour }
    }

    private static func isClose(_ a: UIColor, _ b: UIColor) -> Bool {
        var hueA: CGFloat = 0, satA: CGFloat = 0, briA: CGFloat = 0, alphaA: CGFloat = 0
        var hueB: CGFloat = 0, satB: CGFloat = 0, briB: CGFloat = 0, alphaB: CGFloat = 0
        a.getHue(&hueA, saturation: &satA, brightness: &briA, alpha: &alphaA)
        b.getHue(&hueB, saturation: &satB, brightness: &briB, alpha: &alphaB)
        let gap = min(abs(hueA - hueB) * 360, 360 - abs(hueA - hueB) * 360)
        return gap < 15 && abs(briA - briB) < 0.12
    }

    private static func toHSL(_ colour: UIColor) -> (hue: CGFloat, saturation: CGFloat, lightness: CGFloat) {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        colour.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let lightness = brightness * (1 - saturation / 2)
        return (hue, saturation, lightness)
    }
}

extension UIColor {
    /// Boost saturation and clamp lightness so any cover yields a rich mesh.
    func tuned() -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let boosted = min(saturation * 1.35, 1)
        let lightness = min(max(brightness * (1 - saturation / 2), 0.28), 0.58)
        return UIColor(hue: hue, saturation: boosted,
                       brightness: min(1, lightness * 1.55), alpha: 1)
    }

    func dimmed(to lightness: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return UIColor(hue: hue, saturation: saturation,
                       brightness: min(1, lightness * 1.55), alpha: 1)
    }

    func shifted(hue shift: CGFloat, lightness: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let moved = (hue + shift / 360).truncatingRemainder(dividingBy: 1)
        return UIColor(hue: moved < 0 ? moved + 1 : moved,
                       saturation: saturation,
                       brightness: min(1, brightness + lightness), alpha: 1)
    }

    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
