import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let bar = UINavigationBar.appearance()
        bar.barTintColor = Theme.background
        bar.tintColor = Theme.accent
        bar.isTranslucent = false
        bar.titleTextAttributes = [.foregroundColor: UIColor.white]
        bar.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        let tableView = UITableView.appearance()
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.surface

        // The 320x568 capture run shrinks the window itself: same code, same
        // layout, the size an iPhone SE is actually given.
        let small = ProcessInfo.processInfo.arguments.contains("-BCSmallScreen")
        let frame = small ? CGRect(x: 0, y: 0, width: 320, height: 568) : UIScreen.main.bounds
        let window = UIWindow(frame: frame)
        window.backgroundColor = Theme.background
        window.rootViewController = RootViewController(nibName: nil, bundle: nil)
        window.makeKeyAndVisible()
        self.window = window
        CacheStore.shared.configure()
        // A cold launch from bitchord:// arrives in the launch options, before
        // any view has been asked to appear.
        if let url = launchOptions?[.url] as? URL {
            DeepLinkRouter.handle(url, cold: true)
        }
        ScreenshotHarness.runIfRequested()
        return true
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return DeepLinkRouter.handle(url, cold: false) != "invalid"
    }

    /// The system wakes the app for a finished background transfer and expects
    /// this handler to be held until the session has delivered its events.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        DownloadStore.shared.backgroundEventsCompletion = completionHandler
    }
}
