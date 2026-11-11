import UIKit

final class NowPlayingViewController: UIViewController {
    private let closeButton = UIButton(type: .system)
    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let statusLabel = UILabel()
    private let slider = UISlider()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let lyricsTable = UITableView(frame: .zero, style: .plain)

    private var currentTrackID: String?
    private var lyricsToken = ""
    private var currentLyrics: [LyricLine] = []
    private var lyricsSynced = false
    private var lyricHighlight = -1
    private var userScrolling = false
    private var artworkTask: URLSessionDataTask?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildLayout()

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(playerChanged),
                                              name: .playerDidChange,
                                              object: nil)
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(tick),
                                              name: .playerTimeDidChange,
                                              object: nil)
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    private func buildLayout() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("Done", for: .normal)
        closeButton.titleLabel?.font = Theme.font(16, weight: .medium)
        closeButton.tintColor = Theme.accent
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(closeButton)

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.backgroundColor = Theme.surface
        view.addSubview(artworkView)

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

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = Theme.font(12)
        statusLabel.textColor = Theme.accent
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        view.addSubview(statusLabel)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumTrackTintColor = Theme.accent
        slider.maximumTrackTintColor = Theme.surface
        slider.addTarget(self, action: #selector(sliderDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        view.addSubview(slider)

        for label in [elapsedLabel, remainingLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = Theme.monoDigits(11)
            label.textColor = Theme.secondaryText
            view.addSubview(label)
        }

        previousButton.translatesAutoresizingMaskIntoConstraints = false
        previousButton.setTitle("⏮", for: .normal)
        previousButton.titleLabel?.font = Theme.font(28)
        previousButton.tintColor = Theme.primaryText
        previousButton.addTarget(self, action: #selector(goPrevious), for: .touchUpInside)
        view.addSubview(previousButton)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setTitle("▶", for: .normal)
        playButton.titleLabel?.font = Theme.font(34)
        playButton.tintColor = Theme.primaryText
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        view.addSubview(playButton)

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.setTitle("⏭", for: .normal)
        nextButton.titleLabel?.font = Theme.font(28)
        nextButton.tintColor = Theme.primaryText
        nextButton.addTarget(self, action: #selector(goNext), for: .touchUpInside)
        view.addSubview(nextButton)

        lyricsTable.translatesAutoresizingMaskIntoConstraints = false
        lyricsTable.dataSource = self
        lyricsTable.delegate = self
        lyricsTable.backgroundColor = Theme.background
        lyricsTable.separatorStyle = .none
        lyricsTable.rowHeight = UITableView.automaticDimension
        lyricsTable.estimatedRowHeight = 30
        lyricsTable.register(LyricCell.self, forCellReuseIdentifier: LyricCell.reuseIdentifier)
        view.addSubview(lyricsTable)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            artworkView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            artworkView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 190),
            artworkView.heightAnchor.constraint(equalToConstant: 190),

            titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            statusLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            slider.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            elapsedLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
            elapsedLabel.leadingAnchor.constraint(equalTo: slider.leadingAnchor),

            remainingLabel.topAnchor.constraint(equalTo: elapsedLabel.topAnchor),
            remainingLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor),

            playButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 4),
            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.heightAnchor.constraint(equalToConstant: 48),
            playButton.widthAnchor.constraint(equalToConstant: 72),

            previousButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            previousButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -16),
            previousButton.widthAnchor.constraint(equalToConstant: 48),
            previousButton.heightAnchor.constraint(equalToConstant: 48),

            nextButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 16),
            nextButton.widthAnchor.constraint(equalToConstant: 48),
            nextButton.heightAnchor.constraint(equalToConstant: 48),

            lyricsTable.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 10),
            lyricsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lyricsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lyricsTable.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
        artistLabel.text = track.artist
        statusLabel.text = service.statusText.isEmpty ? nil : service.statusText
        playButton.setTitle(service.isPlaying ? "❚❚" : "▶", for: .normal)
        nextButton.isEnabled = service.currentIndex + 1 < service.queue.count

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
        let duration = service.duration
        let position = service.currentTime
        if !slider.isTracking {
            slider.value = duration > 0 ? Float(min(1, max(0, position / duration))) : 0
        }
        elapsedLabel.text = Theme.format(position)
        remainingLabel.text = duration > 0 ? "-" + Theme.format(max(0, duration - position)) : ""
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

    @objc private func togglePlay() {
        PlayerService.shared.togglePlayPause()
    }

    @objc private func goPrevious() {
        PlayerService.shared.previous()
    }

    @objc private func goNext() {
        PlayerService.shared.advance()
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
