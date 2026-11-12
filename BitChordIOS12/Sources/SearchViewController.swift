import UIKit

/// Search over the same catalogue that plays.
///
/// The previous screen searched YouTube Music and kept only rows whose type token
/// said "Song" — artists and albums have no video id at all, so they were thrown
/// away, and any query whose top hits were a band or a record came back empty.
/// This one asks the catalogue for all three kinds at once and puts them behind
/// the same pill selector upstream uses.
final class SearchViewController: UIViewController {
    private enum Mode: Int {
        case songs
        case artists
        case albums
    }

    private let fieldContainer = UIView()
    private let fieldIcon = UIImageView()
    private let field = UITextField()
    private let clearButton = UIButton(type: .system)
    private let selector = UISegmentedControl(items: ["Songs", "Artists", "Albums"])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let spinner = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    private var songs: [Track] = []
    private var artists: [CatalogueArtist] = []
    private var albums: [CatalogueAlbum] = []
    private var mode: Mode = .songs
    private var modeChosen = false
    private var query = ""
    private var pendingWork: DispatchWorkItem?
    private var requestToken = 0
    private var inFlight = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .always
        buildField()
        buildSelector()
        buildList()
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    // MARK: - Chrome

    private func buildField() {
        fieldContainer.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.backgroundColor = Theme.surfaceVariant
        fieldContainer.layer.cornerRadius = 11
        view.addSubview(fieldContainer)

        fieldIcon.translatesAutoresizingMaskIntoConstraints = false
        fieldIcon.image = Icons.image(.search, size: 17).withRenderingMode(.alwaysTemplate)
        fieldIcon.tintColor = Theme.secondaryText
        fieldIcon.contentMode = .scaleAspectFit
        fieldContainer.addSubview(fieldIcon)

        field.translatesAutoresizingMaskIntoConstraints = false
        field.textColor = Theme.primaryText
        field.tintColor = Theme.accent
        field.font = Theme.font(16)
        field.attributedPlaceholder = NSAttributedString(
            string: "Songs, artists, albums",
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

        NSLayoutConstraint.activate([
            fieldContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            fieldContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fieldContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            fieldContainer.heightAnchor.constraint(equalToConstant: 40),

            fieldIcon.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 11),
            fieldIcon.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            fieldIcon.widthAnchor.constraint(equalToConstant: 17),
            fieldIcon.heightAnchor.constraint(equalToConstant: 17),

            field.leadingAnchor.constraint(equalTo: fieldIcon.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -6),
            field.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            field.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),

            clearButton.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -10),
            clearButton.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 22),
            clearButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func buildSelector() {
        selector.translatesAutoresizingMaskIntoConstraints = false
        selector.selectedSegmentIndex = 0
        selector.tintColor = Theme.primaryText
        if #available(iOS 13.0, *) {
            selector.selectedSegmentTintColor = Theme.surfaceVariant
        }
        selector.setTitleTextAttributes([.foregroundColor: Theme.secondaryText,
                                         .font: Theme.font(13, weight: .semibold)],
                                        for: .normal)
        selector.setTitleTextAttributes([.foregroundColor: Theme.primaryText,
                                         .font: Theme.font(13, weight: .semibold)],
                                        for: .selected)
        selector.addTarget(self, action: #selector(selectorChanged), for: .valueChanged)
        selector.isHidden = true
        view.addSubview(selector)
        NSLayoutConstraint.activate([
            selector.topAnchor.constraint(equalTo: fieldContainer.bottomAnchor, constant: 10),
            selector.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            selector.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            selector.heightAnchor.constraint(equalToConstant: 32)
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
            tableView.topAnchor.constraint(equalTo: selector.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 16)
        ])
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
            modeChosen = false
            inFlight = 0
            spinner.stopAnimating()
            selector.isHidden = true
            tableView.reloadData()
            refresh()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, token == self.requestToken else { return }
            self.run(text)
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
        catalogue.artists(text) { [weak self] rows in
            guard let self = self, token == self.requestToken else { return }
            self.artists = rows
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
        if inFlight == 0 {
            spinner.stopAnimating()
            // The first batch decides the tab, unless the user already picked one.
            if !modeChosen {
                mode = songs.isEmpty && !artists.isEmpty ? .artists : .songs
                selector.selectedSegmentIndex = mode.rawValue
            }
            selector.isHidden = (songs.isEmpty && artists.isEmpty && albums.isEmpty)
            tableView.reloadData()
            refresh()
        }
    }

    private func refresh() {
        let isEmpty = isEmptyForMode()
        if query.isEmpty {
            emptyLabel.text = "Search songs, artists and albums"
        } else if isEmpty {
            emptyLabel.text = emptyText()
        }
        emptyLabel.isHidden = inFlight > 0 || !isEmpty
    }

    private func emptyText() -> String {
        switch mode {
        case .songs: return "No songs for \u{201C}\(query)\u{201D}."
        case .artists: return "No artists for \u{201C}\(query)\u{201D}."
        case .albums: return "No albums for \u{201C}\(query)\u{201D}."
        }
    }

    private func isEmptyForMode() -> Bool {
        switch mode {
        case .songs: return songs.isEmpty
        case .artists: return artists.isEmpty
        case .albums: return albums.isEmpty
        }
    }

    @objc private func clearTapped() {
        field.text = ""
        textChanged()
        field.becomeFirstResponder()
    }

    @objc private func selectorChanged() {
        modeChosen = true
        mode = Mode(rawValue: selector.selectedSegmentIndex) ?? .songs
        tableView.setContentOffset(.zero, animated: false)
        tableView.reloadData()
        refresh()
    }

    private func openArtist(_ artist: CatalogueArtist) {
        let controller = CollectionViewController(title: artist.name,
                                                  subtitle: "Artist",
                                                  artwork: artist.artwork)
        controller.loader = { completion in
            CatalogueSearch.shared.songs(byArtist: artist.id) { tracks in completion(tracks) }
        }
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
        run(text)
        textField.resignFirstResponder()
        return true
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch mode {
        case .songs: return songs.count
        case .artists: return artists.count
        case .albums: return albums.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch mode {
        case .songs:
            let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath)
            if let trackCell = cell as? TrackCell {
                trackCell.configure(with: songs[indexPath.row])
            }
            return cell
        case .artists:
            let cell = tableView.dequeueReusableCell(withIdentifier: CatalogueRowCell.reuseIdentifier, for: indexPath)
            if let row = cell as? CatalogueRowCell {
                let artist = artists[indexPath.row]
                row.configure(title: artist.name, subtitle: "Artist", artwork: artist.artwork, circular: true)
            }
            return cell
        case .albums:
            let cell = tableView.dequeueReusableCell(withIdentifier: CatalogueRowCell.reuseIdentifier, for: indexPath)
            if let row = cell as? CatalogueRowCell {
                let album = albums[indexPath.row]
                let bits = [album.artist, album.year].filter { !$0.isEmpty }
                row.configure(title: album.title,
                              subtitle: bits.isEmpty ? "Album" : bits.joined(separator: " \u{00B7} "),
                              artwork: album.artwork,
                              circular: false)
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch mode {
        case .songs:
            // Capture the queue first: nothing else touches it while the player
            // is presented, and the list must stay as the user left it.
            let picked = songs
            guard indexPath.row < picked.count else { return }
            field.resignFirstResponder()
            PlayerService.shared.play(tracks: picked, startingAt: indexPath.row)
            DispatchQueue.main.async { [weak self] in
                self?.presentNowPlayingFromRoot()
            }
        case .artists:
            guard indexPath.row < artists.count else { return }
            openArtist(artists[indexPath.row])
        case .albums:
            guard indexPath.row < albums.count else { return }
            openAlbum(albums[indexPath.row])
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
