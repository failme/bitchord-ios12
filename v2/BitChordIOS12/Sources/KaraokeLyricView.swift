import UIKit

/// One lyric line, drawn with a real karaoke sweep.
///
/// The text is drawn twice: a dim copy for the whole line, then a bright copy
/// clipped to exactly the characters that have been sung. Which characters
/// those are comes from the provider's own word and syllable timings — Apple
/// TTML from lrc.red, or LyricsPlus' syllabus — so nothing is interpolated
/// across the line and the highlight stops where the voice has actually got to.
final class KaraokeLineView: UIView {
    private var line: WordLyricLine
    private var font: UIFont
    private var paragraph: NSParagraphStyle

    private var storage: NSTextStorage?
    private var manager: NSLayoutManager?
    private var container: NSTextContainer?
    private var builtWidth: CGFloat = 0

    private let verticalPadding: CGFloat = 10

    /// Unsung text stays white and dimmed rather than turning grey; over the
    /// blurred cover that is what the real panel looks like.
    var dimmed: UIColor = UIColor(white: 1, alpha: 0.45) {
        didSet { setNeedsDisplay() }
    }

    /// Playback position this line is drawn at. Setting it repaints only when
    /// the revealed characters actually change, which is most ticks apart.
    var position: TimeInterval = 0 {
        didSet {
            guard Int(position * 20) != Int(oldValue * 20) else { return }
            setNeedsDisplay()
        }
    }

    init(line: WordLyricLine, font: UIFont) {
        self.line = line
        self.font = font
        self.paragraph = KaraokeLineView.style(for: font)
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("KaraokeLineView is created in code")
    }

    /// Swaps the text and type without rebuilding the view hierarchy. The cell
    /// owns one of these for its whole lifetime; only the TextKit layout is
    /// invalidated when the text or type actually changes.
    func update(line: WordLyricLine, font: UIFont) {
        self.line = line
        self.font = font
        self.paragraph = KaraokeLineView.style(for: font)
        storage = nil
        manager = nil
        container = nil
        builtWidth = 0
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// Timing-only refresh for a reused row with the same text and type. The
    /// TextKit layout and row height stay valid; only the sweep needs redrawing.
    func updateTiming(_ line: WordLyricLine) {
        self.line = line
        setNeedsDisplay()
    }

    private static func style(for font: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byWordWrapping
        // The line height tracks the type rather than staying at the old
        // 34pt-panel values, so compact lyrics also get compact rows.
        let lineHeight = KaraokeLineView.lineHeight(for: font)
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }

    private static func lineHeight(for font: UIFont) -> CGFloat {
        return max(font.lineHeight, font.pointSize * 1.2).rounded(.up)
    }

    static func height(text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let style = KaraokeLineView.style(for: font)
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: style],
            context: nil)
        return max(KaraokeLineView.lineHeight(for: font), ceil(bounds.height)) + 20
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(builtWidth - bounds.width) > 0.5 {
            buildLayout(width: bounds.width)
        }
    }

    private func buildLayout(width: CGFloat) {
        guard width > 0 else { return }
        let storage = NSTextStorage(string: line.text, attributes: [
            .font: font,
            .paragraphStyle: paragraph
        ])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        self.storage = storage
        self.manager = manager
        self.container = container
        builtWidth = width
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        // The view is reused for another row in place; make sure a shorter or
        // empty line cannot leave the previous line's pixels behind.
        context.clear(bounds)
        guard !line.text.isEmpty else { return }
        let textRect = CGRect(x: 0,
                              y: verticalPadding,
                              width: bounds.width,
                              height: max(0, bounds.height - verticalPadding * 2))

        let base: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: dimmed
        ]
        NSAttributedString(string: line.text, attributes: base).draw(in: textRect)

        let revealed = revealedRects(textRect: textRect)
        guard !revealed.isEmpty else { return }

        context.saveGState()
        context.clip(to: revealed)
        var sung = base
        sung[.foregroundColor] = Theme.primaryText
        NSAttributedString(string: line.text, attributes: sung).draw(in: textRect)
        context.restoreGState()
    }

    /// The pixel rects of every character sung at `position`. Word timings,
    /// syllable timings where the provider split the word.
    private func revealedRects(textRect: CGRect) -> [CGRect] {
        guard position > 0, let manager = manager, let container = container else { return [] }
        if line.words.isEmpty {
            guard position >= line.time else { return [] }
            return [textRect]
        }
        var rects: [CGRect] = []
        for word in line.words {
            if position <= word.start { break }
            if word.syllables.isEmpty || !SettingsStore.shared.prioritizeSyllableSync {
                let chars = position >= word.end
                    ? word.endChar - word.startChar
                    : Int((max(0, (position - word.start) / max(0.001, word.end - word.start)))
                          * Double(word.endChar - word.startChar))
                appendRects(&rects, from: word.startChar, count: chars,
                            textRect: textRect, manager: manager, container: container)
                continue
            }
            for syllable in word.syllables {
                if position <= syllable.start { break }
                let length = syllable.endChar - syllable.startChar
                let chars = position >= syllable.end
                    ? length
                    : Int((max(0, (position - syllable.start) / max(0.001, syllable.end - syllable.start)))
                          * Double(length))
                appendRects(&rects, from: syllable.startChar, count: chars,
                            textRect: textRect, manager: manager, container: container)
            }
        }
        return rects
    }

    private func appendRects(_ rects: inout [CGRect],
                             from charIndex: Int,
                             count: Int,
                             textRect: CGRect,
                             manager: NSLayoutManager,
                             container: NSTextContainer) {
        guard count > 0, charIndex >= 0, charIndex < line.text.count else { return }
        let length = min(count, line.text.count - charIndex)
        let charRange = NSRange(location: charIndex, length: length)
        let glyphRange = manager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }
        let rect = manager.boundingRect(forGlyphRange: glyphRange, in: container)
        guard rect.width > 0, rect.height > 0 else { return }
        rects.append(rect.offsetBy(dx: textRect.minX, dy: textRect.minY))
    }
}

/// A lyric table row: the karaoke line plus nothing else.
final class KaraokeLyricCell: UITableViewCell {
    static let reuseIdentifier = "KaraokeLyricCell"

    private let lineView: KaraokeLineView
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var configuredText = ""
    private var configuredFontName = ""
    private var configuredPointSize: CGFloat = 0
    private var configuredTiming = ""

    /// How the unsung part of the line is coloured for this row.
    var dimmed: UIColor = UIColor(white: 1, alpha: 0.45) {
        didSet { lineView.dimmed = dimmed }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let blank = WordLyricLine(time: 0, text: "", words: [], end: nil)
        lineView = KaraokeLineView(line: blank, font: Theme.font(30, weight: .heavy))
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        lineView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(lineView)
        leadingConstraint = lineView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                               constant: 30)
        trailingConstraint = lineView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                                 constant: -30)
        NSLayoutConstraint.activate([
            lineView.topAnchor.constraint(equalTo: contentView.topAnchor),
            leadingConstraint,
            trailingConstraint,
            lineView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("KaraokeLyricCell is created in code")
    }

    /// Updates the existing line view in place. The cell never removes and
    /// recreates its TextKit view when it is reused for another lyric row.
    func configure(line: WordLyricLine, font: UIFont, position: TimeInterval,
                   gutter: CGFloat, dimmed: UIColor) {
        // Position updates arrive at the display-link cadence. Only rebuild the
        // TextKit stack when the row actually changes text or type; otherwise
        // this is just a draw-invalidation and the 20Hz position guard stands.
        let timing = KaraokeLyricCell.timingKey(for: line)
        let textOrFontChanged = line.text != configuredText ||
            font.fontName != configuredFontName ||
            font.pointSize != configuredPointSize
        if textOrFontChanged {
            configuredText = line.text
            configuredFontName = font.fontName
            configuredPointSize = font.pointSize
            configuredTiming = timing
            lineView.update(line: line, font: font)
        } else if timing != configuredTiming {
            configuredTiming = timing
            lineView.updateTiming(line)
        }
        if !self.dimmed.isEqual(dimmed) { self.dimmed = dimmed }
        leadingConstraint.constant = gutter
        trailingConstraint.constant = -gutter
        lineView.position = position
    }

    func setPosition(_ position: TimeInterval) {
        lineView.position = position
    }

    /// Text and font are not the whole line: repeated chorus text has the same
    /// glyphs at a different time, and word/syllable timings live alongside the
    /// text. Include those so a reused cell cannot draw the previous row's
    /// timing under the new row's words.
    private static func timingKey(for line: WordLyricLine) -> String {
        var parts = ["\(line.time)", "\(line.end ?? -1)"]
        for word in line.words {
            parts.append("w:\(word.start),\(word.end),\(word.startChar),\(word.endChar)")
            for syllable in word.syllables {
                parts.append("s:\(syllable.start),\(syllable.end),\(syllable.startChar),\(syllable.endChar)")
            }
        }
        return parts.joined(separator: "|")
    }
}
