import io

ROOT = 'C:/Users/natha/Downloads/bitios/v2/BitChordIOS12/Sources/'
p = ROOT + 'NowPlayingViewController.swift'
t = io.open(p, encoding='utf-8').read()


def sub(old, new):
    global t
    if old not in t:
        raise SystemExit('MISSING: %r' % (old[:80],))
    t = t.replace(old, new, 1)


sub('    private let handle = UIView()',
    '''    private let handle = UIView()
    private let stationLabel = UILabel()
    private let peekLabel = UILabel()''')

sub('''        handle.translatesAutoresizingMaskIntoConstraints = false''',
    '''        stationLabel.translatesAutoresizingMaskIntoConstraints = false
        stationLabel.font = Theme.font(13)
        stationLabel.textColor = Theme.secondaryText
        stationLabel.textAlignment = .center
        view.addSubview(stationLabel)

        peekLabel.translatesAutoresizingMaskIntoConstraints = false
        peekLabel.font = Theme.font(15)
        peekLabel.textColor = Theme.secondaryText
        peekLabel.textAlignment = .left
        peekLabel.lineBreakMode = .byTruncatingTail
        peekLabel.isUserInteractionEnabled = true
        peekLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleMode)))
        view.addSubview(peekLabel)

        handle.translatesAutoresizingMaskIntoConstraints = false''')

# --- artwork mode, measured off the real player at 390pt wide -------------
sub('''            closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),''',
    '''            handle.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),

            stationLabel.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 10),
            stationLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stationLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),

            closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),''')

sub('''            artworkView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            artworkView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            artworkView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.80),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),''',
    '''            artworkView.topAnchor.constraint(equalTo: stationLabel.bottomAnchor, constant: 20),
            artworkView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            artworkView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),''')

sub('        titleLabel.font = Theme.font(.headlineMedium)',
    '        titleLabel.font = Theme.font(26, weight: .bold)')
sub('        artistLabel.font = Theme.font(.bodyLarge)',
    '        artistLabel.font = Theme.font(17)')

sub('''            titleUnderArtwork ?? titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),''',
    '''            titleUnderArtwork ?? titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 26),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            titleLabel.trailingAnchor.constraint(equalTo: toggleButton.leadingAnchor, constant: -10),

            toggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            toggleButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor, constant: 10),
            toggleButton.widthAnchor.constraint(equalToConstant: 36),
            toggleButton.heightAnchor.constraint(equalToConstant: 36),

            peekLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 20),
            peekLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            peekLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),''')

sub('''        lyricsTopDefault = lyricsTable.topAnchor.constraint(equalTo: artworkView.topAnchor)''',
    '''        lyricsTopDefault = lyricsTable.topAnchor.constraint(equalTo: stationLabel.bottomAnchor, constant: 8)''')

# Scrubber sits under the peeked lyric line, as it does on the real player.
sub('''            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),''',
    '''            slider.topAnchor.constraint(equalTo: peekLabel.bottomAnchor, constant: 12),
            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),''')

sub('''            playButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: stackGap),''',
    '''            playButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: squat ? 20 : 28),''')

sub('''            playButton.heightAnchor.constraint(equalToConstant: playSide),
            playButton.widthAnchor.constraint(equalToConstant: playSide),''',
    '''            playButton.heightAnchor.constraint(equalToConstant: 56),
            playButton.widthAnchor.constraint(equalToConstant: 56),''')

# The real transport is a heavy pause between double-triangle skips, no disc.
sub('''        playButton.backgroundColor = lyrics ? .clear : .white
        playButton.tintColor = lyrics ? .white : .black''',
    '''        playButton.backgroundColor = .clear
        playButton.tintColor = Theme.primaryText
        playButton.imageEdgeInsets = .zero''')

sub('''        configureTransportButton(previousButton, icon: .previous, size: 40, action: #selector(goPrevious))''',
    '''        configureTransportButton(previousButton, icon: .previous, size: 44, action: #selector(goPrevious))''')
sub('''        configureTransportButton(nextButton, icon: .next, size: 40, action: #selector(goNext))''',
    '''        configureTransportButton(nextButton, icon: .next, size: 44, action: #selector(goNext))''')

# Bottom chrome: the selected comment pill, cast, queue.
sub('''        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.tintColor = Theme.primaryText''',
    '''        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.tintColor = Theme.primaryText
        modeButton.backgroundColor = Theme.surfaceVariant
        modeButton.layer.cornerRadius = 8''')

sub('''            modeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            modeButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 44),
            modeButton.heightAnchor.constraint(equalToConstant: 44),''',
    '''            modeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            modeButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 40),
            modeButton.heightAnchor.constraint(equalToConstant: 30),''')

sub('''            queueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),''',
    '''            queueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),''')

sub('''            volumeSlider.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -footGap),
            volumeSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 44),
            volumeSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -44),''',
    '''            volumeSlider.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -footGap),
            volumeSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            volumeSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),''')

sub('''            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -bottomGap),''',
    '''            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -18),''')

# Footer is the same three items in both modes; shuffle/repeat/like are not on
# the real player at all.
sub('''        shuffleButton.isHidden = lyrics
        repeatButton.isHidden = lyrics
        likeButton.isHidden = lyrics
        modeButton.isHidden = !lyrics''',
    '''        shuffleButton.isHidden = true
        repeatButton.isHidden = true
        likeButton.isHidden = true
        modeButton.isHidden = false
        closeButton.isHidden = true''')

sub('''        toggleButton.backgroundColor = lyrics ? UIColor(white: 1, alpha: 0.1) : .clear
        toggleButton.layer.cornerRadius = 22''',
    '''        toggleButton.backgroundColor = UIColor(white: 1, alpha: 0.10)
        toggleButton.layer.cornerRadius = 18''')

# The header label, artwork mode only.
sub('''        handle.isHidden = !lyrics
        closeButton.isHidden = lyrics''',
    '''        handle.isHidden = lyrics
        stationLabel.isHidden = lyrics
        peekLabel.isHidden = lyrics
        closeButton.isHidden = true''')

io.open(p, 'w', encoding='utf-8', newline='').write(t)
print('ok player chrome')
