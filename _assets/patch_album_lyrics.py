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


# --- Albums: the catalogue retired album.getAlbumDetails -------------------
rw('BitChordIOS12/Sources/CatalogueSearch.swift', [
    ('''    /// The songs on an album, in track order.
    func songs(inAlbum albumID: String, completion: @escaping ([Track]) -> Void) {
        get(call: "album.getAlbumDetails", params: ["albumid": albumID]) { json in
            guard let json = json else {
                completion([])
                return
            }
            var rows = (json["songs"] as? [[String: Any]]) ?? []''',
     '''    /// The songs on an album, in track order.
    ///
    /// `album.getAlbumDetails` was retired by the catalogue and now answers
    /// `INPUT_INVALID / operation is not supported`, which is why every album
    /// page came up saying there was nothing to see. `content.getAlbumDetails`
    /// is the operation that still returns the tracklist, and it puts the songs
    /// under `list`.
    func songs(inAlbum albumID: String, completion: @escaping ([Track]) -> Void) {
        get(call: "content.getAlbumDetails", params: ["albumid": albumID]) { json in
            guard let json = json else {
                completion([])
                return
            }
            var rows = (json["songs"] as? [[String: Any]]) ?? []
            if rows.isEmpty {
                rows = (json["list"] as? [[String: Any]]) ?? []
            }'''),
])

# --- Lyrics panel: full height, compact header, credit above the scrubber --
rw('BitChordIOS12/Sources/NowPlayingViewController.swift', [
    ('''    private let lyricsSourceLabel = UILabel()''',
     '''    private let lyricsSourceLabel = UILabel()
    private let compactHeader = UIView()
    private let headerArtwork = UIImageView()
    private let headerTitle = UILabel()
    private let headerArtist = UILabel()
    private var lyricsTopDefault: NSLayoutConstraint?
    private var lyricsTopCompact: NSLayoutConstraint?'''),
    ('''        view.addSubview(lyricsTable)

        // The real panel credits the provider under the words.''',
     '''        view.addSubview(lyricsTable)

        // The real lyrics panel leads with a small cover, the track and its
        // artist, exactly where the artwork would be.
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

        // The real panel credits the provider under the words.'''),
    ('''            lyricsTable.topAnchor.constraint(equalTo: artworkView.topAnchor),
            lyricsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),''',
     '''            lyricsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),'''),
    ('''            lyricsTable.bottomAnchor.constraint(equalTo: lyricsSourceLabel.topAnchor, constant: -4),''',
     '''            lyricsTable.bottomAnchor.constraint(equalTo: lyricsSourceLabel.topAnchor, constant: -6),

            compactHeader.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            compactHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            compactHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            compactHeader.heightAnchor.constraint(equalToConstant: 44),'''),
    ('''            lyricsSourceLabel.bottomAnchor.constraint(equalTo: artworkView.bottomAnchor,
                                                       constant: -2),''',
     '''            lyricsSourceLabel.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -10),'''),
    # Controls are pinned to the bottom, so the lyrics area can use the screen.
    ('''            slider.topAnchor.constraint(equalTo: diagnosticsLabel.bottomAnchor, constant: 6),''',
     '''            playButton.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -24),'''),
    ('''            likeButton.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 24),''',
     '''            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -4),'''),
    ('''            queueButton.topAnchor.constraint(equalTo: likeButton.topAnchor),''',
     '''            queueButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),'''),
    # Toggle between the two positions the lyrics table can take.
    ('''        titleUnderArtwork = titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor,
                                                            constant: 16)''',
     '''        titleUnderArtwork = titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor,
                                                            constant: 16)
        lyricsTopDefault = lyricsTable.topAnchor.constraint(equalTo: artworkView.topAnchor)
        lyricsTopCompact = lyricsTable.topAnchor.constraint(equalTo: compactHeader.bottomAnchor,
                                                            constant: 12)'''),
    ('''        showingLyrics = lyrics
        artworkView.isHidden = lyrics
        titleUnderArtwork?.isActive = true
        titleUnderClose?.isActive = false''',
     '''        showingLyrics = lyrics
        artworkView.isHidden = lyrics
        compactHeader.isHidden = !lyrics
        titleLabel.isHidden = lyrics
        artistLabel.isHidden = lyrics
        badgeLabel.isHidden = lyrics
        statusLabel.isHidden = lyrics
        diagnosticsLabel.isHidden = lyrics
        lyricsTopCompact?.isActive = lyrics
        lyricsTopDefault?.isActive = !lyrics
        titleUnderArtwork?.isActive = true
        titleUnderClose?.isActive = false'''),
    # Keep the compact header's text in step with the track.
    ('''        artistLabel.text = track.artist.isEmpty ? "Unknown artist" : track.artist''',
     '''        artistLabel.text = track.artist.isEmpty ? "Unknown artist" : track.artist
        headerTitle.text = track.title
        headerArtist.text = artistLabel.text'''),
    ('''    private func applyArtwork(_ image: UIImage?) {
        artworkView.image = image''',
     '''    private func applyArtwork(_ image: UIImage?) {
        artworkView.image = image
        headerArtwork.image = image'''),
])

y = ROOT + 'project.yml'
t = io.open(y, encoding='utf-8').read()
t = t.replace('MARKETING_VERSION: "1.19"', 'MARKETING_VERSION: "1.20"')
t = t.replace('CURRENT_PROJECT_VERSION: "20"', 'CURRENT_PROJECT_VERSION: "21"')
io.open(y, 'w', encoding='utf-8', newline='').write(t)
print('version 1.20 (21)')
