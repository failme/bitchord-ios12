import UIKit

/// Explore, shaped like upstream's: a mood strip, then sideways shelves of
/// trending songs, new albums and top charts instead of one long table.
final class ExploreViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let spinner = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    private let moods: [String] = [
        "Chill", "Energy", "Workout", "Focus", "Party", "Romance",
        "Sad", "Sleep", "Commute", "Feel good", "Pop", "Hip-hop",
        "Rock", "R&B", "Jazz", "Classical", "Electronic", "Indie"
    ]

    private let chips = ChipRowView()
    private let trendingShelf = ShelfRowView()
    private let albumsShelf = CardShelfView()
    private let chartsShelf = CardShelfView()

    private var trending: [Track] = []
    private var albums: [CollectionItem] = []
    private var charts: [CollectionItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Explore"
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .always

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 26
        stack.alignment = .fill
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -28),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        chips.configure(titles: moods)
        chips.onSelect = { [weak self] mood in self?.openMood(mood) }
        addShelf(chips, height: ChipRowView.rowHeight)

        trendingShelf.configure(title: "Trending now", tracks: [])
        trendingShelf.onSelect = { [weak self] index in
            guard let self = self else { return }
            PlayerService.shared.play(tracks: self.trending, startingAt: index)
            self.presentNowPlayingFromRoot()
        }
        trendingShelf.onPlayAll = { [weak self] in
            guard let self = self, !self.trending.isEmpty else { return }
            PlayerService.shared.play(tracks: self.trending, startingAt: 0)
            self.presentNowPlayingFromRoot()
        }
        addShelf(trendingShelf, height: ShelfRowView.rowHeight)

        albumsShelf.configure(title: "New albums", items: [])
        albumsShelf.onSelect = { [weak self] index in
            guard let self = self, index < self.albums.count else { return }
            self.openCollection(self.albums[index])
        }
        addShelf(albumsShelf, height: CardShelfView.rowHeight)

        chartsShelf.configure(title: "Top charts", items: [])
        chartsShelf.onSelect = { [weak self] index in
            guard let self = self, index < self.charts.count else { return }
            self.openCollection(self.charts[index])
        }
        addShelf(chartsShelf, height: CardShelfView.rowHeight)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.contentInset.bottom = 104
        scrollView.scrollIndicatorInsets.bottom = 104
    }

    private func addShelf(_ view: UIView, height: CGFloat) {
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        stack.addArrangedSubview(view)
    }

    private func load() {
        spinner.startAnimating()
        let year = Calendar.current.component(.year, from: Date())

        InnerTube.shared.search("Trending songs today \(year)", filter: .songs) { [weak self] tracks, _ in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            guard let tracks = tracks, !tracks.isEmpty else { return }
            self.trending = Array(tracks.prefix(20))
            self.trendingShelf.configure(title: "Trending now", tracks: self.trending)
        }

        InnerTube.shared.searchCollections("New album releases \(year)", filter: .albums) { [weak self] items in
            guard let self = self, !items.isEmpty else { return }
            self.albums = Array(items.prefix(20))
            self.albumsShelf.configure(title: "New albums", items: self.cards(from: self.albums))
        }

        InnerTube.shared.searchCollections("Top charts \(year)", filter: .playlists) { [weak self] items in
            guard let self = self, !items.isEmpty else { return }
            self.charts = Array(items.prefix(20))
            self.chartsShelf.configure(title: "Top charts", items: self.cards(from: self.charts))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.spinner.stopAnimating()
        }
    }

    private func cards(from items: [CollectionItem]) -> [CardItem] {
        return items.map { CardItem(id: $0.browseID,
                                    title: $0.title,
                                    subtitle: $0.subtitle,
                                    artworkURL: $0.artworkURL) }
    }

    private func openCollection(_ item: CollectionItem) {
        let list = TrackListViewController()
        list.title = item.title
        list.emptyText = "Loading \(item.title)\u{2026}"
        navigationController?.pushViewController(list, animated: true)

        InnerTube.shared.fetchCollection(item.browseID) { tracks, error in
            if let tracks = tracks, !tracks.isEmpty {
                list.setTracks(tracks)
            } else {
                list.emptyText = error ?? "Could not open \(item.title)."
                list.setTracks([])
            }
        }
    }

    private func openMood(_ mood: String) {
        let list = TrackListViewController()
        list.title = mood
        list.emptyText = "Searching \(mood)\u{2026}"
        navigationController?.pushViewController(list, animated: true)

        InnerTube.shared.search("\(mood) music", filter: .songs) { tracks, error in
            if let tracks = tracks, !tracks.isEmpty {
                list.setTracks(tracks)
            } else {
                list.emptyText = error ?? "No results for \(mood)."
                list.setTracks([])
            }
        }
    }
}
