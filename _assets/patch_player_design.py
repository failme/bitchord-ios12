import io

ROOT = 'C:/Users/natha/Downloads/bitios/'

# --- undo the duplicated enum cases from the aborted attempt -------------
p = ROOT + 'BitChordIOS12/Sources/Icons.swift'
t = io.open(p, encoding='utf-8').read()
dup = ('        case grid, books, person, logo\n'
       '        case globe, cast, bubble, speaker\n'
       '        case globe, cast, bubble, speaker')
if dup in t:
    t = t.replace(dup, '        case grid, books, person, logo\n'
                       '        case globe, cast, bubble, speaker', 1)
    io.open(p, 'w', encoding='utf-8', newline='').write(t)
    print('deduped case list')

# --- player design -------------------------------------------------------
p = ROOT + 'BitChordIOS12/Sources/NowPlayingViewController.swift'
t = io.open(p, encoding='utf-8').read()


def need(old, new):
    global t
    if old not in t:
        raise SystemExit('MISSING: %r' % (old[:70],))
    t = t.replace(old, new, 1)


need('    private var lyricsTopDefault: NSLayoutConstraint?',
     '''    private let handle = UIView()
    private let volumeSlider = UISlider()
    private let outputButton = UIButton(type: .system)
    private let outputLabel = UILabel()
    private let modeButton = UIButton(type: .system)
    private let globeButton = UIButton(type: .system)
    private let translitButton = UIButton(type: .system)
    private var lyricsTopDefault: NSLayoutConstraint?''')

need('        compactHeader.translatesAutoresizingMaskIntoConstraints = false',
     '''        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.backgroundColor = UIColor(white: 1, alpha: 0.3)
        handle.layer.cornerRadius = 2.5
        handle.isHidden = true
        view.addSubview(handle)

        compactHeader.translatesAutoresizingMaskIntoConstraints = false''')

need('        // The real panel credits the provider under the words.',
     '''        for button in [globeButton, translitButton] {
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

        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.minimumTrackImage = Theme.trackImage(Theme.primaryText)
        volumeSlider.maximumTrackImage = Theme.trackImage(Theme.outline)
        volumeSlider.setThumbImage(Theme.thumbImage(), for: .normal)
        volumeSlider.value = 1
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        view.addSubview(volumeSlider)

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

        // The real panel credits the provider under the words.''')

need('            compactHeader.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),',
     '''            handle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 5),

            compactHeader.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 12),''')

need('''        lyricsTopCompact = lyricsTable.topAnchor.constraint(equalTo: compactHeader.bottomAnchor,
                                                            constant: 12)''',
     '''        lyricsTopCompact = lyricsTable.topAnchor.constraint(equalTo: compactHeader.bottomAnchor,
                                                            constant: 16)''')

need('            playButton.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -24),',
     '''            volumeSlider.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -14),
            volumeSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 44),
            volumeSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -44),
            volumeSlider.heightAnchor.constraint(equalToConstant: 18),

            playButton.bottomAnchor.constraint(equalTo: volumeSlider.topAnchor, constant: -22),

            modeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            modeButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 44),
            modeButton.heightAnchor.constraint(equalToConstant: 44),

            outputButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            outputButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            outputButton.widthAnchor.constraint(equalToConstant: 44),
            outputButton.heightAnchor.constraint(equalToConstant: 44),

            outputLabel.topAnchor.constraint(equalTo: outputButton.bottomAnchor, constant: -6),
            outputLabel.centerXAnchor.constraint(equalTo: outputButton.centerXAnchor),

            globeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            globeButton.bottomAnchor.constraint(equalTo: lyricsSourceLabel.topAnchor, constant: -10),
            globeButton.widthAnchor.constraint(equalToConstant: 40),
            globeButton.heightAnchor.constraint(equalToConstant: 40),

            translitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            translitButton.centerYAnchor.constraint(equalTo: globeButton.centerYAnchor),
            translitButton.widthAnchor.constraint(equalToConstant: 40),
            translitButton.heightAnchor.constraint(equalToConstant: 40),''')

need('            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -4),',
     '            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -26),')

need('        lyricsTopCompact?.isActive = lyrics',
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
        toggleButton.setTitle(nil, for: .normal)
        toggleButton.setImage(Icons.image(.ellipsis, size: 20), for: .normal)
        lyricsTopCompact?.isActive = lyrics''')

need('    @objc private func toggleMode() {',
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

    @objc private func toggleMode() {''')

io.open(p, 'w', encoding='utf-8', newline='').write(t)
print('ok player design')

y = ROOT + 'project.yml'
p = io.open(y, encoding='utf-8').read()
p = p.replace('MARKETING_VERSION: "1.22"', 'MARKETING_VERSION: "1.23"')
p = p.replace('CURRENT_PROJECT_VERSION: "23"', 'CURRENT_PROJECT_VERSION: "24"')
io.open(y, 'w', encoding='utf-8', newline='').write(p)
print('version 1.23 (24)')
