import UIKit

/// Port of upstream `NowPlayingView`: artwork or lyrics in the centre, quality badge, scrubber,
/// full transport with shuffle and repeat, like, and a queue sheet.
final class NowPlayingViewController: UIViewController {
    private let closeButton = UIButton(type: .system)
    private let artworkView = UIImageView()
    private let backdropView = UIImageView()
    private let meshView = MeshGradientView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let scrimView = UIView()
    private let scrimLayer = CAGradientLayer()
    private let glowView = UIView()
    private let glowLayer = CAGradientLayer()
    private let lyricsTable = UITableView(frame: .zero, style: .plain)
    private let lyricsSourceLabel = UILabel()
    private let compactHeader = UIView()
    private let headerArtwork = UIImageView()
    private let headerTitle = UILabel()
    private let headerArtist = UILabel()
    private let handle = UIView()
    private let volumeSlider = UISlider()
    private let volumeLow = UIImageView()
    private let volumeHigh = UIImageView()
    private let outputButton = UIButton(type: .system)
    private let outputLabel = UILabel()
    private let modeButton = UIButton(type: .system)
    private let globeButton = UIButton(type: .system)
    private let translitButton = UIButton(type: .system)
    private var lyricsTopDefault: NSLayoutConstraint?
    private var lyricsTopCompact: NSLayoutConstraint?
    private var titleUnderArtwork: NSLayoutConstraint?
    private var titleUnderClose: NSLayoutConstraint?
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
    private var currentLyrics: [WordLyricLine] = []
    private var lyricHeights: [Int: CGFloat] = [:]
    private var lyricsSynced = false
    private var lyricHighlight = -1
    private var userScrolling = false
    private var showingLyrics = false
    private var artworkTask: URLSessionDataTask?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildLayout()
        let drag = UISwipeGestureRecognizer(target: self, action: #selector(close))
        drag.direction = .down
        view.addGestureRecognizer(drag)
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrimLayer.frame = scrimView.bounds
        glowLayer.frame = glowView.bounds
        glowLayer.cornerRadius = 30
    }

    // MARK: - Layout

    private func buildLayout() {
        let squat = UIScreen.main.bounds.height < 700
        let headerGap: CGFloat = squat ? 8 : 12
        let headerHeight: CGFloat = squat ? 52 : 56
        let lyricGap: CGFloat = squat ? 12 : 16
        let stackGap: CGFloat = squat ? 8 : 12
        let playSide: CGFloat = squat ? 56 : 64
        let footGap: CGFloat = squat ? 10 : 14
        let bottomGap: CGFloat = squat ? 16 : 26
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.contentMode = .scaleAspectFill
        backdropView.clipsToBounds = true
        backdropView.alpha = 0
        view.addSubview(backdropView)

        // The mesh sits under everything: four blobs sampled from the cover,
        // blurred once into the Apple Music backdrop upstream draws.
        meshView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(meshView)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurView)

        scrimView.translatesAutoresizingMaskIntoConstraints = false
        scrimView.isUserInteractionEnabled = false
        scrimView.layer.addSublayer(scrimLayer)
        scrimLayer.colors = [UIColor.black.withAlphaComponent(0.10).cgColor,
                             UIColor.black.withAlphaComponent(0.38).cgColor,
                             UIColor.black.withAlphaComponent(0.72).cgColor]
        scrimLayer.locations = [0, 0.45, 1]
        scrimView.isHidden = true
        view.addSubview(scrimView)

        glowView.translatesAutoresizingMaskIntoConstraints = false
        glowView.layer.addSublayer(glowLayer)
        glowLayer.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor]
        glowView.layer.shadowOpacity = 0.6
        glowView.layer.shadowRadius = 28
        glowView.layer.shadowOffset = CGSize(width: 0, height: 16)
        view.addSubview(glowView)

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
        artworkView.layer.cornerRadius = 12
        artworkView.backgroundColor = Theme.surface
        artworkView.isUserInteractionEnabled = true
        artworkView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleMode)))
        view.addSubview(artworkView)

        lyricsTable.translatesAutoresizingMaskIntoConstraints = false
        lyricsTable.dataSource = self
        lyricsTable.delegate = self
        lyricsTable.backgroundColor = UIColor.clear
        lyricsTable.separatorStyle = .none
        lyricsTable.rowHeight = UITableView.automaticDimension
        lyricsTable.estimatedRowHeight = 34
        lyricsTable.register(KaraokeLyricCell.self,
                             forCellReuseIdentifier: KaraokeLyricCell.reuseIdentifier)
        lyricsTable.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.addSubview(lyricsTable)

        // The real lyrics panel leads with a small cover, the track and its
        // artist, where the artwork would be.
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.backgroundColor = UIColor(white: 1, alpha: 0.3)
        handle.layer.cornerRadius = 2.5
        handle.isHidden = true
        view.addSubview(handle)

        compactHeader.translatesAutoresizingMaskIntoConstraints = false
        compactHeader.isHidden = true
        view.addSubview(compactHeader)

        headerArtwork.translatesAutoresizingMaskIntoConstraints = false
        headerArtwork.contentMode = .scaleAspectFill
        headerArtwork.clipsToBounds = true
        headerArtwork.layer.cornerRadius = 10
        headerArtwork.backgroundColor = Theme.surfaceVariant
        compactHeader.addSubview(headerArtwork)

        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.font = Theme.font(18, weight: .semibold)
        headerTitle.textColor = Theme.primaryText
        headerTitle.lineBreakMode = .byTruncatingTail
        compactHeader.addSubview(headerTitle)

        headerArtist.translatesAutoresizingMaskIntoConstraints = false
        headerArtist.font = Theme.font(15)
        headerArtist.textColor = Theme.secondaryText
        headerArtist.lineBreakMode = .byTruncatingTail
        compactHeader.addSubview(headerArtist)

        NSLayoutConstraint.activate([
            headerArtwork.leadingAnchor.constraint(equalTo: compactHeader.leadingAnchor),
            headerArtwork.centerYAnchor.constraint(equalTo: compactHeader.centerYAnchor),
            headerArtwork.widthAnchor.constraint(equalToConstant: 48),
            headerArtwork.heightAnchor.constraint(equalToConstant: 48),
            headerTitle.leadingAnchor.constraint(equalTo: headerArtwork.trailingAnchor, constant: 10),
            headerTitle.trailingAnchor.constraint(equalTo: compactHeader.trailingAnchor),
            headerTitle.bottomAnchor.constraint(equalTo: compactHeader.centerYAnchor, constant: -1),
            headerArtist.leadingAnchor.constraint(equalTo: headerTitle.leadingAnchor),
            headerArtist.trailingAnchor.constraint(equalTo: headerTitle.trailingAnchor),
            headerArtist.topAnchor.constraint(equalTo: compactHeader.centerYAnchor, constant: 1)
        ])

        for button in [globeButton, translitButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.backgroundColor = UIColor(white: 1, alpha: 0.08)
            button.layer.cornerRadius = 20
            button.tintColor = UIColor(white: 1, alpha: 0.85)
            button.isHidden = true
            view.addSubview(button)
        }
        globeButton.setImage(Icons.image(.globe, size: 18), for: .normal)
        translitButton.titleLabel?.font = Theme.font(15, weight: .semibold)
        translitButton.setTitle("文A", for: .normal)
        translitButton.setTitleColor(UIColor(white: 1, alpha: 0.85), for: .normal)

        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.setMinimumTrackImage(Theme.trackImage(Theme.primaryText), for: .normal)
        volumeSlider.setMaximumTrackImage(Theme.trackImage(Theme.outline), for: .normal)
        volumeSlider.setThumbImage(Theme.thumbImage(), for: .normal)
        volumeSlider.value = 1
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        for speaker in [volumeLow, volumeHigh] {
            speaker.translatesAutoresizingMaskIntoConstraints = false
            speaker.image = Icons.image(.speaker, size: 14)
            speaker.tintColor = UIColor(white: 1, alpha: 0.5)
            speaker.isHidden = true
            view.addSubview(speaker)
        }
        view.addSubview(volumeSlider)

        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.tintColor = Theme.primaryText
        modeButton.setImage(Icons.image(.bubble, size: 22), for: .normal)
        modeButton.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)
        modeButton.isHidden = true
        view.addSubview(modeButton)

        outputButton.translatesAutoresizingMaskIntoConstraints = false
        outputButton.tintColor = Theme.primaryText
        outputButton.setImage(Icons.image(.cast, size: 22), for: .normal)
        outputButton.addTarget(self, action: #selector(showOutput), for: .touchUpInside)
        view.addSubview(outputButton)

        outputLabel.translatesAutoresizingMaskIntoConstraints = false
        outputLabel.text = "This phone"
        outputLabel.font = Theme.font(11)
        outputLabel.textColor = Theme.secondaryText
        outputLabel.textAlignment = .center
        view.addSubview(outputLabel)

        // The real panel credits the provider under the words.
        lyricsSourceLabel.translatesAutoresizingMaskIntoConstraints = false
        lyricsSourceLabel.font = Theme.font(13)
        lyricsSourceLabel.textColor = Theme.secondaryText
        lyricsSourceLabel.textAlignment = .left
        lyricsSourceLabel.isHidden = true
        view.addSubview(lyricsSourceLabel)

        NSLayoutConstraint.activate([
            meshView.topAnchor.constraint(equalTo: view.topAnchor),
            meshView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            meshView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            meshView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(.headlineMedium)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .left
        view.addSubview(titleLabel)

        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        artistLabel.font = Theme.font(.bodyLarge)
        artistLabel.textColor = Theme.secondaryText
        artistLabel.textAlignment = .left
        view.addSubview(artistLabel)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = Theme.font(10, weight: .semibold)
        badgeLabel.textColor = Theme.accent
        badgeLabel.textAlignment = .left
        view.addSubview(badgeLabel)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = Theme.font(12)
        statusLabel.textColor = Theme.accent
        statusLabel.textAlignment = .left
        statusLabel.numberOfLines = 2
        view.addSubview(statusLabel)

        diagnosticsLabel.translatesAutoresizingMaskIntoConstraints = false
        diagnosticsLabel.font = Theme.monoDigits(9)
        diagnosticsLabel.textColor = Theme.secondaryText
        diagnosticsLabel.textAlignment = .left
        diagnosticsLabel.numberOfLines = 2
        view.addSubview(diagnosticsLabel)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.setMinimumTrackImage(Theme.trackImage(Theme.accent), for: .normal)
        slider.setMaximumTrackImage(Theme.trackImage(Theme.outline), for: .normal)
        slider.setThumbImage(Theme.thumbImage(), for: .normal)
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
        configureTransportButton(previousButton, icon: .previous, size: 40, action: #selector(goPrevious))
        configureTransportButton(playButton, icon: .play, size: 26, action: #selector(togglePlay))
        playButton.backgroundColor = .white
        playButton.layer.cornerRadius = 32
        playButton.tintColor = .black
        playButton.layer.shadowColor = UIColor.black.cgColor
        playButton.layer.shadowOpacity = 0.35
        playButton.layer.shadowRadius = 12
        playButton.layer.shadowOffset = CGSize(width: 0, height: 6)
        configureTransportButton(nextButton, icon: .next, size: 40, action: #selector(goNext))
        configureTransportButton(repeatButton, icon: .repeatAll, size: 20, action: #selector(goRepeat))

        configureTransportButton(likeButton, icon: .heart, size: 22, action: #selector(toggleLike))
        configureTransportButton(queueButton, icon: .list, size: 22, action: #selector(showQueue))

        let safe = view.safeAreaLayoutGuide
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0)
        glowLayer.endPoint = CGPoint(x: 0.5, y: 1)
        titleUnderArtwork = titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor,
                                                            constant: 16)
        lyricsTopDefault = lyricsTable.topAnchor.constraint(equalTo: artworkView.topAnchor)
        lyricsTopCompact = lyricsTable.topAnchor.constraint(equalTo: compactHeader.bottomAnchor,
                                                            constant: lyricGap)
        titleUnderClose = titleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor,
                                                          constant: 10)
        NSLayoutConstraint.activate([
            scrimView.topAnchor.constraint(equalTo: view.topAnchor),
            scrimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            glowView.centerXAnchor.constraint(equalTo: artworkView.centerXAnchor),
            glowView.centerYAnchor.constraint(equalTo: artworkView.centerYAnchor),
            glowView.widthAnchor.constraint(equalTo: artworkView.widthAnchor, constant: 72),
            glowView.heightAnchor.constraint(equalTo: artworkView.heightAnchor, constant: 72),

            closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            toggleButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            toggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toggleButton.widthAnchor.constraint(equalToConstant: 36),
            toggleButton.heightAnchor.constraint(equalToConstant: 36),

            artworkView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            artworkView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            artworkView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.80),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),

            lyricsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lyricsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lyricsTable.bottomAnchor.constraint(equalTo: lyricsSourceLabel.topAnchor, constant: -6),

            handle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 5),

            compactHeader.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: headerGap),
            compactHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            compactHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            compactHeader.heightAnchor.constraint(equalToConstant: headerHeight),

            lyricsSourceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            lyricsSourceLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            lyricsSourceLabel.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -10),

            titleUnderArtwork ?? titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 16),
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

            volumeSlider.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -footGap),
            volumeSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 44),
            volumeSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -44),
            volumeSlider.heightAnchor.constraint(equalToConstant: 18),

            playButton.bottomAnchor.constraint(equalTo: volumeSlider.topAnchor, constant: squat ? -14 : -22),

            modeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            modeButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 44),
            modeButton.heightAnchor.constraint(equalToConstant: 44),

            outputButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            outputButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            outputButton.widthAnchor.constraint(equalToConstant: 44),
            outputButton.heightAnchor.constraint(equalToConstant: 44),

            outputLabel.topAnchor.constraint(equalTo: outputButton.bottomAnchor, constant: -6),
            outputLabel.centerXAnchor.constraint(equalTo: outputButton.centerXAnchor),

            volumeLow.centerYAnchor.constraint(equalTo: volumeSlider.centerYAnchor),
            volumeLow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            volumeLow.widthAnchor.constraint(equalToConstant: 14),
            volumeLow.heightAnchor.constraint(equalToConstant: 14),

            volumeHigh.centerYAnchor.constraint(equalTo: volumeSlider.centerYAnchor),
            volumeHigh.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            volumeHigh.widthAnchor.constraint(equalToConstant: 14),
            volumeHigh.heightAnchor.constraint(equalToConstant: 14),

            globeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            globeButton.bottomAnchor.constraint(equalTo: lyricsSourceLabel.topAnchor, constant: -10),
            globeButton.widthAnchor.constraint(equalToConstant: 36),
            globeButton.heightAnchor.constraint(equalToConstant: 36),

            translitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            translitButton.centerYAnchor.constraint(equalTo: globeButton.centerYAnchor),
            translitButton.widthAnchor.constraint(equalToConstant: 36),
            translitButton.heightAnchor.constraint(equalToConstant: 36),
            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            elapsedLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
            elapsedLabel.leadingAnchor.constraint(equalTo: slider.leadingAnchor),

            remainingLabel.topAnchor.constraint(equalTo: elapsedLabel.topAnchor),
            remainingLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor),

            playButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: stackGap),
            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.heightAnchor.constraint(equalToConstant: playSide),
            playButton.widthAnchor.constraint(equalToConstant: playSide),

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

            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -bottomGap),
            likeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            likeButton.widthAnchor.constraint(equalToConstant: 44),
            likeButton.heightAnchor.constraint(equalToConstant: 44),

            queueButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
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
        // In lyrics mode the words take the screen: the big title and the
        // small print fold away and a compact header takes their place.
        compactHeader.isHidden = !lyrics
        titleLabel.isHidden = lyrics
        artistLabel.isHidden = lyrics
        badgeLabel.isHidden = lyrics
        statusLabel.isHidden = lyrics
        diagnosticsLabel.isHidden = lyrics
        // The real panel draws the transport straight on the background, with
        // no white disc behind the pause.
        playButton.backgroundColor = lyrics ? .clear : .white
        playButton.tintColor = lyrics ? .white : .black
        playButton.setImage(Icons.image(PlayerService.shared.isPlaying ? .pause : .play, size: 48), for: .normal)
        // In lyrics mode the cover itself is the backdrop: the dark blur
        // effect above it softens it exactly the way the real panel does.
        backdropView.alpha = lyrics ? 0.9 : 0
        // The mesh is opaque; in lyrics mode it has to blend with the cover
        // underneath instead of hiding it.
        meshView.alpha = lyrics ? 0.55 : 1
        scrimView.isHidden = !lyrics
        handle.isHidden = !lyrics
        closeButton.isHidden = lyrics
        globeButton.isHidden = !lyrics
        translitButton.isHidden = !lyrics
        volumeSlider.isHidden = !lyrics
        volumeLow.isHidden = !lyrics
        volumeHigh.isHidden = !lyrics
        outputButton.isHidden = !lyrics
        outputLabel.isHidden = !lyrics
        shuffleButton.isHidden = lyrics
        repeatButton.isHidden = lyrics
        likeButton.isHidden = lyrics
        modeButton.isHidden = !lyrics
        toggleButton.setTitle(nil, for: .normal)
        toggleButton.backgroundColor = lyrics ? UIColor(white: 1, alpha: 0.1) : .clear
        toggleButton.layer.cornerRadius = 22
        slider.setThumbImage(lyrics ? UIImage() : Theme.thumbImage(), for: .normal)
        toggleButton.setImage(Icons.image(.ellipsis, size: 18), for: .normal)
        lyricsTopCompact?.isActive = lyrics
        lyricsTopDefault?.isActive = !lyrics
        titleUnderArtwork?.isActive = true
        titleUnderClose?.isActive = false
        lyricsTable.isHidden = !lyrics
        lyricsSourceLabel.isHidden = !lyrics
        toggleButton.setTitle(nil, for: .normal)
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
        if track.isExplicit || AudioEngine.shared.currentIsExplicit {
            let body = NSMutableAttributedString(string: track.title + " ")
            let tile = NSTextAttachment()
            tile.image = Theme.explicitBadgeImage()
            tile.bounds = CGRect(x: 0, y: -2, width: 13, height: 13)
            body.append(NSAttributedString(attachment: tile))
            titleLabel.attributedText = body
        } else {
            titleLabel.attributedText = nil
            titleLabel.text = track.title
        }
        artistLabel.text = track.artist.isEmpty ? "Unknown artist" : track.artist
        headerTitle.text = track.title
        headerArtist.text = artistLabel.text
        // The source tag reads "JIOSAAVN 320KBPS" on every track. Useful when
        // something will not play, noise the rest of the time, so it is only
        // shown when the listener turns debug information on.
        if SettingsStore.shared.showDebugInfo {
            let source = AudioEngine.shared.currentSourceLabel
            let badge = (source.isEmpty ? track.displayAudioQualityBadge : source).uppercased()
            let styled = NSMutableAttributedString(string: badge)
            let full = NSRange(location: 0, length: styled.length)
            styled.addAttribute(.kern, value: 0.8, range: full)
            styled.addAttribute(.foregroundColor, value: Theme.secondaryText, range: full)
            badgeLabel.attributedText = styled
        } else {
            badgeLabel.attributedText = nil
            badgeLabel.text = nil
        }
        statusLabel.text = service.statusText.isEmpty ? nil : service.statusText
        playButton.setImage(Icons.image(service.isPlaying ? .pause : .play, size: 26), for: .normal)
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
            lyricHeights.removeAll()
            if service.lyricsSource.isEmpty {
                lyricsSourceLabel.attributedText = nil
            } else {
                lyricsSourceLabel.attributedText = NSAttributedString(
                    string: "Lyrics by " + service.lyricsSource,
                    attributes: [.font: Theme.font(13),
                                 .foregroundColor: Theme.secondaryText,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue])
            }
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
            applyArtwork(cached)
            return
        }
        artworkView.image = nil
        artworkTask = ArtworkLoader.shared.load(url) { [weak self] image in
            guard let self = self, self.currentTrackID == track.videoID else { return }
            self.applyArtwork(image)
        }
    }

    /// Sets the cover and repaints everything derived from it: the blurred
    /// backdrop and the edge-color glow the cover fades into.
    private func applyArtwork(_ image: UIImage?) {
        artworkView.image = image
        headerArtwork.image = image
        meshView.palette = Theme.meshPalette(of: image)
        UIView.transition(with: backdropView, duration: 0.4, options: .transitionCrossDissolve, animations: {
            self.backdropView.image = image
        }, completion: nil)
        if let image = image, let edge = Theme.edgeColor(of: image) {
            glowLayer.colors = [edge.withAlphaComponent(0.5).cgColor, UIColor.clear.cgColor]
            glowView.layer.shadowColor = edge.cgColor
        } else {
            glowLayer.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor]
            glowView.layer.shadowColor = UIColor.black.cgColor
        }
    }

    private func updateTime() {
        let service = PlayerService.shared
        let total = service.duration
        let position = service.currentTime
        if !slider.isTracking {
            slider.value = total > 0 ? Float(min(1, max(0, position / total))) : 0
        }
        diagnosticsLabel.text = SettingsStore.shared.showDebugInfo
            ? AudioEngine.shared.diagnosticsSummary
            : nil
        elapsedLabel.text = Theme.format(position)
        remainingLabel.text = total > 0 ? "-" + Theme.format(max(0, total - position)) : ""
        updateHighlight(at: position)
    }

    private func updateHighlight(at position: TimeInterval) {
        guard lyricsSynced, !currentLyrics.isEmpty else { return }
        var index = -1
        for (offset, line) in currentLyrics.enumerated() {
            if line.time <= position {
                index = offset
            } else {
                break
            }
        }
        if index != lyricHighlight {
            lyricHighlight = index
            // The active line is set larger, so its measured height is stale.
            lyricHeights.removeAll()
            lyricsTable.reloadData()
            if index >= 0, !userScrolling {
                lyricsTable.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
            }
            return
        }

        // The karaoke view works out what is sung from the provider's own word
        // and syllable timings; this only hands it the clock.
        for cell in lyricsTable.visibleCells {
            guard let lyricCell = cell as? KaraokeLyricCell,
                  let path = lyricsTable.indexPath(for: cell) else { continue }
            lyricCell.setPosition(path.row == lyricHighlight ? position : -1)
        }
    }

    // MARK: - Actions

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    /// Opens the lyrics panel for the screenshot harness.
    func showLyricsForScreenshots() {
        loadViewIfNeeded()
        applyMode(lyrics: true)
        updateHighlight(at: PlayerService.shared.currentTime)
    }

    @objc private func volumeChanged() {
        AudioEngine.shared.setVolume(volumeSlider.value)
    }

    @objc private func showOutput() {
        let alert = UIAlertController(title: "Audio output",
                                      message: "Playing on this phone.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
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

extension NowPlayingViewController {
    /// The active line is large and bold, everything else steps down a size and
    /// a weight — the proportions the real lyrics panel uses.
    static func lyricFont(active: Bool) -> UIFont {
        let height = UIScreen.main.bounds.height
        if height < 600 {
            return active ? Theme.font(27, weight: .bold) : Theme.font(20, weight: .semibold)
        }
        if height < 750 {
            return active ? Theme.font(29, weight: .bold) : Theme.font(21, weight: .semibold)
        }
        return active ? Theme.font(31, weight: .bold) : Theme.font(22, weight: .semibold)
    }
}

extension NowPlayingViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return currentLyrics.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: KaraokeLyricCell.reuseIdentifier,
                                                 for: indexPath)
        if let lyricCell = cell as? KaraokeLyricCell, indexPath.row < currentLyrics.count {
            let row = indexPath.row
            let cellPosition = row == lyricHighlight ? PlayerService.shared.currentTime : -1
            lyricCell.configure(line: currentLyrics[row],
                                font: NowPlayingViewController.lyricFont(active: row == lyricHighlight),
                                position: cellPosition)
            // Every row waits in grey; the karaoke overlay turns the words
            // white as they are sung. Painting the active row white up front
            // would hide the sweep entirely.
            lyricCell.dimmed = Theme.secondaryText
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if let cached = lyricHeights[indexPath.row] { return cached }
        guard indexPath.row < currentLyrics.count else { return 34 }
        let width = max(1, tableView.bounds.width - 64)
        let height = KaraokeLineView.height(
            text: currentLyrics[indexPath.row].text,
            font: NowPlayingViewController.lyricFont(active: indexPath.row == lyricHighlight),
            width: width)
        lyricHeights[indexPath.row] = height
        return height
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
