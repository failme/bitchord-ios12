import io

ROOT = 'C:/Users/natha/Downloads/bitios/'


def rw(p, pairs):
    path = ROOT + p
    t = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        if old not in t:
            raise SystemExit('MISSING in %s: %r' % (p, old[:70]))
        t = t.replace(old, new)
    io.open(path, 'w', encoding='utf-8', newline='').write(t)
    print('ok', p)


# --- Artwork: the catalogue serves WebP, which iOS 12 cannot decode --------
rw('BitChordIOS12/Sources/ArtworkLoader.swift', [
    ('''        config.requestCachePolicy = .returnCacheDataElseLoad''',
     '''        config.requestCachePolicy = .returnCacheDataElseLoad
        // The catalogue's CDN wants a browser agent and referer, otherwise it
        // refuses a good share of the covers.
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
            "Referer": "https://www.jiosaavn.com/",
            "Accept": "image/jpeg,image/png,image/*;q=0.8"
        ]'''),
    ('''    func cached(_ url: URL?) -> UIImage? {
        guard let key = url?.absoluteString else { return nil }
        return cache.object(forKey: key as NSString)
    }''',
     '''    /// The URL an image should actually be fetched from.
    ///
    /// The catalogue now hands out `-150x150.webp` for most rows, and iOS 12
    /// has no WebP decoder, so every one of those covers failed to draw. The
    /// same object is served as a 500x500 JPEG under the same path, which every
    /// device here can decode — so the extension is swapped and the size lifted.
    static func normalized(_ url: URL?) -> URL? {
        guard let text = url?.absoluteString else { return nil }
        var out = text
        if out.lowercased().hasSuffix(".webp") {
            out = String(out.dropLast(5)) + ".jpg"
        }
        for size in ["50x50", "150x150", "250x250"] {
            out = out.replacingOccurrences(of: size, with: "500x500")
        }
        return URL(string: out)
    }

    func cached(_ url: URL?) -> UIImage? {
        guard let key = ArtworkLoader.normalized(url)?.absoluteString else { return nil }
        return cache.object(forKey: key as NSString)
    }'''),
    ('''        guard let url = url else {
            completion(nil)
            return nil
        }
        if let hit = cached(url) {''',
     '''        guard let url = ArtworkLoader.normalized(url) else {
            completion(nil)
            return nil
        }
        if let hit = cached(url) {'''),
])

# --- Card captions: the real cards show one line, not a clipped second -----
rw('BitChordIOS12/Sources/ShelfRowView.swift', [
    ('''        titleLabel.numberOfLines = 2''', '''        titleLabel.numberOfLines = 1'''),
])

# --- Lyrics panel: the real app's type, colour, spacing and credit --------
rw('BitChordIOS12/Sources/KaraokeLyricView.swift', [
    ('    private let verticalPadding: CGFloat = 6',
     '    private let verticalPadding: CGFloat = 10\n\n'
     '    /// Unsung text stays white and dimmed rather than turning grey; over the\n'
     '    /// blurred cover that is what the real panel looks like.\n'
     '    var dimmed: UIColor = UIColor(white: 1, alpha: 0.45)'),
    ('        return ceil(bounds.height) + 12', '        return ceil(bounds.height) + 20'),
    ('''            .foregroundColor: Theme.secondaryText
        ]''',
     '''            .foregroundColor: dimmed
        ]'''),
])

rw('BitChordIOS12/Sources/KaraokeLyricView.swift', [
    ('''    private var lineView: KaraokeLineView?''',
     '''    private var lineView: KaraokeLineView?

    /// How the unsung part of the line is coloured for this row.
    var dimmed: UIColor = UIColor(white: 1, alpha: 0.45) {
        didSet { lineView?.dimmed = dimmed }
    }'''),
    ('''        let view = KaraokeLineView(line: line, font: font)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.position = position''',
     '''        let view = KaraokeLineView(line: line, font: font)
        view.dimmed = dimmed
        view.translatesAutoresizingMaskIntoConstraints = false
        view.position = position'''),
])

rw('BitChordIOS12/Sources/NowPlayingViewController.swift', [
    ('''    private let lyricsTable = UITableView(frame: .zero, style: .plain)''',
     '''    private let lyricsTable = UITableView(frame: .zero, style: .plain)
    private let lyricsSourceLabel = UILabel()'''),
    ('''        lyricsTable.register(KaraokeLyricCell.self,
                             forCellReuseIdentifier: KaraokeLyricCell.reuseIdentifier)
        view.addSubview(lyricsTable)''',
     '''        lyricsTable.register(KaraokeLyricCell.self,
                             forCellReuseIdentifier: KaraokeLyricCell.reuseIdentifier)
        lyricsTable.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.addSubview(lyricsTable)

        // The real panel credits the provider under the words.
        lyricsSourceLabel.translatesAutoresizingMaskIntoConstraints = false
        lyricsSourceLabel.font = Theme.font(13)
        lyricsSourceLabel.textColor = Theme.secondaryText
        lyricsSourceLabel.textAlignment = .left
        lyricsSourceLabel.isHidden = true
        view.addSubview(lyricsSourceLabel)'''),
    ('''            lyricsTable.heightAnchor.constraint(equalTo: artworkView.heightAnchor),''',
     '''            lyricsTable.heightAnchor.constraint(equalTo: artworkView.heightAnchor),

            lyricsSourceLabel.topAnchor.constraint(equalTo: lyricsTable.bottomAnchor, constant: 8),
            lyricsSourceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            lyricsSourceLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),'''),
    ('''        showingLyrics = lyrics
        artworkView.isHidden = lyrics
        lyricsTable.isHidden = !lyrics''',
     '''        showingLyrics = lyrics
        artworkView.isHidden = lyrics
        lyricsTable.isHidden = !lyrics
        lyricsSourceLabel.isHidden = !lyrics'''),
    ('''            lyricHighlight = -1
            lyricHeights.removeAll()
            lyricsTable.reloadData()''',
     '''            lyricHighlight = -1
            lyricHeights.removeAll()
            lyricsSourceLabel.text = service.lyricsSource.isEmpty
                ? nil
                : "Lyrics by " + service.lyricsSource
            lyricsTable.reloadData()'''),
    ('''        if index != lyricHighlight {
            lyricHighlight = index
            lyricsTable.reloadData()''',
     '''        if index != lyricHighlight {
            lyricHighlight = index
            // The active line is set larger, so its measured height is stale.
            lyricHeights.removeAll()
            lyricsTable.reloadData()'''),
    ('''            lyricCell.configure(line: currentLyrics[indexPath.row],
                                font: Theme.font(17, weight: .semibold),
                                position: indexPath.row == lyricHighlight
                                    ? PlayerService.shared.currentTime
                                    : -1)''',
     '''            let row = indexPath.row
            let cellPosition = row == lyricHighlight ? PlayerService.shared.currentTime : -1
            lyricCell.configure(line: currentLyrics[row],
                                font: NowPlayingViewController.lyricFont(active: row == lyricHighlight),
                                position: cellPosition)
            lyricCell.dimmed = row == lyricHighlight
                ? UIColor(white: 1, alpha: 0.5)
                : UIColor(white: 1, alpha: 0.35)'''),
    ('''        let height = KaraokeLineView.height(text: currentLyrics[indexPath.row].text,
                                            font: Theme.font(17, weight: .semibold),
                                            width: width)''',
     '''        let height = KaraokeLineView.height(
            text: currentLyrics[indexPath.row].text,
            font: NowPlayingViewController.lyricFont(active: indexPath.row == lyricHighlight),
            width: width)'''),
    ('''extension NowPlayingViewController: UITableViewDataSource, UITableViewDelegate {''',
     '''extension NowPlayingViewController {
    /// The active line is large and bold, everything else steps down a size and
    /// a weight — the proportions the real lyrics panel uses.
    static func lyricFont(active: Bool) -> UIFont {
        return active ? Theme.font(34, weight: .bold) : Theme.font(28, weight: .semibold)
    }
}

extension NowPlayingViewController: UITableViewDataSource, UITableViewDelegate {'''),
])

# --- Unison as a fourth provider -----------------------------------------
rw('BitChordIOS12/Sources/LyricsService.swift', [
    ('''/// default order: lrc.red first (Apple Music TTML, syllable timing, filed by
/// ISRC), then LyricsPlus (Apple/QQ syllables from community mirrors), and
/// finally LRCLIB for whole-line LRC when neither has the track.''',
     '''/// default order: lrc.red first (Apple Music TTML, syllable timing, filed by
/// ISRC), then LyricsPlus (Apple/QQ syllables from community mirrors), then
/// Unison (contributed, any of TTML/LRC/plain), and finally LRCLIB for
/// whole-line LRC when none of them has the track.'''),
    ('''                self?.lrcLib(track: track, completion: completion)''',
     '''                self?.unison(title: title, artist: artist, duration: duration) { result in
                    if let result = result, !result.lines.isEmpty {
                        completion(result, nil)
                        return
                    }
                    self?.lrcLib(track: track, completion: completion)
                }'''),
    ('''    // MARK: - LRCLIB (whole lines)''',
     '''    // MARK: - Unison (contributed)

    private func unison(title: String,
                        artist: String,
                        duration: Double,
                        completion: @escaping (LyricsResult?) -> Void) {
        var components = URLComponents(string: "https://unison.boidu.dev/lyrics")
        var items = [URLQueryItem(name: "song", value: title),
                     URLQueryItem(name: "artist", value: artist)]
        if duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            completion(nil)
            return
        }
        getJSON(url) { [weak self] json in
            guard let self = self,
                  let object = json as? [String: Any],
                  (object["success"] as? Bool) == true,
                  let data = object["data"] as? [String: Any],
                  let text = data["lyrics"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(nil)
                return
            }
            let format = ((data["format"] as? String) ?? "").lowercased()
            let lines = format.contains("ttml")
                ? TTMLLyrics.parse(text)
                : self.parseLRC(text)
            completion(lines.isEmpty
                ? nil
                : LyricsResult(lines: lines, isSynced: true, source: "Unison"))
        }
    }

    // MARK: - LRCLIB (whole lines)'''),
])

y = ROOT + 'project.yml'
t = io.open(y, encoding='utf-8').read()
t = t.replace('MARKETING_VERSION: "1.16"', 'MARKETING_VERSION: "1.17"')
t = t.replace('CURRENT_PROJECT_VERSION: "17"', 'CURRENT_PROJECT_VERSION: "18"')
io.open(y, 'w', encoding='utf-8', newline='').write(t)
print('version 1.17 (18)')
