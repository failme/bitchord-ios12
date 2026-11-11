import UIKit

/// One lyric line, drawn with a real karaoke sweep.
///
/// The text is drawn twice: a dim copy for the whole line, then a bright copy
/// clipped to exactly the characters that have been sung. Which characters
/// those are comes from the provider's own word and syllable timings — Apple
/// TTML from lrc.red, or LyricsPlus' syllabus — so nothing is interpolated
/// across the line and the highlight stops where the voice has actually got to.
final class KaraokeLineView: UIView {
    private let line: WordLyricLine
    private let font: UIFont
    private let paragraph: NSParagraphStyle

    private var storage: NSTextStorage?
    private var manager: NSLayoutManager?
    private var container: NSTextContainer?
    private var builtWidth: CGFloat = 0

    private let verticalPadding: CGFloat = 6

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
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        self.paragraph = style
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        return nil
    }

    static func height(text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: style],
            context: nil)
        return ceil(bounds.height) + 12
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
        let textRect = CGRect(x: 0,
                              y: verticalPadding,
                              width: bounds.width,
                              height: max(0, bounds.height - verticalPadding * 2))

        let base: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: Theme.secondaryText
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
            if word.syllables.isEmpty {
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

    private var lineView: KaraokeLineView?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configure(line: WordLyricLine, font: UIFont, position: TimeInterval) {
        lineView?.removeFromSuperview()
        let view = KaraokeLineView(line: line, font: font)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.position = position
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        lineView = view
    }

    func setPosition(_ position: TimeInterval) {
        lineView?.position = position
    }
}
