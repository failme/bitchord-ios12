import UIKit

/// The first-run flow, mirroring upstream's onboarding: a welcome, a short
/// tour of what the app does, and a choice of where the library comes from.
///
/// It is one scrollable screen with steps rather than a pager, so the content
/// cannot be clipped on a 320x568 phone: every step is laid out in a scroll
/// view whose content can always be reached.
final class OnboardingViewController: UIViewController {
    static let completedKey = "BitChord.Onboarding.Completed"
    static let pathKey = "BitChord.Onboarding.LibraryPath"

    static var hasCompleted: Bool {
        return SettingsStore.shared.bool(completedKey, false)
    }

    static func reset() {
        SettingsStore.shared.set(false, for: completedKey)
    }

    static func complete(path: String) {
        SettingsStore.shared.set(path, for: pathKey)
        SettingsStore.shared.set(true, for: completedKey)
    }

    /// Steps: 0 welcome, 1 tour, 2 library path, 3 ready.
    private(set) var step = 0
    private(set) var chosenPath = ""

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let actions = UIStackView()
    private let logo = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let features = UIStackView()
    private let primary = UIButton(type: .system)
    private let secondary = UIButton(type: .system)
    private let back = UIButton(type: .system)
    private let close = UIButton(type: .system)
    private var compact = false
    private var logoWidth: NSLayoutConstraint?
    private var logoHeight: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        close.translatesAutoresizingMaskIntoConstraints = false
        close.setTitle("Skip", for: .normal)
        close.setTitleColor(Theme.secondaryText, for: .normal)
        close.titleLabel?.font = Theme.font(14, weight: .medium)
        close.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        view.addSubview(close)

        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.image = UIImage(named: "BrandLogo") ?? Icons.image(.logo, size: 64)
        logo.contentMode = .scaleAspectFit
        logo.tintColor = Theme.accent

        titleLabel.font = Theme.font(28, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 0

        bodyLabel.font = Theme.font(15)
        bodyLabel.textColor = Theme.secondaryText
        bodyLabel.numberOfLines = 0

        features.axis = .vertical
        features.spacing = 12

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(logo)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(bodyLabel)
        stack.addArrangedSubview(features)

        // The buttons live outside the scroll view: whatever the content height,
        // Continue and Skip stay reachable on a 320x568 phone.
        actions.axis = .vertical
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.addArrangedSubview(primary)
        actions.addArrangedSubview(secondary)
        actions.addArrangedSubview(back)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)
        view.addSubview(actions)

        configure(primary, filled: true)
        configure(secondary, filled: false)
        configure(back, filled: false)
        back.setTitle("Back", for: .normal)
        back.setTitleColor(Theme.secondaryText, for: .normal)
        primary.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        secondary.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
        back.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let logoWidth = logo.widthAnchor.constraint(equalToConstant: 64)
        let logoHeight = logo.heightAnchor.constraint(equalToConstant: 64)
        self.logoWidth = logoWidth
        self.logoHeight = logoHeight

        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

            scroll.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -10),

            actions.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            actions.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            actions.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -48),

            logoWidth,
            logoHeight,
            primary.heightAnchor.constraint(equalToConstant: 48),
            secondary.heightAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 36)
        ])

        render()
    }

    /// A 320x568 phone gets smaller type, a smaller mark and tighter spacing so
    /// every step fits without hiding a row under the buttons.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let shouldCompact = view.bounds.height < 620
        guard shouldCompact != compact else { return }
        compact = shouldCompact
        logoWidth?.constant = compact ? 46 : 64
        logoHeight?.constant = compact ? 46 : 64
        stack.spacing = compact ? 10 : 16
        features.spacing = compact ? 8 : 12
        render()
    }

    private func configure(_ button: UIButton, filled: Bool) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = Theme.font(16, weight: .semibold)
        button.layer.cornerRadius = filled ? 24 : 12
        if filled {
            button.backgroundColor = Theme.accent
            button.setTitleColor(Theme.background, for: .normal)
        } else {
            button.backgroundColor = Theme.surfaceVariant
            button.setTitleColor(Theme.primaryText, for: .normal)
        }
    }

    // MARK: - Steps

    private func render() {
        features.arrangedSubviews.forEach { $0.removeFromSuperview() }
        back.isHidden = step == 0
        secondary.isHidden = true
        primary.setTitle("Continue", for: .normal)

        titleLabel.font = Theme.font(compact ? 24 : 28, weight: .bold)
        bodyLabel.font = Theme.font(compact ? 14 : 15)

        switch step {
        case 0:
            titleLabel.text = "Welcome to BitChord"
            bodyLabel.text = "YouTube Music, your downloads and synced lyrics in one player — built to run on iOS 12."
            addFeature("Play anything the catalogue has", detail: "Search, radio, autoplay and a queue you can reorder.")
            addFeature("Take it offline", detail: "Downloads with quality, storage limits and background transfers.")
            addFeature("Sing along", detail: "Synced and syllable-timed lyrics, with mood shelves for the rest.")
        case 1:
            titleLabel.text = "A quick tour"
            bodyLabel.text = "Four tabs, one player."
            addFeature("Home", detail: "Continue listening, your picks and new releases.")
            addFeature("Explore", detail: "Moods, charts and fresh albums.")
            addFeature("Library", detail: "Liked songs, playlists, downloads, local files, history and replay.")
            addFeature("Search", detail: "Songs, artists and albums, with artist pages that play.")
        case 2:
            titleLabel.text = "Choose your library"
            bodyLabel.text = "Where should BitChord look for music you already own?"
            primary.setTitle("Local files", for: .normal)
            secondary.isHidden = false
            secondary.setTitle("Addon server", for: .normal)
            addFeature("Local files", detail: "Drop audio into the BitChord folder in Files; it appears under Library → Local Music.")
            addFeature("Addon server", detail: "Point the lossless addon at your own server in Settings → Sources & addons.")
        default:
            titleLabel.text = "You're set"
            bodyLabel.text = chosenPath == "local"
                ? "Your local folder is ready under Library → Local Music."
                : (chosenPath == "addon"
                    ? "Add your server URL in Settings → Sources & addons."
                    : "You can pick a library later in Settings.")
            primary.setTitle("Start listening", for: .normal)
            addFeature("Change it later", detail: "Settings → Show onboarding again reopens this flow.")
        }
        scroll.setContentOffset(.zero, animated: false)
        UIAccessibility.post(notification: .screenChanged, argument: titleLabel)

        // Each step settles in rather than swapping instantly. Short enough
        // that the 320x568 capture, taken 0.3s later, sees the finished frame.
        guard view.window != nil, UIView.areAnimationsEnabled,
              !UIAccessibility.isReduceMotionEnabled else { return }
        for view in [titleLabel, bodyLabel, features] {
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 10)
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            for view in [self.titleLabel, self.bodyLabel, self.features] {
                view.alpha = 1
                view.transform = .identity
            }
        }
    }

    private func addFeature(_ title: String, detail: String) {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 2
        let name = UILabel()
        name.text = title
        name.font = Theme.font(15, weight: .semibold)
        name.textColor = Theme.primaryText
        let text = UILabel()
        text.text = detail
        text.font = Theme.font(compact ? 12 : 13)
        text.textColor = Theme.secondaryText
        text.numberOfLines = 0
        row.addArrangedSubview(name)
        row.addArrangedSubview(text)
        features.addArrangedSubview(row)
    }

    // MARK: - Actions

    @objc private func primaryTapped() {
        switch step {
        case 0, 1:
            step += 1
            render()
        case 2:
            chosenPath = "local"
            finish(path: "local")
        default:
            completeAndDismiss()
        }
    }

    @objc private func secondaryTapped() {
        guard step == 2 else { return }
        chosenPath = "addon"
        finish(path: "addon")
    }

    @objc private func backTapped() {
        guard step > 0 else { return }
        step -= 1
        render()
    }

    @objc private func skipTapped() {
        finish(path: "skip")
    }

    private func finish(path: String) {
        chosenPath = path
        step = 3
        render()
    }

    private func completeAndDismiss() {
        OnboardingViewController.complete(path: chosenPath.isEmpty ? "skip" : chosenPath)
        // No animation: the capture checks "dismissed" immediately afterwards,
        // and a queued animation is not part of the state being proven.
        dismiss(animated: false, completion: nil)
    }

    // MARK: - Capture hooks

    /// Advances one step and reports where it landed; returns false once the
    /// flow is finished and dismissed.
    @discardableResult
    func advanceForCapture() -> Bool {
        if step >= 3 {
            completeAndDismiss()
            return false
        }
        step += 1
        render()
        return true
    }

    func chooseLocalForCapture() {
        step = 2
        render()
        chosenPath = "local"
        finish(path: "local")
    }

    var stepTitle: String { return titleLabel.text ?? "" }

    func motionTitleAlpha() -> CGFloat {
        return CGFloat(titleLabel.layer.presentation()?.opacity ?? Float(titleLabel.alpha))
    }

    /// Presentation values for the step fade, sampled while it runs.
    func motionSnapshot() -> String {
        let title = titleLabel.layer.presentation()
        let body = bodyLabel.layer.presentation()
        let stack = features.layer.presentation()
        return String(format: "onboarding.step=%d title.alpha=%.2f title.ty=%.1f "
                      + "body.alpha=%.2f features.alpha=%.2f",
                      step,
                      title?.opacity ?? Float(titleLabel.alpha),
                      title?.transform.m42 ?? 0,
                      body?.opacity ?? Float(bodyLabel.alpha),
                      stack?.opacity ?? Float(features.alpha))
    }

    /// Where the primary button lands, in window coordinates, for the small
    /// screen check.
    var primaryFrameInWindow: CGRect {
        return primary.convert(primary.bounds, to: nil)
    }
}
