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


# The mesh was drawn almost black by its own scrim; the real backdrop keeps the
# cover's colour and only darkens enough for white words to sit on it.
edit('BitChordIOS12/Sources/MeshGradientView.swift', [
    ('colors[0].dimmed(to: 0.12).setFill()', 'colors[0].dimmed(to: 0.20).setFill()'),
    ('''            UIColor.black.withAlphaComponent(0.10).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height * 0.45))
            UIColor.black.withAlphaComponent(0.38).setFill()''',
     '''            UIColor.black.withAlphaComponent(0.04).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height * 0.45))
            UIColor.black.withAlphaComponent(0.20).setFill()'''),
    ('blur(source, radius: 42)', 'blur(source, radius: 34)'),
])

edit('BitChordIOS12/Sources/NowPlayingViewController.swift', [
    ('''    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))''',
     '''    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let scrimView = UIView()
    private let scrimLayer = CAGradientLayer()'''),
    ('''        glowView.translatesAutoresizingMaskIntoConstraints = false''',
     '''        scrimView.translatesAutoresizingMaskIntoConstraints = false
        scrimView.isUserInteractionEnabled = false
        scrimView.layer.addSublayer(scrimLayer)
        scrimLayer.colors = [UIColor.black.withAlphaComponent(0.10).cgColor,
                             UIColor.black.withAlphaComponent(0.38).cgColor,
                             UIColor.black.withAlphaComponent(0.72).cgColor]
        scrimLayer.locations = [0, 0.45, 1]
        scrimView.isHidden = true
        view.addSubview(scrimView)

        glowView.translatesAutoresizingMaskIntoConstraints = false'''),
    ('''        glowLayer.frame = glowView.bounds''',
     '''        scrimLayer.frame = scrimView.bounds
        glowLayer.frame = glowView.bounds'''),
    ('''        backdropView.alpha = lyrics ? 1 : 0.85''',
     '''        // In lyrics mode the cover itself is the backdrop: the dark blur
        // effect above it softens it exactly the way the real panel does.
        backdropView.alpha = lyrics ? 0.9 : 0
        scrimView.isHidden = !lyrics'''),
    ('''            backdropView.topAnchor.constraint(equalTo: view.topAnchor),''',
     '''            scrimView.topAnchor.constraint(equalTo: view.topAnchor),
            scrimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backdropView.topAnchor.constraint(equalTo: view.topAnchor),'''),
])

y = ROOT + 'project.yml'
s = io.open(y, encoding='utf-8').read()
s = s.replace('MARKETING_VERSION: "1.25"', 'MARKETING_VERSION: "1.26"')
s = s.replace('CURRENT_PROJECT_VERSION: "26"', 'CURRENT_PROJECT_VERSION: "27"')
io.open(y, 'w', encoding='utf-8', newline='').write(s)
print('version 1.26 (27)')
