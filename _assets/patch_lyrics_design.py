import io

ROOT = 'C:/Users/natha/Downloads/bitios/'


def rw(p, pairs, optional=()):
    path = ROOT + p
    t = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        if old not in t:
            raise SystemExit('MISSING in %s: %r' % (p, old[:70]))
        t = t.replace(old, new, 1)
    for old, new in optional:
        if old in t:
            t = t.replace(old, new, 1)
    io.open(path, 'w', encoding='utf-8', newline='').write(t)
    print('ok', p)


# --- glyphs the real panel draws -----------------------------------------
rw('BitChordIOS12/Sources/Icons.swift', [
    ('        case grid, books, person, logo',
     '        case grid, books, person, logo\n        case globe, cast, bubble, speaker'),
    ('''        case .person:''',
     '''        case .globe:
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
        case .person:'''),
])

# --- words: left aligned, grey upcoming lines -----------------------------
rw('BitChordIOS12/Sources/KaraokeLyricView.swift', [
    ('''        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        self.paragraph = style''',
     '''        // The real panel sets lyrics ragged-right against the left gutter, not
        // centred, so both the measurement and the drawing use that alignment.
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byWordWrapping
        self.paragraph = style'''),
    ('''        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let bounds = (text as NSString).boundingRect(''',
     '''        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byWordWrapping
        let bounds = (text as NSString).boundingRect('''),
    ('''            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),''',
     '''            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),'''),
])

# --- panel chrome --------------------------------------------------------
rw('BitChordIOS12/Sources/NowPlayingViewController.swift', [
    ('''    private var lyricsTopDefault: NSLayoutConstraint?''',
     '''    private let handle = UIView()
    private let volumeSlider = UISlider()
    private let outputButton = UIButton(type: .system)
    private let outputLabel = UILabel()
    private let modeButton = UIButton(type: .system)
    private let globeButton = UIButton(type: .system)
    private let translitButton = UIButton(type: .system)
    private var lyricsTopDefault: NSLayoutConstraint?'''),
    ('''        compactHeader.translatesAutoresizingMaskIntoConstraints = false
        compactHeader.isHidden = true
        view.addSubview(compactHeader)''',
     '''        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.backgroundColor = UIColor(white: 1, alpha: 0.3)
        handle.layer.cornerRadius = 2.5
        handle.isHidden = true
        view.addSubview(handle)

        compactHeader.translatesAutoresizingMaskIntoConstraints = false
        compactHeader.isHidden = true
        view.addSubview(compactHeader)'''),
    ('''        // The real panel credits the provider under the words.''',
     '''        // Floating translation and transliteration buttons sit over the words.
        for button in [globeButton, translitButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.backgroundColor = UIColor(white: 1, alpha: 0.08)
            button.layer.cornerRadius = 20
            button.tintColor = UIColor(white: 1, alpha: 0.85)
            button.isHidden = true
            view.addSubview(button)
        }
        globeButton.setImage(Icons.image(.globe, size: 20), for: .normal)
        translitButton.titleLabel?.font = Theme.font(15, weight: .semibold)
        translitButton.setTitle("文A", for: .normal)
        translitButton.setTitleColor(UIColor(white: 1, alpha: 0.85), for: .normal)

        // Volume, then the three-icon footer the real panel ends on.
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.minimumTrackImage = Theme.trackImage(Theme.primaryText)
        volumeSlider.maximumTrackImage = Theme.trackImage(Theme.outline)
        volumeSlider.setThumbImage(Theme.thumbImage(), for: .normal)
        volumeSlider.value = 1
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        view.addSubview(volumeSlider)

        // The real footer starts with the lyrics bubble, which is how the panel
        // is opened and closed there too.
        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.tintColor = Theme.primaryText
        modeButton.setImage(Icons.image(.bubble, size: 20), for: .normal)
        modeButton.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)
        modeButton.isHidden = true
        view.addSubview(modeButton)

        outputButton.translatesAutoresizingMaskIntoConstraints = false
        outputButton.tintColor = Theme.primaryText
        outputButton.setImage(Icons.image(.cast, size: 20), for: .normal)
        outputButton.addTarget(self, action: #selector(showOutput), for: .touchUpInside)
        view.addSubview(outputButton)

        outputLabel.translatesAutoresizingMaskIntoConstraints = false
        outputLabel.text = "This phone"
        outputLabel.font = Theme.font(11)
        outputLabel.textColor = Theme.secondaryText
        outputLabel.textAlignment = .center
        view.addSubview(outputLabel)

        // The real panel credits the provider under the words.'''),
    ('''            compactHeader.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),''',
     '''            handle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 5),

            compactHeader.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 12),'''),
    ('''            lyricsTable.topAnchor.constraint(equalTo: compactHeader.bottomAnchor,
                                                            constant: 12)''',
     '''            lyricsTable.topAnchor.constraint(equalTo: compactHeader.bottomAnchor,
                                                            constant: 16)'''),
    ('''            playButton.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -24),''',
     '''            volumeSlider.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -14),
            volumeSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 44),
            volumeSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -44),
            volumeSlider.heightAnchor.constraint(equalToConstant: 18),

            playButton.bottomAnchor.constraint(equalTo: volumeSlider.topAnchor, constant: -22),

            globeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            globeButton.bottomAnchor.constraint(equalTo: lyricsSourceLabel.topAnchor, constant: -10),
            globeButton.widthAnchor.constraint(equalToConstant: 40),
            globeButton.heightAnchor.constraint(equalToConstant: 40),

            translitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            translitButton.centerYAnchor.constraint(equalTo: globeButton.centerYAnchor),
            translitButton.widthAnchor.constraint(equalToConstant: 40),
            translitButton.heightAnchor.constraint(equalToConstant: 40),

            modeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            modeButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 44),
            modeButton.heightAnchor.constraint(equalToConstant: 44),

            outputButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            outputButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            outputButton.widthAnchor.constraint(equalToConstant: 44),
            outputButton.heightAnchor.constraint(equalToConstant: 44),

            outputLabel.topAnchor.constraint(equalTo: outputButton.bottomAnchor, constant: -6),
            outputLabel.centerXAnchor.constraint(equalTo: outputButton.centerXAnchor),'''),
    ('''            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -4),''',
     '''            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -26),'''),
    # Show the panel's own chrome only in lyrics mode.
    ('''        lyricsTopCompact?.isActive = lyrics''',
     '''        handle.isHidden = !lyrics
        globeButton.isHidden = !lyrics
        translitButton.isHidden = !lyrics
        volumeSlider.isHidden = !lyrics
        outputButton.isHidden = !lyrics
        outputLabel.isHidden = !lyrics
        shuffleButton.isHidden = lyrics
        repeatButton.isHidden = lyrics
        likeButton.isHidden = lyrics
        modeButton.isHidden = !lyrics
        // The real header ends in an ellipsis, not a worded toggle.
        toggleButton.setTitle(nil, for: .normal)
        toggleButton.setImage(Icons.image(.ellipsis, size: 20), for: .normal)
        lyricsTopCompact?.isActive = lyrics'''),
    ('''    @objc private func toggleMode() {''',
     '''    @objc private func volumeChanged() {
        AudioEngine.shared.setVolume(volumeSlider.value)
    }

    @objc private func showOutput() {
        let alert = UIAlertController(title: "Audio output",
                                      message: "Playing on this phone.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    @objc private func toggleMode() {'''),
])

y = ROOT + 'project.yml'
t = io.open(y, encoding='utf-8').read()
t = t.replace('MARKETING_VERSION: "1.21"', 'MARKETING_VERSION: "1.22"')
t = t.replace('CURRENT_PROJECT_VERSION: "22"', 'CURRENT_PROJECT_VERSION: "23"')
io.open(y, 'w', encoding='utf-8', newline='').write(t)
print('version 1.22 (23)')
