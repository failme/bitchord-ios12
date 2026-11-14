import UIKit

/// Library as the real app draws it: a listening-stats pair of cards, then
/// Downloads / Local Music rows, then the Playlists grid.
final class LibraryViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let titleLabel = UILabel()
    private let statsRow = UIStackView()
    private weak var statsScroller: UIScrollView?
    private let playlistGrid = UIStackView()

    private var playlists: [Playlist] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        // The page draws its own 34pt heading; an empty large-title bar would
        // push every card down by half a screen.
        navigationItem.largeTitleDisplayMode = .never

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
        // Real order: the history/account capsule sits high on the right, then
        // the 34pt Library title drops below it on the next line.
        let header = UIView()
        header.heightAnchor.constraint(equalToConstant: 106).isActive = true

        titleLabel.text = "Library"
        titleLabel.font = Theme.font(34, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)

        // The real header keeps history and the account avatar in one capsule,
        // each a full 48pt target beside the other.
        let pill = UIView()
        pill.backgroundColor = Theme.surfaceVariant
        pill.layer.cornerRadius = 24
        pill.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(pill)

        let history = UIButton(type: .custom)
        history.tintColor = Theme.secondaryText
        history.setImage(Icons.image(.history, size: 21), for: .normal)
        history.addTarget(self, action: #selector(openHistory), for: .touchUpInside)
        history.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(history)

        let avatar = UIButton(type: .custom)
        avatar.backgroundColor = Theme.outline
        avatar.layer.cornerRadius = 17
        avatar.tintColor = Theme.secondaryText
        avatar.setImage(Icons.image(.person, size: 18), for: .normal)
        avatar.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(avatar)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: pill.bottomAnchor, constant: 20),

            pill.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            pill.topAnchor.constraint(equalTo: header.topAnchor, constant: -11),
            pill.widthAnchor.constraint(equalToConstant: 100),
            pill.heightAnchor.constraint(equalToConstant: 48),

            history.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 4),
            history.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            history.widthAnchor.constraint(equalToConstant: 44),
            history.heightAnchor.constraint(equalToConstant: 44),

            avatar.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
            avatar.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 34),
            avatar.heightAnchor.constraint(equalToConstant: 34)
        ])
        stack.addArrangedSubview(header)
    }

    private func buildStats() {
        statsRow.axis = .horizontal
        statsRow.spacing = 12
        statsRow.alignment = .fill
        statsRow.translatesAutoresizingMaskIntoConstraints = false

        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(holder)

        // The real cards are 300pt wide, 189pt tall and paged: the second one
        // peeks in from the right instead of being squeezed beside the first.
        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        scroller.alwaysBounceHorizontal = true
        scroller.decelerationRate = .fast
        scroller.delegate = self
        statsScroller = scroller
        scroller.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(scroller)
        scroller.addSubview(statsRow)

        let experience = LibraryStatCard(colors: [UIColor(red: 0.58, green: 0.36, blue: 0.10, alpha: 1),
                                                  UIColor(red: 0.42, green: 0.11, blue: 0.16, alpha: 1),
                                                  UIColor(red: 0.23, green: 0.06, blue: 0.15, alpha: 1)])
        experience.tag = 9002
        experience.widthAnchor.constraint(equalToConstant: 300).isActive = true
        experience.onTap = { [weak self] in
            self?.navigationController?.pushViewController(ReplayViewController(), animated: true)
        }
        statsRow.addArrangedSubview(experience)

        let top = LibraryStatCard(colors: [UIColor(red: 0.52, green: 0.31, blue: 0.08, alpha: 1),
                                           UIColor(red: 0.38, green: 0.10, blue: 0.14, alpha: 1),
                                           UIColor(red: 0.21, green: 0.05, blue: 0.13, alpha: 1)])
        top.tag = 9003
        top.widthAnchor.constraint(equalToConstant: 300).isActive = true
        top.onTap = { [weak self] in
            self?.navigationController?.pushViewController(ReplayViewController(), animated: true)
        }
        statsRow.addArrangedSubview(top)

        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(equalToConstant: 197),
            scroller.topAnchor.constraint(equalTo: holder.topAnchor, constant: 8),
            scroller.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            scroller.heightAnchor.constraint(equalToConstant: 189),
            statsRow.topAnchor.constraint(equalTo: scroller.topAnchor),
            statsRow.leadingAnchor.constraint(equalTo: scroller.leadingAnchor, constant: 16),
            statsRow.trailingAnchor.constraint(equalTo: scroller.trailingAnchor, constant: -16),
            statsRow.heightAnchor.constraint(equalTo: scroller.heightAnchor)
        ])
    }

    private func buildRows() {
        rowsHolder.axis = .vertical
        rowsHolder.alignment = .fill
        let rows = ["Downloads", "Local Music"]
        var index = 0
        for title in rows {
            let row = LibraryRowButton(title: title,
                                       icon: index == 0 ? .download : .folder)
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            row.tag = index
            rowsHolder.addArrangedSubview(row)
            index += 1
        }
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)
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

        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(equalToConstant: 52),
            heading.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 16),
            heading.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -8)
        ])
        stack.addArrangedSubview(holder)

        playlistGrid.axis = .vertical
        playlistGrid.alignment = .leading
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

        let recent = LibraryStore.shared.recentTracks
        let plays = recent.count
        let year = Calendar.current.component(.year, from: Date())
        if let card = statsRow.viewWithTag(9002) as? LibraryStatCard {
            card.configure(value: "\(plays * 4 + 9)",
                           valueCaption: "MINUTES LISTENED",
                           line: "BITCHORD LISTENER",
                           detail: "\(plays) plays · \(year)",
                           memberCaption: "MEMBER SINCE",
                           memberValue: "11/26")
        }
        if let card = statsRow.viewWithTag(9003) as? LibraryStatCard {
            let song = recent.first
            card.configure(value: song?.title ?? "—",
                           valueCaption: "TOP SONG",
                           line: "BITCHORD LISTENER",
                           detail: song.map { "\($0.artist) · \(plays) \(plays == 1 ? "play" : "plays")" } ?? "No plays yet",
                           memberCaption: "",
                           memberValue: "")
        }

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
        firstRow.widthAnchor.constraint(equalToConstant: 310).isActive = true

        let create = PlaylistCard(title: "New playlist",
                                        caption: "Saved to YouTube Music",
                                        icon: .plus)
        create.onTap = { [weak self] in self?.createPlaylistPrompt() }
        firstRow.addArrangedSubview(create)

        let importCard = PlaylistCard(title: "Import Spotify",
                                            caption: "From a playlist link",
                                            icon: .spotify)
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
                newRow.widthAnchor.constraint(equalToConstant: 310).isActive = true
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
        switch sender.tag {
        case 0:
            navigationController?.pushViewController(DownloadsViewController(), animated: true)
        default:
            navigationController?.pushViewController(LocalMusicViewController(), animated: true)
        }
    }

    @objc private func openHistory() {
        navigationController?.pushViewController(HistoryViewController(), animated: true)
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
    private let gradient = CAGradientLayer()
    private let topCaption = UILabel()
    private let logo = UIImageView(image: Icons.image(.logo, size: 30))
    private let valueLabel = UILabel()
    private let valueCaption = UILabel()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let memberCaption = UILabel()
    private let memberValue = UILabel()
    var onTap: (() -> Void)?

    init(colors: [UIColor]) {
        super.init(frame: .zero)
        layer.cornerRadius = 14
        layer.masksToBounds = true

        gradient.colors = colors.map { $0.cgColor }
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 0.9, y: 1)
        layer.addSublayer(gradient)

        topCaption.translatesAutoresizingMaskIntoConstraints = false
        topCaption.font = Theme.font(10, weight: .semibold)
        topCaption.textColor = UIColor(white: 1, alpha: 0.92)
        topCaption.text = "YOUR LISTENING EXPERIENCE"
        addSubview(topCaption)

        logo.tintColor = .white
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        addSubview(logo)

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = Theme.font(34, weight: .bold)
        valueLabel.textColor = .white
        valueLabel.numberOfLines = 1
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.45
        addSubview(valueLabel)

        valueCaption.translatesAutoresizingMaskIntoConstraints = false
        valueCaption.font = Theme.font(10, weight: .semibold)
        valueCaption.textColor = UIColor(white: 1, alpha: 0.9)
        addSubview(valueCaption)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = Theme.font(12, weight: .semibold)
        nameLabel.textColor = UIColor(white: 1, alpha: 0.94)
        nameLabel.text = "BITCHORD LISTENER"
        addSubview(nameLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = Theme.font(13)
        detailLabel.textColor = UIColor(white: 1, alpha: 0.82)
        detailLabel.numberOfLines = 1
        addSubview(detailLabel)

        memberCaption.translatesAutoresizingMaskIntoConstraints = false
        memberCaption.font = Theme.font(9, weight: .semibold)
        memberCaption.textColor = UIColor(white: 1, alpha: 0.8)
        memberCaption.textAlignment = .right
        addSubview(memberCaption)

        memberValue.translatesAutoresizingMaskIntoConstraints = false
        memberValue.font = Theme.font(15, weight: .bold)
        memberValue.textColor = .white
        memberValue.textAlignment = .right
        addSubview(memberValue)

        NSLayoutConstraint.activate([
            topCaption.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            topCaption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            logo.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            logo.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            logo.widthAnchor.constraint(equalToConstant: 30),
            logo.heightAnchor.constraint(equalToConstant: 30),

            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 62),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            valueCaption.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 1),
            valueCaption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            valueCaption.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            nameLabel.bottomAnchor.constraint(equalTo: detailLabel.topAnchor, constant: -3),

            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: memberCaption.leadingAnchor, constant: -8),

            memberCaption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            memberCaption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),

            memberValue.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            memberValue.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    func configure(value: String,
                   valueCaption: String,
                   line: String,
                   detail: String,
                   memberCaption: String,
                   memberValue: String) {
        valueLabel.text = value
        self.valueCaption.attributedText = Theme.attributed(valueCaption.uppercased(), .labelSmall,
                                                             color: UIColor(white: 1, alpha: 0.9))
        nameLabel.text = line
        detailLabel.text = detail
        self.memberCaption.text = memberCaption
        self.memberValue.text = memberValue
    }

    @objc private func tapped() {
        onTap?()
    }
}

/// "Downloads" / "Local Music" row: icon, label and a hairline.
final class LibraryRowButton: UIControl {
    init(title: String, icon: Icons.Kind) {
        super.init(frame: .zero)
        let glyph = UIImageView(image: Icons.image(icon, size: 20))
        glyph.tintColor = Theme.primaryText
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        let label = UILabel()
        label.text = title
        label.font = Theme.font(20)
        label.textColor = Theme.primaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let hairline = UIView()
        hairline.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 54),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 18),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 56),
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
        build(with: Icons.image(icon, size: 50))
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

        titleLabel.font = Theme.font(19, weight: .medium)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        captionLabel.font = Theme.font(14)
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
        addTarget(self, action: #selector(pressIn), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressOut),
                  for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    @objc private func pressIn() {
        UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
    }

    @objc private func pressOut() {
        UIView.animate(withDuration: 0.24, delay: 0, usingSpringWithDamping: 0.7,
                       initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
            self.transform = .identity
        }
    }

    @objc private func tapped() {
        onTap?()
    }
}

extension LibraryViewController: UIScrollViewDelegate {
    func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                   withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scrollView === statsScroller else { return }
        // The stat cards page one at a time, each card plus its 12pt gap.
        let page: CGFloat = 312
        let proposed = targetContentOffset.pointee.x
        targetContentOffset.pointee.x = (proposed / page).rounded() * page
    }
}
