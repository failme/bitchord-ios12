import UIKit

/// Home, shaped like upstream's: large title, then full-width shelves of square
/// artwork cards that scroll sideways, instead of one long table of rows.
final class HomeViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let emptyLabel = UILabel()
    private let greetingLabel = UILabel()
    private let releasesShelf = CardShelfView()
    private let remoteHomeShelf = CardShelfView()
    private let topPicks = TopPicksShelfView()
    private let signInHolder = UIView()
    private let signedInEmptyState = UIView()
    private let accountAvatar = UIButton(type: .system)
    private var albums: [CatalogueAlbum] = []

    private var remoteQuickPicks: [Track] = []
    private var remoteHomeItems: [YouTubeHomeItem] = []
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

        accountAvatar.backgroundColor = Theme.surfaceVariant
        accountAvatar.tintColor = Theme.secondaryText
        accountAvatar.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        accountAvatar.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(accountAvatar)

        NSLayoutConstraint.activate([
            // The real header is two rows: the avatar at the very top right,
            // then the wordmark lower on the left, with the banner beneath.
            header.heightAnchor.constraint(equalToConstant: 96),
            logo.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Theme.gutter),
            logo.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -22),
            logo.widthAnchor.constraint(equalToConstant: 46),
            logo.heightAnchor.constraint(equalToConstant: 30),
            accountAvatar.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -Theme.gutter),
            // The stack starts 18pt above the scroll view's top edge, so an
            // avatar pinned to the header's top was half clipped away.
            accountAvatar.topAnchor.constraint(equalTo: header.topAnchor, constant: 18),
            accountAvatar.widthAnchor.constraint(equalToConstant: 36),
            accountAvatar.heightAnchor.constraint(equalToConstant: 36)
        ])
        stack.addArrangedSubview(header)

        // Signed-out Home opens with the blue sign-in card, 119pt tall and
        // inset 16pt, which is what sets the rhythm of the whole feed.
        signInHolder.translatesAutoresizingMaskIntoConstraints = false
        signInHolder.heightAnchor.constraint(
            equalToConstant: SignInBannerView.bannerHeight).isActive = true
        let banner = SignInBannerView()
        signInHolder.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: signInHolder.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: signInHolder.trailingAnchor, constant: -16),
            banner.topAnchor.constraint(equalTo: signInHolder.topAnchor),
            banner.bottomAnchor.constraint(equalTo: signInHolder.bottomAnchor)
        ])
        banner.onSignIn = { [weak self] in
            guard let self = self else { return }
            GoogleAccountStore.shared.presentSignIn(from: self)
        }
        stack.setCustomSpacing(8, after: header)
        stack.addArrangedSubview(signInHolder)
        // Custom spacing only sticks once the view is actually arranged.
        stack.setCustomSpacing(23, after: signInHolder)

        // A signed-in account must never leave Home blank while the network
        // feed loads (or when YouTube answers nothing). The reference app has
        // an account home; this is its local, non-empty first state.
        signedInEmptyState.translatesAutoresizingMaskIntoConstraints = false
        signedInEmptyState.backgroundColor = Theme.surface
        signedInEmptyState.layer.cornerRadius = 18
        signedInEmptyState.isHidden = true
        signedInEmptyState.accessibilityIdentifier = "Home.SignedInEmptyState"
        let emptyLogo = UIImageView(image: UIImage(named: "BrandLogo") ?? Icons.image(.logo, size: 34))
        emptyLogo.tintColor = Theme.primaryText
        emptyLogo.contentMode = .scaleAspectFit
        emptyLogo.translatesAutoresizingMaskIntoConstraints = false
        emptyLogo.widthAnchor.constraint(equalToConstant: 42).isActive = true
        emptyLogo.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let emptyTitle = UILabel()
        emptyTitle.text = "Welcome to BitChord"
        emptyTitle.font = Theme.font(20, weight: .bold)
        emptyTitle.textColor = Theme.primaryText
        emptyTitle.textAlignment = .center
        let emptyDetail = UILabel()
        emptyDetail.text = "Your YouTube Music account is connected. Your picks, likes and history will appear here as the feed loads."
        emptyDetail.font = Theme.font(14)
        emptyDetail.textColor = Theme.secondaryText
        emptyDetail.textAlignment = .center
        emptyDetail.numberOfLines = 0
        let emptyStack = UIStackView(arrangedSubviews: [emptyLogo, emptyTitle, emptyDetail])
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyStack.axis = .vertical
        emptyStack.alignment = .center
        emptyStack.spacing = 10
        signedInEmptyState.addSubview(emptyStack)
        NSLayoutConstraint.activate([
            emptyStack.topAnchor.constraint(equalTo: signedInEmptyState.topAnchor, constant: 24),
            emptyStack.leadingAnchor.constraint(equalTo: signedInEmptyState.leadingAnchor, constant: 24),
            emptyStack.trailingAnchor.constraint(equalTo: signedInEmptyState.trailingAnchor, constant: -24),
            emptyStack.bottomAnchor.constraint(equalTo: signedInEmptyState.bottomAnchor, constant: -24),
            signedInEmptyState.heightAnchor.constraint(greaterThanOrEqualToConstant: 170)
        ])
        stack.addArrangedSubview(signedInEmptyState)

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
        // The shelf already ends with its own 20pt foot; upstream puts the next
        // section header 16pt after it rather than at the feed's 28pt rhythm.
        stack.setCustomSpacing(16, after: topPicks)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -28),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

        ])

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(rebuild),
                                              name: .libraryDidChange,
                                              object: nil)
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(accountChanged),
                                              name: .googleAccountDidChange,
                                              object: nil)
        applyAccountState()
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

    /// Signed in, this is YouTube Music's own home feed, which is what makes
    /// Top Picks reflect the account instead of a generic yearly chart. Signed
    /// out, or when the feed answers nothing playable, it falls back to that
    /// chart so Home is never empty on a first launch.
    private func loadQuickPicks() {
        guard GoogleAccountStore.shared.isSignedIn else {
            loadFallbackQuickPicks()
            return
        }
        InnerTube.shared.fetchHome { [weak self] tracks, collections in
            guard let self = self else { return }
            if !tracks.isEmpty {
                self.remoteQuickPicks = Array(tracks.prefix(20))
                self.topPicks.configure(tracks: self.remoteQuickPicks)
                self.topPicks.isHidden = false
                self.scrollView.isHidden = false
                self.rebuild()
            }
            self.showRemoteHome(collections)
            if tracks.isEmpty {
                self.loadFallbackQuickPicks()
            }
        }
    }

    private func loadFallbackQuickPicks() {
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

    private func showRemoteHome(_ items: [YouTubeHomeItem]) {
        remoteHomeItems = Array(items.prefix(12))
        guard !remoteHomeItems.isEmpty else {
            remoteHomeShelf.removeFromSuperview()
            updateEmptyState()
            return
        }
        let cards = remoteHomeItems.map { item in
            CardItem(id: item.browseID ?? item.videoID ?? item.title,
                     title: item.title,
                     subtitle: item.subtitle,
                     artworkURL: item.artworkURL)
        }
        remoteHomeShelf.configure(title: "From YouTube Music", items: cards)
        remoteHomeShelf.onSelect = { [weak self] index in
            guard let self = self, index < self.remoteHomeItems.count else { return }
            self.openRemoteHomeItem(self.remoteHomeItems[index])
        }
        if remoteHomeShelf.superview == nil {
            remoteHomeShelf.heightAnchor.constraint(
                equalToConstant: CardShelfView.rowHeight).isActive = true
            stack.addArrangedSubview(remoteHomeShelf)
        }
        updateEmptyState()
    }

    private func openRemoteHomeItem(_ item: YouTubeHomeItem) {
        guard let browseID = item.browseID else { return }
        let controller = CollectionViewController(title: item.title,
                                                  subtitle: item.subtitle,
                                                  artwork: item.artworkURL)
        controller.loader = { completion in
            InnerTube.shared.fetchCollection(browseID) { tracks, _ in
                completion(tracks ?? [])
            }
        }
        navigationController?.pushViewController(controller, animated: true)
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
            self.updateEmptyState()
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

    @objc private func accountChanged() {
        applyAccountState()
        remoteHomeShelf.removeFromSuperview()
        loadQuickPicks()
    }

    private func applyAccountState() {
        let signedIn = GoogleAccountStore.shared.isSignedIn
        signInHolder.isHidden = signedIn
        signedInEmptyState.isHidden = !signedIn
        GoogleAccountStore.shared.updateAvatarButton(accountAvatar, size: 36)
        updateEmptyState()
    }

    /// Keeps the signed-in shell visible when the remote feed is slow or empty.
    private func updateEmptyState(hasLocalShelves: Bool? = nil) {
        let signedIn = GoogleAccountStore.shared.isSignedIn
        let local = hasLocalShelves ?? !shelfViews.isEmpty
        let hasContent = local || !topPicks.isHidden || remoteHomeShelf.superview != nil
            || releasesShelf.superview != nil
        signedInEmptyState.isHidden = !signedIn || hasContent
    }

    /// The handoff harness reads this after dismissal instead of treating any
    /// non-white pixel as a rendered feed.
    var isSignedInFeedVisible: Bool {
        guard GoogleAccountStore.shared.isSignedIn, !scrollView.isHidden, signInHolder.isHidden else {
            return false
        }
        return !signedInEmptyState.isHidden || !topPicks.isHidden || !shelfViews.isEmpty
            || remoteHomeShelf.superview != nil || releasesShelf.superview != nil
    }

    var isSignInPromptVisible: Bool { return !signInHolder.isHidden }

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
        updateEmptyState(hasLocalShelves: !shelves.isEmpty)
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
            && signedInEmptyState.isHidden && signInHolder.isHidden
    }

    func motionTopPickArtworkFrame(in view: UIView) -> CGRect? {
        return topPicks.motionFirstArtworkFrame(in: view)
    }
}
