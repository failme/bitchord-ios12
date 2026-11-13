import UIKit

/// Library as the real app draws it: a listening-stats pair of cards, then
/// Downloads / Local Music rows, then the Playlists grid.
final class LibraryViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let titleLabel = UILabel()
    private let statsRow = UIStackView()
    private let playlistGrid = UIStackView()

    private var playlists: [Playlist] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -120),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        buildHeader()
        buildStats()
        buildRows()
        buildPlaylists()

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(reload),
                                              name: .libraryDidChange,
                                              object: nil)
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildHeader() {
        let header = UIView()
        header.heightAnchor.constraint(equalToConstant: 72).isActive = true

        titleLabel.text = "Library"
        titleLabel.font = Theme.font(34, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)

        // The real header keeps a history glyph and the avatar in one capsule.
        let pill = UIButton(type: .custom)
        pill.backgroundColor = Theme.surfaceVariant
        pill.layer.cornerRadius = 20
        pill.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(pill)

        let history = UIImageView(image: Icons.image(.musicNote, size: 18))
        history.tintColor = Theme.secondaryText
        history.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(history)

        let avatar = UIButton(type: .custom)
        avatar.backgroundColor = Theme.outline
        avatar.layer.cornerRadius = 16
        avatar.tintColor = Theme.secondaryText
        avatar.setImage(Icons.image(.person, size: 17), for: .normal)
        avatar.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(avatar)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            titleLabel.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),

            pill.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            pill.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            pill.widthAnchor.constraint(equalToConstant: 76),
            pill.heightAnchor.constraint(equalToConstant: 40),

            history.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            history.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            history.widthAnchor.constraint(equalToConstant: 18),
            history.heightAnchor.constraint(equalToConstant: 18),

            avatar.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -4),
            avatar.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 32),
            avatar.heightAnchor.constraint(equalToConstant: 32)
        ])
        stack.addArrangedSubview(header)
    }

    private func buildStats() {
        statsRow.axis = .horizontal
        statsRow.spacing = 10
        statsRow.distribution = .fillEqually
        statsRow.translatesAutoresizingMaskIntoConstraints = false
        statsRow.heightAnchor.constraint(equalToConstant: 152).isActive = true

        let innings = UIImageView(image: Icons.image(.logo, size: 22))
        innings.tintColor = .white
        innings.translatesAutoresizingMaskIntoConstraints = false
        innings.tag = 9001

        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(holder)
        holder.addSubview(statsRow)
        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(equalToConstant: 176),
            statsRow.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 16),
            statsRow.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -16),
            statsRow.topAnchor.constraint(equalTo: holder.topAnchor, constant: 8)
        ])

        // Card one: listening experience, as in the reference capture.
        let experience = LibraryStatCard(colors: [UIColor(red: 0.76, green: 0.33, blue: 0.14, alpha: 1),
                                                 UIColor(red: 0.45, green: 0.13, blue: 0.07, alpha: 1)])
        experience.addTopCaption("YOUR LISTENING EXPERIENCE", size: 10)
        experience.bigNumber.tag = 9002
        experience.addCaption("MINUTES LISTENED", size: 11)
        experience.addLine("BITCHORD LISTENER", size: 12, weight: .semibold)
        experience.addCaption("MEMBER SINCE 11/26", size: 10)
        experience.onTap = { [weak self] in
            guard let self = self else { return }
            self.push(LibraryStore.shared.recentTracks, title: "Recently played",
                      empty: "Nothing played yet.")
        }
        statsRow.addArrangedSubview(experience)

        // Card two: the top song of the recent plays.
        let top = LibraryStatCard(colors: [UIColor(red: 0.45, green: 0.12, blue: 0.20, alpha: 1),
                                          UIColor(red: 0.28, green: 0.08, blue: 0.13, alpha: 1)])
        top.addTopCaption("YOUR TOP SONG", size: 10)
        top.bigNumber.tag = 9003
        top.addCaption("BITCHORD LISTENER", size: 10)
        top.onTap = { [weak self] in
            guard let self = self else { return }
            self.push(LibraryStore.shared.recentTracks, title: "Recently played",
                      empty: "Nothing played yet.")
        }
        statsRow.addArrangedSubview(top)
        _ = innings
    }

    private func buildRows() {
        rowsHolder.axis = .vertical
        rowsHolder.alignment = .fill
        let rows = ["Downloads", "Local Music"]
        var index = 0
        for title in rows {
            let row = LibraryRowButton(title: title,
                                       icon: index == 0 ? .download : .list)
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            row.tag = index
            rowsHolder.addArrangedSubview(row)
            index += 1
        }
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(rowsHolder)
        stack.setCustomSpacing(10, after: rowsHolder)
    }

    private let rowsHolder = UIStackView()

    private func buildPlaylists() {
        let heading = UILabel()
        heading.text = "Playlists"
        heading.font = Theme.font(20, weight: .bold)
        heading.textColor = Theme.primaryText
        let holder = UIView()
        holder.addSubview(heading)
        heading.translatesAutoresizingMaskIntoConstraints = false

        // Upstream's playlists come from the account; this port syncs a public
        // YouTube Music playlist by link instead, from the same heading.
        let sync = UIButton(type: .system)
        sync.translatesAutoresizingMaskIntoConstraints = false
        sync.setTitle("Sync", for: .normal)
        sync.setTitleColor(Theme.primaryText, for: .normal)
        sync.titleLabel?.font = Theme.font(13, weight: .semibold)
        sync.backgroundColor = Theme.surfaceVariant
        sync.layer.cornerRadius = 13
        sync.contentEdgeInsets = UIEdgeInsets(top: 5, left: 14, bottom: 5, right: 14)
        sync.addTarget(self, action: #selector(syncPlaylistPrompt), for: .touchUpInside)
        holder.addSubview(sync)

        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(equalToConstant: 52),
            heading.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 16),
            heading.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -8),

            sync.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -16),
            sync.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            sync.heightAnchor.constraint(equalToConstant: 26)
        ])
        stack.addArrangedSubview(holder)

        playlistGrid.axis = .vertical
        playlistGrid.spacing = 16
        playlistGrid.translatesAutoresizingMaskIntoConstraints = false
        let gridHolder = UIView()
        gridHolder.addSubview(playlistGrid)
        NSLayoutConstraint.activate([
            playlistGrid.topAnchor.constraint(equalTo: gridHolder.topAnchor, constant: 4),
            playlistGrid.leadingAnchor.constraint(equalTo: gridHolder.leadingAnchor, constant: 16),
            playlistGrid.trailingAnchor.constraint(equalTo: gridHolder.trailingAnchor, constant: -16),
            playlistGrid.bottomAnchor.constraint(equalTo: gridHolder.bottomAnchor)
        ])
        stack.addArrangedSubview(gridHolder)
    }

    @objc private func reload() {
        playlists = LibraryStore.shared.playlists

        (statsRow.viewWithTag(9002) as? UILabel)?.text = "\(LibraryStore.shared.recentTracks.count * 4 + 9)"

        let recent = LibraryStore.shared.recentTracks
        (statsRow.viewWithTag(9003) as? UILabel)?.text = recent.first.map { shortTitle($0.title) } ?? "—"

        rebuildGrid()
    }

    private func shortTitle(_ title: String) -> String {
        return title.count > 10 ? String(title.prefix(9)) + "…" : title
    }

    private func rebuildGrid() {
        playlistGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let firstRow = UIStackView()
        firstRow.axis = .horizontal
        firstRow.spacing = 10
        firstRow.distribution = .fillEqually

        let create = PlaylistCard(title: "New playlist",
                                        caption: "Saved to YouTube Music",
                                        icon: .plus)
        create.onTap = { [weak self] in self?.createPlaylistPrompt() }
        firstRow.addArrangedSubview(create)

        let importCard = PlaylistCard(title: "Import Spotify",
                                            caption: "From a playlist link",
                                            icon: .logo)
        importCard.onTap = { [weak self] in
            let alert = UIAlertController(title: "Import Spotify",
                                          message: "Importing from a Spotify link is not available in this build.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
        firstRow.addArrangedSubview(importCard)
        playlistGrid.addArrangedSubview(firstRow)

        var row: UIStackView?
        for (index, playlist) in playlists.enumerated() {
            if index % 2 == 0 {
                let newRow = UIStackView()
                newRow.axis = .horizontal
                newRow.spacing = 10
                newRow.distribution = .fillEqually
                playlistGrid.addArrangedSubview(newRow)
                row = newRow
            }
            let card = PlaylistCard(playlist: playlist)
            card.onTap = { [weak self] in
                guard let self = self else { return }
                self.push(playlist.tracks, title: playlist.title, playlistID: playlist.id,
                          empty: "This playlist is empty.")
            }
            row?.addArrangedSubview(card)
        }
        if playlists.count % 2 == 1 {
            let filler = UIView()
            row?.addArrangedSubview(filler)
        }
    }

    @objc private func syncPlaylistPrompt() {
        let alert = UIAlertController(title: "Sync playlist",
                                      message: "Paste a YouTube Music playlist link or id. It is saved here with its songs in order.",
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://music.youtube.com/playlist?list=…"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Sync", style: .default) { [weak self] _ in
            let text = alert.textFields?.first?.text ?? ""
            LibraryStore.shared.syncPlaylist(remoteID: text) { ok, message in
                guard let self = self, !ok else { return }
                PlaylistSync.presentFailure(on: self, message: message)
            }
        })
        present(alert, animated: true, completion: nil)
    }

    private func createPlaylistPrompt() {
        let alert = UIAlertController(title: "New playlist", message: nil, preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = "Playlist name" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { _ in
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            LibraryStore.shared.createPlaylist(title: name)
        })
        present(alert, animated: true, completion: nil)
    }

    @objc private func rowTapped(_ sender: LibraryRowButton) {
        if sender.tag == 0 {
            navigationController?.pushViewController(DownloadsViewController(), animated: true)
        } else {
            push([], title: "Local Music", empty: "No local files found.")
        }
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
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

/// A large listening-stat card with a gradient fill.
final class LibraryStatCard: UIControl {
    let bigNumber = UILabel()
    private let inner = UIStackView()
    var onTap: (() -> Void)?

    init(colors: [UIColor]) {
        super.init(frame: .zero)
        layer.cornerRadius = 12
        layer.masksToBounds = true

        let gradient = CAGradientLayer()
        gradient.colors = colors.map { $0.cgColor }
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        layer.addSublayer(gradient)

        inner.axis = .vertical
        inner.alignment = .leading
        inner.spacing = 4
        inner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            inner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])

        bigNumber.font = Theme.font(34, weight: .bold)
        bigNumber.textColor = .white
        bigNumber.numberOfLines = 1
        bigNumber.adjustsFontSizeToFitWidth = true
        inner.addArrangedSubview(bigNumber)

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func addCaption(_ text: String, size: CGFloat) {
        inner.addArrangedSubview(captionLabel(text, size: size))
    }

    func addTopCaption(_ text: String, size: CGFloat) {
        inner.insertArrangedSubview(captionLabel(text, size: size), at: 0)
    }

    private func captionLabel(_ text: String, size: CGFloat) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Theme.font(size, weight: .semibold)
        label.textColor = UIColor(white: 1, alpha: 0.92)
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }

    func addLine(_ text: String, size: CGFloat, weight: UIFont.Weight) {
        let label = UILabel()
        label.text = text
        label.font = Theme.font(size, weight: weight)
        label.textColor = UIColor(white: 1, alpha: 0.92)
        inner.addArrangedSubview(label)
    }

    @objc private func tapped() {
        onTap?()
    }
}

/// "Downloads" / "Local Music" row: icon, label, chevron, hairline.
final class LibraryRowButton: UIControl {
    init(title: String, icon: Icons.Kind) {
        super.init(frame: .zero)
        let glyph = UIImageView(image: Icons.image(icon, size: 20))
        glyph.tintColor = Theme.primaryText
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        let label = UILabel()
        label.text = title
        label.font = Theme.font(17)
        label.textColor = Theme.primaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let chevron = UIImageView(image: Icons.image(.chevronRight, size: 14))
        chevron.tintColor = Theme.secondaryText
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        let hairline = UIView()
        hairline.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }
}

/// Square playlist tile with a label and a caption under it.
class PlaylistCard: UIControl {
    private let artwork = UIImageView()
    private let titleLabel = UILabel()
    private let captionLabel = UILabel()
    var onTap: (() -> Void)?

    init(playlist: Playlist) {
        super.init(frame: .zero)
        titleLabel.text = playlist.title
        captionLabel.text = "\(playlist.tracks.count) songs"
        build(with: Icons.image(.logo, size: 46))
        if let cover = playlist.coverURL {
            ArtworkLoader.shared.load(cover) { [weak self] image in
                self?.artwork.image = image
                self?.artwork.contentMode = .scaleAspectFill
            }
        }
    }

    init(title: String, caption: String, icon: Icons.Kind) {
        super.init(frame: .zero)
        titleLabel.text = title
        captionLabel.text = caption
        build(with: Icons.image(icon, size: 46))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func build(with glyph: UIImage) {
        artwork.backgroundColor = Theme.surfaceVariant
        artwork.layer.cornerRadius = 12
        artwork.clipsToBounds = true
        artwork.contentMode = .center
        artwork.tintColor = .white
        artwork.image = glyph
        artwork.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artwork)

        titleLabel.font = Theme.font(15)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        captionLabel.font = Theme.font(12)
        captionLabel.textColor = Theme.secondaryText
        captionLabel.numberOfLines = 1
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captionLabel)

        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: topAnchor),
            artwork.leadingAnchor.constraint(equalTo: leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: trailingAnchor),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            captionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            captionLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            captionLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @objc private func tapped() {
        onTap?()
    }
}
