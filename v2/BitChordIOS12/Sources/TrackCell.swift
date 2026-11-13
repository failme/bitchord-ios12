import UIKit

/// A song row, measured off upstream's `SongRowContent`: 52pt artwork at radius
/// 8 with the same hairline, a 14pt gap, a 16pt medium title, a 14pt grey
/// subtitle, and the length on the right in 12pt.
final class TrackCell: UITableViewCell {
    static let reuseIdentifier = "TrackCell"

    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let durationLabel = UILabel()
    private var artworkTask: URLSessionDataTask?
    private var currentVideoID: String?
    private var track: Track?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let selected = UIView()
        selected.backgroundColor = Theme.surface
        selectedBackgroundView = selected

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.layer.borderWidth = 1
        // Upstream draws the same 15% hairline over every thumbnail.
        artworkView.layer.borderColor = UIColor(white: 1, alpha: 0.15).cgColor
        artworkView.backgroundColor = Theme.surfaceVariant
        contentView.addSubview(artworkView)

        // iOS 12 has no context-menu API, so the real app's per-track menu (its
        // sheet with Download / Delete download) is a long press and an action
        // sheet, which is the idiom this OS actually offers.
        let press = UILongPressGestureRecognizer(target: self, action: #selector(showTrackMenu(_:)))
        press.minimumPressDuration = 0.45
        press.cancelsTouchesInView = false
        contentView.addGestureRecognizer(press)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = Theme.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = Theme.font(.bodyMedium)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(subtitleLabel)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = Theme.font(.labelMedium)
        durationLabel.textColor = Theme.secondaryText
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentView.addSubview(durationLabel)

        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                 constant: Theme.gutter),
            artworkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: Theme.rowArtwork),
            artworkView.heightAnchor.constraint(equalToConstant: Theme.rowArtwork),

            titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -1),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor,
                                                    constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 2),

            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                    constant: -Theme.gutter),
            durationLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    func configure(with track: Track) {
        self.track = track
        currentVideoID = track.videoID
        titleLabel.attributedText = TrackCell.title(for: track)
        subtitleLabel.text = track.artist
        durationLabel.text = track.formattedDuration

        artworkTask?.cancel()
        let url = track.artworkURL
        if let cached = ArtworkLoader.shared.cached(url) {
            artworkView.image = cached
            return
        }
        artworkView.image = nil
        artworkTask = ArtworkLoader.shared.load(url) { [weak self] image in
            guard let self = self, self.currentVideoID == track.videoID else { return }
            self.artworkView.image = image
        }
    }

    // MARK: - Track menu

    @objc private func showTrackMenu(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let track = track,
              let host = TrackCell.topController() else { return }
        let store = DownloadStore.shared
        let sheet = UIAlertController(title: track.title, message: track.artist,
                                      preferredStyle: .actionSheet)
        if store.isDownloaded(track.videoID) {
            sheet.addAction(UIAlertAction(title: "Delete download", style: .destructive) { _ in
                store.remove(track.videoID)
            })
        } else if store.isDownloading(track.videoID) {
            sheet.addAction(UIAlertAction(title: "Cancel download", style: .cancel) { _ in
                store.cancel(track.videoID)
            })
        } else {
            sheet.addAction(UIAlertAction(title: "Download", style: .default) { _ in
                store.download(track) { ok, message in
                    guard !ok else { return }
                    guard let presenter = TrackCell.topController() else { return }
                    let alert = UIAlertController(title: "Download", message: message,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    presenter.present(alert, animated: true)
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = self
            pop.sourceRect = bounds
        }
        host.present(sheet, animated: true)
    }

    private static func topController() -> UIViewController? {
        var node = UIApplication.shared.keyWindow?.rootViewController
        while let presented = node?.presentedViewController {
            node = presented
        }
        return node
    }

    /// The title with Apple's explicit tile ahead of it, in the subtitle's grey,
    /// which is where upstream puts it.
    private static func title(for track: Track) -> NSAttributedString {
        let body = NSMutableAttributedString(string: track.title,
                                             attributes: [.font: Theme.font(.titleMedium),
                                                          .foregroundColor: Theme.primaryText,
                                                          .kern: Theme.kerning(.titleMedium)])
        guard track.isExplicit else { return body }
        let tile = NSTextAttachment()
        tile.image = Theme.explicitBadgeImage(side: 12, color: Theme.secondaryText)
        tile.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)
        let badge = NSMutableAttributedString(attachment: tile)
        badge.append(NSAttributedString(string: " ", attributes: [.font: Theme.font(.titleMedium)]))
        badge.append(body)
        return badge
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkTask?.cancel()
        artworkTask = nil
        artworkView.image = nil
        currentVideoID = nil
    }
}
