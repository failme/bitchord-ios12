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
        case musicNote, headphones, download
        case house, compass, library, list, gear
        case grid, books, person, personOutline, logo
        case people, peopleOutline, plug, wifi, mobileData, dolby
        case history, folder, spotify
        case downloadArrow
        case globe, cast, bubble, speaker, sliders
        case share, radio, trash, info
        case check, checkCircle, circle
        case lyricsQuote, queue
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
            // Upstream's `ic_player_play`: one rounded triangle, not a sharp
            // Material play arrow.
            roundedTriangle(pt(0.333, 0.252), pt(0.729, 0.500), pt(0.333, 0.748),
                            radius: 0.058 * s).fill()
        case .pause:
            UIBezierPath(roundedRect: CGRect(x: 0.297 * s, y: 0.250 * s,
                                             width: 0.167 * s, height: 0.500 * s),
                         cornerRadius: 0.0417 * s).fill()
            UIBezierPath(roundedRect: CGRect(x: 0.536 * s, y: 0.250 * s,
                                             width: 0.167 * s, height: 0.500 * s),
                         cornerRadius: 0.0417 * s).fill()
        case .previous:
            // `ic_player_previous`: two rounded wedges, no centre bar. The bar
            // was the single most obvious glyph mismatch in the transport.
            roundedTriangle(pt(0.942, 0.217), pt(0.519, 0.501), pt(0.942, 0.783),
                            radius: 0.058 * s).fill()
            roundedTriangle(pt(0.505, 0.217), pt(0.082, 0.501), pt(0.505, 0.783),
                            radius: 0.058 * s).fill()
        case .next:
            roundedTriangle(pt(0.058, 0.217), pt(0.481, 0.501), pt(0.058, 0.783),
                            radius: 0.058 * s).fill()
            roundedTriangle(pt(0.495, 0.217), pt(0.918, 0.501), pt(0.495, 0.783),
                            radius: 0.058 * s).fill()
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
            // The real tab is a solid house with the door knocked out, not an
            // outline. Clear-blending the door leaves the bar showing through.
            UIBezierPath(roundedRect: CGRect(x: 0.20 * s, y: 0.43 * s,
                                             width: 0.60 * s, height: 0.41 * s),
                         cornerRadius: 0.05 * s).fill()
            roundedTriangle(pt(0.10, 0.52), pt(0.50, 0.14), pt(0.90, 0.52),
                            radius: 0.07 * s).fill()
            cg.saveGState()
            cg.setBlendMode(.clear)
            UIBezierPath(roundedRect: CGRect(x: 0.43 * s, y: 0.61 * s,
                                             width: 0.14 * s, height: 0.23 * s),
                         cornerRadius: 0.025 * s).fill()
            cg.restoreGState()
        case .compass:
            stroke(UIBezierPath(ovalIn: CGRect(x: 0.23 * s, y: 0.23 * s, width: 0.54 * s, height: 0.54 * s)))
            let n = UIBezierPath()
            n.move(to: pt(0.62, 0.38))
            n.addLine(to: pt(0.55, 0.55))
            n.addLine(to: pt(0.38, 0.62))
            n.addLine(to: pt(0.45, 0.45))
            n.close()
            n.fill()
        case .grid:
            // Four solid tiles with a narrow gutters, exactly the tab glyph's
            // proportions from the 512-unit source path.
            let side = 0.35 * s
            for (x, y) in [(0.115, 0.115), (0.535, 0.115),
                           (0.115, 0.535), (0.535, 0.535)] {
                let tile = UIBezierPath(roundedRect: CGRect(x: x * s, y: y * s,
                                                            width: side, height: side),
                                        cornerRadius: 0.045 * s)
                tile.fill()
            }
        case .books:
            // The real Library tab is one solid book with two pages above it,
            // not the three spines the first pass drew.
            UIBezierPath(roundedRect: CGRect(x: 0.30 * s, y: 0.08 * s,
                                             width: 0.40 * s, height: 0.07 * s),
                         cornerRadius: 0.035 * s).fill()
            UIBezierPath(roundedRect: CGRect(x: 0.22 * s, y: 0.19 * s,
                                             width: 0.56 * s, height: 0.09 * s),
                         cornerRadius: 0.045 * s).fill()
            UIBezierPath(roundedRect: CGRect(x: 0.13 * s, y: 0.32 * s,
                                             width: 0.74 * s, height: 0.60 * s),
                         cornerRadius: 0.13 * s).fill()
        case .share:
            let box = UIBezierPath()
            box.move(to: pt(0.30, 0.44))
            box.addLine(to: pt(0.30, 0.82))
            box.addLine(to: pt(0.70, 0.82))
            box.addLine(to: pt(0.70, 0.44))
            stroke(box)
            let arrow = UIBezierPath()
            arrow.move(to: pt(0.50, 0.16))
            arrow.addLine(to: pt(0.50, 0.58))
            arrow.move(to: pt(0.36, 0.30))
            arrow.addLine(to: pt(0.50, 0.16))
            arrow.addLine(to: pt(0.64, 0.30))
            stroke(arrow)
        case .radio:
            UIBezierPath(ovalIn: CGRect(x: 0.43 * s, y: 0.43 * s,
                                        width: 0.14 * s, height: 0.14 * s)).fill()
            for radius in [0.18, 0.32] {
                let arc = UIBezierPath(arcCenter: pt(0.50, 0.50), radius: CGFloat(radius) * s,
                                       startAngle: -0.75, endAngle: 0.75, clockwise: true)
                stroke(arc, width: w * 0.8)
                let back = UIBezierPath(arcCenter: pt(0.50, 0.50), radius: CGFloat(radius) * s,
                                        startAngle: .pi - 0.75, endAngle: .pi + 0.75, clockwise: true)
                stroke(back, width: w * 0.8)
            }
        case .trash:
            let lid = UIBezierPath()
            lid.move(to: pt(0.20, 0.28))
            lid.addLine(to: pt(0.80, 0.28))
            lid.move(to: pt(0.38, 0.20))
            lid.addLine(to: pt(0.62, 0.20))
            stroke(lid)
            let can = UIBezierPath()
            can.move(to: pt(0.28, 0.36))
            can.addLine(to: pt(0.32, 0.82))
            can.addLine(to: pt(0.68, 0.82))
            can.addLine(to: pt(0.72, 0.36))
            stroke(can)
            for x: CGFloat in [0.44, 0.56] {
                let line = UIBezierPath()
                line.move(to: pt(x, 0.46))
                line.addLine(to: pt(x, 0.70))
                stroke(line, width: w * 0.7)
            }
        case .check:
            let check = UIBezierPath()
            check.move(to: pt(0.22, 0.52))
            check.addLine(to: pt(0.42, 0.72))
            check.addLine(to: pt(0.79, 0.30))
            stroke(check, width: w * 1.15)
        case .circle:
            stroke(UIBezierPath(ovalIn: CGRect(x: 0.12 * s, y: 0.12 * s,
                                               width: 0.76 * s, height: 0.76 * s)))
        case .checkCircle:
            UIBezierPath(ovalIn: CGRect(x: 0.10 * s, y: 0.10 * s,
                                        width: 0.80 * s, height: 0.80 * s)).fill()
            cg.saveGState()
            cg.setBlendMode(.clear)
            let check = UIBezierPath()
            check.move(to: pt(0.29, 0.52))
            check.addLine(to: pt(0.44, 0.67))
            check.addLine(to: pt(0.72, 0.36))
            check.lineWidth = w * 1.2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
            cg.restoreGState()
        case .info:
            stroke(UIBezierPath(ovalIn: CGRect(x: 0.18 * s, y: 0.18 * s,
                                               width: 0.64 * s, height: 0.64 * s)))
            let i = UIBezierPath()
            i.move(to: pt(0.50, 0.46))
            i.addLine(to: pt(0.50, 0.68))
            stroke(i)
            UIBezierPath(ovalIn: CGRect(x: 0.46 * s, y: 0.30 * s,
                                        width: 0.08 * s, height: 0.08 * s)).fill()
        case .sliders:
            for (y, knobX) in [(0.30, 0.36), (0.50, 0.64), (0.70, 0.44)] {
                let line = UIBezierPath()
                line.move(to: pt(0.18, CGFloat(y)))
                line.addLine(to: pt(0.82, CGFloat(y)))
                stroke(line, width: w * 0.8)
                UIBezierPath(ovalIn: CGRect(x: (CGFloat(knobX) - 0.075) * s,
                                            y: (CGFloat(y) - 0.075) * s,
                                            width: 0.15 * s, height: 0.15 * s)).fill()
            }
        case .globe:
            stroke(UIBezierPath(ovalIn: CGRect(x: 0.18 * s, y: 0.18 * s, width: 0.64 * s, height: 0.64 * s)))
            let meridian = UIBezierPath(ovalIn: CGRect(x: 0.34 * s, y: 0.18 * s, width: 0.32 * s, height: 0.64 * s))
            stroke(meridian, width: w * 0.8)
            let equator = UIBezierPath()
            equator.move(to: pt(0.18, 0.50))
            equator.addLine(to: pt(0.82, 0.50))
            stroke(equator, width: w * 0.8)
        case .cast:
            let frame = UIBezierPath()
            frame.move(to: pt(0.22, 0.34))
            frame.addLine(to: pt(0.22, 0.26))
            frame.addLine(to: pt(0.78, 0.26))
            frame.addLine(to: pt(0.78, 0.74))
            frame.addLine(to: pt(0.56, 0.74))
            stroke(frame)
            let arc1 = UIBezierPath(arcCenter: pt(0.26, 0.74), radius: 0.10 * s,
                                    startAngle: -.pi / 2, endAngle: -.pi, clockwise: false)
            stroke(arc1, width: w * 0.85)
            let arc2 = UIBezierPath(arcCenter: pt(0.26, 0.74), radius: 0.20 * s,
                                    startAngle: -.pi / 2, endAngle: -.pi, clockwise: false)
            stroke(arc2, width: w * 0.85)
            UIBezierPath(ovalIn: CGRect(x: 0.22 * s, y: 0.70 * s, width: 0.09 * s, height: 0.09 * s)).fill()
        case .bubble:
            let bubble = UIBezierPath(roundedRect: CGRect(x: 0.15 * s, y: 0.16 * s, width: 0.70 * s, height: 0.58 * s),
                                      cornerRadius: 0.18 * s)
            stroke(bubble, width: w * 0.95)
            let tail = UIBezierPath()
            tail.move(to: pt(0.34, 0.72))
            tail.addLine(to: pt(0.30, 0.83))
            tail.addLine(to: pt(0.46, 0.74))
            stroke(tail, width: w * 0.9)
            for dx in [-0.14, 0.0, 0.14] {
                UIBezierPath(ovalIn: CGRect(x: (0.5 + CGFloat(dx) - 0.038) * s, y: 0.445 * s,
                                            width: 0.076 * s, height: 0.076 * s)).fill()
            }
        case .lyricsQuote:
            // `bc_lyrics_quote`: a speech bubble with two quote marks, the
            // tile's glyph in the real action row.
            let bubble = UIBezierPath()
            bubble.move(to: pt(0.25, 0.1458))
            bubble.addLine(to: pt(0.75, 0.1458))
            bubble.addQuadCurve(to: pt(0.875, 0.2708), controlPoint: pt(0.875, 0.1458))
            bubble.addLine(to: pt(0.875, 0.625))
            bubble.addQuadCurve(to: pt(0.75, 0.75), controlPoint: pt(0.875, 0.75))
            bubble.addLine(to: pt(0.4167, 0.75))
            bubble.addLine(to: pt(0.25, 0.875))
            bubble.addLine(to: pt(0.25, 0.75))
            bubble.addQuadCurve(to: pt(0.125, 0.625), controlPoint: pt(0.125, 0.75))
            bubble.addLine(to: pt(0.125, 0.2708))
            bubble.addQuadCurve(to: pt(0.25, 0.1458), controlPoint: pt(0.125, 0.1458))
            bubble.close()
            stroke(bubble, width: 2.0 / 24.0 * s)
            for x: CGFloat in [7.6 / 24.0, 12.8 / 24.0] {
                let quote = UIBezierPath()
                quote.move(to: pt(x, 0.3333))
                quote.addLine(to: pt(x + 0.125, 0.3333))
                quote.addLine(to: pt(x + 0.125, 0.4625))
                quote.addQuadCurve(to: pt(x + 0.0208, 0.5708),
                                   controlPoint: pt(x + 0.125, 0.55))
                quote.addLine(to: pt(x + 0.0208, 0.5125))
                quote.addQuadCurve(to: pt(x + 0.0708, 0.4583),
                                   controlPoint: pt(x + 0.0708, 0.5))
                quote.addLine(to: pt(x, 0.4583))
                quote.close()
                quote.fill()
            }
        case .queue:
            for y: CGFloat in [0.25, 0.50, 0.75] {
                let line = UIBezierPath()
                line.move(to: pt(0.3333, y))
                line.addLine(to: pt(0.875, y))
                stroke(line, width: 2.0 / 24.0 * s)
                UIBezierPath(ovalIn: CGRect(x: (0.1292 - 0.0521) * s,
                                            y: (y - 0.0521) * s,
                                            width: 0.1042 * s, height: 0.1042 * s)).fill()
            }
        case .speaker:
            let body = UIBezierPath()
            body.move(to: pt(0.20, 0.40))
            body.addLine(to: pt(0.34, 0.40))
            body.addLine(to: pt(0.50, 0.26))
            body.addLine(to: pt(0.50, 0.74))
            body.addLine(to: pt(0.34, 0.60))
            body.addLine(to: pt(0.20, 0.60))
            body.close()
            body.fill()
            for radius in [0.16, 0.28] {
                let wave = UIBezierPath(arcCenter: pt(0.50, 0.50), radius: CGFloat(radius) * s,
                                        startAngle: -0.9, endAngle: 0.9, clockwise: true)
                stroke(wave, width: w * 0.85)
            }
        case .globe:
            stroke(UIBezierPath(ovalIn: CGRect(x: 0.18 * s, y: 0.18 * s, width: 0.64 * s, height: 0.64 * s)))
            let meridian = UIBezierPath(ovalIn: CGRect(x: 0.34 * s, y: 0.18 * s, width: 0.32 * s, height: 0.64 * s))
            stroke(meridian, width: w * 0.8)
            let equator = UIBezierPath()
            equator.move(to: pt(0.18, 0.50))
            equator.addLine(to: pt(0.82, 0.50))
            stroke(equator, width: w * 0.8)
        case .cast:
            let frame = UIBezierPath()
            frame.move(to: pt(0.22, 0.34))
            frame.addLine(to: pt(0.22, 0.26))
            frame.addLine(to: pt(0.78, 0.26))
            frame.addLine(to: pt(0.78, 0.74))
            frame.addLine(to: pt(0.56, 0.74))
            stroke(frame)
            let arc1 = UIBezierPath(arcCenter: pt(0.26, 0.74), radius: 0.10 * s,
                                    startAngle: -.pi / 2, endAngle: -.pi, clockwise: false)
            stroke(arc1, width: w * 0.85)
            let arc2 = UIBezierPath(arcCenter: pt(0.26, 0.74), radius: 0.20 * s,
                                    startAngle: -.pi / 2, endAngle: -.pi, clockwise: false)
            stroke(arc2, width: w * 0.85)
            UIBezierPath(ovalIn: CGRect(x: 0.22 * s, y: 0.70 * s, width: 0.09 * s, height: 0.09 * s)).fill()
        case .bubble:
            let box = UIBezierPath(roundedRect: CGRect(x: 0.16 * s, y: 0.18 * s, width: 0.68 * s, height: 0.56 * s),
                                   cornerRadius: 0.16 * s)
            box.fill()
            for dx in [-0.14, 0.0, 0.14] {
                UIBezierPath(ovalIn: CGRect(x: (0.5 + CGFloat(dx) - 0.035) * s, y: 0.44 * s,
                                            width: 0.07 * s, height: 0.07 * s)).fill()
            }
        case .speaker:
            let body = UIBezierPath()
            body.move(to: pt(0.20, 0.40))
            body.addLine(to: pt(0.34, 0.40))
            body.addLine(to: pt(0.50, 0.26))
            body.addLine(to: pt(0.50, 0.74))
            body.addLine(to: pt(0.34, 0.60))
            body.addLine(to: pt(0.20, 0.60))
            body.close()
            body.fill()
            for radius in [0.16, 0.28] {
                let wave = UIBezierPath(arcCenter: pt(0.50, 0.50), radius: CGFloat(radius) * s,
                                        startAngle: -0.9, endAngle: 0.9, clockwise: true)
                stroke(wave, width: w * 0.85)
            }
        case .personOutline:
            // The outline account glyph every real header and Settings row
            // uses; the filled silhouette merged into a blob at 18pt.
            let head = UIBezierPath(ovalIn: CGRect(x: 0.34 * s, y: 0.18 * s,
                                                   width: 0.32 * s, height: 0.32 * s))
            stroke(head, width: w * 0.9)
            let shoulders = UIBezierPath()
            shoulders.move(to: pt(0.18, 0.82))
            shoulders.addCurve(to: pt(0.82, 0.82),
                               controlPoint1: pt(0.20, 0.52), controlPoint2: pt(0.80, 0.52))
            stroke(shoulders, width: w * 0.9)
        case .peopleOutline:
            let backHead = UIBezierPath(ovalIn: CGRect(x: 0.16 * s, y: 0.24 * s,
                                                       width: 0.22 * s, height: 0.22 * s))
            stroke(backHead, width: w * 0.75)
            let back = UIBezierPath()
            back.move(to: pt(0.08, 0.72))
            back.addCurve(to: pt(0.46, 0.72),
                          controlPoint1: pt(0.10, 0.50), controlPoint2: pt(0.44, 0.50))
            stroke(back, width: w * 0.75)
            let frontHead = UIBezierPath(ovalIn: CGRect(x: 0.50 * s, y: 0.28 * s,
                                                        width: 0.28 * s, height: 0.28 * s))
            stroke(frontHead, width: w * 0.85)
            let front = UIBezierPath()
            front.move(to: pt(0.38, 0.82))
            front.addCurve(to: pt(0.90, 0.82),
                           controlPoint1: pt(0.40, 0.56), controlPoint2: pt(0.88, 0.56))
            stroke(front, width: w * 0.85)
        case .people:
            // Two overlapping listeners: the back head and shoulders, then the
            // front silhouette, matching the Listen together row's glyph.
            UIBezierPath(ovalIn: CGRect(x: 0.22 * s, y: 0.22 * s, width: 0.24 * s, height: 0.24 * s)).fill()
            let back = UIBezierPath()
            back.move(to: pt(0.10, 0.78))
            back.addCurve(to: pt(0.58, 0.78), controlPoint1: pt(0.10, 0.48), controlPoint2: pt(0.58, 0.48))
            back.close()
            back.fill()
            UIBezierPath(ovalIn: CGRect(x: 0.50 * s, y: 0.30 * s, width: 0.26 * s, height: 0.26 * s)).fill()
            let front = UIBezierPath()
            front.move(to: pt(0.38, 0.82))
            front.addCurve(to: pt(0.90, 0.82), controlPoint1: pt(0.38, 0.56), controlPoint2: pt(0.90, 0.56))
            front.close()
            front.fill()
        case .plug:
            // A power plug, for Sources.
            let body = UIBezierPath(roundedRect: CGRect(x: 0.16 * s, y: 0.34 * s,
                                                        width: 0.42 * s, height: 0.32 * s),
                                    cornerRadius: 0.10 * s)
            stroke(body, width: w * 0.95)
            let prongs = UIBezierPath()
            prongs.move(to: pt(0.58, 0.42))
            prongs.addLine(to: pt(0.80, 0.42))
            prongs.move(to: pt(0.58, 0.58))
            prongs.addLine(to: pt(0.80, 0.58))
            prongs.move(to: pt(0.16, 0.50))
            prongs.addLine(to: pt(0.06, 0.50))
            stroke(prongs, width: w * 0.95)
        case .wifi:
            let centre = pt(0.50, 0.76)
            for radius in [0.16, 0.30, 0.44] {
                let arc = UIBezierPath(arcCenter: centre, radius: radius * s,
                                       startAngle: -3 * .pi / 4, endAngle: -.pi / 4,
                                       clockwise: true)
                stroke(arc, width: w * 0.9)
            }
            UIBezierPath(ovalIn: CGRect(x: 0.44 * s, y: 0.70 * s,
                                        width: 0.12 * s, height: 0.12 * s)).fill()
        case .mobileData:
            for (index, height) in [0.16, 0.28, 0.40, 0.52].enumerated() {
                let bar = UIBezierPath(roundedRect: CGRect(x: (0.18 + CGFloat(index) * 0.17) * s,
                                                           y: (0.78 - CGFloat(height)) * s,
                                                           width: 0.10 * s,
                                                           height: CGFloat(height) * s),
                                       cornerRadius: 0.03 * s)
                bar.fill()
            }
        case .dolby:
            // The double-D mark beside Dolby Atmos.
            for x: CGFloat in [0.18, 0.50] {
                let d = UIBezierPath()
                d.move(to: pt(x, 0.30))
                d.addLine(to: pt(x + 0.10, 0.30))
                d.addArc(withCenter: pt(x + 0.10, 0.50), radius: 0.20 * s,
                         startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
                d.addLine(to: pt(x, 0.70))
                stroke(d, width: w * 0.85)
            }
        case .downloadArrow:
            // The solid download glyph in the Downloads empty-state hero: a
            // wide head and short shaft, not the small tray used in rows.
            UIBezierPath(roundedRect: CGRect(x: 0.43 * s, y: 0.24 * s,
                                             width: 0.14 * s, height: 0.30 * s),
                         cornerRadius: 0.04 * s).fill()
            roundedTriangle(pt(0.09, 0.48), pt(0.50, 0.76), pt(0.91, 0.48),
                            radius: 0.045 * s).fill()
        case .person:
            UIBezierPath(ovalIn: CGRect(x: 0.36 * s, y: 0.20 * s, width: 0.28 * s, height: 0.28 * s)).fill()
            let shoulders = UIBezierPath()
            shoulders.move(to: pt(0.20, 0.80))
            shoulders.addCurve(to: pt(0.80, 0.80), controlPoint1: pt(0.20, 0.48), controlPoint2: pt(0.80, 0.48))
            shoulders.close()
            shoulders.fill()
        case .history:
            // A clock face, the glyph in the Library header's history button.
            stroke(UIBezierPath(ovalIn: CGRect(x: 0.22 * s, y: 0.22 * s, width: 0.56 * s, height: 0.56 * s)))
            let hand = UIBezierPath()
            hand.move(to: pt(0.50, 0.50))
            hand.addLine(to: pt(0.50, 0.32))
            hand.move(to: pt(0.50, 0.50))
            hand.addLine(to: pt(0.63, 0.57))
            stroke(hand, width: w * 0.85)
        case .folder:
            // A filled folder with its tab, the Local Music row's glyph.
            let tab = UIBezierPath(roundedRect: CGRect(x: 0.16 * s, y: 0.30 * s, width: 0.30 * s, height: 0.16 * s),
                                   cornerRadius: 0.04 * s)
            tab.fill()
            let body = UIBezierPath(roundedRect: CGRect(x: 0.16 * s, y: 0.40 * s, width: 0.68 * s, height: 0.34 * s),
                                    cornerRadius: 0.06 * s)
            body.fill()
        case .spotify:
            // A filled disc with the three wave bars knocked out, so the tile
            // behind shows through them exactly as on the real import card.
            UIBezierPath(ovalIn: CGRect(x: 0.08 * s, y: 0.08 * s,
                                        width: 0.84 * s, height: 0.84 * s)).fill()
            cg.saveGState()
            cg.setBlendMode(.clear)
            for (index, y) in [0.38, 0.50, 0.62].enumerated() {
                let arc = UIBezierPath()
                arc.move(to: pt(0.26, CGFloat(y) + 0.03))
                arc.addCurve(to: pt(0.74, CGFloat(y) - 0.02),
                             controlPoint1: pt(0.42, CGFloat(y) - 0.05),
                             controlPoint2: pt(0.60, CGFloat(y) - 0.06))
                arc.lineWidth = (0.075 - CGFloat(index) * 0.012) * s
                arc.lineCapStyle = .round
                arc.stroke()
            }
            cg.restoreGState()
        case .logo:
            // The three stacked arcs the real app uses as its mark.
            for (index, radius) in [0.20, 0.34, 0.48].enumerated() {
                let arc = UIBezierPath(arcCenter: CGPoint(x: 0.5 * s, y: 0.86 * s),
                                       radius: CGFloat(radius) * s,
                                       startAngle: -.pi * 0.86, endAngle: -.pi * 0.14,
                                       clockwise: true)
                stroke(arc, width: 0.085 * s + CGFloat(2 - index) * 0.008 * s)
            }
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
        case .download:
            // Arrow into a tray, the glyph the real Downloads row uses.
            let shaft = UIBezierPath()
            shaft.move(to: pt(0.50, 0.20))
            shaft.addLine(to: pt(0.50, 0.56))
            stroke(shaft)
            let head = UIBezierPath()
            head.move(to: pt(0.35, 0.43))
            head.addLine(to: pt(0.50, 0.58))
            head.addLine(to: pt(0.65, 0.43))
            stroke(head)
            let tray = UIBezierPath()
            tray.move(to: pt(0.26, 0.62))
            tray.addLine(to: pt(0.26, 0.78))
            tray.addLine(to: pt(0.74, 0.78))
            tray.addLine(to: pt(0.74, 0.62))
            stroke(tray)
        case .headphones:
            let band = UIBezierPath(arcCenter: pt(0.50, 0.52), radius: 0.26 * s,
                                    startAngle: .pi, endAngle: 0, clockwise: true)
            stroke(band)
            UIBezierPath(roundedRect: CGRect(x: 0.20 * s, y: 0.48 * s, width: 0.10 * s, height: 0.24 * s),
                         cornerRadius: 0.05 * s).fill()
            UIBezierPath(roundedRect: CGRect(x: 0.70 * s, y: 0.48 * s, width: 0.10 * s, height: 0.24 * s),
                         cornerRadius: 0.05 * s).fill()
        case .gear:
            // Eight rounded teeth around a ring: teeth alone read as an
            // asterisk at bar-button size.
            for i in 0..<8 {
                cg.saveGState()
                cg.translateBy(x: 0.5 * s, y: 0.5 * s)
                cg.rotate(by: CGFloat(i) * .pi / 4)
                let tooth = UIBezierPath()
                tooth.move(to: CGPoint(x: 0, y: -0.235 * s))
                tooth.addLine(to: CGPoint(x: 0, y: -0.335 * s))
                tooth.lineWidth = 0.13 * s
                tooth.lineCapStyle = .round
                tooth.stroke()
                cg.restoreGState()
            }
            let ring = UIBezierPath(arcCenter: CGPoint(x: 0.5 * s, y: 0.5 * s),
                                    radius: 0.245 * s,
                                    startAngle: 0, endAngle: .pi * 2, clockwise: true)
            ring.lineWidth = 0.085 * s
            ring.stroke()
        }
    }

    /// A triangle whose corners have upstream's 56/960 radius. The arcs are
    /// tangent to the two edges at each vertex, which is how the Compose vector
    /// rounds the play and skip wedges.
    private static func roundedTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint,
                                        radius r: CGFloat) -> UIBezierPath {
        func pointTowards(_ from: CGPoint, _ to: CGPoint, _ distance: CGFloat) -> CGPoint {
            let dx = to.x - from.x, dy = to.y - from.y
            let length = max(0.0001, sqrt(dx * dx + dy * dy))
            return CGPoint(x: from.x + dx / length * distance,
                           y: from.y + dy / length * distance)
        }
        let path = CGMutablePath()
        path.move(to: pointTowards(a, b, r))
        path.addArc(tangent1End: b, tangent2End: c, radius: r)
        path.addArc(tangent1End: c, tangent2End: a, radius: r)
        path.addArc(tangent1End: a, tangent2End: b, radius: r)
        path.closeSubpath()
        return UIBezierPath(cgPath: path)
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
