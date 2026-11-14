import UIKit

/// Home's "Top Picks for You" row as the real app draws it: 248pt-wide 3:4
/// portrait cards, a small grey source line below the artwork, then the title
/// and its "Single · 2026" style detail.
final class TopPicksShelfView: UIView {
    static let cardWidth: CGFloat = 248
    // Section height: title, 6pt gap, the 3:4 card, then bottom padding.
    static let rowHeight: CGFloat = 393

    private let titleLabel = UILabel()
    private let collectionView: UICollectionView
    private var tracks: [Track] = []

    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: TopPicksShelfView.cardWidth,
                                 height: TopPicksShelfView.cardWidth * 4.0 / 3.0)
        layout.minimumLineSpacing = 14
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

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(tracks: [Track]) {
        self.tracks = tracks
        collectionView.reloadData()
    }

    func motionFirstArtworkFrame(in view: UIView) -> CGRect? {
        layoutIfNeeded()
        guard let cell = collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? TopPickCell else {
            return nil
        }
        return cell.motionArtworkFrame(in: view)
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
    private let captionShade = CAGradientLayer()
    private let sourceLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The real card is one 3:4 picture with its caption sitting on the
        // picture's darkened foot. The first pass put a square cover above a
        // separate text block, which is why the cards read short and boxy.
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true
        contentView.backgroundColor = Theme.surfaceVariant

        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artwork)

        captionShade.colors = [UIColor.clear.cgColor,
                               UIColor(white: 0, alpha: 0.45).cgColor,
                               UIColor(white: 0, alpha: 0.82).cgColor]
        captionShade.locations = [0.45, 0.72, 1]
        captionShade.startPoint = CGPoint(x: 0.5, y: 0)
        captionShade.endPoint = CGPoint(x: 0.5, y: 1)
        contentView.layer.addSublayer(captionShade)

        for label in [sourceLabel, titleLabel, detailLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
        }
        sourceLabel.font = Theme.font(13)
        sourceLabel.textColor = UIColor(white: 1, alpha: 0.62)
        titleLabel.font = Theme.font(17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        detailLabel.font = Theme.font(13)
        detailLabel.textColor = UIColor(white: 1, alpha: 0.86)
        detailLabel.numberOfLines = 2

        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artwork.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            detailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            titleLabel.leadingAnchor.constraint(equalTo: detailLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: detailLabel.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: detailLabel.topAnchor),

            sourceLabel.leadingAnchor.constraint(equalTo: detailLabel.leadingAnchor),
            sourceLabel.trailingAnchor.constraint(equalTo: detailLabel.trailingAnchor),
            sourceLabel.bottomAnchor.constraint(equalTo: titleLabel.topAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        captionShade.frame = contentView.bounds
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.18, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.contentView.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }

    func configure(track: Track) {
        sourceLabel.text = "New from \(track.artist)"
        titleLabel.text = track.title
        detailLabel.text = track.artist
        artwork.image = nil
        ArtworkLoader.shared.load(track.largeArtworkURL) { [weak self] image in
            guard let self = self, let image = image else { return }
            UIView.transition(with: self.artwork, duration: 0.25,
                              options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.artwork.image = image
            }
        }
    }

    func motionArtworkFrame(in view: UIView) -> CGRect {
        return contentView.convert(contentView.bounds, to: view)
    }
}
