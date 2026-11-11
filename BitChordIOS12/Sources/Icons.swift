import UIKit

/// Hand-drawn template icons.
///
/// iOS 12 has no SF Symbols, so every glyph the upstream app draws with
/// `Image(systemName:)` is redrawn here with UIBezierPath. Each factory returns a
/// `.alwaysTemplate` image, so `tintColor` colours it exactly like a symbol.
enum Icons {
    enum Kind {
        case play, pause, previous, next
        case shuffle, repeatAll, repeatOne
        case heart, heartFilled
        case ellipsis
        case chevronDown, chevronRight, chevronLeft
        case search, close, plus
        case musicNote
        case house, compass, library, list, gear
    }

    static func image(_ kind: Kind, size: CGFloat = 24) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let drawn = renderer.image { context in
            UIColor.white.setFill()
            UIColor.white.setStroke()
            draw(kind, size: size, context: context.cgContext)
        }
        return drawn.withRenderingMode(.alwaysTemplate)
    }

    private static func draw(_ kind: Kind, size s: CGFloat, context cg: CGContext) {
        let w = max(1.5, s * 0.085)
        func stroke(_ path: UIBezierPath, width: CGFloat = 0) {
            path.lineWidth = width > 0 ? width : w
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: x * s, y: y * s)
        }
        switch kind {
        case .play:
            let p = UIBezierPath()
            p.move(to: pt(0.34, 0.25))
            p.addLine(to: pt(0.34, 0.75))
            p.addLine(to: pt(0.74, 0.50))
            p.close()
            p.fill()
        case .pause:
            UIBezierPath(roundedRect: CGRect(x: 0.30 * s, y: 0.25 * s, width: 0.15 * s, height: 0.50 * s),
                         cornerRadius: 0.04 * s).fill()
            UIBezierPath(roundedRect: CGRect(x: 0.55 * s, y: 0.25 * s, width: 0.15 * s, height: 0.50 * s),
                         cornerRadius: 0.04 * s).fill()
        case .previous:
            UIBezierPath(roundedRect: CGRect(x: 0.22 * s, y: 0.26 * s, width: 0.10 * s, height: 0.48 * s),
                         cornerRadius: 0.03 * s).fill()
            let p = UIBezierPath()
            p.move(to: pt(0.74, 0.26))
            p.addLine(to: pt(0.74, 0.74))
            p.addLine(to: pt(0.38, 0.50))
            p.close()
            p.fill()
        case .next:
            let p = UIBezierPath()
            p.move(to: pt(0.26, 0.26))
            p.addLine(to: pt(0.26, 0.74))
            p.addLine(to: pt(0.62, 0.50))
            p.close()
            p.fill()
            UIBezierPath(roundedRect: CGRect(x: 0.68 * s, y: 0.26 * s, width: 0.10 * s, height: 0.48 * s),
                         cornerRadius: 0.03 * s).fill()
        case .shuffle:
            let top = UIBezierPath()
            top.move(to: pt(0.16, 0.34))
            top.addCurve(to: pt(0.72, 0.66), controlPoint1: pt(0.38, 0.34), controlPoint2: pt(0.50, 0.66))
            stroke(top)
            let bot = UIBezierPath()
            bot.move(to: pt(0.16, 0.66))
            bot.addCurve(to: pt(0.72, 0.34), controlPoint1: pt(0.38, 0.66), controlPoint2: pt(0.50, 0.34))
            stroke(bot)
            let h1 = UIBezierPath()
            h1.move(to: pt(0.72, 0.66))
            h1.addLine(to: pt(0.62, 0.63))
            h1.move(to: pt(0.72, 0.66))
            h1.addLine(to: pt(0.69, 0.56))
            stroke(h1, width: w * 0.9)
            let h2 = UIBezierPath()
            h2.move(to: pt(0.72, 0.34))
            h2.addLine(to: pt(0.62, 0.37))
            h2.move(to: pt(0.72, 0.34))
            h2.addLine(to: pt(0.69, 0.44))
            stroke(h2, width: w * 0.9)
        case .repeatAll:
            drawRepeat(s: s, w: w, one: false)
        case .repeatOne:
            drawRepeat(s: s, w: w, one: true)
        case .heart:
            stroke(heartPath(s: s))
        case .heartFilled:
            heartPath(s: s).fill()
        case .ellipsis:
            for x: CGFloat in [0.26, 0.50, 0.74] {
                UIBezierPath(ovalIn: CGRect(x: (x - 0.065) * s, y: 0.435 * s,
                                            width: 0.13 * s, height: 0.13 * s)).fill()
            }
        case .chevronDown:
            let p = UIBezierPath()
            p.move(to: pt(0.28, 0.38))
            p.addLine(to: pt(0.50, 0.60))
            p.addLine(to: pt(0.72, 0.38))
            stroke(p)
        case .chevronRight:
            let p = UIBezierPath()
            p.move(to: pt(0.40, 0.28))
            p.addLine(to: pt(0.62, 0.50))
            p.addLine(to: pt(0.40, 0.72))
            stroke(p)
        case .chevronLeft:
            let p = UIBezierPath()
            p.move(to: pt(0.60, 0.28))
            p.addLine(to: pt(0.38, 0.50))
            p.addLine(to: pt(0.60, 0.72))
            stroke(p)
        case .search:
            stroke(UIBezierPath(ovalIn: CGRect(x: 0.22 * s, y: 0.22 * s, width: 0.42 * s, height: 0.42 * s)))
            let h = UIBezierPath()
            h.move(to: pt(0.585, 0.585))
            h.addLine(to: pt(0.76, 0.76))
            stroke(h, width: w * 1.25)
        case .close:
            let p = UIBezierPath()
            p.move(to: pt(0.32, 0.32))
            p.addLine(to: pt(0.68, 0.68))
            p.move(to: pt(0.68, 0.32))
            p.addLine(to: pt(0.32, 0.68))
            stroke(p)
        case .plus:
            let p = UIBezierPath()
            p.move(to: pt(0.50, 0.28))
            p.addLine(to: pt(0.50, 0.72))
            p.move(to: pt(0.28, 0.50))
            p.addLine(to: pt(0.72, 0.50))
            stroke(p)
        case .musicNote:
            UIBezierPath(ovalIn: CGRect(x: 0.26 * s, y: 0.61 * s, width: 0.23 * s, height: 0.17 * s)).fill()
            let stem = UIBezierPath()
            stem.move(to: pt(0.47, 0.62))
            stem.addLine(to: pt(0.47, 0.24))
            stroke(stem, width: w * 1.15)
            let flag = UIBezierPath()
            flag.move(to: pt(0.47, 0.24))
            flag.addCurve(to: pt(0.60, 0.44), controlPoint1: pt(0.64, 0.26), controlPoint2: pt(0.68, 0.34))
            stroke(flag, width: w * 1.15)
        case .house:
            let p = UIBezierPath()
            p.move(to: pt(0.22, 0.50))
            p.addLine(to: pt(0.50, 0.24))
            p.addLine(to: pt(0.78, 0.50))
            stroke(p)
            let b = UIBezierPath()
            b.move(to: pt(0.32, 0.46))
            b.addLine(to: pt(0.32, 0.74))
            b.addLine(to: pt(0.68, 0.74))
            b.addLine(to: pt(0.68, 0.46))
            stroke(b)
        case .compass:
            stroke(UIBezierPath(ovalIn: CGRect(x: 0.23 * s, y: 0.23 * s, width: 0.54 * s, height: 0.54 * s)))
            let n = UIBezierPath()
            n.move(to: pt(0.62, 0.38))
            n.addLine(to: pt(0.55, 0.55))
            n.addLine(to: pt(0.38, 0.62))
            n.addLine(to: pt(0.45, 0.45))
            n.close()
            n.fill()
        case .library:
            for y: CGFloat in [0.34, 0.50, 0.66] {
                UIBezierPath(ovalIn: CGRect(x: 0.195 * s, y: (y - 0.045) * s,
                                            width: 0.09 * s, height: 0.09 * s)).fill()
                let l = UIBezierPath()
                l.move(to: pt(0.36, y))
                l.addLine(to: pt(0.74, y))
                stroke(l, width: w * 0.9)
            }
        case .list:
            for y: CGFloat in [0.34, 0.50, 0.66] {
                let l = UIBezierPath()
                l.move(to: pt(0.26, y))
                l.addLine(to: pt(0.74, y))
                stroke(l)
            }
        case .gear:
            for i in 0..<8 {
                cg.saveGState()
                cg.translateBy(x: 0.5 * s, y: 0.5 * s)
                cg.rotate(by: CGFloat(i) * .pi / 4)
                UIBezierPath(rect: CGRect(x: -0.05 * s, y: -0.315 * s,
                                          width: 0.10 * s, height: 0.115 * s)).fill()
                cg.restoreGState()
            }
            let disc = UIBezierPath(ovalIn: CGRect(x: 0.30 * s, y: 0.30 * s, width: 0.40 * s, height: 0.40 * s))
            disc.append(UIBezierPath(ovalIn: CGRect(x: 0.405 * s, y: 0.405 * s,
                                                   width: 0.19 * s, height: 0.19 * s)))
            disc.usesEvenOddFillRule = true
            disc.fill()
        }
    }

    private static func heartPath(s: CGFloat) -> UIBezierPath {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: x * s, y: y * s)
        }
        let p = UIBezierPath()
        p.move(to: pt(0.50, 0.76))
        p.addCurve(to: pt(0.20, 0.38), controlPoint1: pt(0.30, 0.60), controlPoint2: pt(0.20, 0.48))
        p.addCurve(to: pt(0.36, 0.22), controlPoint1: pt(0.20, 0.28), controlPoint2: pt(0.28, 0.22))
        p.addCurve(to: pt(0.50, 0.32), controlPoint1: pt(0.43, 0.22), controlPoint2: pt(0.48, 0.27))
        p.addCurve(to: pt(0.64, 0.22), controlPoint1: pt(0.52, 0.27), controlPoint2: pt(0.57, 0.22))
        p.addCurve(to: pt(0.80, 0.38), controlPoint1: pt(0.72, 0.22), controlPoint2: pt(0.80, 0.28))
        p.addCurve(to: pt(0.50, 0.76), controlPoint1: pt(0.80, 0.48), controlPoint2: pt(0.70, 0.60))
        p.close()
        return p
    }

    private static func drawRepeat(s: CGFloat, w: CGFloat, one: Bool) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: x * s, y: y * s)
        }
        func loop(_ path: UIBezierPath) {
            path.lineWidth = w
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        let top = UIBezierPath()
        top.move(to: pt(0.68, 0.36))
        top.addLine(to: pt(0.32, 0.36))
        loop(top)
        let h1 = UIBezierPath()
        h1.move(to: pt(0.68, 0.36))
        h1.addLine(to: pt(0.60, 0.295))
        h1.move(to: pt(0.68, 0.36))
        h1.addLine(to: pt(0.60, 0.425))
        loop(h1)
        loop(UIBezierPath(arcCenter: pt(0.32, 0.50), radius: 0.14 * s,
                          startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: true))
        let bot = UIBezierPath()
        bot.move(to: pt(0.68, 0.64))
        bot.addLine(to: pt(0.32, 0.64))
        loop(bot)
        let h2 = UIBezierPath()
        h2.move(to: pt(0.32, 0.64))
        h2.addLine(to: pt(0.40, 0.575))
        h2.move(to: pt(0.32, 0.64))
        h2.addLine(to: pt(0.40, 0.705))
        loop(h2)
        if one {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            ("1" as NSString).draw(in: CGRect(x: 0.37 * s, y: 0.33 * s, width: 0.30 * s, height: 0.34 * s),
                                   withAttributes: [.font: UIFont.boldSystemFont(ofSize: 0.30 * s),
                                                    .foregroundColor: UIColor.white,
                                                    .paragraphStyle: style])
        }
    }
}
