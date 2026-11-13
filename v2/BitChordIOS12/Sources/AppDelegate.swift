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

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = Theme.background
        window.rootViewController = RootViewController(nibName: nil, bundle: nil)
        window.makeKeyAndVisible()
        self.window = window
        ScreenshotHarness.runIfRequested()
        return true
    }

    /// The system wakes the app for a finished background transfer and expects
    /// this handler to be held until the session has delivered its events.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        DownloadStore.shared.backgroundEventsCompletion = completionHandler
    }
}
