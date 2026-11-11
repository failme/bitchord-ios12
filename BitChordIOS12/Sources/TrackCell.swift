import UIKit

final class TrackCell: UITableViewCell {
    static let reuseIdentifier = "TrackCell"

    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var artworkTask: URLSessionDataTask?
    private var currentVideoID: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = Theme.background
        contentView.backgroundColor = Theme.background

        let selected = UIView()
        selected.backgroundColor = Theme.surface
        selectedBackgroundView = selected

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 4
        artworkView.backgroundColor = Theme.surface
        contentView.addSubview(artworkView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(15, weight: .medium)
        titleLabel.textColor = Theme.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = Theme.font(12)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            artworkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 44),
            artworkView.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -1),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 1)
        ])
    }

    func configure(with track: Track) {
        currentVideoID = track.videoID
        titleLabel.text = track.title
        let duration = track.durationText
        if track.artist.isEmpty {
            subtitleLabel.text = duration
        } else if duration.isEmpty {
            subtitleLabel.text = track.artist
        } else {
            subtitleLabel.text = "\(track.artist)  ·  \(duration)"
        }

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

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkTask?.cancel()
        artworkTask = nil
        artworkView.image = nil
        currentVideoID = nil
    }
}
