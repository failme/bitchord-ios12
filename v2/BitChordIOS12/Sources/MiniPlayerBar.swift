import UIKit

final class MiniPlayerBar: UIView {
    var onTap: (() -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let artworkView = UIImageView()
    private let progressView = UIView()
    private var progressWidth: NSLayoutConstraint!
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private var artworkTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        clipsToBounds = true

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.backgroundColor = Theme.accent
        addSubview(progressView)

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 4
        artworkView.backgroundColor = Theme.surface
        addSubview(artworkView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(14, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.text = "Nothing playing"
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = Theme.font(12)
        subtitleLabel.textColor = Theme.secondaryText
        addSubview(subtitleLabel)

        playButton.translatesAutoresizingMaskIntoConstraints = false

        playButton.tintColor = Theme.primaryText
        playButton.setImage(Icons.image(.play, size: 24), for: .normal)
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        addSubview(playButton)

        progressWidth = progressView.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: topAnchor),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 1.5),
            progressWidth,

            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            artworkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 40),
            artworkView.heightAnchor.constraint(equalToConstant: 40),

            playButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleTap))
        swipe.direction = .up
        addGestureRecognizer(swipe)

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(updateProgress),
                                              name: .playerTimeDidChange,
                                              object: nil)

        refresh()
    }

    @objc private func handleTap() {
        onTap?()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func updateProgress() {
        let service = PlayerService.shared
        let total = service.duration
        let fraction = total > 0 ? max(0, min(1, service.currentTime / total)) : 0
        progressWidth.constant = bounds.width * CGFloat(fraction)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateProgress()
    }

    @objc private func togglePlayback() {
        PlayerService.shared.togglePlayPause()
    }

    func refresh() {
        let service = PlayerService.shared
        guard let track = service.currentTrack else {
            titleLabel.text = "Nothing playing"
            subtitleLabel.text = "Search to start"
            playButton.setImage(Icons.image(.play, size: 24), for: .normal)
            artworkTask?.cancel()
            artworkView.image = nil
            return
        }
        titleLabel.text = track.title
        subtitleLabel.text = track.artist.isEmpty ? (service.statusText.isEmpty ? " " : service.statusText) : track.artist
        playButton.setImage(Icons.image(service.isPlaying ? .pause : .play, size: 24), for: .normal)

        let url = track.artworkURL
        if let cached = ArtworkLoader.shared.cached(url) {
            artworkView.image = cached
            return
        }
        artworkView.image = nil
        artworkTask?.cancel()
        artworkTask = ArtworkLoader.shared.load(url) { [weak self] image in
            guard let self = self else { return }
            self.artworkView.image = image
        }
    }
}
