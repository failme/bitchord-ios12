import UIKit

/// Container for the four tabs, the floating capsule bar and the mini player, and the host of the
/// bridge web view. Mirrors upstream `MainTabView`.
final class RootViewController: UIViewController {
    private var navigations: [UINavigationController] = []
    private let tabBar = CapsuleTabBar()
    private let miniBar = MiniPlayerBar()
    private var miniBarHeight: NSLayoutConstraint!
    private var selectedIndex = 0

    private let tabBarHeight: CGFloat = 64
    private let miniBarShownHeight: CGFloat = 56
    private let overlayPadding: CGFloat = 8
    private let overlayInset: CGFloat = 16

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentOnboardingIfNeeded()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        // The embed player must be on screen for WebKit to grant it audio: it sits behind the
        // interface at a small size and never receives touches.
        let bridgeView = YouTubeBridge.shared.makeWebView()
        bridgeView.translatesAutoresizingMaskIntoConstraints = false
        bridgeView.isUserInteractionEnabled = false
        view.addSubview(bridgeView)

        NSLayoutConstraint.activate([
            bridgeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bridgeView.topAnchor.constraint(equalTo: view.topAnchor),
            bridgeView.widthAnchor.constraint(equalToConstant: 320),
            bridgeView.heightAnchor.constraint(equalToConstant: 240)
        ])

        // The bridge stays in the window so WebKit keeps its audio permission,
        // but its white page must never show through a transparent bar or a
        // gap between cards. One opaque sheet above it hides it completely.
        let veil = UIView()
        veil.backgroundColor = Theme.background
        veil.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(veil)
        NSLayoutConstraint.activate([
            veil.topAnchor.constraint(equalTo: view.topAnchor),
            veil.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            veil.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            veil.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        buildTabs()
        buildOverlays()

        install(0)
        playerChanged()

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(playerChanged),
                                              name: .playerDidChange,
                                              object: nil)
    }

    // MARK: - Tabs

    private func buildTabs() {
        let tabs: [UIViewController] = [
            HomeViewController(),
            ExploreViewController(),
            LibraryViewController(),
            SearchViewController()
        ]

        for controller in tabs {
            let navigation = UINavigationController(rootViewController: controller)
            navigation.navigationBar.barTintColor = Theme.background
            navigation.navigationBar.tintColor = Theme.accent
            navigation.navigationBar.isTranslucent = false
            navigation.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
            navigation.navigationBar.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            navigation.navigationBar.prefersLargeTitles = true
            // Flat black bars: upstream draws no hairline under the header.
            navigation.navigationBar.shadowImage = UIImage()
            navigation.navigationBar.setBackgroundImage(UIImage(), for: .any, barMetrics: .default)

            addChild(navigation)
            navigation.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(navigation.view)
            NSLayoutConstraint.activate([
                navigation.view.topAnchor.constraint(equalTo: view.topAnchor),
                navigation.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                navigation.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                navigation.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            navigation.didMove(toParent: self)
            navigations.append(navigation)
        }
    }

    private func install(_ index: Int) {
        selectedIndex = index
        for (position, navigation) in navigations.enumerated() {
            navigation.view.isHidden = position != index
        }
        tabBar.setSelectedIndex(index)
    }

    private func buildOverlays() {
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.onSelect = { [weak self] index in
            self?.install(index)
        }
        view.addSubview(tabBar)

        miniBar.translatesAutoresizingMaskIntoConstraints = false
        miniBar.layer.cornerRadius = 12
        miniBar.onTap = { [weak self] in
            self?.presentNowPlaying()
        }
        view.addSubview(miniBar)

        miniBarHeight = miniBar.heightAnchor.constraint(equalToConstant: 0)
        miniBarHeight.isActive = true

        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: overlayInset),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -overlayInset),
            tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                           constant: -overlayPadding),
            tabBar.heightAnchor.constraint(equalToConstant: tabBarHeight),

            miniBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: overlayInset),
            miniBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -overlayInset),
            miniBar.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -overlayPadding)
        ])
    }

    @objc private func playerChanged() {
        let visible = PlayerService.shared.currentTrack != nil
        miniBar.isHidden = !visible
        miniBarHeight.constant = visible ? miniBarShownHeight : 0
        miniBar.refresh()

        var inset = tabBarHeight + overlayPadding * 2
        if visible {
            inset += miniBarShownHeight + overlayPadding
        }
        for navigation in navigations {
            navigation.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
        }
    }

    /// Drives the tabs for the screenshot harness.
    func showTab(_ index: Int) {
        install(index)
    }

    func navigationForTab(_ index: Int) -> UINavigationController? {
        guard index >= 0, index < navigations.count else { return nil }
        return navigations[index]
    }

    /// Deep-linked "home": every tab back to its first screen.
    func resetToHome() {
        for navigation in navigations {
            navigation.popToRootViewController(animated: false)
        }
        install(0)
    }

    /// Shows the first-run flow once; the capture harness drives it when it
    /// wants to photograph it.
    func presentOnboardingIfNeeded() {
        guard !OnboardingViewController.hasCompleted,
              presentedViewController == nil else { return }
        let onboarding = OnboardingViewController()
        onboarding.modalPresentationStyle = .fullScreen
        present(onboarding, animated: false, completion: nil)
    }

    // MARK: - Now playing

    func presentNowPlaying() {
        guard PlayerService.shared.currentTrack != nil else { return }
        if presentedViewController is NowPlayingViewController { return }
        let controller = NowPlayingViewController()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true, completion: nil)
    }
}
