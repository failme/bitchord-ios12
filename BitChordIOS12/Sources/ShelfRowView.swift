import UIKit

/// A horizontally scrolling shelf of square artwork cards, the shape upstream's
/// Home uses for every section (Quick picks, Recently played, Liked songs).
///
/// This is the piece that changes Home from a stack of table rows into the
/// artwork-forward layout the original app is built around.
final class ShelfRowView: UIView {
    /// Called with the tapped index in `tracks`; the host starts playback there.
    var onSelect: ((Int) -> Void)?
    var onPlayAll: (() -> Void)?

    private let titleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let collectionView: UICollectionView
    private var tracks: [Track] = []

    static let cardWidth: CGFloat = 152
    static let rowHeight: CGFloat = 232

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: ShelfRowView.cardWidth, height: ShelfRowView.rowHeight - 36)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: ShelfRowView.cardWidth, height: ShelfRowView.rowHeight - 36)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(coder: coder)
        build()
    }

    private func build() {
        backgroundColor = .clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(20, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        addSubview(titleLabel)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setTitle("Play", for: .normal)
        playButton.titleLabel?.font = Theme.font(13, weight: .semibold)
        playButton.tintColor = Theme.primaryText
        playButton.addTarget(self, action: #selector(playAll), for: .touchUpInside)
        addSubview(playButton)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ArtworkCardCell.self,
                                forCellWithReuseIdentifier: ArtworkCardCell.reuseIdentifier)
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: playButton.leadingAnchor, constant: -8),

            playButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            playButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(title: String, tracks: [Track], showsPlayAll: Bool = true) {
        titleLabel.text = title
        playButton.isHidden = !showsPlayAll || tracks.isEmpty
        self.tracks = tracks
        collectionView.reloadData()
    }

    @objc private func playAll() {
        onPlayAll?()
    }
}

extension ShelfRowView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tracks.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ArtworkCardCell.reuseIdentifier,
                                                      for: indexPath)
        if let card = cell as? ArtworkCardCell {
            card.configure(with: tracks[indexPath.row])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onSelect?(indexPath.row)
    }
}

/// A shelf of cards that are not playable tracks (albums, charts), so the host
/// decides what a tap means.
struct CardItem {
    let id: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
}

final class CardShelfView: UIView {
    var onSelect: ((Int) -> Void)?
    static let rowHeight: CGFloat = 232

    private let titleLabel = UILabel()
    private let collectionView: UICollectionView
    private var items: [CardItem] = []

    override init(frame: CGRect) {
        collectionView = CardShelfView.makeCollection()
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        collectionView = CardShelfView.makeCollection()
        super.init(coder: coder)
        build()
    }

    private static func makeCollection() -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: ShelfRowView.cardWidth, height: CardShelfView.rowHeight - 36)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }

    private func build() {
        backgroundColor = .clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(20, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        addSubview(titleLabel)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CardItemCell.self, forCellWithReuseIdentifier: CardItemCell.reuseIdentifier)
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(title: String, items: [CardItem]) {
        titleLabel.text = title
        titleLabel.isHidden = title.isEmpty
        self.items = items
        collectionView.reloadData()
    }
}

extension CardShelfView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CardItemCell.reuseIdentifier,
                                                      for: indexPath)
        if let card = cell as? CardItemCell {
            card.configure(items[indexPath.row])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onSelect?(indexPath.row)
    }
}

final class CardItemCell: UICollectionViewCell {
    static let reuseIdentifier = "CardItemCell"

    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var task: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.backgroundColor = Theme.surfaceVariant
        contentView.addSubview(artworkView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(13, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = Theme.font(12)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.numberOfLines = 1
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            artworkView.topAnchor.constraint(equalTo: contentView.topAnchor),
            artworkView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artworkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    func configure(_ item: CardItem) {
        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
        task?.cancel()
        artworkView.image = nil
        guard let url = item.artworkURL else { return }
        if let cached = ArtworkLoader.shared.cached(url) {
            artworkView.image = cached
            return
        }
        task = ArtworkLoader.shared.load(url) { [weak self] image in
            self?.artworkView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        artworkView.image = nil
    }
}

/// The mood strip: pill chips that scroll sideways, as upstream's Home and
/// Explore both open with.
final class ChipRowView: UIView {
    var onSelect: ((String) -> Void)?
    static let rowHeight: CGFloat = 34

    private let collectionView: UICollectionView
    private var titles: [String] = []

    override init(frame: CGRect) {
        collectionView = ChipRowView.makeCollection()
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        collectionView = ChipRowView.makeCollection()
        super.init(coder: coder)
        build()
    }

    private static func makeCollection() -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.estimatedItemSize = CGSize(width: 80, height: 34)
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }

    private func build() {
        backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ChipCell.self, forCellWithReuseIdentifier: ChipCell.reuseIdentifier)
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(titles: [String]) {
        self.titles = titles
        collectionView.reloadData()
    }
}

extension ChipRowView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return titles.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChipCell.reuseIdentifier,
                                                      for: indexPath)
        if let chip = cell as? ChipCell {
            chip.configure(titles[indexPath.row])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onSelect?(titles[indexPath.row])
    }
}

final class ChipCell: UICollectionViewCell {
    static let reuseIdentifier = "ChipCell"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = Theme.surfaceVariant
        contentView.layer.cornerRadius = 17
        contentView.clipsToBounds = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.font(13, weight: .semibold)
        label.textColor = Theme.primaryText
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    func configure(_ title: String) {
        label.text = title
    }
}

/// Artwork, title and artist: the card shape every upstream shelf is made of.
final class ArtworkCardCell: UICollectionViewCell {
    static let reuseIdentifier = "ArtworkCardCell"

    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var artworkTask: URLSessionDataTask?
    private var currentVideoID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.backgroundColor = Theme.surfaceVariant
        contentView.addSubview(artworkView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(13, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = Theme.font(12)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.numberOfLines = 1
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            artworkView.topAnchor.constraint(equalTo: contentView.topAnchor),
            artworkView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artworkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    func configure(with track: Track) {
        currentVideoID = track.videoID
        titleLabel.text = track.title
        subtitleLabel.text = track.artist.isEmpty ? AudioEngine.shared.currentSourceLabel : track.artist

        artworkTask?.cancel()
        let url = track.largeArtworkURL
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
