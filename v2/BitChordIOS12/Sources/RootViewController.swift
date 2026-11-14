import UIKit

/// Container for the four tabs, the floating capsule bar and the mini player, and the host of the
/// bridge web view. Mirrors upstream `MainTabView`.
final class RootViewController: UIViewController {
    private var navigations: [UINavigationController] = []
    private let tabBar = CapsuleTabBar()
    private let miniBar = MiniPlayerBar()
    private var miniBarHeight: NSLayoutConstraint!
    private var selectedIndex = 0

    private let tabBarHeight: CGFloat = 56
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
            // Tab roots are edge-to-edge: the real app has no navigation bar
            // chrome above Home, Library, Explore or Search. Pushed screens
            // get the bar back through the delegate below.
            navigation.delegate = self
            navigation.setNavigationBarHidden(true, animated: false)
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
        let previous = selectedIndex
        selectedIndex = index
        tabBar.setSelectedIndex(index)
        if index == 3,
           let search = navigations[index].viewControllers.first as? SearchViewController {
            DispatchQueue.main.async { search.focusFieldForDisplay() }
        }
        guard previous != index, navigations.indices.contains(index) else {
            for (position, navigation) in navigations.enumerated() {
                navigation.view.isHidden = position != index
            }
            return
        }
        let outgoing = navigations[previous]
        let incoming = navigations[index]
        incoming.view.isHidden = false
        incoming.view.alpha = 0
        view.layoutIfNeeded()
        // A hidden view unhidden and faded in the same transaction jumps
        // straight to its final alpha. One runloop spent at zero gives Core
        // Animation a real start value, so the page actually dissolves in.
        DispatchQueue.main.async {
            guard self.selectedIndex == index else {
                incoming.view.isHidden = true
                incoming.view.alpha = 1
                return
            }
            // A short crossfade, the way the real tab host swaps pages; sliding
            // the whole page would fight the floating bar's own motion.
            UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseOut],
                           animations: {
                outgoing.view.alpha = 0
                incoming.view.alpha = 1
            }, completion: { _ in
                // A second tab tap can land before this fade ends; only hide the
                // page we actually left if the fade still owns the screen.
                if self.selectedIndex == index {
                    outgoing.view.isHidden = true
                }
                outgoing.view.alpha = 1
            })
        }
    }

    private func buildOverlays() {
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.onSelect = { [weak self] index in
            self?.install(index)
        }
        view.addSubview(tabBar)

        miniBar.translatesAutoresizingMaskIntoConstraints = false
        // The bar grows out of the capsule; without clipping its full contents
        // are painted from the first frame and the spring cannot be seen.
        miniBar.clipsToBounds = true
        miniBar.layer.cornerRadius = 28
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
        miniBar.refresh()
        if visible {
            miniBar.isHidden = false
        }

        var inset = tabBarHeight + overlayPadding * 2
        if visible {
            inset += miniBarShownHeight + overlayPadding
        }
        for navigation in navigations {
            navigation.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
        }

        // The bar grows out of the tab bar instead of appearing whole.
        UIView.animate(withDuration: 0.30, delay: 0,
                       usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
                       options: [.beginFromCurrentState, .allowUserInteraction],
                       animations: {
            self.miniBarHeight.constant = visible ? self.miniBarShownHeight : 0
            self.miniBar.alpha = visible ? 1 : 0
            self.view.layoutIfNeeded()
        }, completion: { _ in
            if !visible { self.miniBar.isHidden = true }
        })
    }

    /// Drives the tabs for the screenshot harness.
    func showTab(_ index: Int) {
        install(index)
    }

    // MARK: - Motion capture hooks

    /// Everything the motion report needs, read from the presentation layers so
    /// a value sampled mid-animation is the value actually on screen.
    func motionSnapshot() -> String {
        let pill = tabBar.motionPillFrame()
        var parts = [String(format: "tab=%d pill=%.1f,%.1f,%.1f,%.1f",
                            selectedIndex, pill.origin.x, pill.origin.y,
                            pill.width, pill.height)]
        for (index, navigation) in navigations.enumerated() {
            let alpha = navigation.view.layer.presentation()?.opacity ?? Float(navigation.view.alpha)
            parts.append(String(format: "tab%d.alpha=%.2f", index, alpha))
        }
        let mini = miniBar.layer.presentation()
        parts.append(String(format: "mini.h=%.1f mini.a=%.2f",
                            mini?.bounds.height ?? miniBar.bounds.height,
                            mini?.opacity ?? Float(miniBar.alpha)))
        if let player = presentedViewController as? NowPlayingViewController {
            parts.append(player.motionSnapshot())
        }
        return parts.joined(separator: " ")
    }

    func motionTabAlpha(_ index: Int) -> CGFloat {
        guard navigations.indices.contains(index) else { return 0 }
        let view = navigations[index].view!
        return CGFloat(view.layer.presentation()?.opacity ?? Float(view.alpha))
    }

    func motionMiniHeight() -> CGFloat {
        return miniBar.layer.presentation()?.bounds.height ?? miniBar.bounds.height
    }

    func motionPillFrame() -> CGRect {
        return tabBar.motionPillFrame()
    }

    var motionPresentedPlayer: NowPlayingViewController? {
        return presentedViewController as? NowPlayingViewController
    }

    func motionDismissPlayer() {
        (presentedViewController as? NowPlayingViewController)?.motionCloseForCapture()
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

    /// Presenter used by the motion capture. It hands back the controller so
    /// the harness can sample the entrance before `presentedViewController` is
    /// assigned at the end of the transition.
    func presentNowPlayingForMotion() -> NowPlayingViewController? {
        guard PlayerService.shared.currentTrack != nil else { return nil }
        let controller = NowPlayingViewController()
        controller.modalPresentationStyle = .fullScreen
        motionPlayer = controller
        present(controller, animated: true, completion: nil)
        return controller
    }

    private(set) var motionPlayer: NowPlayingViewController?
}

extension RootViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        let isRoot = viewController === navigationController.viewControllers.first
        navigationController.setNavigationBarHidden(isRoot, animated: animated)
    }
}
