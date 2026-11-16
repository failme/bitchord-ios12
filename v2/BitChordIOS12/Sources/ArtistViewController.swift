import UIKit

/// The artist page, not just a list of songs: photograph, listener count,
/// biography, popular tracks, releases and related artists. Upstream builds
/// this from `BrowseType.ARTIST`; the catalogue supplies the same fields
/// through `artist.getArtistPageDetails`.
final class ArtistViewController: UIViewController {
    private enum Section: CaseIterable {
        case songs, albums, singles, compilations, related, about
    }

    static let albumFilterKey = "BitChord.Artist.AlbumFilter"
    static let albumSortKey = "BitChord.Artist.AlbumSort"
    static let trackSortKey = "BitChord.Artist.TrackSort"
    static let bioExpandedKey = "BitChord.Artist.BioExpanded"
    static let albumFilterChoices = ["All", "Albums", "Singles", "Compilations"]
    static let albumSortChoices = ["Newest", "Title"]
    static let trackSortChoices = ["Popular", "A–Z"]

    private let artist: CatalogueArtist
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let header = ArtistHeaderView()
    private let spinner = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    private var profile: ArtistProfile?
    private var tracks: [Track] = []
    private var suppressLiveLoad = false

    /// The capture harness waits on this instead of guessing how long the
    /// catalogue takes.
    var loadedTrackCount: Int { return tracks.count }

    /// A compact, harness-readable summary of what the page actually drew.
    var reportSummary: String {
        guard let profile = profile else { return "loaded=false" }
        return "loaded=true songs=\(profile.topSongs.count) albums=\(profile.albums.count) "
            + "related=\(profile.related.count) bio=\(profile.bio?.isEmpty == false) "
            + "sections=\(visibleSections.count)"
    }

    private var albumFilter: String {
        let raw = SettingsStore.shared.string(ArtistViewController.albumFilterKey, "All")
        return ArtistViewController.albumFilterChoices.contains(raw) ? raw : "All"
    }

    private var albumSort: String {
        let raw = SettingsStore.shared.string(ArtistViewController.albumSortKey, "Newest")
        return ArtistViewController.albumSortChoices.contains(raw) ? raw : "Newest"
    }

    private var trackSort: String {
        let raw = SettingsStore.shared.string(ArtistViewController.trackSortKey, "Popular")
        return ArtistViewController.trackSortChoices.contains(raw) ? raw : "Popular"
    }

    private var bioExpanded: Bool {
        return SettingsStore.shared.bool(ArtistViewController.bioExpandedKey, false)
    }

    private var displayedTracks: [Track] {
        guard let tracks = profile?.topSongs else { return [] }
        guard trackSort == "A–Z" else { return tracks }
        return tracks.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func sortedAlbums(_ albums: [CatalogueAlbum]) -> [CatalogueAlbum] {
        if albumSort == "Title" {
            return albums.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
        return albums.sorted {
            let left = Int($0.year) ?? 0
            let right = Int($1.year) ?? 0
            if left == right {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return left > right
        }
    }

    private func albums(of kind: ReleaseKind) -> [CatalogueAlbum] {
        guard let albums = profile?.albums else { return [] }
        return sortedAlbums(albums.filter { $0.kind == kind })
    }

    private func kind(isVisible kind: ReleaseKind) -> Bool {
        switch albumFilter {
        case "Albums": return kind == .album
        case "Singles": return kind == .single
        case "Compilations": return kind == .compilation
        default: return true
        }
    }

    var discographySummary: String {
        let counts = ReleaseKind.allCases.map { "\($0.rawValue):\(albums(of: $0).count)" }
            .joined(separator: ",")
        let drawnAlbums = sortedAlbums((profile?.albums ?? []).filter { kind(isVisible: $0.kind) })
        return "filter=\(albumFilter) sort=\(albumSort) trackSort=\(trackSort) "
            + "kinds=\(counts) bio=\(bioExpanded ? "expanded" : "collapsed") "
            + "first=\(drawnAlbums.first?.title ?? "-") "
            + "trackFirst=\(displayedTracks.first?.title ?? "-") "
            + "sections=\(visibleSections.map { sectionTitle($0) }.joined(separator: "|"))"
    }

    /// Harness entry points use the same stored keys and reload path as the
    /// header buttons.
    func setAlbumFilterForProbe(_ value: String) {
        guard ArtistViewController.albumFilterChoices.contains(value) else { return }
        SettingsStore.shared.set(value, for: ArtistViewController.albumFilterKey)
        tableView.reloadData()
    }

    func setAlbumSortForProbe(_ value: String) {
        guard ArtistViewController.albumSortChoices.contains(value) else { return }
        SettingsStore.shared.set(value, for: ArtistViewController.albumSortKey)
        tableView.reloadData()
    }

    func setTrackSortForProbe(_ value: String) {
        guard ArtistViewController.trackSortChoices.contains(value) else { return }
        SettingsStore.shared.set(value, for: ArtistViewController.trackSortKey)
        tableView.reloadData()
    }

    func setBioExpandedForProbe(_ expanded: Bool) {
        SettingsStore.shared.set(expanded, for: ArtistViewController.bioExpandedKey)
        tableView.reloadData()
    }

    func scrollToDiscographyForProbe() {
        guard let section = visibleSections.firstIndex(where: {
            $0 == .albums || $0 == .singles || $0 == .compilations
        }) else { return }
        view.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .middle, animated: false)
    }

    func scrollToAboutForProbe() {
        guard let section = visibleSections.firstIndex(of: .about) else { return }
        view.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .middle, animated: false)
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
        tableView.rowHeight = Theme.rowHeight(64)
        tableView.sectionHeaderHeight = 36
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

        header.configure(name: artist.name, detail: L10n.t("Artist"), artwork: artist.artwork)
        header.onPlay = { [weak self] in self?.play(shuffle: false) }
        header.onShuffle = { [weak self] in self?.play(shuffle: true) }
        header.onRadio = { [weak self] in self?.startRadio() }
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
            guard let self = self, !self.suppressLiveLoad else { return }
            self.apply(profile: profile)
        }
    }

    /// Shared by the catalogue completion and the empty/fallback probes, so a
    /// profile with no songs, releases or copy goes through exactly the same
    /// layout path as a full one.
    func applyProfileForProbe(_ profile: ArtistProfile) {
        suppressLiveLoad = true
        apply(profile: profile)
    }

    private func apply(profile: ArtistProfile) {
        spinner.stopAnimating()
        self.profile = profile
        tracks = profile.topSongs
        header.configure(name: profile.name,
                         detail: profile.listenerText ?? L10n.t("Artist"),
                         artwork: profile.artwork ?? artist.artwork)
        header.isPlayEnabled = !profile.topSongs.isEmpty
        tableView.reloadData()
    }

    private func play(shuffle: Bool) {
        guard !tracks.isEmpty else { return }
        let queue = shuffle ? tracks.shuffled() : tracks
        PlayerService.shared.play(tracks: queue, startingAt: 0)
        presentNowPlayingFromRoot()
    }

    /// Artist radio uses the profile's first popular song as the seed; with no
    /// songs it searches the artist name. The normal PlayerService path owns
    /// the queue and playback.
    func startRadio(presentPlayer: Bool = true,
                    completion: (([Track]?) -> Void)? = nil) {
        ArtistRadio.mix(artistName: profile?.name ?? artist.name, topSongs: tracks) { [weak self] mix in
            guard let self = self else { return }
            guard let mix = mix, !mix.isEmpty else {
                completion?(nil)
                if presentPlayer {
                    RadioService.presentFailure("This artist has no radio right now.", on: self)
                }
                return
            }
            PlayerService.shared.play(tracks: mix, startingAt: 0)
            completion?(mix)
            if presentPlayer {
                self.presentNowPlayingFromRoot()
            }
        }
    }

    private var visibleSections: [Section] {
        guard let profile = profile else { return [] }
        var sections: [Section] = []
        if !profile.topSongs.isEmpty { sections.append(.songs) }
        if kind(isVisible: .album) && !albums(of: .album).isEmpty { sections.append(.albums) }
        if kind(isVisible: .single) && !albums(of: .single).isEmpty { sections.append(.singles) }
        if kind(isVisible: .compilation) && !albums(of: .compilation).isEmpty {
            sections.append(.compilations)
        }
        if !profile.related.isEmpty { sections.append(.related) }
        if profile.bio?.isEmpty == false { sections.append(.about) }
        return sections
    }

    private func sectionTitle(_ section: Section) -> String {
        switch section {
        case .songs: return L10n.t("Popular")
        case .albums: return L10n.t("Albums")
        case .singles: return L10n.t("Singles")
        case .compilations: return L10n.t("Compilations")
        case .related: return L10n.t("Fans also like")
        case .about: return L10n.t("About")
        }
    }

    private func releaseKindTitle(_ kind: ReleaseKind) -> String {
        switch kind {
        case .album: return L10n.t("Albums")
        case .single: return L10n.t("Singles")
        case .compilation: return L10n.t("Compilations")
        }
    }

    private func section(at index: Int) -> Section {
        return visibleSections[index]
    }

    private func openAlbum(_ album: CatalogueAlbum) {
        let detail = [album.artist, album.year].filter { !$0.isEmpty }.joined(separator: " · ")
        let controller = CollectionViewController(title: album.title,
                                                  subtitle: detail.isEmpty
                                                    ? releaseKindTitle(album.kind) : detail,
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
            return displayedTracks.count
        case .albums:
            return albums(of: .album).count
        case .singles:
            return albums(of: .single).count
        case .compilations:
            return albums(of: .compilation).count
        case .related:
            return profile?.related.count ?? 0
        case .about:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch section(at: indexPath.section) {
        case .songs: return Theme.rowHeight(64)
        case .albums, .singles, .compilations, .related: return Theme.rowHeight(72)
        case .about: return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return Theme.rowHeight(80)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch self.section(at: section) {
        case .songs, .albums, .singles, .compilations:
            return 40
        default:
            return 30
        }
    }

    private func headerButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = Theme.font(11, weight: .semibold)
        button.setTitle(title, for: .normal)
        button.setTitleColor(Theme.accent, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let holder = UIView()
        holder.backgroundColor = Theme.background
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.font(12, weight: .semibold)
        label.textColor = Theme.secondaryText
        label.text = sectionTitle(self.section(at: section)).uppercased()
        holder.addSubview(label)

        var trailing: [UIButton] = []
        switch self.section(at: section) {
        case .songs:
            trailing.append(headerButton(trackSort, action: #selector(trackSortTapped)))
        case .albums, .singles, .compilations:
            let firstDiscography = visibleSections.firstIndex(where: {
                $0 == .albums || $0 == .singles || $0 == .compilations
            }) ?? -1
            if firstDiscography == section {
                trailing.append(headerButton(albumFilter, action: #selector(albumFilterTapped)))
                trailing.append(headerButton(albumSort, action: #selector(albumSortTapped)))
            }
        default:
            break
        }

        for button in trailing {
            holder.addSubview(button)
        }
        var constraints: [NSLayoutConstraint] = [
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 20),
            label.centerYAnchor.constraint(equalTo: holder.centerYAnchor, constant: 3)
        ]
        var right = holder.trailingAnchor
        for button in trailing.reversed() {
            constraints.append(button.trailingAnchor.constraint(equalTo: right, constant: -20))
            constraints.append(button.centerYAnchor.constraint(equalTo: label.centerYAnchor))
            right = button.leadingAnchor
        }
        if !trailing.isEmpty {
            constraints.append(label.trailingAnchor.constraint(lessThanOrEqualTo: right,
                                                               constant: -8))
        }
        NSLayoutConstraint.activate(constraints)
        return holder
    }

    @objc private func albumFilterTapped() {
        let sheet = UIAlertController(title: L10n.t("Discography"), message: nil,
                                      preferredStyle: .actionSheet)
        for choice in ArtistViewController.albumFilterChoices {
            sheet.addAction(UIAlertAction(title: L10n.t(choice), style: .default) { [weak self] _ in
                self?.setAlbumFilterForProbe(choice)
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.t("Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func albumSortTapped() {
        let sheet = UIAlertController(title: L10n.t("Sort"), message: nil,
                                      preferredStyle: .actionSheet)
        for choice in ArtistViewController.albumSortChoices {
            sheet.addAction(UIAlertAction(title: L10n.t(choice), style: .default) { [weak self] _ in
                self?.setAlbumSortForProbe(choice)
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.t("Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func trackSortTapped() {
        let sheet = UIAlertController(title: L10n.t("Sort"), message: nil,
                                      preferredStyle: .actionSheet)
        for choice in ArtistViewController.trackSortChoices {
            sheet.addAction(UIAlertAction(title: L10n.t(choice), style: .default) { [weak self] _ in
                self?.setTrackSortForProbe(choice)
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.t("Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch section(at: indexPath.section) {
        case .songs:
            let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier,
                                                     for: indexPath) as! TrackCell
            if indexPath.row < displayedTracks.count {
                cell.configure(with: displayedTracks[indexPath.row])
            }
            return cell
        case .albums, .singles, .compilations:
            let cell = tableView.dequeueReusableCell(withIdentifier: ArtistTileCell.reuseIdentifier,
                                                     for: indexPath) as! ArtistTileCell
            let kind: ReleaseKind = self.section(at: indexPath.section) == .albums ? .album
                : (self.section(at: indexPath.section) == .singles ? .single : .compilation)
            let rows = albums(of: kind)
            if indexPath.row < rows.count {
                let album = rows[indexPath.row]
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
                cell.configure(title: related.name, subtitle: L10n.t("Artist"), artwork: related.artwork)
            }
            return cell
        case .about:
            let cell = tableView.dequeueReusableCell(withIdentifier: ArtistAboutCell.reuseIdentifier,
                                                     for: indexPath) as! ArtistAboutCell
            cell.configure(text: profile?.bio ?? "", detail: profile?.listenerText,
                           expanded: bioExpanded) { [weak self] in
                guard let self = self else { return }
                SettingsStore.shared.set(!self.bioExpanded,
                                         for: ArtistViewController.bioExpandedKey)
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch section(at: indexPath.section) {
        case .songs:
            let picked = displayedTracks
            guard indexPath.row < picked.count else { return }
            PlayerService.shared.play(tracks: picked, startingAt: indexPath.row)
            presentNowPlayingFromRoot()
        case .albums:
            let rows = albums(of: .album)
            if indexPath.row < rows.count { openAlbum(rows[indexPath.row]) }
        case .singles:
            let rows = albums(of: .single)
            if indexPath.row < rows.count { openAlbum(rows[indexPath.row]) }
        case .compilations:
            let rows = albums(of: .compilation)
            if indexPath.row < rows.count { openAlbum(rows[indexPath.row]) }
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
    var onRadio: (() -> Void)?

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
    private let radioButton = UIButton(type: .system)
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

        styleAction(playButton, title: L10n.t("Play"), icon: .play, filled: true)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        styleAction(shuffleButton, title: L10n.t("Shuffle"), icon: .shuffle, filled: false)
        shuffleButton.addTarget(self, action: #selector(shuffleTapped), for: .touchUpInside)

        styleAction(radioButton, title: L10n.t("Radio"), icon: .radio, filled: false)
        radioButton.addTarget(self, action: #selector(radioTapped), for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [playButton, shuffleButton, radioButton])
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 8
        addSubview(actions)

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

            actions.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 16),
            actions.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            actions.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func styleAction(_ button: UIButton, title: String, icon: Icons.Kind, filled: Bool) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 21
        button.titleLabel?.font = Theme.font(13, weight: .semibold)
        button.setTitle(title, for: .normal)
        button.setImage(Icons.image(icon, size: 14), for: .normal)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 5)
        if filled {
            button.backgroundColor = Theme.accent
            button.tintColor = Theme.background
            button.setTitleColor(Theme.background, for: .normal)
        } else {
            button.layer.borderWidth = 1
            button.layer.borderColor = Theme.outline.cgColor
            button.tintColor = Theme.primaryText
            button.setTitleColor(Theme.primaryText, for: .normal)
        }
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

    @objc private func radioTapped() {
        onRadio?()
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
    private let moreButton = UIButton(type: .system)
    private var onToggle: (() -> Void)?

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

        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.contentHorizontalAlignment = .left
        moreButton.titleLabel?.font = Theme.font(13, weight: .semibold)
        moreButton.setTitleColor(Theme.accent, for: .normal)
        moreButton.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)
        contentView.addSubview(moreButton)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = Theme.font(12)
        detailLabel.textColor = Theme.secondaryText
        detailLabel.numberOfLines = 1
        contentView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            bodyLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            moreButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 6),
            moreButton.leadingAnchor.constraint(equalTo: bodyLabel.leadingAnchor),
            moreButton.heightAnchor.constraint(equalToConstant: 28),

            detailLabel.topAnchor.constraint(equalTo: moreButton.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: bodyLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: bodyLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(text: String, detail: String?, expanded: Bool, onToggle: @escaping () -> Void) {
        bodyLabel.text = text
        detailLabel.text = detail
        detailLabel.isHidden = (detail ?? "").isEmpty
        bodyLabel.numberOfLines = expanded ? 0 : 3
        moreButton.isHidden = text.count <= 180
        moreButton.setTitle(L10n.t(expanded ? "Show less" : "Show more"), for: .normal)
        self.onToggle = onToggle
    }

    @objc private func toggleTapped() {
        onToggle?()
    }
}
