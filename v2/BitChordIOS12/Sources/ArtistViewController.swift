import UIKit

/// The artist page, not just a list of songs: photograph, listener count,
/// biography, popular tracks, releases and related artists. Upstream builds
/// this from `BrowseType.ARTIST`; the catalogue supplies the same fields
/// through `artist.getArtistPageDetails`.
final class ArtistViewController: UIViewController {
    private enum Section: CaseIterable {
        case songs, albums, related, about
    }

    private let artist: CatalogueArtist
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let header = ArtistHeaderView()
    private let spinner = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    private var profile: ArtistProfile?
    private var tracks: [Track] = []

    /// The capture harness waits on this instead of guessing how long the
    /// catalogue takes.
    var loadedTrackCount: Int { return tracks.count }

    /// A compact, harness-readable summary of what the page actually drew.
    var reportSummary: String {
        guard let profile = profile else { return "loaded=false" }
        return "loaded=true songs=\(profile.topSongs.count) albums=\(profile.albums.count) "
            + "related=\(profile.related.count) bio=\(profile.bio?.isEmpty == false)"
    }

    init(artist: CatalogueArtist) {
        self.artist = artist
        super.init(nibName: nil, bundle: nil)
        title = artist.name
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.sectionHeaderHeight = 30
        tableView.tableFooterView = UIView()
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 40, right: 0)
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        tableView.register(ArtistTileCell.self, forCellReuseIdentifier: ArtistTileCell.reuseIdentifier)
        tableView.register(ArtistAboutCell.self, forCellReuseIdentifier: ArtistAboutCell.reuseIdentifier)
        view.addSubview(tableView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.style = .gray
        spinner.color = Theme.secondaryText
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        header.configure(name: artist.name, detail: "Artist", artwork: artist.artwork)
        header.onPlay = { [weak self] in self?.play(shuffle: false) }
        header.onShuffle = { [weak self] in self?.play(shuffle: true) }
        layoutHeader()
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if header.frame.width != view.bounds.width {
            layoutHeader()
        }
    }

    private func layoutHeader() {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        header.frame = CGRect(x: 0, y: 0, width: width, height: 372)
        header.layoutIfNeeded()
        tableView.tableHeaderView = header
    }

    private func load() {
        spinner.startAnimating()
        CatalogueSearch.shared.artistProfile(id: artist.id,
                                             name: artist.name,
                                             artwork: artist.artwork) { [weak self] profile in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            self.profile = profile
            self.tracks = profile.topSongs
            self.header.configure(name: profile.name,
                                  detail: profile.listenerText ?? "Artist",
                                  artwork: profile.artwork ?? self.artist.artwork)
            self.header.isPlayEnabled = !profile.topSongs.isEmpty
            self.tableView.reloadData()
        }
    }

    private func play(shuffle: Bool) {
        guard !tracks.isEmpty else { return }
        let queue = shuffle ? tracks.shuffled() : tracks
        PlayerService.shared.play(tracks: queue, startingAt: 0)
        presentNowPlayingFromRoot()
    }

    private var visibleSections: [Section] {
        guard let profile = profile else { return [] }
        var sections: [Section] = []
        if !profile.topSongs.isEmpty { sections.append(.songs) }
        if !profile.albums.isEmpty { sections.append(.albums) }
        if !profile.related.isEmpty { sections.append(.related) }
        if profile.bio?.isEmpty == false { sections.append(.about) }
        return sections
    }

    private func section(at index: Int) -> Section {
        return visibleSections[index]
    }

    private func openAlbum(_ album: CatalogueAlbum) {
        let detail = [album.artist, album.year].filter { !$0.isEmpty }.joined(separator: " · ")
        let controller = CollectionViewController(title: album.title,
                                                  subtitle: detail.isEmpty ? "Album" : detail,
                                                  artwork: album.artwork)
        controller.loader = { completion in
            CatalogueSearch.shared.songs(inAlbum: album.id) { tracks in
                completion(tracks)
            }
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openArtist(_ related: CatalogueArtist) {
        navigationController?.pushViewController(ArtistPage.make(artist: related), animated: true)
    }
}

extension ArtistViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch self.section(at: section) {
        case .songs:
            return profile?.topSongs.count ?? 0
        case .albums:
            return profile?.albums.count ?? 0
        case .related:
            return profile?.related.count ?? 0
        case .about:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch section(at: indexPath.section) {
        case .songs: return 64
        case .albums, .related: return 72
        case .about: return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 30
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let holder = UIView()
        holder.backgroundColor = Theme.background
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.font(12, weight: .semibold)
        label.textColor = Theme.secondaryText
        switch self.section(at: section) {
        case .songs: label.text = "POPULAR"
        case .albums: label.text = "ALBUMS & SINGLES"
        case .related: label.text = "FANS ALSO LIKE"
        case .about: label.text = "ABOUT"
        }
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 20),
            label.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -6)
        ])
        return holder
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch section(at: indexPath.section) {
        case .songs:
            let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier,
                                                     for: indexPath) as! TrackCell
            if let track = profile?.topSongs[indexPath.row] {
                cell.configure(with: track)
            }
            return cell
        case .albums:
            let cell = tableView.dequeueReusableCell(withIdentifier: ArtistTileCell.reuseIdentifier,
                                                     for: indexPath) as! ArtistTileCell
            if let album = profile?.albums[indexPath.row] {
                var parts: [String] = []
                if !album.year.isEmpty { parts.append(album.year) }
                if album.songCount > 0 { parts.append("\(album.songCount) songs") }
                if !album.artist.isEmpty { parts.append(album.artist) }
                cell.configure(title: album.title,
                               subtitle: parts.joined(separator: " · "),
                               artwork: album.artwork)
            }
            return cell
        case .related:
            let cell = tableView.dequeueReusableCell(withIdentifier: ArtistTileCell.reuseIdentifier,
                                                     for: indexPath) as! ArtistTileCell
            if let related = profile?.related[indexPath.row] {
                cell.configure(title: related.name, subtitle: "Artist", artwork: related.artwork)
            }
            return cell
        case .about:
            let cell = tableView.dequeueReusableCell(withIdentifier: ArtistAboutCell.reuseIdentifier,
                                                     for: indexPath) as! ArtistAboutCell
            cell.configure(text: profile?.bio ?? "", detail: profile?.listenerText)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch section(at: indexPath.section) {
        case .songs:
            guard let picked = profile?.topSongs, indexPath.row < picked.count else { return }
            PlayerService.shared.play(tracks: picked, startingAt: indexPath.row)
            presentNowPlayingFromRoot()
        case .albums:
            if let album = profile?.albums[indexPath.row] { openAlbum(album) }
        case .related:
            if let related = profile?.related[indexPath.row] { openArtist(related) }
        case .about:
            break
        }
    }
}

/// The photograph, listener count and the two actions an artist page opens
/// with. The count is the catalogue's own subtitle or follower number, never a
/// fabricated figure.
final class ArtistHeaderView: UIView {
    var onPlay: (() -> Void)?
    var onShuffle: (() -> Void)?

    var isPlayEnabled = false {
        didSet {
            playButton.alpha = isPlayEnabled ? 1 : 0.4
            shuffleButton.alpha = isPlayEnabled ? 1 : 0.4
        }
    }

    private let artworkView = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    private var artworkTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 14
        artworkView.backgroundColor = Theme.surfaceVariant
        artworkView.layer.borderWidth = 1
        artworkView.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        addSubview(artworkView)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = Theme.font(30, weight: .bold)
        nameLabel.textColor = Theme.primaryText
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        addSubview(nameLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = Theme.font(13)
        detailLabel.textColor = Theme.secondaryText
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 2
        addSubview(detailLabel)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.backgroundColor = Theme.accent
        playButton.layer.cornerRadius = 21
        playButton.tintColor = Theme.background
        playButton.setTitle("  Play  ", for: .normal)
        playButton.setTitleColor(Theme.background, for: .normal)
        playButton.titleLabel?.font = Theme.font(15, weight: .semibold)
        playButton.setImage(Icons.image(.play, size: 14), for: .normal)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        addSubview(playButton)

        shuffleButton.translatesAutoresizingMaskIntoConstraints = false
        shuffleButton.layer.cornerRadius = 21
        shuffleButton.layer.borderWidth = 1
        shuffleButton.layer.borderColor = Theme.outline.cgColor
        shuffleButton.tintColor = Theme.primaryText
        shuffleButton.setTitle("  Shuffle  ", for: .normal)
        shuffleButton.setTitleColor(Theme.primaryText, for: .normal)
        shuffleButton.titleLabel?.font = Theme.font(15, weight: .semibold)
        shuffleButton.setImage(Icons.image(.shuffle, size: 15), for: .normal)
        shuffleButton.addTarget(self, action: #selector(shuffleTapped), for: .touchUpInside)
        addSubview(shuffleButton)

        NSLayoutConstraint.activate([
            artworkView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            artworkView.centerXAnchor.constraint(equalTo: centerXAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 200),
            artworkView.heightAnchor.constraint(equalToConstant: 200),

            nameLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            playButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 16),
            playButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            playButton.heightAnchor.constraint(equalToConstant: 42),
            playButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 124),

            shuffleButton.topAnchor.constraint(equalTo: playButton.topAnchor),
            shuffleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            shuffleButton.heightAnchor.constraint(equalToConstant: 42),
            shuffleButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 124)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(name: String, detail: String, artwork: URL?) {
        nameLabel.text = name
        detailLabel.text = detail
        artworkTask?.cancel()
        if let cached = ArtworkLoader.shared.cached(artwork) {
            artworkView.image = cached
            return
        }
        artworkView.image = nil
        artworkTask = ArtworkLoader.shared.load(artwork) { [weak self] image in
            self?.artworkView.image = image
        }
    }

    @objc private func playTapped() {
        guard isPlayEnabled else { return }
        onPlay?()
    }

    @objc private func shuffleTapped() {
        guard isPlayEnabled else { return }
        onShuffle?()
    }
}

/// A release or related-artist row: square art, title and one metadata line.
final class ArtistTileCell: UITableViewCell {
    static let reuseIdentifier = "ArtistTileCell"

    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView(image: Icons.image(.chevronRight, size: 14))
    private var artworkTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let selected = UIView()
        selected.backgroundColor = Theme.surface
        selectedBackgroundView = selected

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.backgroundColor = Theme.surfaceVariant
        contentView.addSubview(artworkView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(16, weight: .medium)
        titleLabel.textColor = Theme.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = Theme.font(13)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(subtitleLabel)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = Theme.secondaryText
        chevron.contentMode = .scaleAspectFit
        contentView.addSubview(chevron)

        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            artworkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 52),
            artworkView.heightAnchor.constraint(equalToConstant: 52),

            titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -1),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 2),

            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    func configure(title: String, subtitle: String, artwork: URL?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        artworkTask?.cancel()
        if let cached = ArtworkLoader.shared.cached(artwork) {
            artworkView.image = cached
            return
        }
        artworkView.image = nil
        artworkTask = ArtworkLoader.shared.load(artwork) { [weak self] image in
            self?.artworkView.image = image
        }
    }
}

/// The editorial biography and listener count at the foot of an artist page.
final class ArtistAboutCell: UITableViewCell {
    static let reuseIdentifier = "ArtistAboutCell"

    private let bodyLabel = UILabel()
    private let detailLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = Theme.font(15)
        bodyLabel.textColor = Theme.primaryText
        bodyLabel.numberOfLines = 0
        contentView.addSubview(bodyLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = Theme.font(12)
        detailLabel.textColor = Theme.secondaryText
        detailLabel.numberOfLines = 1
        contentView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            bodyLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            detailLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 10),
            detailLabel.leadingAnchor.constraint(equalTo: bodyLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: bodyLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(text: String, detail: String?) {
        bodyLabel.text = text
        detailLabel.text = detail
        detailLabel.isHidden = (detail ?? "").isEmpty
    }
}
