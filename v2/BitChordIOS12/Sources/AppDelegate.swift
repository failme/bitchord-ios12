import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var appliedTheme = Theme.mode

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        SettingsProbe.markLaunchIfRequested()
        // The screenshot harness uses this to launch straight into either
        // palette; the Settings row writes the same key at runtime.
        let launchArguments = ProcessInfo.processInfo.arguments
        if let theme = launchArguments.firstIndex(of: "-BCTheme"),
           theme + 1 < launchArguments.count {
            UserDefaults.standard.set(launchArguments[theme + 1].uppercased(), forKey: Theme.modeKey)
        }
        appliedTheme = Theme.mode
        Theme.configureBars()
        applyStatusBarStyle()

        // The 320x568 capture run shrinks the window itself: same code, same
        // layout, the size an iPhone SE is actually given.
        let small = ProcessInfo.processInfo.arguments.contains("-BCSmallScreen")
        let frame = small ? CGRect(x: 0, y: 0, width: 320, height: 568) : UIScreen.main.bounds
        let window = UIWindow(frame: frame)
        window.backgroundColor = Theme.background
        window.rootViewController = RootViewController(nibName: nil, bundle: nil)
        window.makeKeyAndVisible()
        self.window = window
        if DiwaliGate.shouldPresent() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak window] in
                guard let root = window?.rootViewController,
                      root.presentedViewController == nil else { return }
                let greeting = DiwaliGreetingViewController()
                greeting.modalPresentationStyle = .fullScreen
                root.present(greeting, animated: false, completion: nil)
            }
        }
        CacheStore.shared.configure()
        applyReduceAnimation()
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(settingsChanged),
                                              name: .settingsDidChange,
                                              object: nil)
        // A cold launch from bitchord:// arrives in the launch options, before
        // any view has been asked to appear.
        if let url = launchOptions?[.url] as? URL {
            DeepLinkRouter.handle(url, cold: true)
        }
        // SpringBoard asks for confirmation before opening a custom scheme, and
        // a headless simulator cannot tap it. The CI launch feeds the same URL
        // through the same router from a cold process instead.
        let arguments = ProcessInfo.processInfo.arguments
        if let link = arguments.firstIndex(of: "-BCDeepLink"), link + 1 < arguments.count,
           let url = URL(string: arguments[link + 1]) {
            DeepLinkRouter.handle(url, cold: true)
        }
        ScreenshotHarness.runIfRequested()
        SettingsProbe.runIfRequested()
        // A saved remote playlist with "Keep downloads updated" on is refreshed
        // once the first screen has settled, without blocking launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            PlaylistSync.autoUpdate()
        }
        return true
    }

    private func applyReduceAnimation() {
        UIView.setAnimationsEnabled(!SettingsStore.shared.bool("BitChord.Appearance.ReduceAnimation", false))
    }

    @objc private func settingsChanged() {
        applyReduceAnimation()
        guard appliedTheme != Theme.mode else { return }
        appliedTheme = Theme.mode
        rebuildRootForTheme()
    }

    /// Upstream recomposes the whole tree when its Material theme changes. UIKit
    /// views resolve the palette in `viewDidLoad`, so the equivalent is a fresh
    /// root with the same stores and playback service still underneath it.
    private func rebuildRootForTheme() {
        guard let window = window else { return }
        let old = window.rootViewController
        old?.dismiss(animated: false, completion: nil)
        Theme.configureBars()
        applyStatusBarStyle()
        let root = RootViewController(nibName: nil, bundle: nil)
        UIView.transition(with: window, duration: 0.22,
                          options: [.transitionCrossDissolve, .allowAnimatedContent]) {
            window.rootViewController = root
            window.backgroundColor = Theme.background
        }
        old?.view.removeFromSuperview()
    }

    /// `Info.plist` opts out of view-controller status-bar appearance, so the
    /// palette has to drive the app-wide style directly. Midnight and the
    /// light theme need opposite status-bar glyphs.
    private func applyStatusBarStyle() {
        UIApplication.shared.statusBarStyle = Theme.isDark ? .lightContent : .default
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return DeepLinkRouter.handle(url, cold: false) != "invalid"
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL,
              DeepLink.parse(url) != nil else { return false }
        return DeepLinkRouter.handle(url, cold: false) != "invalid"
    }

    /// The system wakes the app for a finished background transfer and expects
    /// this handler to be held until the session has delivered its events.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        DownloadStore.shared.backgroundEventsCompletion = completionHandler
    }

    func applicationWillTerminate(_ application: UIApplication) {
        if SettingsStore.shared.bool("BitChord.Misc.StopOnCloseRecents", false) {
            PlayerService.shared.stopForTermination()
        }
    }
}
