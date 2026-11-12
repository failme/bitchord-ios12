import io

ROOT = 'C:/Users/natha/Downloads/bitios/'


def rw(p, pairs):
    path = ROOT + p
    t = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        if old not in t:
            raise SystemExit('MISSING in %s: %r' % (p, old[:70]))
        t = t.replace(old, new, 1)
    io.open(path, 'w', encoding='utf-8', newline='').write(t)
    print('ok', p)


# --- bubble: an outlined bubble with three dots, not a solid block --------
rw('BitChordIOS12/Sources/Icons.swift', [
    ('''        case .bubble:
            let box = UIBezierPath(roundedRect: CGRect(x: 0.16 * s, y: 0.18 * s, width: 0.68 * s, height: 0.56 * s),
                                   cornerRadius: 0.16 * s)
            box.fill()''',
     '''        case .bubble:
            let box = UIBezierPath(roundedRect: CGRect(x: 0.16 * s, y: 0.18 * s, width: 0.68 * s, height: 0.56 * s),
                                   cornerRadius: 0.16 * s)
            stroke(box)'''),
])

rw('BitChordIOS12/Sources/NowPlayingViewController.swift', [
    # The real header ends in an ellipsis alone.
    ('''        toggleButton.setTitle(lyrics ? "Artwork" : "Lyrics", for: .normal)''',
     '''        toggleButton.setTitle(nil, for: .normal)'''),
    # The real panel has no chevron; it is dismissed by dragging down.
    ('''        handle.isHidden = !lyrics''',
     '''        handle.isHidden = !lyrics
        closeButton.isHidden = lyrics'''),
    ('''            outputLabel.centerXAnchor.constraint(equalTo: outputButton.centerXAnchor),''',
     '''            outputLabel.centerXAnchor.constraint(equalTo: outputButton.centerXAnchor),

            volumeLow.centerYAnchor.constraint(equalTo: volumeSlider.centerYAnchor),
            volumeLow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            volumeLow.widthAnchor.constraint(equalToConstant: 14),
            volumeLow.heightAnchor.constraint(equalToConstant: 14),

            volumeHigh.centerYAnchor.constraint(equalTo: volumeSlider.centerYAnchor),
            volumeHigh.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            volumeHigh.widthAnchor.constraint(equalToConstant: 14),
            volumeHigh.heightAnchor.constraint(equalToConstant: 14),'''),
    ('''    private let volumeSlider = UISlider()''',
     '''    private let volumeSlider = UISlider()
    private let volumeLow = UIImageView()
    private let volumeHigh = UIImageView()'''),
    ('''        view.addSubview(volumeSlider)''',
     '''        for speaker in [volumeLow, volumeHigh] {
            speaker.translatesAutoresizingMaskIntoConstraints = false
            speaker.image = Icons.image(.speaker, size: 14)
            speaker.tintColor = UIColor(white: 1, alpha: 0.5)
            speaker.isHidden = true
            view.addSubview(speaker)
        }
        view.addSubview(volumeSlider)'''),
    ('''        volumeSlider.isHidden = !lyrics''',
     '''        volumeSlider.isHidden = !lyrics
        volumeLow.isHidden = !lyrics
        volumeHigh.isHidden = !lyrics'''),
    # Line the credit up with the words.
    ('''            lyricsSourceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),''',
     '''            lyricsSourceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),'''),
    # Drag down to dismiss, the way the real sheet closes.
    ('''        applyMode(lyrics: false)''',
     '''        let drag = UISwipeGestureRecognizer(target: self, action: #selector(close))
        drag.direction = .down
        view.addGestureRecognizer(drag)
        applyMode(lyrics: false)'''),
])

y = ROOT + 'project.yml'
t = io.open(y, encoding='utf-8').read()
t = t.replace('MARKETING_VERSION: "1.23"', 'MARKETING_VERSION: "1.24"')
t = t.replace('CURRENT_PROJECT_VERSION: "24"', 'CURRENT_PROJECT_VERSION: "25"')
io.open(y, 'w', encoding='utf-8', newline='').write(t)
print('version 1.24 (25)')
