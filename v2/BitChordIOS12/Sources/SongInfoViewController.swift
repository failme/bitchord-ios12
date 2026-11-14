import UIKit

/// Upstream's song-info dialog: a 270pt alert card with the track at its head,
/// Album / Release date / Views / Likes / Comments rows, and Done at its foot.
/// The counts belong to this exact upload, so they are fetched only when the
/// dialog opens.
final class SongInfoViewController: UIViewController {
    private let track: Track
    private let card = UIView()
    private let scrim = UIView()
    private var rowViews: [String: SongInfoRow] = [:]

    init(track: Track) {
        self.track = track
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        scrim.alpha = 0
        scrim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissSelf)))
        view.addSubview(scrim)

        card.backgroundColor = Theme.surfaceVariant
        card.layer.cornerRadius = 14
        card.layer.masksToBounds = true
        card.alpha = 0
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let heading = UILabel()
        heading.text = "Song info"
        heading.font = Theme.font(17, weight: .semibold)
        heading.textColor = Theme.primaryText
        heading.textAlignment = .center
        heading.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = track.title
        title.font = Theme.font(13)
        title.textColor = Theme.primaryText
        title.textAlignment = .center
        title.numberOfLines = 2
        title.translatesAutoresizingMaskIntoConstraints = false

        let artist = UILabel()
        artist.text = track.artist
        artist.font = Theme.font(13)
        artist.textColor = UIColor(white: 1, alpha: 0.60)
        artist.textAlignment = .center
        artist.numberOfLines = 1
        artist.translatesAutoresizingMaskIntoConstraints = false

        let head = UIView()
        head.addSubview(heading)
        head.addSubview(title)
        head.addSubview(artist)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: head.topAnchor, constant: 19),
            heading.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: 16),
            heading.trailingAnchor.constraint(equalTo: head.trailingAnchor, constant: -16),
            title.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: head.trailingAnchor, constant: -16),
            artist.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 0),
            artist.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: 16),
            artist.trailingAnchor.constraint(equalTo: head.trailingAnchor, constant: -16),
            artist.bottomAnchor.constraint(equalTo: head.bottomAnchor, constant: -19)
        ])
        stack.addArrangedSubview(head)
        stack.addArrangedSubview(rule(fullWidth: true))

        let body = SongInfoViewController.rows(for: track)
        for (index, row) in body.enumerated() {
            if index > 0 {
                stack.addArrangedSubview(rule(fullWidth: false))
            }
            let rowView = SongInfoRow(label: row.label, value: row.value)
            rowViews[row.label] = rowView
            stack.addArrangedSubview(rowView)
        }

        stack.addArrangedSubview(rule(fullWidth: true))

        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.setTitleColor(Theme.primaryText, for: .normal)
        done.titleLabel?.font = Theme.font(17, weight: .semibold)
        done.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        done.translatesAutoresizingMaskIntoConstraints = false
        let doneHolder = UIView()
        doneHolder.addSubview(done)
        doneHolder.heightAnchor.constraint(equalToConstant: 44).isActive = true
        NSLayoutConstraint.activate([
            done.leadingAnchor.constraint(equalTo: doneHolder.leadingAnchor),
            done.trailingAnchor.constraint(equalTo: doneHolder.trailingAnchor),
            done.topAnchor.constraint(equalTo: doneHolder.topAnchor),
            done.bottomAnchor.constraint(equalTo: doneHolder.bottomAnchor)
        ])
        stack.addArrangedSubview(doneHolder)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 270),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        loadInfo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrim.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard card.alpha == 0 else { return }
        card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.22, delay: 0,
                       usingSpringWithDamping: 0.9, initialSpringVelocity: 0.4) {
            self.scrim.alpha = 1
            self.card.alpha = 1
            self.card.transform = .identity
        }
    }

    private func rule(fullWidth: Bool) -> UIView {
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        let line = UIView()
        line.backgroundColor = UIColor(white: 1, alpha: 0.10)
        line.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(line)
        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(equalToConstant: 0.5),
            line.topAnchor.constraint(equalTo: holder.topAnchor),
            line.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: fullWidth ? 0 : 16),
            line.trailingAnchor.constraint(equalTo: holder.trailingAnchor)
        ])
        return holder
    }

    private func loadInfo() {
        SongInfoLoader.load(track) { [weak self] info in
            guard let self = self else { return }
            self.rowViews["Album"]?.set(info.album ?? "—")
            self.rowViews["Release date"]?.set(info.releaseDate ?? "—")
            self.rowViews["Views"]?.set(info.views ?? "—")
            self.rowViews["Likes"]?.set(info.likes ?? "—")
            self.rowViews["Comments"]?.set(info.comments ?? "—")
        }
    }

    @objc private func dismissSelf() {
        dismiss(animated: false, completion: nil)
    }

    /// The body's metadata rows; the headline above them is the track itself.
    static func rows(for track: Track) -> [(label: String, value: String)] {
        return [
            ("Album", track.album.isEmpty ? "—" : track.album),
            ("Release date", "—"),
            ("Views", "—"),
            ("Likes", "—"),
            ("Comments", "—")
        ]
    }
}

private struct SongInfoValues {
    var album: String? = nil
    var releaseDate: String? = nil
    var views: String? = nil
    var likes: String? = nil
    var comments: String? = nil
}

/// The watch page already carries the player response and the initial data the
/// web player uses. Reading those two payloads avoids a second authenticated
/// API, and the counts stay tied to the exact video that opened the dialog.
private enum SongInfoLoader {
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    static func load(_ track: Track, completion: @escaping (SongInfoValues) -> Void) {
        let localAlbum = track.album.isEmpty ? nil : track.album
        if track.videoID.hasPrefix(LocalMusicStore.idPrefix)
            || track.videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) == nil {
            completion(SongInfoValues(album: localAlbum))
            return
        }
        var components = URLComponents(string: "https://www.youtube.com/watch")!
        components.queryItems = [
            URLQueryItem(name: "v", value: track.videoID),
            URLQueryItem(name: "hl", value: "en")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Without a consent answer an EU request lands on consent.youtube.com,
        // whose page has no player response. SOCS=CAI rejects everything.
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion(SongInfoValues(album: localAlbum)) }
                return
            }
            let parsed = parse(html, videoID: track.videoID)
            DispatchQueue.main.async {
                completion(SongInfoValues(album: parsed.album ?? localAlbum,
                                          releaseDate: parsed.releaseDate,
                                          views: parsed.views,
                                          likes: parsed.likes,
                                          comments: parsed.comments))
            }
        }.resume()
    }

    private static func parse(_ html: String, videoID: String) -> SongInfoValues {
        guard let player = jsonObject(named: "ytInitialPlayerResponse", in: html),
              let details = player["videoDetails"] as? [String: Any],
              (details["videoId"] as? String) == videoID else {
            return SongInfoValues()
        }
        let data = jsonObject(named: "ytInitialData", in: html)
        var likes: String?
        var comments: String?
        if let data = data {
            if let primary = objects(key: "videoPrimaryInfoRenderer", in: data).first {
                let toggles = objects(key: "toggleButtonRenderer", in: primary)
                if let like = toggles.first(where: {
                    (($0["defaultIcon"] as? [String: Any])?["iconType"] as? String) == "LIKE"
                }), let count = text(like["defaultText"]), count.rangeOfCharacter(from: .decimalDigits) != nil {
                    likes = count
                } else if let viewModel = objects(key: "likeButtonViewModel", in: primary).first,
                          let button = objects(key: "buttonViewModel", in: viewModel).first,
                          let title = button["title"] as? String,
                          title.rangeOfCharacter(from: .decimalDigits) != nil {
                    likes = title
                }
            }
            if let header = objects(key: "commentsHeaderRenderer", in: data).first,
               let count = text(header["countText"]),
               count.rangeOfCharacter(from: .decimalDigits) != nil {
                comments = count
            } else if let entry = objects(key: "commentsEntryPointHeaderRenderer", in: data).first,
                      let count = text(entry["commentCount"]),
                      count.rangeOfCharacter(from: .decimalDigits) != nil {
                comments = count
            } else if let panel = objects(key: "engagementPanelSectionListRenderer", in: data).first(where: {
                let target = $0["targetId"] as? String
                let identifier = $0["panelIdentifier"] as? String
                return target == "engagement-panel-comments-section"
                    || identifier == "engagement-panel-comments-section"
            }), let header = objects(key: "engagementPanelTitleHeaderRenderer", in: panel).first,
               let count = text(header["contextualInfo"]),
               count.rangeOfCharacter(from: .decimalDigits) != nil {
                comments = count
            }
        }
        let description = details["shortDescription"] as? String
        let views = (details["viewCount"] as? String).flatMap { compactCount($0) }
        return SongInfoValues(album: nil,
                              releaseDate: releaseDate(in: description),
                              views: views,
                              likes: likes,
                              comments: comments)
    }

    /// Catalogue uploads state the recording date in the description; upload
    /// and publish dates describe the video, so they are never substituted.
    private static func releaseDate(in description: String?) -> String? {
        guard let description = description,
              let regex = try? NSRegularExpression(pattern: "Released on:\\s*(\\d{4}-\\d{2}-\\d{2})",
                                                   options: .caseInsensitive) else { return nil }
        for raw in description.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line) else { continue }
            return String(line[range])
        }
        return nil
    }

    /// YouTube's short form: 950, 1.2K, 100K, 2.3M — truncated, never rounded.
    private static func compactCount(_ raw: String) -> String {
        guard let n = Int64(raw), n >= 0 else { return raw }
        let unit: Int64
        let suffix: String
        if n >= 1_000_000_000 {
            unit = 1_000_000_000; suffix = "B"
        } else if n >= 1_000_000 {
            unit = 1_000_000; suffix = "M"
        } else if n >= 1_000 {
            unit = 1_000; suffix = "K"
        } else {
            return String(n)
        }
        let whole = n / unit
        if whole >= 10 { return "\(whole)\(suffix)" }
        let tenth = n % unit * 10 / unit
        return tenth == 0 ? "\(whole)\(suffix)" : "\(whole).\(tenth)\(suffix)"
    }

    private static func jsonObject(named name: String, in html: String) -> [String: Any]? {
        let pattern = "(?:var\\s+)?" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*\\{"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = html as NSString
        guard let match = regex.firstMatch(in: html,
                                           range: NSRange(location: 0, length: source.length)) else {
            return nil
        }
        let start = match.range.location + match.range.length - 1
        var depth = 0
        var quoted = false
        var escaped = false
        var index = start
        while index < source.length {
            let character = source.character(at: index)
            if quoted {
                if escaped {
                    escaped = false
                } else if character == 92 {
                    escaped = true
                } else if character == 34 {
                    quoted = false
                }
            } else if character == 34 {
                quoted = true
            } else if character == 123 {
                depth += 1
            } else if character == 125 {
                depth -= 1
                if depth == 0 {
                    let json = source.substring(with: NSRange(location: start, length: index - start + 1))
                    guard let data = json.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
                    return object as? [String: Any]
                }
            }
            index += 1
        }
        return nil
    }

    private static func objects(key: String, in node: Any) -> [[String: Any]] {
        var found: [[String: Any]] = []
        if let dictionary = node as? [String: Any] {
            if let child = dictionary[key] as? [String: Any] {
                found.append(child)
            }
            for value in dictionary.values {
                found.append(contentsOf: objects(key: key, in: value))
            }
        } else if let array = node as? [Any] {
            for value in array {
                found.append(contentsOf: objects(key: key, in: value))
            }
        }
        return found
    }

    private static func text(_ node: Any?) -> String? {
        if let dictionary = node as? [String: Any] {
            if let simple = dictionary["simpleText"] as? String, !simple.isEmpty {
                return simple
            }
            if let runs = dictionary["runs"] as? [[String: Any]] {
                let joined = runs.compactMap { $0["text"] as? String }.joined()
                return joined.isEmpty ? nil : joined
            }
        }
        if let string = node as? String, !string.isEmpty {
            return string
        }
        return nil
    }
}

private final class SongInfoRow: UIView {
    private let detail = UILabel()

    init(label: String, value: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = label
        title.font = Theme.font(15)
        title.textColor = UIColor(white: 1, alpha: 0.60)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)

        detail.text = value
        detail.font = Theme.font(15)
        detail.textColor = Theme.primaryText
        detail.textAlignment = .right
        detail.numberOfLines = 1
        detail.lineBreakMode = .byTruncatingMiddle

        for view in [title, detail] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
            detail.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func set(_ value: String) {
        detail.text = value
    }
}
