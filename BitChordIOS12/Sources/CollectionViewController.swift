import UIKit

/// An artist or album page: big cover, title, and the tracks behind it, ready to
/// play. Upstream's `BrowseScreen` in miniature — the artwork is the header, the
/// list sits straight under it, and one tap on Play queues the whole thing.
final class CollectionViewController: UIViewController {
    /// Fills in the tracks when the page opens.
    var loader: ((([Track]) -> Void) -> Void)?

    private let heading: String
    private let detail: String
    private let artwork: URL?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let header = CollectionHeaderView()
    private let spinner = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
    private let emptyLabel = UILabel()

    private var tracks: [Track] = []

    init(title: String, subtitle: String, artwork: URL?) {
        self.heading = title
        self.detail = subtitle
        self.artwork = artwork
        super.init(nibName: nil, bundle: nil)
        self.title = title
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
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        view.addSubview(tableView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = Theme.secondaryText
        view.addSubview(spinner)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.font = Theme.font(14)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        header.configure(title: heading, subtitle: detail, artwork: artwork)
        header.onPlay = { [weak self] in
            guard let self = self, !self.tracks.isEmpty else { return }
            PlayerService.shared.play(tracks: self.tracks, startingAt: 0)
            self.presentNowPlayingFromRoot()
        }
        layoutHeader()
        load()
    }

    /// The header is the table's own header view, so it scrolls away with the list.
    private func layoutHeader() {
        let width = UIScreen.main.bounds.width
        header.frame = CGRect(x: 0, y: 0, width: width, height: 268)
        header.layoutIfNeeded()
        tableView.tableHeaderView = header
    }

    private func load() {
        spinner.startAnimating()
        loader? { [weak self] tracks in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            self.tracks = tracks
            self.header.isPlayEnabled = !tracks.isEmpty
            self.emptyLabel.text = tracks.isEmpty ? "Nothing to play here." : nil
            self.emptyLabel.isHidden = !tracks.isEmpty
            self.tableView.reloadData()
        }
    }
}

extension CollectionViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tracks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath)
        if let trackCell = cell as? TrackCell {
            trackCell.configure(with: tracks[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let picked = tracks
        guard indexPath.row < picked.count else { return }
        PlayerService.shared.play(tracks: picked, startingAt: indexPath.row)
        DispatchQueue.main.async { [weak self] in
            self?.presentNowPlayingFromRoot()
        }
    }
}

/// Cover, title, subtitle and a Play pill.
final class CollectionHeaderView: UIView {
    var onPlay: (() -> Void)?
    var isPlayEnabled = false {
        didSet { playButton.alpha = isPlayEnabled ? 1 : 0.4 }
    }

    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private var artworkTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.backgroundColor = Theme.surfaceVariant
        addSubview(artworkView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(22, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = Theme.font(13)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.numberOfLines = 1
        addSubview(subtitleLabel)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.backgroundColor = Theme.accent
        playButton.layer.cornerRadius = 18
        playButton.tintColor = .white
        playButton.setTitle("  Play  ", for: .normal)
        playButton.setTitleColor(.white, for: .normal)
        playButton.titleLabel?.font = Theme.font(14, weight: .semibold)
        playButton.setImage(Icons.image(.play, size: 15), for: .normal)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        addSubview(playButton)

        NSLayoutConstraint.activate([
            artworkView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            artworkView.centerXAnchor.constraint(equalTo: centerXAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 168),
            artworkView.heightAnchor.constraint(equalToConstant: 168),

            titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            playButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            playButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            playButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
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

    @objc private func playTapped() {
        onPlay?()
    }
}
