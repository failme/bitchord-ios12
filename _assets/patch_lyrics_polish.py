import io

ROOT = 'C:/Users/natha/Downloads/bitios/'
p = ROOT + 'BitChordIOS12/Sources/NowPlayingViewController.swift'
t = io.open(p, encoding='utf-8').read()
orig = t


def sub(old, new):
    global t
    if old not in t:
        print('skip:', old[:60])
        return
    t = t.replace(old, new, 1)


# The real active line is white; only the lines around it are grey.
sub('''            lyricCell.dimmed = row == lyricHighlight
                ? UIColor(white: 1, alpha: 0.55)
                : Theme.secondaryText''',
    '''            lyricCell.dimmed = row == lyricHighlight ? .white : Theme.secondaryText''')

# Bigger transport, as the real panel draws it.
sub('configureTransportButton(previousButton, icon: .previous, size: 30, action: #selector(goPrevious))',
    'configureTransportButton(previousButton, icon: .previous, size: 36, action: #selector(goPrevious))')
sub('configureTransportButton(nextButton, icon: .next, size: 30, action: #selector(goNext))',
    'configureTransportButton(nextButton, icon: .next, size: 36, action: #selector(goNext))')
sub('playButton.setImage(Icons.image(PlayerService.shared.isPlaying ? .pause : .play, size: 30), for: .normal)',
    'playButton.setImage(Icons.image(PlayerService.shared.isPlaying ? .pause : .play, size: 44), for: .normal)')

# Ellipsis lives in a soft disc, and the scrubber has no thumb in this mode.
sub('        toggleButton.setTitle(nil, for: .normal)',
    '''        toggleButton.setTitle(nil, for: .normal)
        toggleButton.backgroundColor = lyrics ? UIColor(white: 1, alpha: 0.1) : .clear
        toggleButton.layer.cornerRadius = 22
        slider.setThumbImage(lyrics ? UIImage() : Theme.thumbImage(), for: .normal)''')

# Let the blurred cover read through instead of near-black.
sub('        backdropView.image = image', '        backdropView.alpha = 0.85\n        backdropView.image = image')
sub('        handle.isHidden = !lyrics',
    '''        backdropView.alpha = lyrics ? 1 : 0.85
        handle.isHidden = !lyrics''')

if t == orig:
    raise SystemExit('nothing changed')
io.open(p, 'w', encoding='utf-8', newline='').write(t)
print('ok player polish')

y = ROOT + 'project.yml'
s = io.open(y, encoding='utf-8').read()
s = s.replace('MARKETING_VERSION: "1.24"', 'MARKETING_VERSION: "1.25"')
s = s.replace('CURRENT_PROJECT_VERSION: "25"', 'CURRENT_PROJECT_VERSION: "26"')
io.open(y, 'w', encoding='utf-8', newline='').write(s)
print('version 1.25 (26)')
