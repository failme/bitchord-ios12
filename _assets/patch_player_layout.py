import io

ROOT = 'C:/Users/natha/Downloads/bitios/'
PATH = ROOT + 'BitChordIOS12/Sources/NowPlayingViewController.swift'
t = io.open(PATH, encoding='utf-8').read()


def need(old, new):
    global t
    if old not in t:
        raise SystemExit('MISSING: %r' % (old[:80],))
    t = t.replace(old, new, 1)


def maybe(old, new):
    global t
    if old in t:
        t = t.replace(old, new, 1)
        return True
    return False


need('''    private let lyricsSourceLabel = UILabel()''',
     '''    private let lyricsSourceLabel = UILabel()
    private let compactHeader = UIView()
    private let headerArtwork = UIImageView()
    private let headerTitle = UILabel()
    private let headerArtist = UILabel()
    private var lyricsTopDefault: NSLayoutConstraint?
    private var lyricsTopCompact: NSLayoutConstraint?''')

# Compact header, mirroring the real panel's cover / title / artist row.
need('''        // The real panel credits the provider under the words.''',
     '''        // The real lyrics panel leads with a small cover, the track and its
        // artist, where the artwork would be.
        compactHeader.translatesAutoresizingMaskIntoConstraints = false
        compactHeader.isHidden = true
        view.addSubview(compactHeader)

        headerArtwork.translatesAutoresizingMaskIntoConstraints = false
        headerArtwork.contentMode = .scaleAspectFill
        headerArtwork.clipsToBounds = true
        headerArtwork.layer.cornerRadius = 6
        headerArtwork.backgroundColor = Theme.surfaceVariant
        compactHeader.addSubview(headerArtwork)

        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.font = Theme.font(17, weight: .semibold)
        headerTitle.textColor = Theme.primaryText
        headerTitle.lineBreakMode = .byTruncatingTail
        compactHeader.addSubview(headerTitle)

        headerArtist.translatesAutoresizingMaskIntoConstraints = false
        headerArtist.font = Theme.font(14)
        headerArtist.textColor = Theme.secondaryText
        headerArtist.lineBreakMode = .byTruncatingTail
        compactHeader.addSubview(headerArtist)

        NSLayoutConstraint.activate([
            headerArtwork.leadingAnchor.constraint(equalTo: compactHeader.leadingAnchor),
            headerArtwork.centerYAnchor.constraint(equalTo: compactHeader.centerYAnchor),
            headerArtwork.widthAnchor.constraint(equalToConstant: 40),
            headerArtwork.heightAnchor.constraint(equalToConstant: 40),
            headerTitle.leadingAnchor.constraint(equalTo: headerArtwork.trailingAnchor, constant: 10),
            headerTitle.trailingAnchor.constraint(equalTo: compactHeader.trailingAnchor),
            headerTitle.bottomAnchor.constraint(equalTo: compactHeader.centerYAnchor, constant: -1),
            headerArtist.leadingAnchor.constraint(equalTo: headerTitle.leadingAnchor),
            headerArtist.trailingAnchor.constraint(equalTo: headerTitle.trailingAnchor),
            headerArtist.topAnchor.constraint(equalTo: compactHeader.centerYAnchor, constant: 1)
        ])

        // The real panel credits the provider under the words.''')

maybe('''            lyricsTable.topAnchor.constraint(equalTo: artworkView.topAnchor),
''', '')
maybe('''            lyricsTable.bottomAnchor.constraint(equalTo: lyricsSourceLabel.topAnchor, constant: -4),''',
      '''            lyricsTable.bottomAnchor.constraint(equalTo: lyricsSourceLabel.topAnchor, constant: -6),

            compactHeader.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            compactHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            compactHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            compactHeader.heightAnchor.constraint(equalToConstant: 44),''')
maybe('''            lyricsSourceLabel.bottomAnchor.constraint(equalTo: artworkView.bottomAnchor,
                                                       constant: -2),''',
      '''            lyricsSourceLabel.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -10),''')

# Transport pinned to the bottom so the words get the screen.
maybe('''            slider.topAnchor.constraint(equalTo: diagnosticsLabel.bottomAnchor, constant: 6),''',
      '''            playButton.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -24),''')
maybe('''            likeButton.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 24),''',
      '''            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -4),''')
maybe('''            queueButton.topAnchor.constraint(equalTo: likeButton.topAnchor),''',
      '''            queueButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),''')

need('''        titleUnderArtwork = titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor,
                                                            constant: 16)''',
     '''        titleUnderArtwork = titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor,
                                                            constant: 16)
        lyricsTopDefault = lyricsTable.topAnchor.constraint(equalTo: artworkView.topAnchor)
        lyricsTopCompact = lyricsTable.topAnchor.constraint(equalTo: compactHeader.bottomAnchor,
                                                            constant: 12)''')

need('''        showingLyrics = lyrics
        artworkView.isHidden = lyrics
        // The panel keeps the title under the cover: the scrubber and transport
        // hang off that chain, so moving it would pull them up the screen.
        titleUnderArtwork?.isActive = true
        titleUnderClose?.isActive = false''',
     '''        showingLyrics = lyrics
        artworkView.isHidden = lyrics
        // In lyrics mode the words take the screen: the big title and the
        // small print fold away and a compact header takes their place.
        compactHeader.isHidden = !lyrics
        titleLabel.isHidden = lyrics
        artistLabel.isHidden = lyrics
        badgeLabel.isHidden = lyrics
        statusLabel.isHidden = lyrics
        diagnosticsLabel.isHidden = lyrics
        lyricsTopCompact?.isActive = lyrics
        lyricsTopDefault?.isActive = !lyrics
        titleUnderArtwork?.isActive = true
        titleUnderClose?.isActive = false''')

need('''        artistLabel.text = track.artist.isEmpty ? "Unknown artist" : track.artist''',
     '''        artistLabel.text = track.artist.isEmpty ? "Unknown artist" : track.artist
        headerTitle.text = track.title
        headerArtist.text = artistLabel.text''')

need('''    private func applyArtwork(_ image: UIImage?) {
        artworkView.image = image''',
     '''    private func applyArtwork(_ image: UIImage?) {
        artworkView.image = image
        headerArtwork.image = image''')

io.open(PATH, 'w', encoding='utf-8', newline='').write(t)
print('ok player layout')

y = ROOT + 'project.yml'
p = io.open(y, encoding='utf-8').read()
p = p.replace('MARKETING_VERSION: "1.20"', 'MARKETING_VERSION: "1.21"')
p = p.replace('CURRENT_PROJECT_VERSION: "21"', 'CURRENT_PROJECT_VERSION: "22"')
io.open(y, 'w', encoding='utf-8', newline='').write(p)
print('version 1.21 (22)')
