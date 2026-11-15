import UIKit

/// Downloads, shaped like the real destination: the circled back button and
/// 34pt title the other settings-style screens use, then one list — anything
/// still downloading at the top, then everything already on the device.
///
/// The rows are the same 52pt-artwork rows the library uses, so this holds from
/// a 320pt iPhone SE to an iPad without a separate layout.
final class DownloadsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let emptyTitle = UILabel()
    private let emptyDetail = UILabel()
    private let hero = UIView()
    private let heroIcon = UIImageView()
    private let heroBar = UIView()

    private enum Row {
        case active(Track, Double)
        case failed(Track, String)
        case saved(DownloadedTrack)
    }

    private var rows: [Row] {
        var items: [Row] = DownloadStore.shared.activeItems.map { track in
            .active(track, DownloadStore.shared.progress(for: track.videoID) ?? 0)
        }
        items.append(contentsOf: DownloadStore.shared.failedItems.map { Row.failed($0.track, $0.reason) })
        items.append(contentsOf: DownloadStore.shared.saved.map { Row.saved($0) })
        return items
    }

    /// Saved rows start after the in-flight and held ones.
    private var savedOffset: Int {
        return DownloadStore.shared.activeItems.count + DownloadStore.shared.failedItems.count
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildHeader()
        buildList()
        buildEmptyState()
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(downloadsChanged),
                                              name: .downloadsDidChange,
                                              object: nil)
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Chrome

    private func buildHeader() {
        let safe = view.safeAreaLayoutGuide

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.backgroundColor = UIColor(white: 1, alpha: 0.06)
        backButton.layer.cornerRadius = 22
        backButton.tintColor = Theme.primaryText
        backButton.setImage(Icons.image(.chevronLeft, size: 20), for: .normal)
        backButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(backButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Downloads"
        titleLabel.font = Theme.font(20, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        view.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Downloaded songs"
        subtitleLabel.font = Theme.font(15)
        subtitleLabel.textColor = Theme.secondaryText
        view.addSubview(subtitleLabel)

        // The real empty screen shows a large dark tile with a download glyph,
        // then the title and its subtitle centred under it.
        hero.translatesAutoresizingMaskIntoConstraints = false
        hero.backgroundColor = Theme.surfaceVariant
        hero.layer.cornerRadius = 16
        view.addSubview(hero)

        heroIcon.translatesAutoresizingMaskIntoConstraints = false
        heroIcon.image = Icons.image(.downloadArrow, size: 108)
        heroIcon.tintColor = UIColor(white: 0.62, alpha: 1)
        heroIcon.contentMode = .scaleAspectFit
        hero.addSubview(heroIcon)

        heroBar.translatesAutoresizingMaskIntoConstraints = false
        heroBar.backgroundColor = UIColor(white: 0.62, alpha: 1)
        heroBar.layer.cornerRadius = 4
        hero.addSubview(heroBar)

        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = Theme.surfaceVariant
        pill.layer.cornerRadius = 22
        view.addSubview(pill)

        let filter = UIImageView(image: Icons.image(.sliders, size: 20))
        filter.tintColor = Theme.secondaryText
        filter.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(filter)

        let account = UIButton(type: .system)
        account.backgroundColor = Theme.outline
        account.layer.cornerRadius = 15
        account.tintColor = Theme.secondaryText
        account.setImage(Icons.image(.personOutline, size: 17), for: .normal)
        account.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        account.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(account)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: -10),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            pill.topAnchor.constraint(equalTo: backButton.topAnchor),
            pill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            pill.widthAnchor.constraint(equalToConstant: 100),
            pill.heightAnchor.constraint(equalToConstant: 44),

            filter.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 18),
            filter.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            filter.widthAnchor.constraint(equalToConstant: 20),
            filter.heightAnchor.constraint(equalToConstant: 20),

            account.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
            account.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            account.widthAnchor.constraint(equalToConstant: 30),
            account.heightAnchor.constraint(equalToConstant: 30),

            hero.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 15),
            hero.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hero.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.76),
            hero.heightAnchor.constraint(equalTo: hero.widthAnchor, multiplier: 0.96),

            heroIcon.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            heroIcon.centerYAnchor.constraint(equalTo: hero.centerYAnchor, constant: -2),
            heroIcon.widthAnchor.constraint(equalToConstant: 108),
            heroIcon.heightAnchor.constraint(equalToConstant: 108),

            heroBar.topAnchor.constraint(equalTo: hero.centerYAnchor, constant: 32),
            heroBar.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            heroBar.widthAnchor.constraint(equalToConstant: 60),
            heroBar.heightAnchor.constraint(equalToConstant: 8),

            titleLabel.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 25),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func buildList() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 68
        tableView.tableFooterView = UIView()
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 40, right: 0)
        tableView.register(DownloadCell.self, forCellReuseIdentifier: DownloadCell.reuseIdentifier)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 14),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func buildEmptyState() {
        emptyTitle.translatesAutoresizingMaskIntoConstraints = false
        emptyTitle.text = "No downloaded tracks"
        emptyTitle.font = Theme.font(15)
        emptyTitle.textColor = Theme.secondaryText
        emptyTitle.textAlignment = .center
        view.addSubview(emptyTitle)

        emptyDetail.translatesAutoresizingMaskIntoConstraints = false
        emptyDetail.isHidden = true
        emptyDetail.font = Theme.font(14)
        emptyDetail.textColor = Theme.secondaryText
        emptyDetail.textAlignment = .center
        emptyDetail.numberOfLines = 0
        view.addSubview(emptyDetail)

        NSLayoutConstraint.activate([
            emptyTitle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyTitle.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 71),
            emptyTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyTitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            emptyDetail.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyDetail.topAnchor.constraint(equalTo: emptyTitle.bottomAnchor, constant: 8),
            emptyDetail.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyDetail.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The screen has its own circled back button, so no system bar above it.
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    @objc private func close() {
        if let nav = navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true, completion: nil)
        }
    }

    @objc private func downloadsChanged() {
        reload()
    }

    private func reload() {
        tableView.reloadData()
        let empty = rows.isEmpty
        emptyTitle.isHidden = !empty
        emptyDetail.isHidden = true
        tableView.isHidden = empty
    }

    @objc private func openSettings() {
        let settings = SettingsViewController()
        let navigation = UINavigationController(rootViewController: settings)
        navigation.navigationBar.barTintColor = Theme.background
        navigation.navigationBar.tintColor = Theme.accent
        navigation.navigationBar.isTranslucent = false
        navigation.navigationBar.titleTextAttributes = [.foregroundColor: Theme.primaryText]
        settings.modalPresentationStyle = .fullScreen
        present(navigation, animated: true, completion: nil)
    }

    private func delete(at index: Int, item: DownloadedTrack) {
        let alert = UIAlertController(
            title: "Delete download",
            message: "Remove \u{201C}\(item.track.title)\u{201D} from this device? Tap again to confirm.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            DownloadStore.shared.remove(item.track.videoID)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func play(at index: Int) {
        // The queue is everything saved, so next/previous stay inside the
        // downloaded set and every item resolves to a file.
        let tracks = DownloadStore.shared.saved.map { $0.track }
        guard index < tracks.count else { return }
        PlayerService.shared.play(tracks: tracks, startingAt: index)
        // Pushed inside the Library, the container above this screen hosts the
        // player. Presented (from Settings, or on its own), the whole modal
        // stack has to come down first or the root is already presenting.
        if navigationController != nil {
            presentNowPlayingFromRoot()
        } else if let root = UIApplication.shared.keyWindow?.rootViewController as? RootViewController {
            presentingViewController?.dismiss(animated: false) {
                root.presentNowPlaying()
            }
        } else {
            presentNowPlayingFromRoot()
        }
    }
}

extension DownloadsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DownloadCell.reuseIdentifier,
                                                 for: indexPath) as! DownloadCell
        switch rows[indexPath.row] {
        case .active(let track, let fraction):
            let percent = Int((fraction * 100).rounded())
            cell.configure(track: track, detail: "Downloading\u{2026}",
                           trailing: "\(percent)%", progress: fraction)
        case .failed(let track, let reason):
            cell.configure(track: track, detail: reason, trailing: "HELD",
                           progress: nil, warning: true)
        case .saved(let item):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let size = formatter.string(fromByteCount: item.byteSize)
            let quality = item.qualityLabel.isEmpty ? "Audio" : item.qualityLabel
            cell.configure(track: item.track,
                           detail: "\(quality) \u{00B7} \(size)",
                           trailing: nil, progress: nil)
            cell.accessoryType = .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .saved:
            play(at: max(0, indexPath.row - savedOffset))
        case .failed(let track, _):
            // Tapping a held row tries again with the current settings.
            DownloadStore.shared.download(track)
        case .active:
            break
        }
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        let action: UIContextualAction
        switch rows[indexPath.row] {
        case .saved(let item):
            action = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
                DownloadStore.shared.remove(item.track.videoID)
                done(true)
                self?.reload()
            }
        case .active(let track, _):
            action = UIContextualAction(style: .normal, title: "Cancel") { _, _, done in
                DownloadStore.shared.cancel(track.videoID)
                done(true)
            }
            action.backgroundColor = Theme.surfaceVariant
        case .failed(let track, _):
            action = UIContextualAction(style: .normal, title: "Retry") { _, _, done in
                DownloadStore.shared.download(track)
                done(true)
            }
            action.backgroundColor = Theme.surfaceVariant
        }
        return UISwipeActionsConfiguration(actions: [action])
    }
}

/// One download row: artwork, title, and either a size or live progress.
final class DownloadCell: UITableViewCell {
    static let reuseIdentifier = "DownloadCell"

    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let trailingLabel = UILabel()
    private let bar = UIView()
    private var barWidth: NSLayoutConstraint!
    private var fraction: Double = 0
    private var artworkTask: URLSessionDataTask?
    private var currentVideoID: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let selected = UIView()
        selected.backgroundColor = Theme.surface
        selectedBackgroundView = selected

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.layer.borderWidth = 1
        artworkView.layer.borderColor = UIColor(white: 1, alpha: 0.15).cgColor
        artworkView.backgroundColor = Theme.surfaceVariant
        contentView.addSubview(artworkView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(.titleMedium)
        titleLabel.textColor = Theme.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = Theme.font(.bodyMedium)
        detailLabel.textColor = Theme.secondaryText
        detailLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(detailLabel)

        trailingLabel.translatesAutoresizingMaskIntoConstraints = false
        trailingLabel.font = Theme.font(.labelMedium)
        trailingLabel.textColor = Theme.secondaryText
        trailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(trailingLabel)

        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = Theme.accent
        bar.layer.cornerRadius = 1.5
        bar.isHidden = true
        contentView.addSubview(bar)

        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.gutter),
            artworkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: Theme.rowArtwork),
            artworkView.heightAnchor.constraint(equalToConstant: Theme.rowArtwork),

            titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingLabel.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -1),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingLabel.leadingAnchor, constant: -8),
            detailLabel.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 2),

            trailingLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.gutter),
            trailingLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            bar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            bar.heightAnchor.constraint(equalToConstant: 3)
        ])
        // The filled part is a fraction of the row's text width, clipped by a track.
        barWidth = bar.widthAnchor.constraint(equalToConstant: 0)
        barWidth.isActive = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(track: Track, detail: String, trailing: String?, progress: Double?,
                   warning: Bool = false) {
        titleLabel.text = track.title
        detailLabel.text = detail
        trailingLabel.text = trailing
        let warningColor = UIColor(red: 1, green: 0.62, blue: 0.04, alpha: 1)
        detailLabel.textColor = warning ? warningColor : Theme.secondaryText
        trailingLabel.textColor = warning ? warningColor : Theme.secondaryText
        detailLabel.numberOfLines = warning ? 2 : 1
        if let progress = progress {
            bar.isHidden = false
            fraction = max(0, min(1, progress))
            setNeedsLayout()
        } else {
            bar.isHidden = true
            fraction = 0
            barWidth.constant = 0
        }

        currentVideoID = track.videoID
        artworkTask?.cancel()
        let url = track.artworkURL
        if let cached = ArtworkLoader.shared.cached(url) {
            artworkView.image = cached
            return
        }
        artworkView.image = nil
        artworkTask = ArtworkLoader.shared.load(url) { [weak self] image in
            guard let self = self, self.currentVideoID == track.videoID else { return }
            self.artworkView.image = image
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The progress bar spans the text column, which is whatever the row has
        // left after the 52pt artwork — 320pt SE through iPad, no fixed width.
        guard !bar.isHidden else { return }
        let available = contentView.bounds.width - (Theme.gutter + Theme.rowArtwork + 14 + Theme.gutter)
        barWidth.constant = CGFloat(fraction) * max(0, available)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkTask?.cancel()
        artworkTask = nil
        artworkView.image = nil
        currentVideoID = nil
    }
}
