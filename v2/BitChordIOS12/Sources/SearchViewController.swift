import UIKit

/// Search, shaped like the real screen: the field and account avatar on top,
/// the YouTube / Library / Addons source bar directly under them, and one
/// result list — songs, then albums, then artists — in the order the real
/// results list puts them.
final class SearchViewController: UIViewController {
    private enum Source: Int {
        case youtube
        case library
        case addons
    }

    private enum Row {
        case song(Track)
        case album(CatalogueAlbum)
        case artist(CatalogueArtist)
        case recent(Track)
    }

    private var recents: [Track] { return LibraryStore.shared.recentSearches }

    private let fieldContainer = UIView()
    private let fieldIcon = UIImageView()
    private let field = UITextField()
    private let clearButton = UIButton(type: .system)
    private let avatarButton = UIButton(type: .system)
    private let sourceSelector = PillSelectorView(titles: ["YouTube", "Library", "Addons"])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let spinner = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    private var songs: [Track] = []
    private var artists: [CatalogueArtist] = []
    private var albums: [CatalogueAlbum] = []
    private var source: Source = .youtube
    private var query = ""
    private var pendingWork: DispatchWorkItem?
    private var requestToken = 0
    private var inFlight = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = ""
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        buildField()
        buildSourceBar()
        buildList()
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        refresh()
    }

    /// Called by the tab host when this page becomes visible. The real Search
    /// opens with the field active; a view-appearance callback never fires on
    /// a tab swap because all four pages stay in the same hierarchy.
    func focusFieldForDisplay() {
        guard query.isEmpty, (field.text ?? "").isEmpty,
              presentedViewController == nil else { return }
        field.becomeFirstResponder()
    }

    // MARK: - Chrome

    private func buildField() {
        fieldContainer.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.backgroundColor = Theme.surfaceVariant
        fieldContainer.layer.cornerRadius = 23
        view.addSubview(fieldContainer)

        fieldIcon.translatesAutoresizingMaskIntoConstraints = false
        fieldIcon.image = Icons.image(.search, size: 20).withRenderingMode(.alwaysTemplate)
        fieldIcon.tintColor = Theme.secondaryText
        fieldIcon.contentMode = .scaleAspectFit
        fieldContainer.addSubview(fieldIcon)

        field.translatesAutoresizingMaskIntoConstraints = false
        field.textColor = Theme.primaryText
        field.tintColor = Theme.accent
        field.font = Theme.font(17)
        field.attributedPlaceholder = NSAttributedString(
            string: "Artists, Songs, Lyrics and More",
            attributes: [.foregroundColor: Theme.secondaryText]
        )
        field.keyboardAppearance = .dark
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.clearButtonMode = .never
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        fieldContainer.addSubview(field)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.tintColor = Theme.secondaryText
        clearButton.setImage(Icons.image(.close, size: 13), for: .normal)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        clearButton.isHidden = true
        fieldContainer.addSubview(clearButton)

        // The real search bar pairs the field with a round account avatar.
        avatarButton.translatesAutoresizingMaskIntoConstraints = false
        avatarButton.backgroundColor = Theme.surfaceVariant
        avatarButton.layer.cornerRadius = 22
        avatarButton.tintColor = Theme.secondaryText
        avatarButton.setImage(Icons.image(.personOutline, size: 21), for: .normal)
        view.addSubview(avatarButton)

        NSLayoutConstraint.activate([
            fieldContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -14),
            fieldContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fieldContainer.trailingAnchor.constraint(equalTo: avatarButton.leadingAnchor, constant: -10),
            fieldContainer.heightAnchor.constraint(equalToConstant: 46),

            fieldIcon.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 14),
            fieldIcon.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            fieldIcon.widthAnchor.constraint(equalToConstant: 20),
            fieldIcon.heightAnchor.constraint(equalToConstant: 20),

            field.leadingAnchor.constraint(equalTo: fieldIcon.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -6),
            field.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            field.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),

            clearButton.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -10),
            clearButton.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 22),
            clearButton.heightAnchor.constraint(equalToConstant: 22),

            avatarButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.gutter),
            avatarButton.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            avatarButton.widthAnchor.constraint(equalToConstant: 44),
            avatarButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func buildSourceBar() {
        sourceSelector.translatesAutoresizingMaskIntoConstraints = false
        sourceSelector.select(0, animated: false)
        sourceSelector.onSelect = { [weak self] index in
            guard let self = self, let picked = Source(rawValue: index) else { return }
            self.source = picked
            self.tableView.setContentOffset(.zero, animated: false)
            self.tableView.reloadData()
            self.refresh()
            // Switching back to YouTube re-runs the live query; the other two
            // sources answer from the library and need no request.
            if picked == .youtube, self.query.count >= 2 {
                self.requestToken += 1
                self.run(self.query)
            }
        }
        view.addSubview(sourceSelector)
        NSLayoutConstraint.activate([
            sourceSelector.topAnchor.constraint(equalTo: fieldContainer.bottomAnchor, constant: 0),
            sourceSelector.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.gutter),
            sourceSelector.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.gutter),
            sourceSelector.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func buildList() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.keyboardDismissMode = .onDrag
        tableView.tableFooterView = UIView()
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        tableView.register(CatalogueRowCell.self, forCellReuseIdentifier: CatalogueRowCell.reuseIdentifier)
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.font = Theme.font(14)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        view.addSubview(emptyLabel)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = Theme.secondaryText
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: sourceSelector.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // The real empty state sits in the upper third, not dead centre.
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: sourceSelector.bottomAnchor, constant: 64),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 16)
        ])
    }

    // MARK: - Rows

    private var rows: [Row] {
        switch source {
        case .youtube:
            if query.isEmpty && !recents.isEmpty {
                return recents.map(Row.recent)
            }
            return songs.map(Row.song) + albums.map(Row.album) + artists.map(Row.artist)
        case .library:
            return libraryRows()
        case .addons:
            return []
        }
    }

    private func libraryRows() -> [Row] {
        guard !query.isEmpty else { return [] }
        let store = LibraryStore.shared
        let pool = store.likedTracks
            + store.recentTracks
            + store.playlists.flatMap { $0.tracks }
        let needle = query.lowercased()
        var seen = Set<String>()
        var found: [Row] = []
        for track in pool {
            let matches = track.title.lowercased().contains(needle)
                || track.artist.lowercased().contains(needle)
                || track.album.lowercased().contains(needle)
            guard matches, seen.insert(track.videoID).inserted else { continue }
            found.append(.song(track))
        }
        return found
    }

    private var songQueue: [Track] {
        return rows.compactMap { row in
            if case .song(let track) = row { return track }
            return nil
        }
    }

    // MARK: - Searching

    @objc private func textChanged() {
        let text = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        clearButton.isHidden = text.isEmpty
        pendingWork?.cancel()
        requestToken += 1
        let token = requestToken

        guard text.count >= 2 else {
            query = ""
            songs = []
            artists = []
            albums = []
            inFlight = 0
            spinner.stopAnimating()
            tableView.reloadData()
            refresh()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, token == self.requestToken else { return }
            if self.source == .youtube {
                self.run(text)
            } else {
                self.query = text
                self.tableView.reloadData()
                self.refresh()
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func run(_ text: String) {
        query = text
        inFlight = 3
        spinner.startAnimating()
        emptyLabel.isHidden = true
        let token = requestToken
        let catalogue = CatalogueSearch.shared

        catalogue.songs(text) { [weak self] rows in
            guard let self = self, token == self.requestToken else { return }
            self.songs = rows
            self.landed(token: token)
        }
        // Artists come from YouTube Music, which is where upstream's artist
        // pages live; the catalogue's own artist call no longer returns songs.
        InnerTube.shared.searchCollections(text, filter: .artists) { [weak self] rows in
            guard let self = self, token == self.requestToken else { return }
            self.artists = rows.map { item in
                CatalogueArtist(id: item.browseID, name: item.title, artwork: item.artworkURL)
            }
            self.landed(token: token)
        }
        catalogue.albums(text) { [weak self] rows in
            guard let self = self, token == self.requestToken else { return }
            self.albums = rows
            self.landed(token: token)
        }
    }

    private func landed(token: Int) {
        guard token == requestToken else { return }
        inFlight = max(0, inFlight - 1)
        guard inFlight == 0 else { return }
        spinner.stopAnimating()
        tableView.reloadData()
        refresh()
    }

    private func updateRecentsHeader() {
        guard source == .youtube, query.isEmpty, !recents.isEmpty else {
            tableView.tableHeaderView = nil
            return
        }
        let header = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 46))
        let title = UILabel()
        title.text = "Recent searches"
        title.font = Theme.font(20, weight: .bold)
        title.textColor = Theme.primaryText
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        let clear = UIButton(type: .system)
        clear.setTitle("Clear", for: .normal)
        clear.setTitleColor(Theme.secondaryText, for: .normal)
        clear.titleLabel?.font = Theme.font(14)
        clear.addTarget(self, action: #selector(clearRecents), for: .touchUpInside)
        clear.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(clear)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            title.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -10),
            clear.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            clear.centerYAnchor.constraint(equalTo: title.centerYAnchor)
        ])
        tableView.tableHeaderView = header
    }

    @objc private func clearRecents() {
        LibraryStore.shared.clearRecentSearches()
        tableView.reloadData()
        refresh()
    }

    private func refresh() {
        updateRecentsHeader()
        let isEmpty = rows.isEmpty
        if query.isEmpty {
            switch source {
            case .youtube:
                emptyLabel.text = "Search millions of songs on YouTube Music."
            case .library:
                emptyLabel.text = "Search your liked songs, playlists and recents."
            case .addons:
                emptyLabel.text = "No addon sources are configured."
            }
        } else if isEmpty {
            switch source {
            case .youtube:
                emptyLabel.text = "No results for \u{201C}\(query)\u{201D}."
            case .library:
                emptyLabel.text = "Nothing in your library matches \u{201C}\(query)\u{201D}."
            case .addons:
                emptyLabel.text = "No addon sources are configured."
            }
        }
        emptyLabel.isHidden = inFlight > 0 || !isEmpty
    }

    @objc private func clearTapped() {
        field.text = ""
        textChanged()
        field.becomeFirstResponder()
    }

    private func openArtist(_ artist: CatalogueArtist) {
        let controller = ArtistPage.make(artist: artist)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openAlbum(_ album: CatalogueAlbum) {
        let detail = album.artist.isEmpty
            ? (album.year.isEmpty ? "Album" : album.year)
            : (album.year.isEmpty ? album.artist : album.artist + " \u{00B7} " + album.year)
        let controller = CollectionViewController(title: album.title,
                                                  subtitle: detail,
                                                  artwork: album.artwork)
        controller.loader = { completion in
            CatalogueSearch.shared.songs(inAlbum: album.id) { tracks in completion(tracks) }
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}

extension SearchViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        pendingWork?.cancel()
        let text = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 1 else { return true }
        requestToken += 1
        if source == .youtube {
            run(text)
        } else {
            query = text
            tableView.reloadData()
            refresh()
        }
        textField.resignFirstResponder()
        return true
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        switch row {
        case .song(let track):
            let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath)
            if let trackCell = cell as? TrackCell {
                trackCell.configure(with: track)
            }
            return cell
        case .album(let album):
            let cell = tableView.dequeueReusableCell(withIdentifier: CatalogueRowCell.reuseIdentifier, for: indexPath)
            if let row = cell as? CatalogueRowCell {
                let bits = [album.artist, album.year].filter { !$0.isEmpty }
                row.configure(title: album.title,
                              subtitle: bits.isEmpty ? "Album" : "Album \u{00B7} " + bits.joined(separator: " \u{00B7} "),
                              artwork: album.artwork,
                              circular: false)
            }
            return cell
        case .artist(let artist):
            let cell = tableView.dequeueReusableCell(withIdentifier: CatalogueRowCell.reuseIdentifier, for: indexPath)
            if let row = cell as? CatalogueRowCell {
                row.configure(title: artist.name, subtitle: "Artist", artwork: artist.artwork, circular: true)
            }
            return cell
        case .recent(let track):
            let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath)
            if let trackCell = cell as? TrackCell {
                trackCell.configure(with: track)
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = rows[indexPath.row]
        switch row {
        case .song(let track):
            LibraryStore.shared.addRecentSearch(track)
            let queue = songQueue
            let start = queue.firstIndex(where: { $0.videoID == track.videoID }) ?? 0
            field.resignFirstResponder()
            PlayerService.shared.play(tracks: queue, startingAt: start)
            DispatchQueue.main.async { [weak self] in
                self?.presentNowPlayingFromRoot()
            }
        case .album(let album):
            openAlbum(album)
        case .artist(let artist):
            openArtist(artist)
        case .recent(let track):
            field.text = track.title
            query = track.title
            requestToken += 1
            run(track.title)
            LibraryStore.shared.addRecentSearch(track)
        }
    }
}

/// An artist or album row: artwork, title, and what kind of thing it is.
final class CatalogueRowCell: UITableViewCell {
    static let reuseIdentifier = "CatalogueRowCell"

    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var artworkTask: URLSessionDataTask?
    private var currentURL: URL?
    private var circular = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .default
        let selected = UIView()
        selected.backgroundColor = Theme.surface
        selectedBackgroundView = selected

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.backgroundColor = Theme.surfaceVariant
        artworkView.layer.cornerRadius = 6
        contentView.addSubview(artworkView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(15, weight: .medium)
        titleLabel.textColor = Theme.primaryText
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = Theme.font(12)
        subtitleLabel.textColor = Theme.secondaryText
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            artworkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 48),
            artworkView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -2),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 2)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(title: String, subtitle: String, artwork: URL?, circular: Bool) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        self.circular = circular
        artworkView.layer.cornerRadius = circular ? 24 : 6
        artworkTask?.cancel()
        currentURL = artwork
        if let cached = ArtworkLoader.shared.cached(artwork) {
            artworkView.image = cached
            return
        }
        artworkView.image = nil
        artworkTask = ArtworkLoader.shared.load(artwork) { [weak self] image in
            guard let self = self, self.currentURL == artwork else { return }
            self.artworkView.image = image
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        artworkView.layer.cornerRadius = circular ? artworkView.bounds.width / 2 : 6
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkTask?.cancel()
        artworkTask = nil
        artworkView.image = nil
    }
}
