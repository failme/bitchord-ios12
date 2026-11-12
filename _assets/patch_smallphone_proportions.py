import io

ROOT = 'C:/Users/natha/Downloads/bitios/'


def edit(path, pairs):
    p = ROOT + path
    t = io.open(p, encoding='utf-8').read()
    for old, new in pairs:
        if old not in t:
            raise SystemExit('MISSING in %s: %r' % (path, old[:70]))
        t = t.replace(old, new, 1)
    io.open(p, 'w', encoding='utf-8', newline='').write(t)
    print('ok', path)


# --- A. Karaoke: Apple writes "0.12s" and "12500ms" too; Double() chokes and
# every span silently drops, leaving whole-line-only lyrics.
edit('BitChordIOS12/Sources/TTMLLyrics.swift', [
    ('''        let raw = ns.substring(with: match.range(at: 1))
        // Apple writes either a plain second count or `hh:mm:ss.sss`.''',
     '''        let raw = ns.substring(with: match.range(at: 1))
        // Apple writes a plain second count, `hh:mm:ss.sss`, or a suffixed
        // count like `0.12s` / `12500ms`; the suffix must come off first.
        if raw.hasSuffix("ms"), let ms = Double(raw.dropLast(2)) {
            return ms / 1000
        }
        if raw.hasSuffix("s"), let secs = Double(raw.dropLast(1)) {
            return secs
        }
        // Apple writes either a plain second count or `hh:mm:ss.sss`.'''),
])

# --- B/C/D/E/F/H/I/J/L: the player panel.
edit('BitChordIOS12/Sources/NowPlayingViewController.swift', [
    # Squat screens (SE 568/667pt) get tighter vertical rhythm at build time.
    ('''    private func buildLayout() {
        backdropView.translatesAutoresizingMaskIntoConstraints = false''',
     '''    private func buildLayout() {
        let squat = UIScreen.main.bounds.height < 700
        let headerGap: CGFloat = squat ? 8 : 12
        let headerHeight: CGFloat = squat ? 52 : 56
        let lyricGap: CGFloat = squat ? 12 : 16
        let stackGap: CGFloat = squat ? 8 : 12
        let playSide: CGFloat = squat ? 56 : 64
        let footGap: CGFloat = squat ? 10 : 14
        let bottomGap: CGFloat = squat ? 16 : 26
        backdropView.translatesAutoresizingMaskIntoConstraints = false'''),
    # The 48pt cover never fit the 44pt header: unsatisfiable on every phone.
    ('''            compactHeader.heightAnchor.constraint(equalToConstant: 44),''',
     '''            compactHeader.heightAnchor.constraint(equalToConstant: headerHeight),'''),
    ('''            handle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),''',
     '''            handle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),'''),
    ('''            compactHeader.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 12),''',
     '''            compactHeader.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: headerGap),'''),
    ('''        headerArtwork.layer.cornerRadius = 6''',
     '''        headerArtwork.layer.cornerRadius = 10'''),
    # The ellipsis disc: a fixed 36pt target, dots to match the real size.
    ('''        toggleButton.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)''',
     '''        toggleButton.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)'''),
    ('''            toggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),''',
     '''            toggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toggleButton.widthAnchor.constraint(equalToConstant: 36),
            toggleButton.heightAnchor.constraint(equalToConstant: 36),'''),
    ('''        toggleButton.setImage(Icons.image(.ellipsis, size: 20), for: .normal)''',
     '''        toggleButton.setImage(Icons.image(.ellipsis, size: 18), for: .normal)'''),
    # Measure with the width the words are actually drawn at (32pt each side).
    ('''        let width = max(1, tableView.bounds.width - 48)''',
     '''        let width = max(1, tableView.bounds.width - 64)'''),
    # Measured off the real panel at 390pt wide: 31 bold sung, 22 semibold
    # waiting, stepping down on short screens so nothing clips or overlaps.
    ('''    static func lyricFont(active: Bool) -> UIFont {
        return active ? Theme.font(34, weight: .bold) : Theme.font(28, weight: .semibold)
    }''',
     '''    static func lyricFont(active: Bool) -> UIFont {
        let height = UIScreen.main.bounds.height
        if height < 600 {
            return active ? Theme.font(27, weight: .bold) : Theme.font(20, weight: .semibold)
        }
        if height < 750 {
            return active ? Theme.font(29, weight: .bold) : Theme.font(21, weight: .semibold)
        }
        return active ? Theme.font(31, weight: .bold) : Theme.font(22, weight: .semibold)
    }'''),
    # The provider credit is a link on the real panel.
    ('''            lyricsSourceLabel.text = service.lyricsSource.isEmpty
                ? nil
                : "Lyrics by " + service.lyricsSource''',
     '''            if service.lyricsSource.isEmpty {
                lyricsSourceLabel.attributedText = nil
            } else {
                lyricsSourceLabel.attributedText = NSAttributedString(
                    string: "Lyrics by " + service.lyricsSource,
                    attributes: [.font: Theme.font(13),
                                 .foregroundColor: Theme.secondaryText,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue])
            }'''),
    # Floating circles match the real 36pt.
    ('''            globeButton.widthAnchor.constraint(equalToConstant: 40),
            globeButton.heightAnchor.constraint(equalToConstant: 40),''',
     '''            globeButton.widthAnchor.constraint(equalToConstant: 36),
            globeButton.heightAnchor.constraint(equalToConstant: 36),'''),
    ('''            translitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),''',
     '''            translitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),'''),
    ('''            translitButton.widthAnchor.constraint(equalToConstant: 40),
            translitButton.heightAnchor.constraint(equalToConstant: 40),''',
     '''            translitButton.widthAnchor.constraint(equalToConstant: 36),
            translitButton.heightAnchor.constraint(equalToConstant: 36),'''),
    ('''        globeButton.setImage(Icons.image(.globe, size: 20), for: .normal)''',
     '''        globeButton.setImage(Icons.image(.globe, size: 18), for: .normal)'''),
    # Footer glyphs carry the real weight.
    ('''        modeButton.setImage(Icons.image(.bubble, size: 20), for: .normal)''',
     '''        modeButton.setImage(Icons.image(.bubble, size: 22), for: .normal)'''),
    ('''        outputButton.setImage(Icons.image(.cast, size: 20), for: .normal)''',
     '''        outputButton.setImage(Icons.image(.cast, size: 22), for: .normal)'''),
    ('''        configureTransportButton(likeButton, icon: .heart, size: 20, action: #selector(toggleLike))''',
     '''        configureTransportButton(likeButton, icon: .heart, size: 22, action: #selector(toggleLike))'''),
    ('''        configureTransportButton(queueButton, icon: .list, size: 20, action: #selector(showQueue))''',
     '''        configureTransportButton(queueButton, icon: .list, size: 22, action: #selector(showQueue))'''),
    # Tighten the bottom stack on short screens.
    ('''            playButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 12),''',
     '''            playButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: stackGap),'''),
    ('''            playButton.heightAnchor.constraint(equalToConstant: 64),
            playButton.widthAnchor.constraint(equalToConstant: 64),''',
     '''            playButton.heightAnchor.constraint(equalToConstant: playSide),
            playButton.widthAnchor.constraint(equalToConstant: playSide),'''),
    ('''            volumeSlider.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -14),''',
     '''            volumeSlider.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -footGap),'''),
    ('''            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -26),''',
     '''            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -bottomGap),'''),
    ('''            playButton.bottomAnchor.constraint(equalTo: volumeSlider.topAnchor, constant: -22),''',
     '''            playButton.bottomAnchor.constraint(equalTo: volumeSlider.topAnchor, constant: squat ? -14 : -22),'''),
    ('''        lyricsTopCompact = lyricsTable.topAnchor.constraint(equalTo: compactHeader.bottomAnchor,
                                                            constant: 16)''',
     '''        lyricsTopCompact = lyricsTable.topAnchor.constraint(equalTo: compactHeader.bottomAnchor,
                                                            constant: lyricGap)'''),
])

# --- G. Pause bars carry the real thickness.
edit('BitChordIOS12/Sources/Icons.swift', [
    ('''        case .pause:
            UIBezierPath(roundedRect: CGRect(x: 0.30 * s, y: 0.25 * s, width: 0.15 * s, height: 0.50 * s),
                         cornerRadius: 0.04 * s).fill()
            UIBezierPath(roundedRect: CGRect(x: 0.55 * s, y: 0.25 * s, width: 0.15 * s, height: 0.50 * s),
                         cornerRadius: 0.04 * s).fill()''',
     '''        case .pause:
            UIBezierPath(roundedRect: CGRect(x: 0.27 * s, y: 0.25 * s, width: 0.18 * s, height: 0.50 * s),
                         cornerRadius: 0.05 * s).fill()
            UIBezierPath(roundedRect: CGRect(x: 0.55 * s, y: 0.25 * s, width: 0.18 * s, height: 0.50 * s),
                         cornerRadius: 0.05 * s).fill()'''),
])

# --- F. The real scrubber is a 4pt track, not a 2pt hairline.
edit('BitChordIOS12/Sources/Theme.swift', [
    ('''    /// A 2pt track image: the thin-slider look in `UISlider` form (iOS 12-safe).
    static func trackImage(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 4, height: 2)''',
     '''    /// A 4pt track image: the thin-slider look in `UISlider` form (iOS 12-safe).
    static func trackImage(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 4, height: 4)'''),
])

# --- L. A breath between lines, as the real panel sets.
edit('BitChordIOS12/Sources/KaraokeLyricView.swift', [
    ('''    private let verticalPadding: CGFloat = 10''',
     '''    private let verticalPadding: CGFloat = 12'''),
    ('''        return ceil(bounds.height) + 20''',
     '''        return ceil(bounds.height) + 24'''),
])

y = ROOT + 'project.yml'
s = io.open(y, encoding='utf-8').read()
s = s.replace('MARKETING_VERSION: "1.26"', 'MARKETING_VERSION: "1.27"')
s = s.replace('CURRENT_PROJECT_VERSION: "27"', 'CURRENT_PROJECT_VERSION: "28"')
io.open(y, 'w', encoding='utf-8', newline='').write(s)
print('version 1.27 (28)')
