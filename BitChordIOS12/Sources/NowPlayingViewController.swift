import UIKit

/// Port of upstream `NowPlayingView`: artwork or lyrics in the centre, quality badge, scrubber,
/// full transport with shuffle and repeat, like, and a queue sheet.
final class NowPlayingViewController: UIViewController {
    private let closeButton = UIButton(type: .system)
    private let artworkView = UIImageView()
    private let lyricsTable = UITableView(frame: .zero, style: .plain)
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let badgeLabel = UILabel()
    private let statusLabel = UILabel()
    private let diagnosticsLabel = UILabel()
    private let slider = UISlider()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()

    private let shuffleButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)
    private let likeButton = UIButton(type: .system)
    private let queueButton = UIButton(type: .system)
    private let toggleButton = UIButton(type: .system)

    private var currentTrackID: String?
    private var lyricsToken = ""
    private var currentLyrics: [LyricLine] = []
    private var lyricsSynced = false
    private var lyricHighlight = -1
    private var userScrolling = false
    private var showingLyrics = false
    private var artworkTask: URLSessionDataTask?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildLayout()
        applyMode(lyrics: false)

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(playerChanged),
                                              name: .playerDidChange,
                                              object: nil)
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(tick),
                                              name: .playerTimeDidChange,
                                              object: nil)
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(playerChanged),
                                              name: .libraryDidChange,
                                              object: nil)
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    private func buildLayout() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(Icons.image(.chevronDown, size: 22), for: .normal)

        closeButton.tintColor = Theme.primaryText
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(closeButton)

        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.setTitle("Lyrics", for: .normal)
        toggleButton.titleLabel?.font = Theme.font(14, weight: .semibold)
        toggleButton.tintColor = Theme.accent
        toggleButton.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)
        view.addSubview(toggleButton)

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.backgroundColor = Theme.surface
        artworkView.isUserInteractionEnabled = true
        artworkView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleMode)))
        view.addSubview(artworkView)

        lyricsTable.translatesAutoresizingMaskIntoConstraints = false
        lyricsTable.dataSource = self
        lyricsTable.delegate = self
        lyricsTable.backgroundColor = Theme.background
        lyricsTable.separatorStyle = .none
        lyricsTable.rowHeight = UITableView.automaticDimension
        lyricsTable.estimatedRowHeight = 30
        lyricsTable.register(LyricCell.self, forCellReuseIdentifier: LyricCell.reuseIdentifier)
        view.addSubview(lyricsTable)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(20, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        artistLabel.font = Theme.font(14)
        artistLabel.textColor = Theme.secondaryText
        artistLabel.textAlignment = .center
        view.addSubview(artistLabel)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = Theme.font(10, weight: .semibold)
        badgeLabel.textColor = Theme.accent
        badgeLabel.textAlignment = .center
        view.addSubview(badgeLabel)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = Theme.font(12)
        statusLabel.textColor = Theme.accent
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        view.addSubview(statusLabel)

        diagnosticsLabel.translatesAutoresizingMaskIntoConstraints = false
        diagnosticsLabel.font = Theme.monoDigits(9)
        diagnosticsLabel.textColor = Theme.secondaryText
        diagnosticsLabel.textAlignment = .center
        diagnosticsLabel.numberOfLines = 2
        view.addSubview(diagnosticsLabel)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumTrackTintColor = Theme.accent
        slider.maximumTrackTintColor = Theme.surface
        slider.addTarget(self, action: #selector(sliderDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderUp),
                         for: [.touchUpInside, .touchUpOutside, .touchCancel])
        view.addSubview(slider)

        for label in [elapsedLabel, remainingLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = Theme.monoDigits(11)
            label.textColor = Theme.secondaryText
            view.addSubview(label)
        }

        configureTransportButton(shuffleButton, icon: .shuffle, size: 20, action: #selector(goShuffle))
        configureTransportButton(previousButton, icon: .previous, size: 28, action: #selector(goPrevious))
        configureTransportButton(playButton, icon: .play, size: 34, action: #selector(togglePlay))
        configureTransportButton(nextButton, icon: .next, size: 28, action: #selector(goNext))
        configureTransportButton(repeatButton, icon: .repeatAll, size: 20, action: #selector(goRepeat))

        configureTransportButton(likeButton, icon: .heart, size: 20, action: #selector(toggleLike))
        configureTransportButton(queueButton, icon: .list, size: 20, action: #selector(showQueue))

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            toggleButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            toggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            artworkView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            artworkView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 260),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),

            lyricsTable.topAnchor.constraint(equalTo: artworkView.topAnchor),
            lyricsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lyricsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lyricsTable.heightAnchor.constraint(equalTo: artworkView.heightAnchor),

            titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            badgeLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 6),
            badgeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            badgeLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            statusLabel.topAnchor.constraint(equalTo: badgeLabel.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            diagnosticsLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            diagnosticsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            diagnosticsLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            slider.topAnchor.constraint(equalTo: diagnosticsLabel.bottomAnchor, constant: 6),
            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            elapsedLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
            elapsedLabel.leadingAnchor.constraint(equalTo: slider.leadingAnchor),

            remainingLabel.topAnchor.constraint(equalTo: elapsedLabel.topAnchor),
            remainingLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor),

            playButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 12),
            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.heightAnchor.constraint(equalToConstant: 48),
            playButton.widthAnchor.constraint(equalToConstant: 64),

            previousButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            previousButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -12),
            previousButton.widthAnchor.constraint(equalToConstant: 48),
            previousButton.heightAnchor.constraint(equalToConstant: 48),

            nextButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 12),
            nextButton.widthAnchor.constraint(equalToConstant: 48),
            nextButton.heightAnchor.constraint(equalToConstant: 48),

            shuffleButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            shuffleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            shuffleButton.widthAnchor.constraint(equalToConstant: 44),
            shuffleButton.heightAnchor.constraint(equalToConstant: 44),

            repeatButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            repeatButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            repeatButton.widthAnchor.constraint(equalToConstant: 44),
            repeatButton.heightAnchor.constraint(equalToConstant: 44),

            likeButton.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 24),
            likeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            likeButton.widthAnchor.constraint(equalToConstant: 44),
            likeButton.heightAnchor.constraint(equalToConstant: 44),

            queueButton.topAnchor.constraint(equalTo: likeButton.topAnchor),
            queueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            queueButton.widthAnchor.constraint(equalToConstant: 44),
            queueButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureTransportButton(_ button: UIButton, icon: Icons.Kind, size: CGFloat, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(Icons.image(icon, size: size), for: .normal)

        button.tintColor = Theme.primaryText
        button.addTarget(self, action: action, for: .touchUpInside)
        view.addSubview(button)
    }

    private func applyMode(lyrics: Bool) {
        showingLyrics = lyrics
        artworkView.isHidden = lyrics
        lyricsTable.isHidden = !lyrics
        toggleButton.setTitle(lyrics ? "Artwork" : "Lyrics", for: .normal)
        if !lyrics {
            lyricsTable.setContentOffset(.zero, animated: false)
        }
    }

    // MARK: - State

    @objc private func playerChanged() {
        refresh()
    }

    @objc private func tick() {
        updateTime()
    }

    private func refresh() {
        let service = PlayerService.shared
        guard let track = service.currentTrack else {
            dismiss(animated: true, completion: nil)
            return
        }
        if currentTrackID != track.videoID {
            currentTrackID = track.videoID
            loadArtwork(track)
        }
        titleLabel.text = track.title
        artistLabel.text = track.artist.isEmpty ? "Unknown artist" : track.artist
        badgeLabel.text = track.displayAudioQualityBadge.uppercased()
        statusLabel.text = service.statusText.isEmpty ? nil : service.statusText
        playButton.setImage(Icons.image(service.isPlaying ? .pause : .play, size: 34), for: .normal)
        nextButton.isEnabled = service.currentIndex + 1 < service.queue.count
        likeButton.setImage(Icons.image(LibraryStore.shared.isLiked(track) ? .heartFilled : .heart, size: 20), for: .normal)
        likeButton.tintColor = LibraryStore.shared.isLiked(track) ? Theme.accent : Theme.primaryText
        shuffleButton.alpha = service.isShuffled ? 1 : 0.4
        switch service.repeatMode {
        case .off: repeatButton.setImage(Icons.image(.repeatAll, size: 20), for: .normal); repeatButton.alpha = 0.4
        case .all: repeatButton.setImage(Icons.image(.repeatAll, size: 20), for: .normal); repeatButton.alpha = 1
        case .one: repeatButton.setImage(Icons.image(.repeatOne, size: 20), for: .normal); repeatButton.alpha = 1
        }

        let token = "\(track.videoID)-\(service.lyrics.count)"
        if token != lyricsToken {
            lyricsToken = token
            currentLyrics = service.lyrics
            lyricsSynced = service.lyricsAreSynced
            lyricHighlight = -1
            lyricsTable.reloadData()
            if !currentLyrics.isEmpty {
                lyricsTable.setContentOffset(.zero, animated: false)
            }
        }
        updateTime()
    }

    private func loadArtwork(_ track: Track) {
        artworkTask?.cancel()
        let url = track.largeArtworkURL
        if let cached = ArtworkLoader.shared.cached(url) {
            artworkView.image = cached
            return
        }
        artworkView.image = nil
        artworkTask = ArtworkLoader.shared.load(url) { [weak self] image in
            guard let self = self, self.currentTrackID == track.videoID else { return }
            self.artworkView.image = image
        }
    }

    private func updateTime() {
        let service = PlayerService.shared
        let total = service.duration
        let position = service.currentTime
        if !slider.isTracking {
            slider.value = total > 0 ? Float(min(1, max(0, position / total))) : 0
        }
        diagnosticsLabel.text = YouTubeBridge.shared.diagnosticsSummary
        elapsedLabel.text = Theme.format(position)
        remainingLabel.text = total > 0 ? "-" + Theme.format(max(0, total - position)) : ""
        updateHighlight(at: position)
    }

    private func updateHighlight(at position: TimeInterval) {
        guard lyricsSynced, !currentLyrics.isEmpty else { return }
        var index = 0
        for (offset, line) in currentLyrics.enumerated() {
            if line.time <= position {
                index = offset
            } else {
                break
            }
        }
        guard index != lyricHighlight else { return }
        lyricHighlight = index
        lyricsTable.reloadData()
        if !userScrolling, index < currentLyrics.count {
            lyricsTable.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
        }
    }

    // MARK: - Actions

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func toggleMode() {
        applyMode(lyrics: !showingLyrics)
    }

    @objc private func togglePlay() {
        PlayerService.shared.togglePlayPause()
    }

    @objc private func goPrevious() {
        PlayerService.shared.previous()
    }

    @objc private func goNext() {
        PlayerService.shared.advance()
    }

    @objc private func goShuffle() {
        PlayerService.shared.toggleShuffle()
    }

    @objc private func goRepeat() {
        PlayerService.shared.cycleRepeatMode()
    }

    @objc private func toggleLike() {
        guard let track = PlayerService.shared.currentTrack else { return }
        LibraryStore.shared.toggleLike(track)
        refresh()
    }

    @objc private func showQueue() {
        let queue = QueueViewController()
        queue.modalPresentationStyle = .pageSheet
        present(queue, animated: true, completion: nil)
    }

    @objc private func sliderDown() {
        PlayerService.shared.isScrubbing = true
    }

    @objc private func sliderUp() {
        PlayerService.shared.isScrubbing = false
        PlayerService.shared.seek(toFraction: Double(slider.value))
    }
}

extension NowPlayingViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return currentLyrics.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LyricCell.reuseIdentifier, for: indexPath)
        if let lyricCell = cell as? LyricCell {
            let active = lyricsSynced && indexPath.row == lyricHighlight
            lyricCell.configure(text: currentLyrics[indexPath.row].text, active: active)
        }
        return cell
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userScrolling = true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            userScrolling = false
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userScrolling = false
    }
}

final class LyricCell: UITableViewCell {
    static let reuseIdentifier = "LyricCell"

    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        contentView.backgroundColor = Theme.background
        selectionStyle = .none

        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5)
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configure(text: String, active: Bool) {
        label.text = text
        label.font = Theme.font(active ? 16 : 15, weight: active ? .semibold : .regular)
        label.textColor = active ? Theme.primaryText : Theme.secondaryText
    }
}

/// Upstream's queue sheet: now playing, then upcoming tracks, tap to jump.
final class QueueViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        headerLabel.text = "Queue"
        headerLabel.font = Theme.font(17, weight: .semibold)
        headerLabel.textColor = Theme.primaryText
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.tableFooterView = UIView()
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            tableView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

extension QueueViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return PlayerService.shared.queue.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath)
        let queue = PlayerService.shared.queue
        if let trackCell = cell as? TrackCell, indexPath.row < queue.count {
            trackCell.configure(with: queue[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        PlayerService.shared.playTrack(at: indexPath.row)
        dismiss(animated: true, completion: nil)
    }
}
