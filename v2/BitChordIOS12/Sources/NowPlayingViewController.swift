import AVFoundation
import QuartzCore
import UIKit

private struct LyricHeightKey: Hashable {
    let row: Int
    let width: Int
    let pointSizeTenths: Int
}

/// Breaks the display link's strong-target cycle. The link and the view
/// controller own the target, while the target only weakly owns both, so the
/// controller can deallocate even if a link was left running off-screen.
private final class LyricDisplayLinkTarget: NSObject {
    weak var owner: NowPlayingViewController?
    weak var link: CADisplayLink?

    @objc func tick() {
        guard let owner = owner else {
            link?.invalidate()
            return
        }
        owner.lyricClockTick()
    }
}

/// Port of upstream `NowPlayingView`: artwork or lyrics in the centre, quality badge, scrubber,
/// full transport with shuffle and repeat, like, and a queue sheet.
final class NowPlayingViewController: UIViewController {
    private let closeButton = UIButton(type: .system)
    private let artworkView = UIImageView()
    private let artworkFadeView = UIView()
    private let artworkFadeLayer = CAGradientLayer()
    private let backdropView = UIImageView()
    private let meshView = MeshGradientView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let scrimView = UIView()
    private let scrimLayer = CAGradientLayer()
    private let glowView = UIView()
    private let glowLayer = CAGradientLayer()
    private let lyricsTable = UITableView(frame: .zero, style: .plain)
    private let lyricsFade = CAGradientLayer()
    private let lyricsSourceLabel = UILabel()
    private let emptyLyricsLabel = UILabel()
    private let compactHeader = UIView()
    private let headerArtwork = UIImageView()
    private let headerTitle = UILabel()
    private let headerArtist = UILabel()
    private let handle = UIView()
    private let stationLabel = UILabel()
    private let peekLabel = UILabel()
    private let volumeSlider = ThinSliderView()
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
    private let slider = ThinSliderView()
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
    private var lyricHeights: [LyricHeightKey: CGFloat] = [:]
    private var lastLyricsTableWidth: CGFloat = 0
    private var lyricsSynced = false
    private var lyricHighlight = -1
    private var userScrolling = false
    private var showingLyrics = false
    private var artworkTask: URLSessionDataTask?
    private var didAnimateIn = false
    private var toggleUnderTitle: NSLayoutConstraint?
    private var toggleInHeader: NSLayoutConstraint?
    private var chromeTimer: Timer?
    private var chromePresentationTimer: Timer?
    private var chromeVisible = true
    private var lyricDisplayLink: CADisplayLink?
    private var lyricLinkTarget: LyricDisplayLinkTarget?
    private var lyricAnchorPosition: TimeInterval = 0
    private var lyricAnchorTimestamp: CFTimeInterval = 0

    /// The controls that belong to the player chrome. The lyric rows are not
    /// here: they stay interactive and visible when the chrome fades.
    private var chromeViews: [UIView] {
        return [closeButton, toggleButton, compactHeader, lyricsSourceLabel,
                slider, elapsedLabel, remainingLabel, previousButton, playButton,
                nextButton, queueButton, volumeSlider, volumeLow, volumeHigh,
                outputButton, outputLabel, modeButton, globeButton, translitButton,
                handle]
    }

    /// The lyrics table is either the full column or the one line that is
    /// being sung, as the Lyrics → Show full lyrics setting asks.
    private var showsFullLyrics: Bool {
        return SettingsStore.shared.bool("BitChord.Lyrics.ShowFullLyrics", true)
    }

    override var prefersStatusBarHidden: Bool {
        return SettingsStore.shared.bool("BitChord.Misc.HideStatusBarInPlayer", false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsStatusBarAppearanceUpdate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildLayout()
        installLyricsFade()
        let drag = UISwipeGestureRecognizer(target: self, action: #selector(close))
        drag.direction = .down
        view.addGestureRecognizer(drag)
        let chromeTap = UITapGestureRecognizer(target: self, action: #selector(chromeTapped))
        chromeTap.cancelsTouchesInView = false
        view.addGestureRecognizer(chromeTap)
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
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(settingsChanged),
                                              name: .settingsDidChange,
                                              object: nil)
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(appDidEnterBackground),
                                              name: UIApplication.didEnterBackgroundNotification,
                                              object: nil)
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(appWillEnterForeground),
                                              name: UIApplication.willEnterForegroundNotification,
                                              object: nil)
        refresh()
    }

    deinit {
        chromeTimer?.invalidate()
        chromePresentationTimer?.invalidate()
        lyricDisplayLink?.invalidate()
        lyricLinkTarget = nil
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        userScrolling = false
        stopLyricsClock()
        invalidateChromeTimer()
        invalidateChromePresentationTimer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        userScrolling = false
        stopLyricsClock()
        invalidateChromeTimer()
        invalidateChromePresentationTimer()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrimLayer.frame = scrimView.bounds
        glowLayer.frame = glowView.bounds
        glowLayer.cornerRadius = 30
        artworkFadeLayer.frame = artworkFadeView.bounds
        lyricsFade.frame = lyricsTable.bounds
        let width = lyricsTable.bounds.width
        if width > 1, abs(width - lastLyricsTableWidth) > 0.5 {
            // While the table is hidden behind the cover, leave the recorded
            // width alone; showing the lyrics then reloads once at the new
            // width and picks up the compact or regular type and gutters.
            if showingLyrics {
                lastLyricsTableWidth = width
                // Width changes are the one time row heights must be queried
                // again; active-line changes never touch the table.
                lyricsTable.reloadData()
            }
        }
    }

    /// The reference panel lets lyrics run under the header and the controls,
    /// fading at both ends rather than cutting them off on a hard table edge.
    private func installLyricsFade() {
        lyricsFade.colors = [UIColor.clear.cgColor,
                             UIColor.black.cgColor,
                             UIColor.black.cgColor,
                             UIColor.clear.cgColor]
        lyricsFade.locations = [0, 0.055, 0.74, 1]
        lyricsFade.startPoint = CGPoint(x: 0.5, y: 0)
        lyricsFade.endPoint = CGPoint(x: 0.5, y: 1)
        lyricsTable.layer.mask = lyricsFade
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if showingLyrics {
            // Returning from a full-screen menu or another screen should not
            // strand the lyrics page with invisible controls.
            applyChromeVisibility(true, animated: false)
        }
        if presentedViewController != nil {
            suspendChromeTimerForPresentation()
        } else {
            startLyricsClockIfNeeded()
            scheduleChromeHideIfNeeded()
        }
        guard !didAnimateIn else { return }
        didAnimateIn = true
        // The cover grows into place while the controls settle under it, the
        // way the real player opens from the mini bar.
        artworkView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        for view in [artworkView, compactHeader, titleLabel, artistLabel, slider,
                     previousButton, playButton, nextButton] {
            view.alpha = 0
        }
        UIView.animate(withDuration: 0.46, delay: 0.02,
                       usingSpringWithDamping: 0.86, initialSpringVelocity: 0.35,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.artworkView.transform = .identity
            for view in [self.artworkView, self.compactHeader, self.titleLabel, self.artistLabel,
                         self.slider, self.previousButton, self.playButton, self.nextButton] {
                view.alpha = 1
            }
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        // The player is presented edge to edge, so its own bounds are the
        // reliable screen size — `UIScreen.main` stays the simulator's size
        // even when the capture harness runs the app in a 320x568 window.
        // The capture harness also passes -BCSmallScreen, because a view made
        // before it joins the shrunken window can still report the simulator's
        // full screen size once, even though its final bounds are 320x568.
        let forcedSmall = ProcessInfo.processInfo.arguments.contains("-BCSmallScreen")
        let compact = forcedSmall || view.bounds.height < 650 || view.bounds.width < 350
        let squat = compact || view.bounds.height < 700
        let headerGap: CGFloat = squat ? 8 : 12
        let headerHeight: CGFloat = squat ? 52 : 56
        let lyricGap: CGFloat = squat ? 16 : 20
        let stackGap: CGFloat = squat ? 8 : 12
        let playSide: CGFloat = compact ? 64 : 74
        let transportSide: CGFloat = compact ? 48 : 53
        let transportGap: CGFloat = compact ? 52 : 58
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
        // Upstream never lays a dark live blur over the cover: the backdrop is
        // the artwork mesh plus one blurred still, so the cover's colours are
        // still there at the bottom of the screen. Keeping the dark effect here
        // was what turned every mesh into a nearly black rectangle.
        blurView.isHidden = true
        view.addSubview(blurView)

        scrimView.translatesAutoresizingMaskIntoConstraints = false
        scrimView.isUserInteractionEnabled = false
        scrimView.layer.addSublayer(scrimLayer)
        scrimLayer.colors = [UIColor.black.withAlphaComponent(0.0).cgColor,
                             UIColor.black.withAlphaComponent(0.14).cgColor,
                             UIColor.black.withAlphaComponent(0.55).cgColor]
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
        toggleButton.addTarget(self, action: #selector(showTrackActions), for: .touchUpInside)
        view.addSubview(toggleButton)

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 0
        artworkView.backgroundColor = Theme.surface
        artworkView.isUserInteractionEnabled = true
        artworkView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleMode)))
        view.addSubview(artworkView)

        // The banner doesn't stop on a hard seam: its last stretch dissolves
        // into the mesh the way Apple Music's full-bleed artwork does.
        artworkFadeView.translatesAutoresizingMaskIntoConstraints = false
        artworkFadeView.isUserInteractionEnabled = false
        artworkFadeLayer.colors = [UIColor.clear.cgColor,
                                   UIColor.black.withAlphaComponent(0.18).cgColor]
        artworkFadeLayer.locations = [0, 1]
        artworkFadeView.layer.addSublayer(artworkFadeLayer)
        view.addSubview(artworkFadeView)

        lyricsTable.translatesAutoresizingMaskIntoConstraints = false
        lyricsTable.dataSource = self
        lyricsTable.delegate = self
        lyricsTable.backgroundColor = UIColor.clear
        lyricsTable.separatorStyle = .none
        lyricsTable.rowHeight = UITableView.automaticDimension
        lyricsTable.estimatedRowHeight = 34
        lyricsTable.register(KaraokeLyricCell.self,
                             forCellReuseIdentifier: KaraokeLyricCell.reuseIdentifier)
                    lyricsTable.contentInset = UIEdgeInsets(top: 30, left: 0, bottom: 56, right: 0)
        view.addSubview(lyricsTable)

        // The real lyrics panel leads with a small cover, the track and its
        // artist, where the artwork would be.
        stationLabel.translatesAutoresizingMaskIntoConstraints = false
        stationLabel.font = Theme.font(13)
        // The station line sits on the cover itself in the real panel, so it
        // needs white type rather than the usual grey.
        stationLabel.textColor = UIColor(white: 1, alpha: 0.85)
        stationLabel.layer.shadowColor = UIColor.black.cgColor
        stationLabel.layer.shadowOpacity = 0.5
        stationLabel.layer.shadowRadius = 3
        stationLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        stationLabel.textAlignment = .center
        view.addSubview(stationLabel)

        peekLabel.translatesAutoresizingMaskIntoConstraints = false
        peekLabel.font = Theme.font(16, weight: .medium)
        peekLabel.textColor = UIColor(white: 1, alpha: 0.78)
        peekLabel.textAlignment = .left
        peekLabel.lineBreakMode = .byTruncatingTail
        peekLabel.isUserInteractionEnabled = true
        peekLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleMode)))
        view.addSubview(peekLabel)

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
        headerArtwork.layer.cornerRadius = 8
        headerArtwork.backgroundColor = Theme.surfaceVariant
        compactHeader.addSubview(headerArtwork)

        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.font = Theme.font(16, weight: .semibold)
        headerTitle.textColor = Theme.primaryText
        headerTitle.lineBreakMode = .byTruncatingTail
        compactHeader.addSubview(headerTitle)

        headerArtist.translatesAutoresizingMaskIntoConstraints = false
        headerArtist.font = Theme.font(16, weight: .medium)
        headerArtist.textColor = UIColor(white: 1, alpha: 0.55)
        headerArtist.lineBreakMode = .byTruncatingTail
        compactHeader.addSubview(headerArtist)

        NSLayoutConstraint.activate([
            headerArtwork.leadingAnchor.constraint(equalTo: compactHeader.leadingAnchor),
            headerArtwork.centerYAnchor.constraint(equalTo: compactHeader.centerYAnchor),
            headerArtwork.widthAnchor.constraint(equalToConstant: 54),
            headerArtwork.heightAnchor.constraint(equalToConstant: 54),
            headerTitle.leadingAnchor.constraint(equalTo: headerArtwork.trailingAnchor, constant: 12),
            headerTitle.trailingAnchor.constraint(equalTo: compactHeader.trailingAnchor, constant: -54),
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
        globeButton.setImage(Icons.image(.globe, size: 20), for: .normal)
        translitButton.titleLabel?.font = Theme.font(15, weight: .semibold)
        translitButton.setTitle("文A", for: .normal)
        translitButton.setTitleColor(UIColor(white: 1, alpha: 0.85), for: .normal)

        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.idleHeight = 6
        volumeSlider.activeHeight = 10
        volumeSlider.value = 1
        volumeSlider.onValueChange = { [weak self] value in
            self?.showChromeForInteraction()
            AudioEngine.shared.setVolume(value)
        }
        for speaker in [volumeLow, volumeHigh] {
            speaker.translatesAutoresizingMaskIntoConstraints = false
            speaker.image = Icons.image(.speaker, size: 20)
            speaker.tintColor = UIColor(white: 1, alpha: 0.5)
            speaker.isHidden = true
            view.addSubview(speaker)
        }
        view.addSubview(volumeSlider)

        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.tintColor = Theme.primaryText
        modeButton.backgroundColor = UIColor(white: 1, alpha: 0.10)
        modeButton.layer.cornerRadius = 8
        modeButton.setImage(Icons.image(.lyricsQuote, size: 24), for: .normal)
        modeButton.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)
        modeButton.isHidden = true
        view.addSubview(modeButton)

        outputButton.translatesAutoresizingMaskIntoConstraints = false
        outputButton.tintColor = Theme.primaryText
        outputButton.setImage(Icons.image(.cast, size: 26), for: .normal)
        outputButton.addTarget(self, action: #selector(showOutput), for: .touchUpInside)
        view.addSubview(outputButton)

        outputLabel.translatesAutoresizingMaskIntoConstraints = false
        outputLabel.text = "This phone"
        outputLabel.font = Theme.font(12, weight: .medium)
        outputLabel.textColor = UIColor(white: 1, alpha: 0.55)
        outputLabel.textAlignment = .center
        view.addSubview(outputLabel)

        // The real panel credits the provider under the words.
        lyricsSourceLabel.translatesAutoresizingMaskIntoConstraints = false
        lyricsSourceLabel.font = Theme.font(13)
        lyricsSourceLabel.textColor = UIColor(white: 1, alpha: 0.55)
        lyricsSourceLabel.textAlignment = .left
        lyricsSourceLabel.isHidden = true
        view.addSubview(lyricsSourceLabel)

        emptyLyricsLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLyricsLabel.text = "No lyrics for this track"
        emptyLyricsLabel.font = Theme.font(20)
        emptyLyricsLabel.textColor = Theme.secondaryText
        emptyLyricsLabel.textAlignment = .center
        emptyLyricsLabel.isHidden = true
        view.addSubview(emptyLyricsLabel)

        NSLayoutConstraint.activate([
            meshView.topAnchor.constraint(equalTo: view.topAnchor),
            meshView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            meshView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            meshView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(compact ? 18 : 20, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = compact ? 1 : 2
        titleLabel.textAlignment = .left
        view.addSubview(titleLabel)

        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        artistLabel.font = Theme.font(compact ? 16 : 20, weight: .medium)
        artistLabel.textColor = UIColor(white: 1, alpha: 0.55)
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
        slider.idleHeight = 7
        slider.activeHeight = 12
        slider.onTrackingBegan = { [weak self] in
            self?.sliderDown()
        }
        slider.onValueChangeFinished = { [weak self] value in
            self?.sliderUp(value: value)
        }
        view.addSubview(slider)

        for label in [elapsedLabel, remainingLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = Theme.font(12, weight: .medium)
            label.textColor = UIColor(white: 1, alpha: 0.55)
            view.addSubview(label)
        }

        configureTransportButton(shuffleButton, icon: .shuffle, size: 20, action: #selector(goShuffle))
        configureTransportButton(previousButton, icon: .previous, size: transportSide, action: #selector(goPrevious))
        configureTransportButton(playButton, icon: .play, size: playSide, action: #selector(togglePlay))
        // Apple Music's transport is white ink on the backdrop, not a filled
        // white disc; upstream `TransportRow` draws the glyph alone.
        playButton.backgroundColor = .clear
        playButton.layer.cornerRadius = 0
        playButton.tintColor = Theme.primaryText
        configureTransportButton(nextButton, icon: .next, size: transportSide, action: #selector(goNext))
        configureTransportButton(repeatButton, icon: .repeatAll, size: 20, action: #selector(goRepeat))

        configureTransportButton(likeButton, icon: .heart, size: 22, action: #selector(toggleLike))
        configureTransportButton(queueButton, icon: .queue, size: 26, action: #selector(showQueue))

        let safe = view.safeAreaLayoutGuide
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0)
        glowLayer.endPoint = CGPoint(x: 0.5, y: 1)
                    titleUnderArtwork = titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor,
                                                            constant: 20)
        lyricsTopDefault = lyricsTable.topAnchor.constraint(equalTo: stationLabel.bottomAnchor, constant: 8)
        lyricsTopCompact = lyricsTable.topAnchor.constraint(equalTo: compactHeader.bottomAnchor,
                                                            constant: lyricGap)
        titleUnderClose = titleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor,
                                                          constant: 10)
        toggleUnderTitle = toggleButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor,
                                                                 constant: 10)
        toggleInHeader = toggleButton.centerYAnchor.constraint(equalTo: compactHeader.centerYAnchor)
        toggleUnderTitle?.isActive = true
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

            stationLabel.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 10),
            stationLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stationLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),

            closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 36),


            // The real cover runs edge to edge under the status bar and the
            // station line, about half the screen tall, rather than sitting
            // in a square inset frame.
            artworkView.topAnchor.constraint(equalTo: view.topAnchor),
            artworkView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            artworkView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            artworkView.heightAnchor.constraint(equalTo: view.heightAnchor,
                                                multiplier: compact ? 0.47 : (squat ? 0.52 : 0.55)),

            artworkFadeView.leadingAnchor.constraint(equalTo: artworkView.leadingAnchor),
            artworkFadeView.trailingAnchor.constraint(equalTo: artworkView.trailingAnchor),
            artworkFadeView.bottomAnchor.constraint(equalTo: artworkView.bottomAnchor),
            artworkFadeView.heightAnchor.constraint(equalTo: artworkView.heightAnchor, multiplier: 0.18),

            emptyLyricsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLyricsLabel.centerYAnchor.constraint(equalTo: lyricsTable.centerYAnchor),
            emptyLyricsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),

            lyricsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lyricsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lyricsTable.bottomAnchor.constraint(equalTo: lyricsSourceLabel.topAnchor, constant: -6),

            handle.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 5),

            compactHeader.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: headerGap),
            compactHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            compactHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            compactHeader.heightAnchor.constraint(equalToConstant: 60),

            lyricsSourceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            lyricsSourceLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            lyricsSourceLabel.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -10),

            titleUnderArtwork ?? titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor,
                                                                  constant: compact ? 10 : 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            titleLabel.trailingAnchor.constraint(equalTo: toggleButton.leadingAnchor, constant: -10),

            toggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            toggleButton.widthAnchor.constraint(equalToConstant: 40),
            toggleButton.heightAnchor.constraint(equalToConstant: 40),

            peekLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 12),
            peekLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            peekLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),

            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 0),
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
            volumeSlider.leadingAnchor.constraint(equalTo: volumeLow.trailingAnchor, constant: 10),
            volumeSlider.trailingAnchor.constraint(equalTo: volumeHigh.leadingAnchor, constant: -10),
            volumeSlider.heightAnchor.constraint(equalToConstant: 32),

            modeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 56),
            modeButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 35),
            modeButton.heightAnchor.constraint(equalToConstant: 35),

            outputButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            outputButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            outputButton.widthAnchor.constraint(equalToConstant: 44),
            outputButton.heightAnchor.constraint(equalToConstant: 44),

            outputLabel.topAnchor.constraint(equalTo: outputButton.bottomAnchor, constant: 12),
            outputLabel.centerXAnchor.constraint(equalTo: outputButton.centerXAnchor),

            volumeLow.centerYAnchor.constraint(equalTo: volumeSlider.centerYAnchor),
            volumeLow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            volumeLow.widthAnchor.constraint(equalToConstant: 20),
            volumeLow.heightAnchor.constraint(equalToConstant: 20),

            volumeHigh.centerYAnchor.constraint(equalTo: volumeSlider.centerYAnchor),
            volumeHigh.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            volumeHigh.widthAnchor.constraint(equalToConstant: 20),
            volumeHigh.heightAnchor.constraint(equalToConstant: 20),

            globeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            globeButton.bottomAnchor.constraint(equalTo: lyricsSourceLabel.topAnchor, constant: -10),
            globeButton.widthAnchor.constraint(equalToConstant: 40),
            globeButton.heightAnchor.constraint(equalToConstant: 40),

            translitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            translitButton.centerYAnchor.constraint(equalTo: globeButton.centerYAnchor),
            translitButton.widthAnchor.constraint(equalToConstant: 40),
            translitButton.heightAnchor.constraint(equalToConstant: 40),
            slider.topAnchor.constraint(equalTo: peekLabel.bottomAnchor, constant: 0),
            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            slider.heightAnchor.constraint(equalToConstant: 34),

            elapsedLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: -4),
            elapsedLabel.leadingAnchor.constraint(equalTo: slider.leadingAnchor),

            remainingLabel.topAnchor.constraint(equalTo: elapsedLabel.topAnchor),
            remainingLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor),

            playButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor,
                                            constant: compact ? 6 : (squat ? 10 : 18)),
            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.heightAnchor.constraint(equalToConstant: playSide),
            playButton.widthAnchor.constraint(equalToConstant: playSide),

            previousButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            previousButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -transportGap),
            previousButton.widthAnchor.constraint(equalToConstant: transportSide),
            previousButton.heightAnchor.constraint(equalToConstant: transportSide),

            nextButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: transportGap),
            nextButton.widthAnchor.constraint(equalToConstant: transportSide),
            nextButton.heightAnchor.constraint(equalToConstant: transportSide),

            shuffleButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            shuffleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            shuffleButton.widthAnchor.constraint(equalToConstant: 44),
            shuffleButton.heightAnchor.constraint(equalToConstant: 44),

            repeatButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            repeatButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            repeatButton.widthAnchor.constraint(equalToConstant: 44),
            repeatButton.heightAnchor.constraint(equalToConstant: 44),

            // The output label hangs 34pt below this row. On a 568pt screen
            // pinning the row to the very bottom clipped it, so the compact
            // footer sits high enough for its own label.
            likeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor,
                                               constant: compact ? -34 : (squat ? -28 : -8)),
            likeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            likeButton.widthAnchor.constraint(equalToConstant: compact ? 38 : 44),
            likeButton.heightAnchor.constraint(equalToConstant: compact ? 38 : 44),

            queueButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            queueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -56),
            queueButton.widthAnchor.constraint(equalToConstant: compact ? 38 : 44),
            queueButton.heightAnchor.constraint(equalToConstant: compact ? 38 : 44)
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
        userScrolling = false
        invalidateChromePresentationTimer()
        let fullBleed = SettingsStore.shared.fullBleedArtwork
        let progressive = SettingsStore.shared.bool("BitChord.Appearance.ProgressiveBlur", true)
        let blendOff = SettingsStore.shared.bool("BitChord.Appearance.DisableBlendEffects", false)
        let liquidGlass = SettingsStore.shared.bool("BitChord.Appearance.LiquidGlass", true)
        artworkFadeView.isHidden = !fullBleed || !progressive || blendOff
        artworkView.contentMode = fullBleed ? .scaleAspectFill : .scaleAspectFit
        artworkView.backgroundColor = fullBleed ? Theme.surface : Theme.background
        glowView.isHidden = blendOff
        backdropView.alpha = liquidGlass ? 1 : 0
        artworkView.isHidden = lyrics
        artworkFadeView.isHidden = lyrics
        // In lyrics mode the words take the screen: the big title and the
        // small print fold away and a compact header takes their place.
        compactHeader.isHidden = !lyrics
        titleLabel.isHidden = lyrics
        artistLabel.isHidden = lyrics
        badgeLabel.isHidden = lyrics
        statusLabel.isHidden = lyrics || SettingsStore.shared.bool("BitChord.Misc.HideSongStatus", false)
        diagnosticsLabel.isHidden = lyrics
        // The real panel draws the transport straight on the background, with
        // no white disc behind the pause.
        playButton.backgroundColor = .clear
        playButton.layer.cornerRadius = 0
        playButton.layer.shadowOpacity = 0
        playButton.tintColor = Theme.primaryText
        playButton.imageEdgeInsets = .zero
        playButton.setImage(Icons.image(PlayerService.shared.isPlaying ? .pause : .play, size: 74), for: .normal)
        // Upstream's fallback backdrop for the lyrics/queue/player surfaces is
        // the cover itself, pre-blurred and stretched to the full screen. Using
        // that here (rather than the mesh, whose renderer is still flat on this
        // target) guarantees the surface is always the sleeve's colours.
        backdropView.alpha = 1
        meshView.isHidden = true
        scrimView.isHidden = false
        scrimLayer.colors = (lyrics
            ? [UIColor.black.withAlphaComponent(0.34).cgColor,
               UIColor.black.withAlphaComponent(0.48).cgColor,
               UIColor.black.withAlphaComponent(0.64).cgColor]
            : [UIColor.black.withAlphaComponent(0.02).cgColor,
               UIColor.black.withAlphaComponent(0.12).cgColor,
               UIColor.black.withAlphaComponent(0.44).cgColor])
        scrimLayer.locations = [0, 0.45, 1]
        handle.isHidden = false
        stationLabel.isHidden = lyrics
        peekLabel.isHidden = lyrics
        closeButton.isHidden = !lyrics
        globeButton.isHidden = !lyrics
        translitButton.isHidden = !lyrics
        // The real panel keeps the volume row and the output footer on screen
        // in both the cover and the lyrics layout.
        let hideVolume = SettingsStore.shared.bool("BitChord.Misc.HideVolumeSlider", false)
        volumeSlider.isHidden = hideVolume
        volumeLow.isHidden = hideVolume
        volumeHigh.isHidden = hideVolume
        outputButton.isHidden = false
        outputLabel.isHidden = false
        shuffleButton.isHidden = true
        repeatButton.isHidden = true
        likeButton.isHidden = true
        modeButton.isHidden = false
        // The quote tile is lit only while the lyrics panel is up, the same
        // way `BottomGlyph(highlighted = lyricsOpen)` behaves upstream.
        modeButton.backgroundColor = lyrics ? UIColor(white: 1, alpha: 0.10) : .clear
        toggleButton.setTitle(nil, for: .normal)
        toggleButton.backgroundColor = UIColor(white: 1, alpha: 0.10)
        toggleButton.layer.cornerRadius = 20
        toggleButton.setImage(Icons.image(.ellipsis, size: 20), for: .normal)
        lyricsTopCompact?.isActive = lyrics
        lyricsTopDefault?.isActive = !lyrics
        toggleInHeader?.isActive = lyrics
        toggleUnderTitle?.isActive = !lyrics
        titleUnderArtwork?.isActive = true
        titleUnderClose?.isActive = false
        lyricsTable.isHidden = !lyrics
        emptyLyricsLabel.isHidden = !lyrics || !currentLyrics.isEmpty
        lyricsSourceLabel.isHidden = !lyrics
        toggleButton.setTitle(nil, for: .normal)
        if !lyrics {
            lyricsTable.setContentOffset(.zero, animated: false)
        } else if !showsFullLyrics, !currentLyrics.isEmpty {
            // A single-line table may have changed its active line while it
            // was hidden behind the cover; ask for the current row height now
            // that the table is visible again.
            lyricsTable.beginUpdates()
            lyricsTable.endUpdates()
        }

        if lyrics {
            chromeVisible = true
            applyChromeVisibility(true, animated: false)
            if presentedViewController != nil {
                suspendChromeTimerForPresentation()
            } else {
                startLyricsClockIfNeeded()
                scheduleChromeHideIfNeeded()
            }
        } else {
            invalidateChromeTimer()
            stopLyricsClock()
            chromeVisible = true
            applyChromeVisibility(true, animated: false)
        }
    }

    /// Frames used by the compact-layout capture. They are read after a real
    /// layout pass, so a screen whose controls overlap cannot pass by looking
    /// right in a still.
    func layoutFrames(in host: UIView) -> [String: CGRect] {
        view.layoutIfNeeded()
        return [
            "artwork": artworkView.convert(artworkView.bounds, to: host),
            "title": titleLabel.convert(titleLabel.bounds, to: host),
            "play": playButton.convert(playButton.bounds, to: host),
            "previous": previousButton.convert(previousButton.bounds, to: host),
            "next": nextButton.convert(nextButton.bounds, to: host),
            "like": likeButton.convert(likeButton.bounds, to: host),
            "queue": queueButton.convert(queueButton.bounds, to: host),
            "output": outputLabel.convert(outputLabel.bounds, to: host)
        ]
    }

    // MARK: - State

    @objc private func playerChanged() {
        refresh()
        guard showingLyrics else { return }
        if PlayerService.shared.isPlaying, !PlayerService.shared.isScrubbing {
            if presentedViewController != nil {
                suspendChromeTimerForPresentation()
            } else {
                startLyricsClockIfNeeded()
                scheduleChromeHideIfNeeded()
            }
        } else {
            stopLyricsClock()
            invalidateChromeTimer()
            invalidateChromePresentationTimer()
            applyChromeVisibility(true, animated: true)
        }
    }

    @objc private func tick() {
        updateTime()
    }

    @objc private func settingsChanged() {
        lyricsToken = ""
        applyMode(lyrics: showingLyrics)
        refresh()
        if let image = artworkView.image {
            applyArtwork(image)
        }
    }

    private func refresh() {
        let service = PlayerService.shared
        guard let track = service.currentTrack else {
            stopLyricsClock()
            invalidateChromeTimer()
            invalidateChromePresentationTimer()
            dismiss(animated: true, completion: nil)
            return
        }
        if currentTrackID != track.videoID {
            currentTrackID = track.videoID
            loadArtwork(track)
        }
        if track.isExplicit || AudioEngine.shared.currentIsExplicit {
            // The real credit row leads with the badge, before the title, in
            // the artist line's colour.
            let body = NSMutableAttributedString()
            let tile = NSTextAttachment()
            tile.image = Theme.explicitBadgeImage()
            tile.bounds = CGRect(x: 0, y: -2, width: 13, height: 13)
            body.append(NSAttributedString(attachment: tile))
            body.append(NSAttributedString(string: " " + track.title))
            titleLabel.attributedText = body
        } else {
            titleLabel.attributedText = nil
            titleLabel.text = track.title
        }
        artistLabel.text = track.artist.isEmpty ? "Unknown artist" : track.artist
        stationLabel.text = "Playing " + (track.album.isEmpty ? "This phone" : track.album)
        headerTitle.text = track.title
        headerArtist.text = artistLabel.text
        // The source tag reads "JIOSAAVN 320KBPS" on every track. Useful when
        // something will not play, noise the rest of the time, so it is only
        // shown when the listener turns debug information on.
        if SettingsStore.shared.showNerdStats {
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
        statusLabel.isHidden = showingLyrics || SettingsStore.shared.bool("BitChord.Misc.HideSongStatus", false)
        // Upstream's `TransportRow` swaps the two vectors outright; the
        // enlargement is what makes the glyph read at Apple Music's size.
        playButton.setImage(Icons.image(service.isPlaying ? .pause : .play, size: 74),
                            for: .normal)
        nextButton.isEnabled = service.currentIndex + 1 < service.queue.count
        likeButton.setImage(Icons.image(LibraryStore.shared.isLiked(track) ? .heartFilled : .heart, size: 20), for: .normal)
        likeButton.tintColor = LibraryStore.shared.isLiked(track) ? Theme.accent : Theme.primaryText
        shuffleButton.alpha = service.isShuffled ? 1 : 0.4
        switch service.repeatMode {
        case .off: repeatButton.setImage(Icons.image(.repeatAll, size: 20), for: .normal); repeatButton.alpha = 0.4
        case .all: repeatButton.setImage(Icons.image(.repeatAll, size: 20), for: .normal); repeatButton.alpha = 1
        case .one: repeatButton.setImage(Icons.image(.repeatOne, size: 20), for: .normal); repeatButton.alpha = 1
        }

        let syncedSetting = SettingsStore.shared.syncedLyrics
        let bilingual = SettingsStore.shared.bool("BitChord.Lyrics.ShowBilingual", false)
        let translationLanguage = SettingsStore.shared.string("BitChord.Lyrics.TranslationLanguage", "Off")
        let token = "\(track.videoID)-\(service.lyrics.count)-\(service.lyricsAreSynced)-\(syncedSetting)-\(bilingual)-\(translationLanguage)"
        if token != lyricsToken {
            lyricsToken = token
            currentLyrics = service.lyrics
            lyricsSynced = service.lyricsAreSynced && syncedSetting
            lyricHighlight = -1
            lyricHeights.removeAll()
            let caption = service.lyricsSource.isEmpty
                ? "No lyrics found"
                : "Lyrics by " + service.lyricsSource
            lyricsSourceLabel.attributedText = NSAttributedString(
                string: caption,
                attributes: [.font: Theme.font(13),
                             .foregroundColor: UIColor(white: 1, alpha: 0.55),
                             .underlineStyle: NSUnderlineStyle.single.rawValue])
            emptyLyricsLabel.isHidden = !currentLyrics.isEmpty
            lyricsTable.reloadData()
            if bilingual, TranslationService.code(for: translationLanguage) != nil,
               !currentLyrics.isEmpty {
                let source = currentLyrics
                TranslationService.shared.translate(lines: source.map { $0.text },
                                                    to: translationLanguage) { [weak self] translated in
                    guard let self = self, self.lyricsToken == token else { return }
                    self.currentLyrics = source.enumerated().map { index, line in
                        let extra = index < translated.count ? translated[index] : line.text
                        return WordLyricLine(time: line.time,
                                             text: line.text + "\n" + extra,
                                             words: [], end: line.end)
                    }
                    self.lyricHeights.removeAll()
                    self.lyricsTable.reloadData()
                }
            }
            if !currentLyrics.isEmpty {
                lyricsTable.setContentOffset(.zero, animated: false)
            }
        }
        updateTime()
        if showingLyrics, lyricsSynced, PlayerService.shared.isPlaying,
           !PlayerService.shared.isScrubbing {
            if presentedViewController != nil {
                suspendChromeTimerForPresentation()
            } else {
                startLyricsClockIfNeeded()
                scheduleChromeHideIfNeeded()
            }
        } else {
            stopLyricsClock()
        }
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
        // Crossfade a new cover over the old one; the tracks behind the player
        // normally load while it is open, so swapping the image outright reads
        // as a flash.
        if artworkView.image != nil, let image = image {
            // Coil's 200ms crossfade: covers arrive with a short dissolve
            // rather than a hard cut.
            UIView.transition(with: artworkView, duration: 0.20,
                              options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.artworkView.image = image
            }
        } else {
            artworkView.image = image
        }
        updateArtworkMotion()
        headerArtwork.image = image
        let legacyMesh = SettingsStore.shared.bool("BitChord.Appearance.LegacyMesh", false)
        meshView.palette = legacyMesh ? Theme.meshFallbackPalette : Theme.meshPalette(of: image)
        // One blurred still per song, not a live dark blur: this is what keeps
        // the lyrics backdrop in the artwork's colours.
        let radius = NowPlayingViewController.backdropBlurRadius(
            reduceBlur: SettingsStore.shared.bool("BitChord.Appearance.ReduceDynamicBlur", false)
                || SettingsStore.shared.bool("BitChord.Appearance.GlassPerformance", false),
            highPerformance: SettingsStore.shared.highPerformanceMode,
            renderQuality: SettingsStore.shared.renderQuality)
        let blurred = Theme.blurredImage(image, radius: radius)
        let theme = SettingsStore.shared.string("BitChord.Appearance.PlayerTheme", "Cover")
        if theme == "Solid" {
            backdropView.backgroundColor = Theme.background
        } else if theme == "Legacy" {
            backdropView.backgroundColor = Theme.meshFallbackPalette.first ?? Theme.background
        } else {
            backdropView.backgroundColor = .clear
        }
        UIView.transition(with: backdropView, duration: 0.36, options: .transitionCrossDissolve, animations: {
            self.backdropView.image = theme == "Cover" ? blurred : nil
        }, completion: nil)
        if let image = image, let edge = Theme.edgeColor(of: image) {
            glowLayer.colors = [edge.withAlphaComponent(0.5).cgColor, UIColor.clear.cgColor]
            glowView.layer.shadowColor = edge.cgColor
        } else {
            glowLayer.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor]
            glowView.layer.shadowColor = UIColor.black.cgColor
        }
    }

    static func artworkMotionEnabled(animated: Bool, cellular: Bool,
                                     reduce: Bool, onWiFi: Bool) -> Bool {
        return animated && !reduce && (cellular || onWiFi)
    }

    private func updateArtworkMotion() {
        artworkView.layer.removeAnimation(forKey: "bitchord.animatedCover")
        artworkView.layer.removeAnimation(forKey: "bitchord.animatedCoverPan")
        let store = SettingsStore.shared
        guard NowPlayingViewController.artworkMotionEnabled(
            animated: store.bool("BitChord.Appearance.AnimatedCover", false),
            cellular: store.bool("BitChord.Appearance.AnimatedCoverCellular", true),
            reduce: store.bool("BitChord.Appearance.ReduceAnimation", false),
            onWiFi: NetworkStatus.isOnWiFi),
              artworkView.image != nil else { return }
        let zoom = CABasicAnimation(keyPath: "transform.scale")
        zoom.fromValue = 1.0
        zoom.toValue = 1.055
        zoom.duration = 9
        zoom.autoreverses = true
        zoom.repeatCount = .infinity
        zoom.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        artworkView.layer.add(zoom, forKey: "bitchord.animatedCover")
        let pan = CABasicAnimation(keyPath: "transform.translation.x")
        pan.fromValue = -3.0
        pan.toValue = 3.0
        pan.duration = 9
        pan.autoreverses = true
        pan.repeatCount = .infinity
        pan.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        artworkView.layer.add(pan, forKey: "bitchord.animatedCoverPan")
    }

    /// Read by the screenshot harness after the sleeve has loaded.
    func artworkMotionActiveForScreenshots() -> Bool {
        return artworkView.layer.animation(forKey: "bitchord.animatedCover") != nil
    }

    private func updateTime() {
        let service = PlayerService.shared
        let total = service.duration
        let position = service.currentTime
        if !slider.isTracking {
            slider.value = total > 0 ? Float(min(1, max(0, position / total))) : 0
        }
        diagnosticsLabel.text = SettingsStore.shared.showNerdStats
            ? AudioEngine.shared.diagnosticsSummary
            : nil
        elapsedLabel.text = Theme.format(position)
        remainingLabel.text = total > 0 ? "-" + Theme.format(max(0, total - position)) : ""
        updateLyricHighlight(at: position)
        anchorLyricsClock()
    }

    /// Performance knobs have to show up somewhere visible on this target:
    /// both the high-performance switch and the low render quality drop the
    /// per-track 42pt blur to a cheap 12pt one.
    static func backdropBlurRadius(reduceBlur: Bool, highPerformance: Bool,
                                   renderQuality: String) -> CGFloat {
        return reduceBlur || highPerformance || renderQuality == "Low" ? 12 : 42
    }

    private func updateLyricHighlight(at position: TimeInterval) {
        let index = NowPlayingViewController.lyricIndex(lines: currentLyrics,
                                                        position: position,
                                                        offsetMilliseconds: SettingsStore.shared.lyricsOffsetMilliseconds,
                                                        synced: lyricsSynced)
        guard index != -2 else { return }
        let shifted = position - SettingsStore.shared.lyricsOffsetMilliseconds / 1000

        if index != lyricHighlight {
            let previous = lyricHighlight
            lyricHighlight = index
            if index >= 0, index < currentLyrics.count {
                // The strip's chevron is a 14pt glyph at half alpha, not a text
                // character sharing the lyric's 16pt white: upstream draws an
                // icon after a 6dp spacer.
                let line = currentLyrics[index].text
                let mark = "  ›"
                let strip = NSMutableAttributedString(
                    string: line + mark,
                    attributes: [.font: Theme.font(16, weight: .medium),
                                 .foregroundColor: UIColor(white: 1, alpha: 0.78)])
                let markRange = NSRange(location: (line as NSString).length,
                                        length: (mark as NSString).length)
                strip.addAttribute(.font, value: Theme.font(14), range: markRange)
                strip.addAttribute(.foregroundColor,
                                   value: UIColor(white: 1, alpha: 0.50),
                                   range: markRange)
                peekLabel.attributedText = strip
            } else {
                peekLabel.attributedText = nil
            }

            // Only the row that stopped being active and the row that became
            // active need their line view updated. The table's data and cached
            // heights stay untouched, so the scroll animation does not fight a
            // reload on the same frame.
            applyLyricCell(lineIndex: previous, position: -1, active: false)
            applyLyricCell(lineIndex: index, position: shifted, active: true)
            if !showsFullLyrics, !lyricsTable.isHidden {
                // The whole table is the one live line in this mode, so its
                // height may change with the new line. Ask for the new height
                // without reloading data or dropping cached measurements.
                lyricsTable.beginUpdates()
                lyricsTable.endUpdates()
            }
            // With "Show full lyrics" off the table is a single live line, so
            // there is no column to keep scrolled under the active row.
            if index >= 0, index < currentLyrics.count,
               !userScrolling, showsFullLyrics {
                lyricsTable.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
            }
            return
        }

        // The karaoke view works out what is sung from the provider's own word
        // and syllable timings; this only hands it the clock. The row is
        // already configured, so this is a position-only update.
        applyLyricPosition(lineIndex: index, position: shifted)
    }

    private func applyLyricPosition(lineIndex: Int, position: TimeInterval) {
        guard lineIndex >= 0, lineIndex < currentLyrics.count else { return }
        let displayRow = showsFullLyrics ? lineIndex : 0
        guard let cell = lyricsTable.cellForRow(at: IndexPath(row: displayRow, section: 0))
            as? KaraokeLyricCell else { return }
        cell.setPosition(position)
    }

    /// Updates one visible lyric row. This deliberately never reloads the
    /// table and never invalidates the height cache; those are content/width
    /// changes, not an active-line change.
    private func applyLyricCell(lineIndex: Int, position: TimeInterval, active: Bool) {
        guard lineIndex >= 0, lineIndex < currentLyrics.count else { return }
        let displayRow = showsFullLyrics ? lineIndex : 0
        guard let cell = lyricsTable.cellForRow(at: IndexPath(row: displayRow, section: 0))
            as? KaraokeLyricCell else { return }
        let width = max(1, lyricsTable.bounds.width)
        let font = NowPlayingViewController.lyricFont(synced: lyricsSynced, width: width)
        let gutter = NowPlayingViewController.lyricGutter(width: width)
        let blurUnfocused = SettingsStore.shared.bool("BitChord.Lyrics.BlurUnfocused", true)
        let alpha: CGFloat = active ? 0.55 : (blurUnfocused ? 0.28 : 0.45)
        cell.configure(line: currentLyrics[lineIndex], font: font,
                       position: position, gutter: gutter,
                       dimmed: UIColor(white: 1, alpha: alpha))
    }

    /// -2 means the panel is not in synced mode (nothing to highlight), -1
    /// means no line has started yet, and anything else is the active line.
    static func lyricIndex(lines: [WordLyricLine], position: TimeInterval,
                           offsetMilliseconds: Double, synced: Bool) -> Int {
        guard synced, !lines.isEmpty else { return -2 }
        let shifted = position - offsetMilliseconds / 1000
        var index = -1
        for (offset, line) in lines.enumerated() {
            if line.time <= shifted { index = offset } else { break }
        }
        return index
    }

    // MARK: - Lyrics clock and chrome

    /// The player's published time is intentionally coarse (0.5s) so the
    /// labels are cheap. The karaoke sweep interpolates from the last real
    /// sample with a display link, but only while the lyrics page is actually
    /// on screen and playing.
    private func anchorLyricsClock() {
        lyricAnchorPosition = PlayerService.shared.currentTime
        lyricAnchorTimestamp = CACurrentMediaTime()
    }

    private func startLyricsClockIfNeeded() {
        guard showingLyrics, lyricsSynced, !currentLyrics.isEmpty,
              view.window != nil, presentedViewController == nil,
              PlayerService.shared.isPlaying,
              !PlayerService.shared.isScrubbing,
              lyricDisplayLink == nil else { return }
        anchorLyricsClock()
        let target = LyricDisplayLinkTarget()
        target.owner = self
        let link = CADisplayLink(target: target,
                                 selector: #selector(LyricDisplayLinkTarget.tick))
        target.link = link
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        lyricLinkTarget = target
        lyricDisplayLink = link
    }

    private func stopLyricsClock() {
        lyricDisplayLink?.invalidate()
        lyricDisplayLink = nil
        lyricLinkTarget = nil
    }

    fileprivate func lyricClockTick() {
        guard showingLyrics, !currentLyrics.isEmpty,
              view.window != nil, presentedViewController == nil,
              lyricsSynced, PlayerService.shared.isPlaying,
              !PlayerService.shared.isScrubbing else {
            stopLyricsClock()
            return
        }
        let elapsed = CACurrentMediaTime() - lyricAnchorTimestamp
        let projected = lyricAnchorPosition + elapsed * SettingsStore.shared.playbackRate
        let duration = PlayerService.shared.duration
        let position = duration > 0 ? min(projected, duration) : projected
        updateLyricHighlight(at: max(0, position))
    }

    /// When the chrome is hidden, the whole page is still interactive: the
    /// table scrolls, the scrubber can be found again, and a tap brings the
    /// controls back. Paused playback and an open menu are never masked.
    private func scheduleChromeHideIfNeeded() {
        invalidateChromeTimer()
        guard showingLyrics, view.window != nil, presentedViewController == nil,
              PlayerService.shared.isPlaying,
              !PlayerService.shared.isScrubbing,
              !userScrolling else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            self?.chromeTimerFired()
        }
        chromeTimer = timer
    }

    private func invalidateChromeTimer() {
        chromeTimer?.invalidate()
        chromeTimer = nil
    }

    /// Invalidate the inactivity timer the moment a menu or sheet is opened.
    /// A separate, weak watcher resumes it once the presented controller is
    /// gone, so the controls stay visible for the whole presentation without
    /// leaving the hide timer armed while it is covered.
    private func suspendChromeTimerForPresentation() {
        invalidateChromeTimer()
        // The karaoke sweep is not visible under a menu or sheet; stop it here
        // and let the watcher restart it when the presentation is gone.
        stopLyricsClock()
        invalidateChromePresentationTimer()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.chromePresentationTick()
        }
        chromePresentationTimer = timer
    }

    private func invalidateChromePresentationTimer() {
        chromePresentationTimer?.invalidate()
        chromePresentationTimer = nil
    }

    @objc private func chromePresentationTick() {
        guard showingLyrics, view.window != nil else {
            invalidateChromePresentationTimer()
            return
        }
        guard presentedViewController == nil else { return }
        invalidateChromePresentationTimer()
        startLyricsClockIfNeeded()
        scheduleChromeHideIfNeeded()
    }

    private func applyChromeVisibility(_ visible: Bool, animated: Bool) {
        chromeVisible = visible
        let views = chromeViews
        for control in views {
            control.isUserInteractionEnabled = visible
        }
        let changes: () -> Void = {
            for control in views { control.alpha = visible ? 1 : 0 }
        }
        if animated, UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: visible ? 0.18 : 0.35,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: changes)
        } else {
            changes()
        }
    }

    private func showChromeForInteraction() {
        invalidateChromeTimer()
        applyChromeVisibility(true, animated: true)
        if presentedViewController != nil {
            suspendChromeTimerForPresentation()
            return
        }
        if PlayerService.shared.isPlaying { startLyricsClockIfNeeded() }
        scheduleChromeHideIfNeeded()
    }

    @objc private func chromeTimerFired() {
        chromeTimer = nil
        guard showingLyrics, view.window != nil else { return }
        guard PlayerService.shared.isPlaying,
              !PlayerService.shared.isScrubbing, !userScrolling else {
            applyChromeVisibility(true, animated: true)
            return
        }
        guard chromeVisible else { return }
        guard presentedViewController == nil else {
            // A presentation slipped in without its own suspension; keep the
            // controls up and watch for it to go away.
            suspendChromeTimerForPresentation()
            return
        }
        applyChromeVisibility(false, animated: true)
    }

    @objc private func chromeTapped() {
        guard showingLyrics else { return }
        showChromeForInteraction()
    }

    @objc private func appDidEnterBackground() {
        userScrolling = false
        stopLyricsClock()
        invalidateChromeTimer()
        invalidateChromePresentationTimer()
    }

    @objc private func appWillEnterForeground() {
        guard showingLyrics else { return }
        applyChromeVisibility(true, animated: false)
        if presentedViewController != nil {
            // A menu or sheet survived the background; keep watching it
            // instead of running the sweep behind it.
            suspendChromeTimerForPresentation()
            return
        }
        startLyricsClockIfNeeded()
        scheduleChromeHideIfNeeded()
    }

    // MARK: - Actions

    @objc private func close() {
        // Collapse the whole panel downwards, matching the swipe the real
        // player uses, instead of a stock modal slide.
        userScrolling = false
        stopLyricsClock()
        invalidateChromeTimer()
        invalidateChromePresentationTimer()
        UIView.animate(withDuration: 0.26, delay: 0,
                       options: [.curveEaseIn, .beginFromCurrentState], animations: {
            self.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
            self.view.alpha = 0
        }, completion: { _ in
            self.dismiss(animated: false, completion: nil)
        })
    }

    /// Collapses the panel for the motion capture, through the same path the
    /// close button uses.
    func motionCloseForCapture() {
        close()
    }

    func motionArtworkAlpha() -> CGFloat {
        return CGFloat(artworkView.layer.presentation()?.opacity ?? Float(artworkView.alpha))
    }

    func motionArtworkScale() -> CGFloat {
        return artworkView.layer.presentation()?.transform.m11 ?? 1
    }

    func motionPanelTranslateY() -> CGFloat {
        return view.layer.presentation()?.transform.m42 ?? 0
    }

    /// Presentation values for the entrance/collapse and artwork crossfade.
    func motionSnapshot() -> String {
        let panel = view.layer.presentation()
        let artwork = artworkView.layer.presentation()
        let title = titleLabel.layer.presentation()
        let header = compactHeader.layer.presentation()
        return String(format: "player.alpha=%.2f player.ty=%.1f player.scale=%.3f "
                      + "art.alpha=%.2f art.scale=%.3f title.alpha=%.2f header.alpha=%.2f track=%@",
                      panel?.opacity ?? Float(view.alpha),
                      panel?.transform.m42 ?? 0,
                      artwork?.transform.m11 ?? 1,
                      artwork?.opacity ?? 1,
                      artwork?.transform.m11 ?? 1,
                      title?.opacity ?? Float(titleLabel.alpha),
                      header?.opacity ?? Float(compactHeader.alpha),
                      PlayerService.shared.currentTrack?.videoID ?? "none")
    }

    /// Opens the lyrics panel for the screenshot harness.
    func showLyricsForScreenshots() {
        loadViewIfNeeded()
        applyMode(lyrics: true)
        updateLyricHighlight(at: PlayerService.shared.currentTime)
    }

    @objc private func volumeChanged() {
        showChromeForInteraction()
        AudioEngine.shared.setVolume(volumeSlider.value)
    }

    @objc private func showOutput() {
        showChromeForInteraction()
        suspendChromeTimerForPresentation()
        let names = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portName }
        let route = names.isEmpty ? "this phone" : names.joined(separator: ", ")
        let alert = UIAlertController(title: "Audio output",
                                      message: "Playing on \(route).",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    @objc private func toggleMode() {
        applyMode(lyrics: !showingLyrics)
    }

    @objc private func showTrackActions() {
        guard let track = PlayerService.shared.currentTrack else { return }
        showChromeForInteraction()
        suspendChromeTimerForPresentation()
        TrackActions.present(for: track, from: self, sourceView: toggleButton)
    }

    @objc private func togglePlay() {
        showChromeForInteraction()
        PlayerService.shared.togglePlayPause()
    }

    @objc private func goPrevious() {
        showChromeForInteraction()
        PlayerService.shared.previous()
    }

    @objc private func goNext() {
        showChromeForInteraction()
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
        showChromeForInteraction()
        suspendChromeTimerForPresentation()
        let queue = QueueViewController()
        queue.modalPresentationStyle = .pageSheet
        present(queue, animated: true, completion: nil)
    }

    /// Called by the scrubber's tracking closures, not by a target/action, so
    /// the display link and the inactivity timer follow a real scrub.
    private func sliderDown() {
        PlayerService.shared.isScrubbing = true
        stopLyricsClock()
        invalidateChromePresentationTimer()
        showChromeForInteraction()
    }

    private func sliderUp(value: Float) {
        PlayerService.shared.isScrubbing = false
        PlayerService.shared.seek(toFraction: Double(value))
        stopLyricsClock()
        anchorLyricsClock()
        showChromeForInteraction()
    }
}

extension NowPlayingViewController {
    /// Upstream's lyrics are one size for every line: 34sp/41sp extra-bold for
    /// synced words, 30sp/38sp for plain text. On a compact phone that size
    /// pushes a long line into three or four rows, so the base size and the
    /// gutter both come down while the active line remains the brightest row.
    static func lyricFont(synced: Bool, width: CGFloat) -> UIFont {
        let compact = width > 0 && width < 360
        let base: CGFloat = synced ? (compact ? 26 : 34) : (compact ? 23 : 30)
        // Keep the user's text-size choice, but stop the accessibility/display
        // scale from growing a compact lyric back into a wall of text.
        let maximum: CGFloat = compact ? 30 : 38
        let font = Theme.font(base, weight: .heavy)
        return font.pointSize > maximum ? font.withSize(maximum) : font
    }

    static func lyricGutter(width: CGFloat) -> CGFloat {
        let compact = width > 0 && width < 360
        return compact ? 20 : 30
    }
}

extension NowPlayingViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !showsFullLyrics { return currentLyrics.isEmpty ? 0 : 1 }
        return currentLyrics.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: KaraokeLyricCell.reuseIdentifier,
                                                 for: indexPath)
        let row = showsFullLyrics ? indexPath.row : max(0, lyricHighlight)
        if let lyricCell = cell as? KaraokeLyricCell, row < currentLyrics.count {
            let width = max(1, tableView.bounds.width)
            let font = NowPlayingViewController.lyricFont(synced: lyricsSynced, width: width)
            let cellPosition = row == lyricHighlight
                ? PlayerService.shared.currentTime - SettingsStore.shared.lyricsOffsetMilliseconds / 1000
                : -1
            let blurUnfocused = SettingsStore.shared.bool("BitChord.Lyrics.BlurUnfocused", true)
            let active = row == lyricHighlight
            let alpha: CGFloat = active ? 0.55 : (blurUnfocused ? 0.28 : 0.45)
            lyricCell.configure(line: currentLyrics[row],
                                font: font,
                                position: cellPosition,
                                gutter: NowPlayingViewController.lyricGutter(width: width),
                                dimmed: UIColor(white: 1, alpha: alpha))
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let row = showsFullLyrics ? indexPath.row : max(0, lyricHighlight)
        guard row < currentLyrics.count else { return 34 }
        let width = max(1, tableView.bounds.width)
        let font = NowPlayingViewController.lyricFont(synced: lyricsSynced, width: width)
        let key = LyricHeightKey(row: row,
                                 width: Int(width.rounded()),
                                 pointSizeTenths: Int((font.pointSize * 10).rounded()))
        if let cached = lyricHeights[key] { return cached }
        let gutter = NowPlayingViewController.lyricGutter(width: width)
        let height = KaraokeLineView.height(
            text: currentLyrics[row].text,
            font: font,
            width: max(1, width - gutter * 2))
        lyricHeights[key] = height
        return height
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Mark the scroll before showing chrome: showChromeForInteraction()
        // refreshes the inactivity timer, and it must not arm one mid-drag.
        userScrolling = true
        if scrollView === lyricsTable { showChromeForInteraction() }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            userScrolling = false
            if scrollView === lyricsTable { scheduleChromeHideIfNeeded() }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userScrolling = false
        if scrollView === lyricsTable { scheduleChromeHideIfNeeded() }
    }
}

/// Upstream's queue sheet: the songs that already played (when the setting is
/// on), then the upcoming queue, tap to jump.
final class QueueViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerLabel = UILabel()
    private var showsHistory = false
    private let editButton = UIButton(type: .system)

    private static let emptyIdentifier = "QueueHistoryEmpty"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        showsHistory = PlaybackHistoryStore.shared.isEnabled

        headerLabel.text = "Queue"
        headerLabel.font = Theme.font(17, weight: .semibold)
        headerLabel.textColor = Theme.primaryText
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        // Upstream reorders the queue by dragging; the table's own edit mode
        // is the iOS 12 way to do that.
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.setTitle("Edit", for: .normal)
        editButton.setTitleColor(Theme.primaryText, for: .normal)
        editButton.titleLabel?.font = Theme.font(14, weight: .semibold)
        editButton.addTarget(self, action: #selector(toggleEditing), for: .touchUpInside)
        view.addSubview(editButton)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.tableFooterView = UIView()
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: QueueViewController.emptyIdentifier)
        view.addSubview(tableView)

        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: .playbackHistoryDidChange, object: nil)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            editButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            editButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func reload() {
        tableView.reloadData()
    }

    @objc private func toggleEditing() {
        tableView.setEditing(!tableView.isEditing, animated: true)
        editButton.setTitle(tableView.isEditing ? "Done" : "Edit", for: .normal)
    }

    private var historySection: Int? {
        return showsHistory ? 0 : nil
    }

    private var queueSection: Int {
        return showsHistory ? 1 : 0
    }
}

extension QueueViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return showsHistory ? 2 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if showsHistory, section == 0 {
            // The empty state is a row so the heading is never a bare label.
            return max(1, PlaybackHistoryStore.shared.items.count)
        }
        return PlayerService.shared.queue.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard showsHistory else { return nil }
        return section == 0 ? "History" : "Queue"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if showsHistory, indexPath.section == 0 {
            let history = PlaybackHistoryStore.shared.items
            guard indexPath.row < history.count else {
                let cell = tableView.dequeueReusableCell(withIdentifier: QueueViewController.emptyIdentifier,
                                                         for: indexPath)
                cell.backgroundColor = .clear
                cell.textLabel?.text = "Nothing played yet"
                cell.textLabel?.font = Theme.font(.bodyMedium)
                cell.textLabel?.textColor = Theme.secondaryText
                cell.selectionStyle = .none
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath)
            if let trackCell = cell as? TrackCell {
                trackCell.configure(with: history[indexPath.row])
            }
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath)
        let queue = PlayerService.shared.queue
        if let trackCell = cell as? TrackCell, indexPath.row < queue.count {
            trackCell.configure(with: queue[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if showsHistory, indexPath.section == 0 {
            let history = PlaybackHistoryStore.shared.items
            guard indexPath.row < history.count else { return }
            // Playing from history puts that song first and keeps the queue
            // behind it, which is what the real sheet does.
            let track = history[indexPath.row]
            let rest = PlayerService.shared.queue.filter { $0.videoID != track.videoID }
            PlayerService.shared.play(tracks: [track] + rest, startingAt: 0)
            dismiss(animated: true, completion: nil)
            return
        }
        PlayerService.shared.playTrack(at: indexPath.row)
        dismiss(animated: true, completion: nil)
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return !(showsHistory && indexPath.section == 0)
    }

    func tableView(_ tableView: UITableView,
                   moveRowAt sourceIndexPath: IndexPath,
                   to destinationIndexPath: IndexPath) {
        guard !(showsHistory && sourceIndexPath.section == 0) else { return }
        // UITableView's destination counts the row before removal.
        let target = destinationIndexPath.row > sourceIndexPath.row
            ? destinationIndexPath.row - 1
            : destinationIndexPath.row
        PlayerService.shared.moveInQueue(from: sourceIndexPath.row, to: target)
        tableView.reloadData()
    }

    /// Upstream lets a song be dropped from the queue; on iOS 12 the swipe is
    /// the gesture that exists.
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        if showsHistory, indexPath.section == 0 { return nil }
        let action = UIContextualAction(style: .destructive, title: "Remove") { _, _, done in
            PlayerService.shared.removeFromQueue(at: indexPath.row)
            tableView.reloadData()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }
}
