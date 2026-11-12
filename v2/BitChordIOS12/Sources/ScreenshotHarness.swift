import UIKit

/// Renders the tabs to PNGs when the app is launched with `-BCScreenshots <dir>`.
///
/// There is no iOS 12 runtime to look at and no Mac in hand, but the deployment
/// target is 12.0, so the app runs unchanged on the simulator the build machine
/// already has. This writes the screens out for the CI job to collect — the only
/// way to judge the interface without a device.
enum ScreenshotHarness {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-BCScreenshots"),
              flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        // Give Home and Explore a moment to make their network calls.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            capture(directory: directory)
        }
    }

    private static func capture(directory: URL) {
        guard let window = UIApplication.shared.keyWindow,
              let root = window.rootViewController as? RootViewController else { return }
        let names = ["home", "explore", "library", "search"]
        var index = 0
        var step: (() -> Void)?

        step = {
            guard index < names.count else {
                capturePlayer(window: window, root: root, directory: directory)
                return
            }
            let name = names[index]
            root.showTab(index)
            index += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                write(window: window, name: name, directory: directory)
                step?()
            }
        }
        step?()
    }

    /// Plays a track and photographs the lyrics panel, so the one screen whose
    /// look depends on a live provider is still judged from a capture.
    private static func capturePlayer(window: UIWindow, root: RootViewController, directory: URL) {
        CatalogueSearch.shared.songs("Blinding Lights The Weeknd") { tracks in
            guard let track = tracks.first else {
                exit(0)
            }
            PlayerService.shared.play(tracks: [track], startingAt: 0)
            root.presentNowPlayingFromRoot()
            // The vocal enters around half a minute in; seek there so the
            // capture shows the sweep mid-line instead of a silent intro.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                PlayerService.shared.seek(toFraction: 0.16)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if let player = root.presentedViewController as? NowPlayingViewController {
                    player.showLyricsForScreenshots()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    write(window: window, name: "lyrics", directory: directory)
                    guard let player = root.presentedViewController as? NowPlayingViewController else {
                        exit(0)
                    }
                    let settings = SettingsViewController()
                    settings.modalPresentationStyle = .fullScreen
                    player.present(settings, animated: false) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            write(window: window, name: "settings", directory: directory)
                            exit(0)
                        }
                    }
                }
            }
        }
    }

    private static func write(window: UIWindow, name: String, directory: URL) {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { return }
        try? data.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
