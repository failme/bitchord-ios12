import UIKit

/// Library, shaped like upstream's: two large tiles for Liked Songs and
/// Recently Played, then a grid of playlist covers you can open or create.
final class LibraryViewController: UIViewController {
    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    private var playlists: [Playlist] = []
    private var likedCount = 0
    private var recentCount = 0

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        collectionView = LibraryViewController.makeCollection()
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        collectionView = LibraryViewController.makeCollection()
        super.init(coder: coder)
    }

    private static func makeCollection() -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 20
        layout.minimumInteritemSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 4, left: 20, bottom: 28, right: 20)
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Library"
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: Icons.image(.plus, size: 20),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(createPlaylist))

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = Theme.background
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(LibraryTileCell.self,
                                forCellWithReuseIdentifier: LibraryTileCell.reuseIdentifier)
        collectionView.register(LibraryHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: LibraryHeaderView.reuseIdentifier)
        view.addSubview(collectionView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(reload),
                                              name: .libraryDidChange,
                                              object: nil)
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reload() {
        let store = LibraryStore.shared
        playlists = store.playlists
        likedCount = store.likedTracks.count
        recentCount = store.recentTracks.count
        collectionView.reloadData()
    }

    @objc private func createPlaylist() {
        let alert = UIAlertController(title: "New playlist", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Playlist name"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { _ in
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            LibraryStore.shared.createPlaylist(title: name)
        })
        present(alert, animated: true, completion: nil)
    }

    private func push(_ tracks: [Track], title: String, playlistID: String? = nil, empty: String) {
        let list = TrackListViewController()
        list.title = title
        list.tracks = tracks
        list.playlistID = playlistID
        list.emptyText = empty
        navigationController?.pushViewController(list, animated: true)
    }
}

extension LibraryViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return section == 0 ? 2 : playlists.count + 1
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: LibraryHeaderView.reuseIdentifier,
            for: indexPath)
        if let titled = header as? LibraryHeaderView {
            titled.configure(title: indexPath.section == 1 ? "Playlists" : "")
        }
        return header
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard section == 1 else { return .zero }
        return CGSize(width: collectionView.bounds.width, height: 34)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let available = collectionView.bounds.width - 40 - 12
        let width = floor(available / 2)
        return CGSize(width: width, height: width + 44)
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LibraryTileCell.reuseIdentifier,
                                                      for: indexPath)
        guard let tile = cell as? LibraryTileCell else { return cell }

        if indexPath.section == 0 {
            if indexPath.item == 0 {
                tile.configure(title: "Liked Songs",
                               subtitle: "\(likedCount) songs",
                               icon: .heartFilled,
                               artworkURL: LibraryStore.shared.likedTracks.first?.largeArtworkURL)
            } else {
                tile.configure(title: "Recently Played",
                               subtitle: "\(recentCount) songs",
                               icon: .musicNote,
                               artworkURL: LibraryStore.shared.recentTracks.first?.largeArtworkURL)
            }
            return tile
        }

        if indexPath.item < playlists.count {
            let playlist = playlists[indexPath.item]
            tile.configure(title: playlist.title,
                           subtitle: "\(playlist.tracks.count) songs",
                           icon: .musicNote,
                           artworkURL: playlist.tracks.first?.largeArtworkURL)
        } else {
            tile.configureEmpty(title: "New Playlist")
        }
        return tile
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        let store = LibraryStore.shared

        if indexPath.section == 0 {
            if indexPath.item == 0 {
                push(store.likedTracks, title: "Liked Songs", empty: "Songs you like appear here.")
            } else {
                push(store.recentTracks, title: "Recently Played", empty: "Nothing played yet.")
            }
            return
        }

        if indexPath.item < playlists.count {
            let playlist = playlists[indexPath.item]
            push(playlist.tracks, title: playlist.title, playlistID: playlist.id,
                 empty: "This playlist is empty.")
        } else {
            createPlaylist()
        }
    }
}

/// A square cover with a title and a count under it — the library grid's unit.
final class LibraryTileCell: UICollectionViewCell {
    static let reuseIdentifier = "LibraryTileCell"

    private let artworkView = UIImageView()
    private let iconView = UIImageView()
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

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = UIColor(white: 1, alpha: 0.75)
        iconView.contentMode = .scaleAspectFit
        artworkView.addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(13, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = Theme.font(12)
        subtitleLabel.textColor = Theme.secondaryText
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            artworkView.topAnchor.constraint(equalTo: contentView.topAnchor),
            artworkView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artworkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),

            iconView.centerXAnchor.constraint(equalTo: artworkView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: artworkView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    func configure(title: String, subtitle: String, icon: Icons.Kind, artworkURL: URL?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        iconView.image = Icons.image(icon, size: 26)
        task?.cancel()
        artworkView.image = nil
        guard let url = artworkURL else { return }
        if let cached = ArtworkLoader.shared.cached(url) {
            artworkView.image = cached
            return
        }
        task = ArtworkLoader.shared.load(url) { [weak self] image in
            self?.artworkView.image = image
        }
    }

    func configureEmpty(title: String) {
        titleLabel.text = title
        subtitleLabel.text = "Create a playlist"
        iconView.image = Icons.image(.plus, size: 26)
        artworkView.image = nil
        task?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        artworkView.image = nil
    }
}

final class LibraryHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "LibraryHeaderView"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.font(20, weight: .bold)
        label.textColor = Theme.primaryText
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configure(title: String) {
        label.text = title
        label.isHidden = title.isEmpty
    }
}
