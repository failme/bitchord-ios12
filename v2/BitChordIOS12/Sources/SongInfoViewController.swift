import UIKit

/// Upstream's song-info dialog: what is playing, where it came from and at what
/// quality. Values are the ones playback is using, not a second lookup.
final class SongInfoViewController: UIViewController {
    private let track: Track
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    init(track: Track) {
        self.track = track
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let title = UILabel()
        title.text = "Song info"
        title.font = Theme.font(22, weight: .bold)
        title.textColor = Theme.primaryText
        title.translatesAutoresizingMaskIntoConstraints = false

        let close = UIButton(type: .system)
        close.setTitle("Done", for: .normal)
        close.setTitleColor(Theme.primaryText, for: .normal)
        close.titleLabel?.font = Theme.font(15, weight: .semibold)
        close.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in SongInfoViewController.rows(for: track) {
            stack.addArrangedSubview(SongInfoRow(label: row.label, value: row.value))
        }

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(title)
        view.addSubview(close)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            stack.topAnchor.constraint(equalTo: scroll.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])
    }

    @objc private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }

    /// The same rows the screen draws, so the harness can assert the values.
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
        let title = UILabel()
        title.text = label.uppercased()
        title.font = Theme.font(11, weight: .semibold)
        title.textColor = Theme.secondaryText

        let detail = UILabel()
        detail.text = value
        detail.font = Theme.font(15)
        detail.textColor = Theme.primaryText
        detail.numberOfLines = 0

        for view in [title, detail] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor),
            title.leadingAnchor.constraint(equalTo: leadingAnchor),
            title.trailingAnchor.constraint(equalTo: trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            detail.leadingAnchor.constraint(equalTo: leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor),
            detail.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }
}
