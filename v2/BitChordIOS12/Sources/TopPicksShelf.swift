import UIKit

/// Home's "Top Picks for You" row as the real app draws it: 300pt cards whose
/// artwork fills the card, a small grey source line above the title, then the
/// title and its "Single · 2026" style detail.
final class TopPicksShelfView: UIView {
    static let cardWidth: CGFloat = 248
    static let rowHeight: CGFloat = 368

    private let titleLabel = UILabel()
    private let collectionView: UICollectionView
    private var tracks: [Track] = []

    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: TopPicksShelfView.cardWidth,
                                 height: TopPicksShelfView.rowHeight - 34)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func build() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(16, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.text = "Top Picks for You"
        addSubview(titleLabel)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TopPickCell.self,
                                forCellWithReuseIdentifier: TopPickCell.reuseIdentifier)
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(tracks: [Track]) {
        self.tracks = tracks
        collectionView.reloadData()
    }
}

extension TopPicksShelfView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tracks.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TopPickCell.reuseIdentifier,
                                                      for: indexPath) as! TopPickCell
        cell.configure(track: tracks[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(indexPath.item)
    }
}

final class TopPickCell: UICollectionViewCell {
    static let reuseIdentifier = "TopPickCell"

    private let artwork = UIImageView()
    private let sourceLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 8
        artwork.backgroundColor = Theme.surfaceVariant
        artwork.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artwork)

        for label in [sourceLabel, titleLabel, detailLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
        }
        sourceLabel.font = Theme.font(12)
        sourceLabel.textColor = Theme.secondaryText
        titleLabel.font = Theme.font(18, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2
        detailLabel.font = Theme.font(14)
        detailLabel.textColor = Theme.secondaryText

        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artwork.heightAnchor.constraint(equalToConstant: 248),

            sourceLabel.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: 10),
            sourceLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sourceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            titleLabel.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 2),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(track: Track) {
        sourceLabel.text = track.album.isEmpty ? "Top pick" : track.album
        titleLabel.text = track.title
        detailLabel.text = track.artist
        artwork.image = nil
        ArtworkLoader.shared.load(track.largeArtworkURL) { [weak self] image in
            self?.artwork.image = image
        }
    }
}
