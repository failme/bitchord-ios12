import UIKit

/// Upstream's song-info dialog: a narrow alert card with the track at its head,
/// label/value rows, and a Done action at its foot. It is a dialog rather than
/// a page, so it opens over whatever raised it.
final class SongInfoViewController: UIViewController {
    private let track: Track
    private let card = UIView()
    private let scrim = UIView()

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

        // The title and artist are already the card's head, as in the real
        // dialog; the body carries the metadata behind them.
        let bodyRows = SongInfoViewController.rows(for: track).filter {
            $0.label != "Title" && $0.label != "Artist"
        }
        for (index, row) in bodyRows.enumerated() {
            if index > 0 {
                stack.addArrangedSubview(rule(fullWidth: false))
            }
            stack.addArrangedSubview(SongInfoRow(label: row.label, value: row.value))
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
        doneHolder.heightAnchor.constraint(equalToConstant: 48).isActive = true
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
            card.widthAnchor.constraint(equalToConstant: 280),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
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

    @objc private func dismissSelf() {
        dismiss(animated: false, completion: nil)
    }

    /// The same rows the dialog draws, so the harness can assert the values.
    static func rows(for track: Track) -> [(label: String, value: String)] {
        let saved = DownloadStore.shared.saved.first { $0.track.videoID == track.videoID }
        let source: String
        if track.videoID.hasPrefix(LocalMusicStore.idPrefix) {
            source = "Local file"
        } else if saved != nil {
            source = "Downloaded"
        } else {
            source = track.source == .youtube ? "YouTube Music" : "JioSaavn"
        }
        let quality = saved.map { $0.qualityLabel.isEmpty ? "Downloaded" : $0.qualityLabel }
            ?? (track.videoID.hasPrefix(LocalMusicStore.idPrefix) ? "Device file" : "Stream")
        return [
            ("Title", track.title),
            ("Artist", track.artist.isEmpty ? "Unknown artist" : track.artist),
            ("Album", track.album.isEmpty ? "Single" : track.album),
            ("Duration", track.formattedDuration),
            ("Source", source),
            ("Quality", quality),
            ("Track id", track.videoID)
        ]
    }
}

private final class SongInfoRow: UIView {
    init(label: String, value: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = label
        title.font = Theme.font(15)
        title.textColor = UIColor(white: 1, alpha: 0.60)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)

        let detail = UILabel()
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
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 13),
            detail.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -13)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }
}
