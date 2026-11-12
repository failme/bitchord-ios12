import UIKit

/// Home, shaped like upstream's: large title, then full-width shelves of square
/// artwork cards that scroll sideways, instead of one long table of rows.
final class HomeViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let emptyLabel = UILabel()
    private let greetingLabel = UILabel()
    private let releasesShelf = CardShelfView()
    private let topPicks = TopPicksShelfView()
    private var albums: [CatalogueAlbum] = []

    private var remoteQuickPicks: [Track] = []
    private var shelfViews: [String: ShelfRowView] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = ""
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 28
        stack.alignment = .fill
        scrollView.addSubview(stack)

        // The real Home has no page title: the mark sits at the left of a bare
        // top bar and the account avatar at its right.
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false

        // The app's own artwork, rasterised from its shipped SVG rather than
        // redrawn by hand.
        let logo = UIImageView(image: UIImage(named: "BrandLogo") ?? Icons.image(.logo, size: 30))
        logo.tintColor = Theme.primaryText
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(logo)

        let avatar = UIButton(type: .system)
        avatar.backgroundColor = Theme.surfaceVariant
        avatar.layer.cornerRadius = 19
        avatar.tintColor = Theme.secondaryText
        avatar.setImage(Icons.image(.person, size: 20), for: .normal)
        avatar.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(avatar)

        NSLayoutConstraint.activate([
            // Upstream's HomeTitle: the wordmark is 0.9x the 34pt display size,
            // 730:484, with 14pt under it.
            header.heightAnchor.constraint(equalToConstant: 46),
            logo.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Theme.gutter),
            logo.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 56),
            logo.heightAnchor.constraint(equalToConstant: 37),
            avatar.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -Theme.gutter),
            avatar.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 38),
            avatar.heightAnchor.constraint(equalToConstant: 38)
        ])
        stack.addArrangedSubview(header)

        // The real feed opens with the large Top Picks cards, not a small shelf.
        topPicks.translatesAutoresizingMaskIntoConstraints = false
        topPicks.heightAnchor.constraint(equalToConstant: TopPicksShelfView.rowHeight).isActive = true
        topPicks.isHidden = true
        topPicks.onSelect = { [weak self] index in
            guard let self = self else { return }
            PlayerService.shared.play(tracks: self.remoteQuickPicks, startingAt: index)
            self.presentNowPlayingFromRoot()
        }
        stack.addArrangedSubview(topPicks)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -28),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

        ])

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(rebuild),
                                              name: .libraryDidChange,
                                              object: nil)
        rebuild()
        loadQuickPicks()
        loadNewReleases()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<17: part = "Good afternoon"
        case 17..<22: part = "Good evening"
        default: part = "Good night"
        }
        return part
    }

    /// Live catalog shelf, so Home is not empty on a first launch with no local history.
    private func loadQuickPicks() {
        let year = Calendar.current.component(.year, from: Date())
        InnerTube.shared.search("Top songs \(year)", filter: .songs) { [weak self] tracks, _ in
            guard let self = self, let tracks = tracks, !tracks.isEmpty else { return }
            self.remoteQuickPicks = Array(tracks.prefix(20))
            self.topPicks.configure(tracks: self.remoteQuickPicks)
            self.topPicks.isHidden = false
            // rebuild() can return early when the shelf shape is unchanged, so
            // the empty state is cleared here, where the feed first appears.
            self.scrollView.isHidden = false
            self.rebuild()
        }
    }

    /// A second shelf straight from the catalogue, so a first launch has more
    /// on it than one row of picks.
    private func loadNewReleases() {
        CatalogueSearch.shared.albums("Latest albums") { [weak self] albums in
            guard let self = self else { return }
            // The catalogue answers a "new releases" query with compilations
            // literally called "Releases", "New Releases", "Recent Releases"…
            // They are not albums anyone meant to browse, so they are dropped
            // and the shelf keeps only rows with a real name.
            let generic: Set<String> = ["releases", "new releases", "recent releases",
                                        "latest releases", "all music releases", "releases 2026"]
            let named = albums.filter { album in
                let key = album.title.lowercased().trimmingCharacters(in: .whitespaces)
                return !generic.contains(key) && !key.hasSuffix(" releases")
            }
            guard !named.isEmpty else { return }
            self.albums = Array(named.prefix(12))
            var cards: [CardItem] = []
            for album in self.albums {
                let bits = [album.artist, album.year].filter { !$0.isEmpty }
                cards.append(CardItem(id: album.id,
                                      title: album.title,
                                      subtitle: bits.joined(separator: " · "),
                                      artworkURL: album.artwork))
            }
            self.releasesShelf.configure(title: "Albums & singles", items: cards)
            self.releasesShelf.onSelect = { [weak self] index in
                guard let self = self, index < self.albums.count else { return }
                self.openAlbum(self.albums[index])
            }
            if self.releasesShelf.superview == nil {
                self.releasesShelf.heightAnchor.constraint(
                    equalToConstant: CardShelfView.rowHeight).isActive = true
                self.stack.addArrangedSubview(self.releasesShelf)
            }
        }
    }

    private func openAlbum(_ album: CatalogueAlbum) {
        let controller = CollectionViewController(title: album.title,
                                                  subtitle: album.artist,
                                                  artwork: album.artwork)
        controller.loader = { completion in
            CatalogueSearch.shared.songs(inAlbum: album.id) { completion($0) }
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The capsule tab bar floats over the content, so the list needs its
        // own clearance or the last shelf scrolls under it.
        scrollView.contentInset.bottom = 104
        scrollView.scrollIndicatorInsets.bottom = 104
    }

    @objc private func openSettings() {
        let settings = SettingsViewController()
        let navigation = UINavigationController(rootViewController: settings)
        navigation.navigationBar.barTintColor = Theme.background
        navigation.navigationBar.tintColor = Theme.accent
        navigation.navigationBar.isTranslucent = false
        navigation.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        settings.modalPresentationStyle = .fullScreen
        present(navigation, animated: true, completion: nil)
    }

    @objc private func rebuild() {
        let store = LibraryStore.shared
        var shelves: [(String, [Track])] = []
        if let continueTrack = store.continueListeningTrack {
            shelves.append(("Continue listening", [continueTrack]))
        }
        if !store.recentTracks.isEmpty {
            shelves.append(("Recently played", store.recentTracks))
        }
        if !store.quickPicks.isEmpty {
            shelves.append(("Your picks", store.quickPicks))
        }
        if !store.likedTracks.isEmpty {
            shelves.append(("Liked songs", store.likedTracks))
        }

        // Rebuild only when the shape changed; reloading on every library event
        // would reset each shelf's horizontal scroll position.
        let signature = shelves.map { $0.0 + ":" + $0.1.map { $0.videoID }.joined(separator: ",") }
        if signature == (stack.arrangedSubviews.compactMap { ($0 as? ShelfRowView)?.accessibilityIdentifier }) {
            return
        }

        for view in stack.arrangedSubviews where view is ShelfRowView {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        shelfViews.removeAll()

        for (title, tracks) in shelves {
            let row = ShelfRowView()
            row.accessibilityIdentifier = title + ":" + tracks.map { $0.videoID }.joined(separator: ",")
            row.configure(title: title, tracks: tracks)
            row.onSelect = { [weak self] index in
                guard let self = self else { return }
                PlayerService.shared.play(tracks: tracks, startingAt: index)
                self.presentNowPlayingFromRoot()
            }
            row.onPlayAll = { [weak self] in
                guard !tracks.isEmpty else { return }
                PlayerService.shared.play(tracks: tracks, startingAt: 0)
                self?.presentNowPlayingFromRoot()
            }
            row.heightAnchor.constraint(equalToConstant: ShelfRowView.rowHeight).isActive = true
            stack.addArrangedSubview(row)
            shelfViews[title] = row
        }

        scrollView.isHidden = shelves.isEmpty && topPicks.isHidden
    }
}
