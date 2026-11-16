import UIKit

/// Renders the tabs to PNGs when the app is launched with `-BCScreenshots <dir>`.
///
/// There is no iOS 12 runtime to look at and no Mac in hand, but the deployment
/// target is 12.0, so the app runs unchanged on the simulator the build machine
/// already has. This writes the screens out for the CI job to collect — the only
/// way to judge the interface without a device.
enum ScreenshotHarness {
    static func runIfRequested() {
        MotionHarness.runIfRequested()
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-BCScreenshots"),
           index + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            writeText("started", name: "screens-launched.txt", directory: directory)
        }
        // The Google handoff has its own multi-launch fixture: sign in through
        // the real browser/controller, relaunch to restore, sign out, then
        // relaunch again to prove the stored session is gone.
        if let fixture = arguments.firstIndex(of: "-BCSignInStage"), fixture + 3 < arguments.count {
            runSignInStage(directory: URL(fileURLWithPath: arguments[fixture + 1], isDirectory: true),
                           mode: arguments[fixture + 2],
                           stage: arguments[fixture + 3])
            return
        }
        // A first launch downloads one track and exits; CI then relaunches with
        // -BCScreenshots, so the capture proves the index survived a restart
        // rather than reading back this process's memory.
        if let seed = arguments.firstIndex(of: "-BCSeedDownload"), seed + 1 < arguments.count {
            seedDownload(directory: URL(fileURLWithPath: arguments[seed + 1], isDirectory: true))
            return
        }
        // Background transfers get their own launch pair: start one and quit,
        // then launch again and see what the system delivered.
        if let start = arguments.firstIndex(of: "-BCBackgroundStart"), start + 1 < arguments.count {
            // `keep` leaves the process alive so CI can background it and bring
            // it back; without it the run exits while the transfer is live.
            let keep = arguments.count > start + 2 && arguments[start + 2] == "keep"
            backgroundStart(directory: URL(fileURLWithPath: arguments[start + 1], isDirectory: true),
                            keep: keep)
            return
        }
        if let verify = arguments.firstIndex(of: "-BCBackgroundVerify"), verify + 1 < arguments.count {
            // An optional label keeps the two scenarios' reports apart: one where
            // the app is only backgrounded, one where it is killed outright.
            let label = arguments.count > verify + 2 ? arguments[verify + 2] : "verify"
            backgroundVerify(directory: URL(fileURLWithPath: arguments[verify + 1], isDirectory: true),
                             label: label)
            return
        }
        // A separate 320x568 launch for the Jellyfin browser.
        if let flag = arguments.firstIndex(of: "-BCJellyfinOnly"), flag + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                captureJellyfinOnly(directory: directory)
            }
            return
        }
        // The light palette is a separate launch because the real Settings row
        // rebuilds the root; this proves the persisted choice is honoured from
        // a cold start and photographs the same screens in the other palette.
        if let flag = arguments.firstIndex(of: "-BCThemeScreens"), flag + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
            OnboardingViewController.complete(path: "local")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                captureTheme(directory: directory)
            }
            return
        }
        // The web-form routes are parser/router behaviour, not a SpringBoard
        // handoff: exercise the same `DeepLink.parse` the universal-link
        // callback uses, without asking `simctl` to pass a query-bearing
        // https URL through `launch`.
        if let flag = arguments.firstIndex(of: "-BCWebLinks"), flag + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
            captureWebLinks(directory: directory)
            return
        }
        // A 320x568 pass over the live tabs and the player. This runs with
        // -BCSmallScreen, so the same code and constraints are exercised at the
        // width where the fixed-size Explore rows and player stack used to fail.
        if let flag = arguments.firstIndex(of: "-BCSmallScreens"), flag + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
            // This pass photographs the tabs, not onboarding.
            OnboardingViewController.complete(path: "local")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                captureCompact(directory: directory)
            }
            return
        }
        // A separate 320x568 launch just for the first-run flow.
        if let flag = arguments.firstIndex(of: "-BCOnboardingOnly"), flag + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
            OnboardingViewController.reset()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                captureOnboardingOnly(directory: directory)
            }
            return
        }
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

    /// Drives the Google → YouTube Music handoff without a live Google account.
    /// The browser still visits Google's origin, redirects to the music origin,
    /// and reads cookies from the web view's own store, so this exercises the
    /// same controller and data path that a real login uses.
    private static func runSignInStage(directory: URL, mode: String, stage: String) {
        guard let window = UIApplication.shared.keyWindow,
              let root = window.rootViewController as? RootViewController,
              let shell = GoogleHandoffFixture.Shell(rawValue: mode) else {
            writeText("handoff.absent=true", name: "handoff-\(mode)-\(stage).txt", directory: directory)
            exit(1)
            return
        }
        OnboardingViewController.complete(path: "local")
        switch stage {
        case "handoff":
            signInHandoff(window: window, root: root, shell: shell, directory: directory)
        case "restore":
            signInRestore(window: window, root: root, mode: mode, directory: directory)
        case "signout":
            signInSignOut(window: window, root: root, mode: mode, directory: directory)
        case "verify":
            signInSignedOut(window: window, root: root, mode: mode, directory: directory)
        default:
            writeText("handoff.stage=unknown", name: "handoff-\(mode)-\(stage).txt", directory: directory)
            exit(1)
        }
    }

    private static func signInHandoff(window: UIWindow,
                                      root: RootViewController,
                                      shell: GoogleHandoffFixture.Shell,
                                      directory: URL) {
        // Clear the old keychain item and browser jar, then seed only the
        // fixture's Google/YouTube cookies immediately before the browser runs.
        GoogleAccountStore.shared.signOut {
            DispatchQueue.main.async {
                GoogleHandoffFixture.active = GoogleHandoffFixture(shell: shell)
                GoogleAccountStore.shared.presentSignIn(from: root)
                DispatchQueue.main.asyncAfter(deadline: .now() + 22) {
                    guard !GoogleAccountStore.shared.isSignedIn else { return }
                    let probe = GoogleHandoffFixture.probe
                    var report: [String] = []
                    report.append("handoff.path=\(shell.rawValue)")
                    report.append("handoff.timeout=true")
                    report.append("handoff.probe.loginOrigin=\(probe.loginOrigin)")
                    report.append("handoff.probe.shellOrigin=\(probe.shellOrigin)")
                    report.append("handoff.probe.shellBlank=\(probe.documentBlank)")
                    report.append("handoff.probe.ytcfg=\(probe.pageConfigRead)")
                    report.append("handoff.probe.networkFallback=\(probe.networkFallbackUsed)")
                    report.append("handoff.probe.networkCookie=\(probe.networkHadCookie)")
                    report.append("handoff.signedIn=false")
                    report.append("handoff.completed=false")
                    write(window: window,
                          name: "signed-in-home-\(shell.rawValue)",
                          directory: directory)
                    writeText(report.joined(separator: "\n"),
                              name: "handoff-report-\(shell.rawValue).txt",
                              directory: directory)
                    writeText("done",
                              name: "handoff-done-\(shell.rawValue).txt",
                              directory: directory)
                    exit(0)
                }
                waitUntil({
                    root.presentedViewController == nil && GoogleAccountStore.shared.isSignedIn
                }, timeout: 35) { finished in
                    after(1.0) {
                        let store = GoogleAccountStore.shared
                        let probe = GoogleHandoffFixture.probe
                        let home = root.navigationForTab(0)?.viewControllers.first as? HomeViewController
                        let homeVisible = home?.isSignedInFeedVisible ?? false
                        var report: [String] = []
                        report.append("handoff.path=\(shell.rawValue)")
                        report.append("handoff.probe.loginOrigin=\(probe.loginOrigin)")
                        report.append("handoff.probe.shellOrigin=\(probe.shellOrigin)")
                        report.append("handoff.probe.shellBlank=\(probe.documentBlank)")
                        report.append("handoff.probe.ytcfg=\(probe.pageConfigRead)")
                        report.append("handoff.probe.networkFallback=\(probe.networkFallbackUsed)")
                        report.append("handoff.probe.networkCookie=\(probe.networkHadCookie)")
                        report.append("handoff.probe.documentCookie=\(probe.documentCookie)")
                        report.append("handoff.document.youtubeCookie=\(probe.documentCookie.contains("BC_VISIBLE=1"))")
                        report.append("handoff.document.googleCookie=\(probe.documentCookie.contains("GOOGLE_ONLY=1"))")
                        report.append("handoff.dismissed=\(root.presentedViewController == nil)")
                        report.append("handoff.signedIn=\(store.isSignedIn)")
                        report.append("handoff.authUser=\(store.authUser)")
                        report.append("handoff.dataSync=\(store.dataSyncId ?? "")")
                        report.append("handoff.accountName=\(store.displayName)")
                        report.append("handoff.homeVisible=\(homeVisible)")
                        report.append("handoff.cookieHeader=\(store.requestHeaders()["Cookie"] != nil)")
                        report.append("handoff.persistence=\(store.usesSimulatorFallback ? "simulator-fallback" : "keychain")")
                        report.append("handoff.keychainStatus=\(Keychain.lastStatus)")
                        report.append("handoff.completed=\(finished)")
                        report.append("handoff.accountVisible=\(!store.displayName.isEmpty)")
                        write(window: window, name: "signed-in-home-\(shell.rawValue)", directory: directory)
                        writeText(report.joined(separator: "\n"),
                                  name: "handoff-report-\(shell.rawValue).txt",
                                  directory: directory)
                        writeText("done",
                                  name: "handoff-done-\(shell.rawValue).txt",
                                  directory: directory)
                        exit(0)
                    }
                }
            }
        }
    }

    private static func signInRestore(window: UIWindow,
                                      root: RootViewController,
                                      mode: String,
                                      directory: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let store = GoogleAccountStore.shared
            let home = root.navigationForTab(0)?.viewControllers.first as? HomeViewController
            let homeVisible = home?.isSignedInFeedVisible ?? false
            var report: [String] = []
            report.append("restore.signedIn=\(store.isSignedIn)")
            report.append("restore.authUser=\(store.authUser)")
            report.append("restore.dataSync=\(store.dataSyncId ?? "")")
            report.append("restore.cookieHeader=\(store.requestHeaders()["Cookie"] != nil)")
            report.append("restore.persistence=\(store.usesSimulatorFallback ? "simulator-fallback" : "keychain")")
            report.append("restore.keychainStatus=\(Keychain.lastStatus)")
            report.append("restore.homeVisible=\(homeVisible)")
            report.append("restore.requiresSignIn=\(!store.isSignedIn)")
            write(window: window, name: "signed-in-home-restored-\(mode)", directory: directory)
            writeText(report.joined(separator: "\n"),
                      name: "restore-report-\(mode).txt",
                      directory: directory)
            writeText("done", name: "restore-done-\(mode).txt", directory: directory)
            exit(0)
        }
    }

    private static func signInSignOut(window: UIWindow,
                                      root: RootViewController,
                                      mode: String,
                                      directory: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let account = AccountViewController()
            root.present(chrome(account), animated: false) {
                after(0.5) {
                    var report: [String] = []
                    report.append("signout.startedSignedIn=\(GoogleAccountStore.shared.isSignedIn)")
                    write(window: window, name: "signed-in-account-signout-\(mode)", directory: directory)
                    account.signOutForCapture()
                    after(0.7) {
                        report.append("signout.cleared=\(!GoogleAccountStore.shared.isSignedIn)")
                        report.append("signout.signedOutScreen=\(account.isShowingSignIn)")
                        report.append("signout.cookieHeader=\(GoogleAccountStore.shared.requestHeaders()["Cookie"] != nil)")
                        write(window: window, name: "signed-out-account-\(mode)", directory: directory)
                        root.dismiss(animated: false) {
                            after(0.6) {
                                let home = root.navigationForTab(0)?.viewControllers.first as? HomeViewController
                                report.append("signout.homePrompt=\(home?.isSignInPromptVisible ?? false)")
                                write(window: window, name: "signed-out-home-signout-\(mode)", directory: directory)
                                writeText(report.joined(separator: "\n"),
                                          name: "signout-report-\(mode).txt",
                                          directory: directory)
                                writeText("done", name: "signout-done-\(mode).txt", directory: directory)
                                exit(0)
                            }
                        }
                    }
                }
            }
        }
    }

    private static func signInSignedOut(window: UIWindow,
                                        root: RootViewController,
                                        mode: String,
                                        directory: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let home = root.navigationForTab(0)?.viewControllers.first as? HomeViewController
            var report: [String] = []
            report.append("verify.signedIn=\(GoogleAccountStore.shared.isSignedIn)")
            report.append("verify.cookieHeader=\(GoogleAccountStore.shared.requestHeaders()["Cookie"] != nil)")
            report.append("verify.signInPrompt=\(home?.isSignInPromptVisible ?? false)")
            write(window: window, name: "signed-out-home-verify-\(mode)", directory: directory)
            writeText(report.joined(separator: "\n"),
                      name: "verify-report-\(mode).txt",
                      directory: directory)
            writeText("done", name: "verify-done-\(mode).txt", directory: directory)
            // The handoff fixture suppresses first-run onboarding while it
            // drives the account flow. Put the app back on a first-run state
            // so the later screenshot pass still captures onboarding.
            OnboardingViewController.reset()
            exit(0)
        }
    }

    private static func capture(directory: URL) {
        guard let window = UIApplication.shared.keyWindow,
              let root = window.rootViewController as? RootViewController else { return }
        let capture = DownloadCapture(window: window, root: root, directory: directory)
        let begin = { captureTabs(window: window, root: root, directory: directory) }
        if let onboarding = root.presentedViewController as? OnboardingViewController {
            captureOnboarding(onboarding, capture: capture, completion: begin)
        } else {
            begin()
        }
    }

    /// Cold-start capture of the persisted theme. The app was launched with
    /// `-BCTheme light`, so every view here is built from the light palette.
    private static func captureTheme(directory: URL) {
        guard let window = UIApplication.shared.keyWindow,
              let root = window.rootViewController as? RootViewController else {
            writeText("theme.absent=true", name: "theme-report.txt", directory: directory)
            exit(0)
            return
        }
        var report: [String] = []
        report.append("theme.mode=\(Theme.mode.rawValue)")
        report.append("theme.dark=\(Theme.isDark)")
        report.append("theme.backgroundLight=\(Theme.background == UIColor.white)")
        report.append("theme.textDark=\(Theme.primaryText == UIColor.black)")
        let writeShot = { (name: String) in write(window: window, name: name, directory: directory) }
        root.showTab(0)
        after(1.2) {
            writeShot("theme-home-light")
            let settings = SettingsViewController()
            root.present(chrome(settings), animated: false) {
                after(0.8) {
                    writeShot("theme-settings-light")
                    report.append("theme.settingsBackgroundLight=\(settings.view.backgroundColor == UIColor.white)")
                    root.dismiss(animated: false) {
                        let account = AccountViewController()
                        root.present(chrome(account), animated: false) {
                            after(0.8) {
                                writeShot("theme-account-light")
                                report.append("theme.accountBackgroundLight=\(account.view.backgroundColor == UIColor.white)")
                                let finish = {
                                    writeText(report.joined(separator: "\n"),
                                              name: "theme-report.txt", directory: directory)
                                    writeText("done", name: "theme-done.txt", directory: directory)
                                    // Leave the next harness launch on the normal
                                    // Midnight palette rather than leaking this
                                    // test-only launch argument into it.
                                    UserDefaults.standard.set(Theme.Mode.dark.rawValue, forKey: Theme.modeKey)
                                    exit(0)
                                }
                                report.append("theme.appIconSupported=\(UIApplication.shared.supportsAlternateIcons)")
                                guard UIApplication.shared.supportsAlternateIcons else { finish(); return }
                                report.append("theme.appIconAttempt=true")
                                AppIconChoice.apply("Monochrome") { error in
                                    report.append("theme.appIconError=\(error ?? "")_")
                                    report.append("theme.appIconAlternate=\(UIApplication.shared.alternateIconName ?? "Default")")
                                    AppIconChoice.apply("Default") { _ in finish() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The first-run flow, photographed step by step before the tabs are shown.
    private static func captureOnboarding(_ onboarding: OnboardingViewController,
                                         capture: DownloadCapture,
                                         completion: @escaping () -> Void) {
        // The tab capture below builds its own DownloadCapture and rewrites the
        // main report, so the first-run proof goes to its own file.
        var lines: [String] = ["onboarding.shown=true"]
        func save() {
            writeText(lines.joined(separator: "\n"), name: "onboarding-report.txt", directory: capture.directory)
        }
        lines.append("onboarding.step1=\(onboarding.stepTitle)")
        save()
        capture.shot("onboarding-welcome")
        onboarding.advanceForCapture()
        after(0.5) {
            lines.append("onboarding.step2=\(onboarding.stepTitle)")
            save()
            capture.shot("onboarding-tour")
            onboarding.advanceForCapture()
            after(0.5) {
                lines.append("onboarding.step3=\(onboarding.stepTitle)")
                save()
                capture.shot("onboarding-library")
                onboarding.chooseLocalForCapture()
                after(0.5) {
                    lines.append("onboarding.step4=\(onboarding.stepTitle)")
                    save()
                    capture.shot("onboarding-ready")
                    onboarding.advanceForCapture()
                    after(0.8) {
                        lines.append("onboarding.completed=\(OnboardingViewController.hasCompleted)")
                        lines.append("onboarding.dismissed=\(capture.root.presentedViewController == nil)")
                        save()
                        capture.checkpoint()
                        completion()
                    }
                }
            }
        }
    }

    /// A 320x568 launch: the same flow, checking every control lands on screen.
    private static func captureOnboardingOnly(directory: URL) {
        guard let window = UIApplication.shared.keyWindow,
              let root = window.rootViewController as? RootViewController,
              let onboarding = root.presentedViewController as? OnboardingViewController else {
            writeText("onboarding.absent=true", name: "onboarding-small-report.txt", directory: directory)
            exit(0)
            return
        }
        var report: [String] = []
        report.append("onboarding.shown=true")
        report.append("onboarding.window=\(Int(window.bounds.width))x\(Int(window.bounds.height))")
        let within = { (controller: OnboardingViewController) -> Bool in
            let frame = controller.primaryFrameInWindow
            return frame.maxY <= controller.view.bounds.height + 0.5 && frame.maxY <= window.bounds.height
        }
        report.append("onboarding.primaryVisible=\(within(onboarding))")
        write(window: window, name: "onboarding-small-welcome", directory: directory)
        report.append("onboarding.step1=\(onboarding.stepTitle)")
        onboarding.advanceForCapture()
        after(0.3) {
            report.append("onboarding.step2=\(onboarding.stepTitle)")
            report.append("onboarding.primaryVisible2=\(within(onboarding))")
            write(window: window, name: "onboarding-small-tour", directory: directory)
            onboarding.advanceForCapture()
            after(0.3) {
                report.append("onboarding.step3=\(onboarding.stepTitle)")
                report.append("onboarding.primaryVisible3=\(within(onboarding))")
                write(window: window, name: "onboarding-small-library", directory: directory)
                onboarding.chooseLocalForCapture()
                after(0.3) {
                    report.append("onboarding.step4=\(onboarding.stepTitle)")
                    report.append("onboarding.primaryVisible4=\(within(onboarding))")
                    write(window: window, name: "onboarding-small-ready", directory: directory)
                    onboarding.advanceForCapture()
                    after(0.8) {
                        report.append("onboarding.completed=\(OnboardingViewController.hasCompleted)")
                        report.append("onboarding.dismissed=\(root.presentedViewController == nil)")
                        writeText(report.joined(separator: "\n"), name: "onboarding-small-report.txt", directory: directory)
                        exit(0)
                    }
                }
            }
        }
    }

    /// The Jellyfin browser at 320x568: sign in, list the library, photograph it.
    private static func captureJellyfinOnly(directory: URL) {
        guard let window = UIApplication.shared.keyWindow,
              let root = window.rootViewController as? RootViewController else {
            writeText("jellyfin.absent=true", name: "jellyfin-small-report.txt", directory: directory)
            exit(0)
            return
        }
        let environment = ProcessInfo.processInfo.environment
        guard let base = environment["BC_JELLYFIN_URL"], !base.isEmpty else {
            writeText("jellyfin.env=false", name: "jellyfin-small-report.txt", directory: directory)
            exit(0)
            return
        }
        let controller = JellyfinViewController()
        // Same chrome as the main capture, so the small screen shows the nav
        // title instead of the removed in-form header.
        root.present(chrome(controller), animated: false) {
            after(0.5) {
                controller.signInForCapture(url: base,
                                            username: environment["BC_JELLYFIN_USER"] ?? "",
                                            password: environment["BC_JELLYFIN_PASS"] ?? "")
                waitUntil({ !controller.isBusy && !controller.entryNames.isEmpty }, timeout: 25) { listed in
                    var report: [String] = []
                    report.append("jellyfin.window=\(Int(window.bounds.width))x\(Int(window.bounds.height))")
                    report.append("jellyfin.listed=\(listed)")
                    report.append("jellyfin.items=\(controller.entryNames.joined(separator: "|"))")
                    report.append("jellyfin.tableVisible=\(controller.view.bounds.height > 300)")
                    writeText(report.joined(separator: "\n"), name: "jellyfin-small-report.txt", directory: directory)
                    write(window: window, name: "jellyfin-small", directory: directory)
                    exit(0)
                }
            }
        }
    }

    /// The compact pass: every tab, the player and the account page at the
    /// smallest supported size. It reports geometry rather than trusting the
    /// PNGs, so a clipped control fails CI even if the still looks plausible.
    private static func captureCompact(directory: URL) {
        guard let window = UIApplication.shared.keyWindow,
              let root = window.rootViewController as? RootViewController else {
            writeText("compact.absent=true", name: "small-report.txt", directory: directory)
            exit(0)
            return
        }
        var report: [String] = []
        report.append("small.window=\(Int(window.bounds.width))x\(Int(window.bounds.height))")
        report.append("auth.signedIn=\(GoogleAccountStore.shared.isSignedIn)")
        report.append("auth.browserFlow=google-web-session")
        report.append("auth.hasCookie=\(GoogleAccountStore.shared.requestHeaders()["Cookie"] != nil)")
        let spotifyLink = "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc"
        let spotifyURI = "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"
        let foreignPlaylist = "https://example.com/playlist/37i9dQZF1DXcBWIGoYBM5M"
        let spotifyID = SpotifyImporter.extractPlaylistID(spotifyLink)
        let spotifyLinkOK = spotifyID == "37i9dQZF1DXcBWIGoYBM5M"
        let spotifyURIOK = SpotifyImporter.extractPlaylistID(spotifyURI) != nil
        let spotifyRejectOK = SpotifyImporter.extractPlaylistID(foreignPlaylist) == nil
        let dataSyncOK = GoogleAccountStore.normalizeDataSyncID("page||account") == "account"
        report.append("spotify.link=\(spotifyLinkOK)")
        report.append("spotify.uri=\(spotifyURIOK)")
        report.append("spotify.reject=\(spotifyRejectOK)")
        report.append("auth.dataSyncNormalize=\(dataSyncOK)")

        func shot(_ name: String) {
            write(window: window, name: name, directory: directory)
        }

        root.showTab(0)
        after(1.2) {
            shot("small-home")
            report.append("home.visible=\(window.bounds.width > 300)")
            root.showTab(1)
            after(1.2) {
                shot("small-explore")
                let explore = root.children.compactMap { $0 as? UINavigationController }
                    .compactMap { $0.viewControllers.first as? ExploreViewController }
                    .first
                if let tile = explore?.motionFirstTileFrame(in: window), tile.width > 0 {
                    let ratio = tile.height / tile.width
                    report.append(String(format: "explore.tile=%.1f,%.1f,%.1f,%.1f",
                                         tile.origin.x, tile.origin.y, tile.width, tile.height))
                    report.append(String(format: "explore.ratio=%.3f", ratio))
                    report.append("explore.ratioOk=\(abs(ratio - 1.0 / 1.72) < 0.035)")
                    report.append("explore.within=\(tile.maxX <= window.bounds.width + 0.5)")
                } else {
                    report.append("explore.ratioOk=false")
                    report.append("explore.within=false")
                }
                root.showTab(2)
                after(1.2) {
                    shot("small-library")
                    report.append("library.visible=\(window.bounds.width > 300)")
                    root.showTab(3)
                    after(1.2) {
                        shot("small-search")
                        report.append("search.visible=\(window.bounds.width > 300)")
                        captureCompactPlayer(window: window, root: root, directory: directory,
                                             report: report)
                    }
                }
            }
        }
    }

    private static func captureCompactPlayer(window: UIWindow,
                                             root: RootViewController,
                                             directory: URL,
                                             report: [String]) {
        var report = report
        CatalogueSearch.shared.songs("Blinding Lights The Weeknd") { tracks in
            guard let track = tracks.first else {
                report.append("small.player=false")
                writeText(report.joined(separator: "\n"), name: "small-report.txt", directory: directory)
                exit(0)
                return
            }
            PlayerService.shared.play(tracks: [track], startingAt: 0)
            root.presentNowPlayingFromRoot()
            after(2.5) {
                guard let player = root.presentedViewController as? NowPlayingViewController else {
                    report.append("small.player=false")
                    writeText(report.joined(separator: "\n"), name: "small-report.txt", directory: directory)
                    exit(0)
                    return
                }
                write(window: window, name: "small-now-playing", directory: directory)
                let frames = player.layoutFrames(in: window)
                if let play = frames["play"], let like = frames["like"],
                   let previous = frames["previous"], let next = frames["next"],
                   let artwork = frames["artwork"], let output = frames["output"] {
                    report.append(String(format: "player.play=%.1f,%.1f,%.1f,%.1f",
                                         play.origin.x, play.origin.y, play.width, play.height))
                    report.append(String(format: "player.footerTop=%.1f", like.minY))
                    report.append("player.noOverlap=\(play.maxY <= like.minY - 2)")
                    report.append("player.transportFits=\(previous.minX >= -0.5 && next.maxX <= window.bounds.width + 0.5)")
                    report.append("player.artworkFits=\(artwork.maxY <= window.bounds.height)")
                    report.append("player.outputFits=\(output.maxY <= window.bounds.height + 0.5)")
                    report.append("player.fits=\(play.maxY <= like.minY - 2 && previous.minX >= -0.5 && next.maxX <= window.bounds.width + 0.5 && output.maxY <= window.bounds.height + 0.5)")
                } else {
                    report.append("player.fits=false")
                }
                let track = PlayerService.shared.currentTrack
                if let track = track {
                    TrackActions.present(for: track, from: player, sourceView: nil)
                }
                after(1.0) {
                    write(window: window, name: "small-song-actions", directory: directory)
                    TrackActions.topController()?.dismiss(animated: false) {
                        root.dismiss(animated: false) {
                            let account = AccountViewController()
                            account.modalPresentationStyle = .fullScreen
                            root.present(chrome(account), animated: false) {
                                after(1.0) {
                                    write(window: window, name: "small-account", directory: directory)
                                    report.append("auth.accountSheet=\(account.isShowingSignedOut || GoogleAccountStore.shared.isSignedIn)")
                                    account.dismiss(animated: false) {
                                        let settings = SettingsViewController()
                                        root.present(chrome(settings), animated: false) {
                                            after(0.8) {
                                                write(window: window, name: "small-settings", directory: directory)
                                                report.append("small.done=true")
                                                writeText(report.joined(separator: "\n"),
                                                          name: "small-report.txt", directory: directory)
                                                try? "done".write(to: directory.appendingPathComponent("small-done.txt"),
                                                                  atomically: true, encoding: .utf8)
                                                after(0.4) { exit(0) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func captureTabs(window: UIWindow, root: RootViewController, directory: URL) {
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
            let savedAnimated = SettingsStore.shared.bool("BitChord.Appearance.AnimatedCover", false)
            let savedCellular = SettingsStore.shared.bool("BitChord.Appearance.AnimatedCoverCellular", true)
            let savedReduce = SettingsStore.shared.bool("BitChord.Appearance.ReduceAnimation", false)
            let savedEQ = SettingsStore.shared.string("BitChord.Audio.Equalizer", "Off")
            SettingsStore.shared.set(true, for: "BitChord.Appearance.AnimatedCover")
            SettingsStore.shared.set(true, for: "BitChord.Appearance.AnimatedCoverCellular")
            SettingsStore.shared.set(false, for: "BitChord.Appearance.ReduceAnimation")
            SettingsStore.shared.set("Bass boost", for: "BitChord.Audio.Equalizer")
            PlayerService.shared.play(tracks: [track], startingAt: 0)
            root.presentNowPlayingFromRoot()
            // The vocal enters around half a minute in; seek there so the
            // capture shows the sweep mid-line instead of a silent intro.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                PlayerService.shared.seek(toFraction: 0.16)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                write(window: window, name: "now-playing", directory: directory)
                if let player = root.presentedViewController as? NowPlayingViewController {
                    write(window: window, name: "animated-cover", directory: directory)
                    writeText("animatedCover.active=\(player.artworkMotionActiveForScreenshots())\n"
                                + "animatedCover.setting=\(SettingsStore.shared.bool("BitChord.Appearance.AnimatedCover", false))\n",
                              name: "animated-cover.txt", directory: directory)
                }
                SettingsStore.shared.set(savedAnimated, for: "BitChord.Appearance.AnimatedCover")
                SettingsStore.shared.set(savedCellular, for: "BitChord.Appearance.AnimatedCoverCellular")
                SettingsStore.shared.set(savedReduce, for: "BitChord.Appearance.ReduceAnimation")
            }
            // The tap installs after the item's tracks load, which can lag the
            // fixed capture timer on a slow catalogue response. Poll for the
            // first processed buffer so this file is a live proof rather than
            // a race against the network; the deterministic renderer proof is
            // still checked separately in the settings probe.
            func emitDSP(_ attempt: Int) {
                let frames = AudioDSP.shared.processedFrames
                guard frames > 0 || attempt >= 20 else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        emitDSP(attempt + 1)
                    }
                    return
                }
                writeText("dsp.tapAttached=\(AudioDSP.shared.tapAttached)\n"
                            + "dsp.processedFrames=\(AudioDSP.shared.processedFrames)\n"
                            + "dsp.lastRMS=\(AudioDSP.shared.lastRMS)\n"
                            + "dsp.lastGain=\(AudioDSP.shared.lastGain)\n",
                          name: "dsp-playback.txt", directory: directory)
                SettingsStore.shared.set(savedEQ, for: "BitChord.Audio.Equalizer")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { emitDSP(0) }
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
                            settings.scrollToDownloadSection()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                write(window: window, name: "settings-downloads", directory: directory)
                                captureDownloads(window: window, root: root, directory: directory)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Downloads

    /// Downloads one track and writes what happened beside the screenshots.
    private static func seedDownload(directory: URL) {
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        var report = ["seed: start"]
        CatalogueSearch.shared.songs("Blinding Lights The Weeknd") { tracks in
            guard let track = tracks.first else {
                report.append("seed: no search results")
                writeReport(report.joined(separator: "\n"), directory: directory)
                exit(0)
            }
            report.append("seed: track \(track.title) / \(track.artist)")
            if DownloadStore.shared.isDownloaded(track.videoID) {
                report.append("seed: already downloaded")
                writeReport(report.joined(separator: "\n"), directory: directory)
                exit(0)
            }
            DownloadStore.shared.download(track) { ok, message in
                report.append("seed: download ok=\(ok) message=\(message)")
                report.append("seed: transport=\(DownloadStore.shared.transport[track.videoID] ?? "") (background session)")
                report.append("seed: saved=\(DownloadStore.shared.saved.count)")
                report.append("seed: bytes=\(DownloadStore.shared.totalBytes)")
                if let url = DownloadStore.shared.localURL(for: track.videoID) {
                    report.append("seed: file=\(url.lastPathComponent)")
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                    report.append("seed: fileBytes=\(size)")
                } else {
                    report.append("seed: no local file")
                }
                writeReport(report.joined(separator: "\n"), directory: directory)
                exit(0)
            }
        }
        // A 320kbps file over a cold CI runner can take a while; give the
        // background session enough room to finish before calling it a miss.
        DispatchQueue.main.asyncAfter(deadline: .now() + 240) {
            report.append("seed: timed out")
            writeReport(report.joined(separator: "\n"), directory: directory)
            exit(0)
        }
    }

    /// Photographs the Downloads screen, then plays the saved file and
    /// photographs the player — recording whether the engine really took the
    /// local path rather than a stream. The saved track here was written by the
    /// seed launch, so finding it is the relaunch proof.
    private static func captureDownloads(window: UIWindow, root: RootViewController, directory: URL) {
        let capture = DownloadCapture(window: window, root: root, directory: directory)
        root.dismiss(animated: false) {
            let downloads = DownloadsViewController()
            downloads.modalPresentationStyle = .fullScreen
            root.present(downloads, animated: false) {
                after(2) { captureResume(capture, downloads: downloads) }
            }
        }
    }

    /// The state the seed left behind, offline playback, then deletion.
    private static func captureResume(_ capture: DownloadCapture, downloads: DownloadsViewController) {
        let store = capture.store
        capture.report.append("resume.saved=\(store.saved.count)")
        capture.report.append("resume.totalBytes=\(store.totalBytes)")
        guard let item = store.saved.first,
              let fileURL = store.localURL(for: item.track.videoID) else {
            capture.report.append("resume.missing=true")
            capture.shot("downloads")
            capture.finish()
            return
        }
        capture.seedTrack = item.track
        capture.highBytes = item.byteSize
        capture.report.append("quality.high.bytes=\(item.byteSize)")
        capture.report.append("quality.high.label=\(item.qualityLabel)")
        capture.shot("downloads")
        // Keep the 320 file so the CI runner can measure it with afinfo.
        copy(fileURL, to: capture.directory.appendingPathComponent("quality-high.m4a"))
        capture.checkpoint()

        PlayerService.shared.play(tracks: [item.track], startingAt: 0)
        after(6) {
            capture.report.append("localPlayback=\(AudioEngine.shared.currentIsLocal)")
            capture.report.append("source=\(AudioEngine.shared.currentSourceLabel)")
            downloads.dismiss(animated: false) { capture.root.presentNowPlaying() }
            after(3) {
                capture.shot("offline")
                let path = store.localURL(for: item.track.videoID)
                store.remove(item.track.videoID)
                capture.report.append("deletedRows=\(store.saved.count)")
                capture.report.append("fileRemoved=\(path.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false)")
                capture.checkpoint()
                capture.root.dismiss(animated: false) {
                    let empty = DownloadsViewController()
                    empty.modalPresentationStyle = .fullScreen
                    capture.root.present(empty, animated: false) {
                        after(1) {
                            capture.shot("downloads-empty")
                            startQualityProbe(capture, host: empty)
                        }
                    }
                }
            }
        }
    }

    /// Downloads the same track again at Data saver, photographs the transfer
    /// mid-flight, then records what was stored.
    private static func startQualityProbe(_ capture: DownloadCapture, host: UIViewController) {
        guard let track = capture.seedTrack else {
            capture.finish()
            return
        }
        // The same key the Settings row writes, through the same store.
        SettingsStore.shared.set(DownloadQuality.dataSaver.rawValue,
                                 for: "BitChord.Download.Quality")
        capture.report.append("quality.setting=\(SettingsStore.shared.string("BitChord.Download.Quality", ""))")
        // ~75 chunks for a 2.4 MB file at 96 kbps, so the transfer lasts long
        // enough to photograph at a real percentage.
        capture.store.progressPace = 0.08
        capture.store.download(track) { ok, message in
            capture.report.append("quality.saver.ok=\(ok)")
            if !ok { capture.report.append("quality.saver.message=\(message)") }
        }
        after(1.2) {
            snapProgress(capture, track: track, attempt: 0) {
                waitUntil({ capture.store.isDownloaded(track.videoID)
                            || capture.store.failure(for: track.videoID) != nil },
                          timeout: 90) { finished in
                    capture.store.progressPace = 0
                    guard finished, let item = capture.store.savedItem(for: track.videoID),
                          let url = capture.store.localURL(for: track.videoID) else {
                        capture.report.append("quality.saver.missing=true")
                        capture.finish()
                        return
                    }
                    capture.saverBytes = item.byteSize
                    capture.report.append("quality.saver.bytes=\(item.byteSize)")
                    capture.report.append("quality.saver.label=\(item.qualityLabel)")
                    capture.report.append("quality.saverSmaller=\(item.byteSize < capture.highBytes)")
                    copy(url, to: capture.directory.appendingPathComponent("quality-saver.m4a"))
                    capture.shot("downloads-saver")
                    capture.checkpoint()
                    captureSettings(capture, host: host)
                }
            }
        }
    }

    /// Waits for a percentage that is clearly mid-transfer, then shoots it. The
    /// last real partial value is kept, so a transfer that outruns the camera
    /// still gets the best frame it produced rather than a 0% one.
    private static func snapProgress(_ capture: DownloadCapture, track: Track, attempt: Int,
                                     best: Double = 0, then: @escaping () -> Void) {
        let fraction = capture.store.progress(for: track.videoID) ?? 0
        let partial = fraction > 0 && fraction < 0.98 ? fraction : 0
        let bestNow = max(best, partial)
        if bestNow >= 0.2 || attempt >= 12 {
            let percent = Int((bestNow * 100).rounded())
            capture.report.append("progress.captured=\(percent)")
            capture.shot("download-progress")
            then()
            return
        }
        after(0.6) {
            snapProgress(capture, track: track, attempt: attempt + 1, best: bestNow, then: then)
        }
    }

    private static func captureSettings(_ capture: DownloadCapture, host: UIViewController) {
        let settings = SettingsViewController()
        settings.modalPresentationStyle = .fullScreen
        host.present(settings, animated: false) {
            after(0.8) {
                settings.scrollToDownloadSection()
                after(0.8) {
                    capture.shot("settings-downloads")
                    capture.report.append("settings.storage=\(capture.store.storageText())")
                    capture.checkpoint()
                    captureSettingsSections(capture, settings: settings) {
                        captureEqualizer(capture, settings: settings) {
                            // Re-run the flow from the real Settings entry point.
                            settings.showOnboarding()
                            after(0.8) {
                                if let rerun = settings.presentedViewController as? OnboardingViewController {
                                    capture.report.append("onboarding.rerun=true")
                                    capture.report.append("onboarding.rerunTitle=\(rerun.stepTitle)")
                                    capture.shot("onboarding-rerun")
                                    rerun.dismiss(animated: false) {
                                        settings.dismiss(animated: false) {
                                            captureSheets(capture, host: host)
                                        }
                                    }
                                } else {
                                    capture.report.append("onboarding.rerun=false")
                                    settings.dismiss(animated: false) {
                                        captureSheets(capture, host: host)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The new control groups are captured from the same live table. Values are
    /// written straight to defaults for the frame (no root rebuild), then put
    /// back, so the probe still sees a clean process after this pass.
    private static func captureSettingsSections(_ capture: DownloadCapture,
                                                settings: SettingsViewController,
                                                completion: @escaping () -> Void) {
        let keys = [Theme.accentKey,
                    "BitChord.Audio.ResumeOnLaunch",
                    "BitChord.Audio.PauseOnHeadphoneDisconnect"]
        let old = keys.map { UserDefaults.standard.object(forKey: $0) }
        UserDefaults.standard.set("Mint", forKey: Theme.accentKey)
        UserDefaults.standard.set(true, forKey: "BitChord.Audio.ResumeOnLaunch")
        UserDefaults.standard.set(true, forKey: "BitChord.Audio.PauseOnHeadphoneDisconnect")
        settings.refreshForCapture()

        settings.scrollToKey(Theme.accentKey)
        after(0.5) {
            capture.shot("settings-appearance")
            capture.report.append("settings.appearanceShown=\(Theme.accentName)")
            settings.scrollToKey("BitChord.Audio.ResumeOnLaunch")
            after(0.5) {
                capture.shot("settings-playback")
                capture.report.append("settings.playbackShown=resume="
                    + "\(SettingsStore.shared.resumeOnLaunch) headphones="
                    + "\(SettingsStore.shared.pauseOnHeadphoneDisconnect)")
                settings.scrollToKey("BitChord.Storage.ClearSearchHistory")
                after(0.5) {
                    capture.shot("settings-maintenance")
                    capture.report.append("settings.maintenanceShown=true")
                    for (index, key) in keys.enumerated() {
                        if let value = old[index] {
                            UserDefaults.standard.set(value, forKey: key)
                        } else {
                            UserDefaults.standard.removeObject(forKey: key)
                        }
                    }
                    settings.refreshForCapture()
                    completion()
                }
            }
        }
    }

    /// Drives the real equalizer screen with a manual preset and the tone pad
    /// away from centre, then captures the ten faders and the puck together.
    private static func captureEqualizer(_ capture: DownloadCapture,
                                         settings: SettingsViewController,
                                         completion: @escaping () -> Void) {
        let store = SettingsStore.shared
        let keys = ["BitChord.Audio.Equalizer", "BitChord.Audio.EqualizerManual",
                    "BitChord.Audio.EqBands", "BitChord.Audio.EqToneX",
                    "BitChord.Audio.EqToneY"]
        let old = keys.map { UserDefaults.standard.object(forKey: $0) }
        store.set(true, for: "BitChord.Audio.EqualizerManual")
        store.set("Manual", for: "BitChord.Audio.Equalizer")
        store.set([6, 3, 0, -2, 0, 3, 6, 4, 2, 1], for: "BitChord.Audio.EqBands")
        store.set(4.0, for: "BitChord.Audio.EqToneX")
        store.set(-3.0, for: "BitChord.Audio.EqToneY")

        let equalizer = EqualizerViewController()
        let nav = chrome(equalizer)
        settings.present(nav, animated: false) {
            after(1.0) {
                capture.shot("equalizer")
                capture.report.append("equalizer.screen=true")
                capture.report.append("equalizer.bands=\(AudioDSP.bandFrequencies.count)")
                capture.report.append("equalizer.toneX=\(store.double("BitChord.Audio.EqToneX", 0))")
                capture.report.append("equalizer.toneY=\(store.double("BitChord.Audio.EqToneY", 0))")
                capture.report.append("equalizer.preset=\(store.string("BitChord.Audio.Equalizer", "Off"))")
                capture.checkpoint()
                nav.dismiss(animated: false) {
                    for (index, key) in keys.enumerated() {
                        if let value = old[index] {
                            UserDefaults.standard.set(value, forKey: key)
                        } else {
                            UserDefaults.standard.removeObject(forKey: key)
                        }
                    }
                    completion()
                }
            }
        }
    }

    /// Opens the real row menu in all three states on one real list, so the
    /// shots show the sheet a long press produces, not a mock of it.
    private static func captureSheets(_ capture: DownloadCapture, host: UIViewController) {
        guard let saved = capture.store.saved.first else {
            capture.report.append("sheets.noSaved=true")
            capture.finish()
            return
        }
        CatalogueSearch.shared.songs("Shape of You Ed Sheeran") { found in
            let others = found.filter { $0.videoID != saved.track.videoID }
            guard let downloading = others.first, let untouched = others.dropFirst().first else {
                capture.report.append("sheets.tracks=false")
                capture.finish()
                return
            }
            capture.extraTrack = untouched
            capture.spareTrack = others.dropFirst(2).first
            // Slow enough that the menu can be photographed while the row still
            // says it is downloading, then cancelled from that same menu.
            capture.store.progressPace = 0.1
            capture.store.download(downloading) { _, _ in }
            after(0.8) {
                host.dismiss(animated: false) {
                    let list = TrackListViewController()
                    list.tracks = [saved.track, downloading, untouched]
                    list.modalPresentationStyle = .fullScreen
                    capture.root.present(list, animated: false) {
                        after(1) {
                            let cells = trackCells(in: list.view)
                            guard cells.count >= 3 else {
                                capture.report.append("sheets.cells=\(cells.count)")
                                capture.finish()
                                return
                            }
                            cells[0].presentMenu()
                            after(0.7) {
                                capture.shot("sheet-delete")
                                capture.report.append("sheet.delete.downloaded=\(capture.store.isDownloaded(saved.track.videoID))")
                                TrackActions.topController()?.dismiss(animated: false) {
                                    cells[1].presentMenu()
                                    after(0.7) {
                                        capture.shot("sheet-cancel")
                                        capture.report.append("sheet.cancel.downloading=\(capture.store.isDownloading(downloading.videoID))")
                                        TrackActions.topController()?.dismiss(animated: false) {
                                            cells[2].presentMenu()
                                            after(0.7) {
                                                capture.shot("sheet-download")
                                                let idle = !capture.store.isDownloaded(untouched.videoID)
                                                    && !capture.store.isDownloading(untouched.videoID)
                                                capture.report.append("sheet.download.idle=\(idle)")
                                                capture.checkpoint()
                                                TrackActions.topController()?.dismiss(animated: false) {
                                                    capture.store.cancel(downloading.videoID)
                                                    capture.store.progressPace = 0
                                                    after(0.5) { wifiProbe(capture, host: list) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// With Wi-Fi-only on and the connection reported as metered, the store must
    /// hold the download and the row must say why.
    private static func wifiProbe(_ capture: DownloadCapture, host: UIViewController) {
        guard let track = capture.extraTrack else {
            capture.finish()
            return
        }
        SettingsStore.shared.set(true, for: "BitChord.Download.WifiOnly")
        capture.report.append("wifi.setting=\(SettingsStore.shared.bool("BitChord.Download.WifiOnly", false))")
        capture.store.connectivityOverride = { false }
        capture.store.download(track) { ok, message in
            capture.report.append("wifi.blocked=\(!ok)")
            capture.report.append("wifi.message=\(message)")
        }
        after(1) {
            host.dismiss(animated: false) {
                let downloads = DownloadsViewController()
                downloads.modalPresentationStyle = .fullScreen
                capture.root.present(downloads, animated: false) {
                    after(1.2) {
                        capture.shot("wifi-blocked")
                        capture.report.append("wifi.failedRows=\(capture.store.failedItems.count)")
                        capture.store.connectivityOverride = nil
                        storageCapProbe(capture, host: downloads)
                    }
                }
            }
        }
    }

    // MARK: - Storage cap

    /// With a 10 MB limit and 2.5 MB already saved, a ~8 MB track must be held
    /// with a reason, and the existing file must be untouched; then the limit is
    /// dropped below the usage to prove nothing is deleted behind the user's back.
    private static func storageCapProbe(_ capture: DownloadCapture, host: UIViewController) {
        guard let track = capture.spareTrack else {
            capture.report.append("cap.missing=true")
            playlistSyncProbe(capture, host: host)
            return
        }
        let beforeCount = capture.store.saved.count
        let beforeBytes = capture.store.totalBytes
        // The quality probe left this on Data saver; the cap has to be tested
        // against the rendition the user would actually get.
        SettingsStore.shared.set(DownloadQuality.high.rawValue, for: "BitChord.Download.Quality")
        SettingsStore.shared.set("10 MB", for: DownloadStore.storageLimitKey)
        capture.report.append("cap.setting=\(SettingsStore.shared.string(DownloadStore.storageLimitKey, ""))")
        capture.report.append("cap.usage=\(capture.store.storageText())")
        capture.report.append("cap.estimate=\(capture.store.estimatedBytes(for: track, quality: .high))")
        capture.store.download(track) { ok, message in
            capture.report.append("cap.blocked=\(!ok)")
            capture.report.append("cap.reason=\(capture.store.failure(for: track.videoID) ?? "")")
            capture.report.append("cap.message=\(message)")
        }
        after(1) {
            capture.report.append("cap.savedUnchanged=\(capture.store.saved.count == beforeCount && capture.store.totalBytes == beforeBytes)")
            capture.checkpoint()
            host.dismiss(animated: false) {
                let downloads = DownloadsViewController()
                downloads.modalPresentationStyle = .fullScreen
                capture.root.present(downloads, animated: false) {
                    after(1) {
                        capture.shot("storage-cap")
                        // Lowering the limit under the current usage keeps every file.
                        SettingsStore.shared.set("1 MB", for: DownloadStore.storageLimitKey)
                        let filesKept = capture.store.saved.allSatisfy {
                            capture.store.localURL(for: $0.track.videoID) != nil
                        }
                        capture.report.append("cap.lowLimitFiles=\(filesKept)")
                        capture.report.append("cap.lowLimitCount=\(capture.store.saved.count)")
                        capture.checkpoint()
                        let settings = SettingsViewController()
                        settings.modalPresentationStyle = .fullScreen
                        downloads.present(settings, animated: false) {
                            after(0.8) {
                                settings.scrollToDownloadSection()
                                after(0.8) {
                                    capture.shot("settings-storage")
                                    capture.report.append("settings.cap=\(SettingsStore.shared.string(DownloadStore.storageLimitKey, ""))")
                                    capture.report.append("settings.usage=\(capture.store.storageText())")
                                    settings.dismiss(animated: false) {
                                        // Back to a workable limit for the addon run.
                                        SettingsStore.shared.set("Unlimited", for: DownloadStore.storageLimitKey)
                                        playlistSyncProbe(capture, host: downloads)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Playlist sync

    private static func playlistSyncProbe(_ capture: DownloadCapture, host: UIViewController) {
        InnerTube.shared.searchCollections("Top songs", filter: .playlists) { items in
            // A playlist search can answer with a channel as well; only ids that
            // name a playlist are worth syncing, and one empty mix should not
            // fail the run when the next one has songs.
            let playlists = items.filter { $0.browseID.hasPrefix("VL") || $0.browseID.hasPrefix("MPRE") }
            trySync(capture, host: host, candidates: playlists.isEmpty ? items : playlists, index: 0)
        }
    }

    private static func trySync(_ capture: DownloadCapture,
                                host: UIViewController,
                                candidates: [CollectionItem],
                                index: Int) {
        guard index < candidates.count else {
            capture.report.append("sync.target=false")
            capture.finish()
            return
        }
        let item = candidates[index]
        LibraryStore.shared.syncPlaylist(remoteID: item.browseID) { ok, message in
            guard ok else {
                trySync(capture, host: host, candidates: candidates, index: index + 1)
                return
            }
            capture.report.append("sync.target=\(item.browseID)")
            capture.report.append("sync.ok=\(ok)")
                capture.report.append("sync.message=\(message)")
                capture.report.append("sync.playlists=\(LibraryStore.shared.playlists.count)")
                if let playlist = LibraryStore.shared.playlists.first(where: { $0.id.hasPrefix("remote:") }) {
                    capture.report.append("sync.title=\(playlist.title)")
                    capture.report.append("sync.tracks=\(playlist.tracks.count)")
                    capture.report.append("sync.first=\(playlist.tracks.first?.title ?? "")")
                    capture.report.append("sync.last=\(playlist.tracks.last?.title ?? "")")
                    capture.syncedTitle = playlist.title
                    capture.syncedTracks = playlist.tracks
                }
                capture.checkpoint()
                host.dismiss(animated: false) {
                    capture.root.showTab(2)
                    after(1.5) {
                        capture.shot("library-synced")
                        let list = TrackListViewController()
                        list.tracks = capture.syncedTracks
                        list.title = capture.syncedTitle
                        list.emptyText = "This playlist is empty."
                        list.modalPresentationStyle = .fullScreen
                        capture.root.present(list, animated: false) {
                            after(1) {
                                capture.shot("playlist-synced")
                                list.dismiss(animated: false) {
                                    playlistFailureProbe(capture, host: capture.root)
                                }
                            }
                        }
                    }
                }
            }
        }

    /// The remote side refusing: the UI shows the failure instead of pretending
    /// the playlist synced, and the saved set stays as it was.
    private static func playlistFailureProbe(_ capture: DownloadCapture, host: UIViewController) {
        let before = LibraryStore.shared.playlists.count
        LibraryStore.shared.syncPlaylist(remoteID: "this-is-not-a-playlist") { ok, message in
            capture.report.append("sync.failure.ok=\(!ok)")
            capture.report.append("sync.failure.message=\(message)")
            capture.report.append("sync.failure.unchanged=\(LibraryStore.shared.playlists.count == before)")
            guard !ok else {
                capture.finish()
                return
            }
            PlaylistSync.presentFailure(on: host, message: message)
            after(0.8) {
                capture.shot("sync-failed")
                PlaylistSync.dismissFailure(on: host)
                after(0.5) { addonProbe(capture, host: host) }
            }
        }
    }

    // MARK: - Lossless addon

    /// The addon serves one track and answers 404 for the other, so the same
    /// quality setting has to take the addon when it has something and the
    /// standard catalogue when it does not.
    private static func addonProbe(_ capture: DownloadCapture, host: UIViewController) {
        guard let addonURL = URL(string: ProcessInfo.processInfo.environment["BC_ADDON_URL"] ?? "http://127.0.0.1:8765") else {
            capture.report.append("addon.missing=true")
            capture.finish()
            return
        }
        CatalogueSearch.shared.songs("Levitating Dua Lipa") { tracks in
            guard tracks.count >= 2 else {
                capture.report.append("addon.tracks=false")
                capture.finish()
                return
            }
            capture.checkpoint()
            let fresh = tracks.filter { !DownloadStore.shared.isDownloaded($0.videoID) }
            guard fresh.count >= 2 else {
                capture.report.append("addon.tracks=false")
                capture.checkpoint()
                capture.finish()
                return
            }
            let losslessTrack = fresh[0]
            let fallbackTrack = fresh[1]
            capture.report.append("addon.track=\(losslessTrack.videoID)")
            capture.report.append("addon.fallbackTrack=\(fallbackTrack.videoID)")
            SettingsStore.shared.set(addonURL.absoluteString, for: AddonService.urlKey)
            SettingsStore.shared.set(DownloadQuality.lossless.rawValue, for: "BitChord.Download.Quality")
            // Tell the test server which id it should be able to serve.
            AddonService.shared.manifest { manifest, error in
                capture.report.append("addon.manifest=\(manifest?.name ?? "none") error=\(error ?? "")")
            }
            var request = URLRequest(url: addonURL.appendingPathComponent("serve").appendingPathComponent(losslessTrack.videoID))
            request.timeoutInterval = 5
            URLSession.shared.dataTask(with: request) { _, _, _ in
                DispatchQueue.main.async {
                    capture.store.download(losslessTrack) { ok, message in
                        capture.report.append("addon.ok=\(ok)")
                        if !ok { capture.report.append("addon.message=\(message)") }
                    }
                    waitUntil({ capture.store.isDownloaded(losslessTrack.videoID)
                                || capture.store.failure(for: losslessTrack.videoID) != nil },
                              timeout: 120) { finished in
                        if let item = capture.store.savedItem(for: losslessTrack.videoID),
                           let url = capture.store.localURL(for: losslessTrack.videoID) {
                            capture.report.append("addon.bytes=\(item.byteSize)")
                            capture.report.append("addon.label=\(item.qualityLabel)")
                            copy(url, to: capture.directory.appendingPathComponent("quality-lossless.m4a"))
                        } else {
                            capture.report.append("addon.bytes=0")
                            capture.report.append("addon.failed=\(finished)")
                        }
                        capture.report.append("addon.error=\(AddonService.shared.lastError ?? "")")
                        capture.checkpoint()
                        capture.store.download(fallbackTrack) { ok, message in
                            capture.report.append("addon.fallback.ok=\(ok)")
                            if !ok { capture.report.append("addon.fallback.message=\(message)") }
                        }
                        waitUntil({ capture.store.isDownloaded(fallbackTrack.videoID)
                                    || capture.store.failure(for: fallbackTrack.videoID) != nil },
                                  timeout: 120) { _ in
                            if let item = capture.store.savedItem(for: fallbackTrack.videoID),
                               let url = capture.store.localURL(for: fallbackTrack.videoID) {
                                capture.report.append("addon.fallback.bytes=\(item.byteSize)")
                                capture.report.append("addon.fallback.label=\(item.qualityLabel)")
                                copy(url, to: capture.directory.appendingPathComponent("quality-fallback.m4a"))
                            } else {
                                capture.report.append("addon.fallback.bytes=0")
                            }
                            capture.checkpoint()
                            SettingsStore.shared.set(DownloadQuality.high.rawValue, for: "BitChord.Download.Quality")
                            host.dismiss(animated: false) {
                                let downloads = DownloadsViewController()
                                downloads.modalPresentationStyle = .fullScreen
                                capture.root.present(downloads, animated: false) {
                                    after(1.5) {
                                        capture.shot("downloads-addon")
                                        libraryExtrasProbe(capture, host: downloads)
                                    }
                                }
                            }
                        }
                    }
                }
            }.resume()
        }
    }

    private static func after(_ seconds: TimeInterval, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body)
    }

    /// Screenshot-only stand-in for a modal player. Adding the view as a child
    /// keeps the root free for the artist pages and removes an animated
    /// dismissal from the critical path.
    private static func addOverlay(_ controller: UIViewController, to parent: UIViewController,
                                    aboveWindow: Bool = false) {
        parent.addChild(controller)
        let parentView: UIView = parent.view
        let host: UIView = aboveWindow ? (parentView.window ?? parentView) : parentView
        controller.view.frame = host.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(controller.view)
        controller.didMove(toParent: parent)
    }

    private static func removeOverlay(_ controller: UIViewController) {
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
    }

    private static func waitUntil(_ condition: @escaping () -> Bool,
                                  timeout: TimeInterval,
                                  then: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() { then(true); return }
            if Date() > deadline { then(false); return }
            after(0.5) { poll() }
        }
        poll()
    }

    private static func copy(_ from: URL, to: URL) {
        try? FileManager.default.removeItem(at: to)
        try? FileManager.default.copyItem(at: from, to: to)
    }

    private static func trackCells(in view: UIView) -> [TrackCell] {
        var found: [TrackCell] = []
        func walk(_ node: UIView) {
            if let cell = node as? TrackCell { found.append(cell) }
            node.subviews.forEach(walk)
        }
        walk(view)
        return found.sorted {
            $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY
        }
    }

    // MARK: - Local music, queue history, radio, lyrics, artist, moods

    /// Everything the audit still called unported, exercised through its own
    /// screen or menu: the local locker, queue history, a radio, enhanced-LRC
    /// syllables, an artist page and a mood tile.
    private static func libraryExtrasProbe(_ capture: DownloadCapture, host: UIViewController) {
        host.dismiss(animated: false) {
            capture.root.showTab(2)
            after(0.8) { localMusicProbe(capture) }
        }
    }

    private static func localMusicProbe(_ capture: DownloadCapture) {
        // Seed the locker with a real audio file: the download this run already
        // has, copied into the folder the scanner reads.
        let manager = FileManager.default
        let folder = LocalMusicStore.shared.rootURL.appendingPathComponent("Test Album", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        if let saved = capture.store.saved.first,
           let source = capture.store.localURL(for: saved.track.videoID) {
            let destination = folder.appendingPathComponent("01 \(saved.track.title).m4a")
            try? manager.removeItem(at: destination)
            try? manager.copyItem(at: source, to: destination)
        }
        LocalMusicStore.shared.scan { songs in
            capture.report.append("local.folders=\(LocalMusicStore.shared.folders.count)")
            capture.report.append("local.tracks=\(songs.count)")
            capture.report.append("local.title=\(songs.first?.track.title ?? "")")
            capture.report.append("local.duration=\(Int(songs.first?.track.durationSeconds ?? 0))")
            let library = LocalMusicViewController()
            capture.root.present(chrome(library), animated: false) {
                after(1.2) {
                    capture.shot("local-music")
                    library.openFolderForCapture()
                    after(1.2) {
                        capture.shot("local-songs")
                        let tracks = songs.map { $0.track }
                        PlayerService.shared.play(tracks: tracks, startingAt: 0)
                        after(1.5) {
                            let current = PlayerService.shared.currentTrack
                            capture.report.append("local.playing=\(current?.videoID.hasPrefix(LocalMusicStore.idPrefix) ?? false)")
                            capture.report.append("local.engine=\(AudioEngine.shared.diagnosticsSummary)")
                            capture.checkpoint()
                            library.dismiss(animated: false) { badgeProbe(capture) }
                        }
                    }
                }
            }
        }
    }

    private static func badgeProbe(_ capture: DownloadCapture) {
        guard let saved = capture.store.saved.first else {
            historyProbe(capture)
            return
        }
        let list = TrackListViewController()
        list.tracks = [saved.track]
        list.title = "Downloaded"
        capture.root.present(chrome(list), animated: false) {
            after(1) {
                let cell = trackCells(in: list.view).first
                capture.report.append("badge.downloaded=\(cell?.showsDownloadedBadge ?? false)")
                list.dismiss(animated: false) { historyProbe(capture) }
            }
        }
    }

    private static func historyProbe(_ capture: DownloadCapture) {
        SettingsStore.shared.set(true, for: PlaybackHistoryStore.settingKey)
        PlaybackHistoryStore.shared.clear()
        let tracks = [capture.store.saved.first?.track, capture.extraTrack].compactMap { $0 }
        if tracks.count >= 2 {
            PlayerService.shared.play(tracks: tracks, startingAt: 0)
            after(1.2) { PlayerService.shared.advance() }
        }
        after(2.6) {
            let history = PlaybackHistoryStore.shared.items
            capture.report.append("history.enabled=\(PlaybackHistoryStore.shared.isEnabled)")
            capture.report.append("history.count=\(history.count)")
            capture.report.append("history.top=\(history.first?.title ?? "")")
            capture.report.append("history.limit=\(PlaybackHistoryStore.limit)")
            let queue = QueueViewController()
            queue.modalPresentationStyle = .fullScreen
            capture.root.present(queue, animated: false) {
                after(1.2) {
                    capture.shot("queue-history")
                    capture.checkpoint()
                    queue.dismiss(animated: false) { radioProbe(capture) }
                }
            }
        }
    }

    private static func radioProbe(_ capture: DownloadCapture) {
        guard let seed = capture.seedTrack ?? capture.store.saved.first?.track else {
            radioFailureProbe(capture)
            return
        }
        // The menu's own path: resolve the seed on YouTube, ask for the mix,
        // replace the queue and open Now Playing.
        capture.report.append("radio.seed=\(RadioService.isYouTubeVideoID(seed.videoID) ? "youtube" : "catalogue-resolved")")
        var delivered: [Track] = []
        RadioService.start(from: seed, host: capture.root) { tracks in
            delivered = tracks
        }
        waitUntil({ !delivered.isEmpty }, timeout: 45) { met in
            capture.report.append("radio.tracks=\(delivered.count)")
            capture.report.append("radio.first=\(delivered.first?.title ?? "")")
            capture.report.append("radio.playing=\(met && PlayerService.shared.currentTrack != nil)")
            capture.report.append("radio.queued=\(PlayerService.shared.queue.count)")
            capture.checkpoint()
            // RadioService leaves Now Playing up on success and an alert on
            // failure; clear either before the next screen.
            capture.root.dismiss(animated: false) {
                guard met else {
                    radioFailureProbe(capture)
                    return
                }
                let sheet = QueueViewController()
                sheet.modalPresentationStyle = .fullScreen
                capture.root.present(sheet, animated: false) {
                    after(1.2) {
                        capture.shot("radio")
                        sheet.dismiss(animated: false) { radioFailureProbe(capture) }
                    }
                }
            }
        }
    }

    /// The remote refusing: the same alert the menu shows, on screen.
    private static func radioFailureProbe(_ capture: DownloadCapture) {
        RadioService.presentFailure("This track has no radio.", on: capture.root)
        after(0.9) {
            capture.shot("radio-failed")
            capture.report.append("radio.failedShown=true")
            capture.root.dismiss(animated: false) { lyricsProbe(capture) }
        }
    }

    private static func lyricsProbe(_ capture: DownloadCapture) {
        // Enhanced LRC: words carry their own `<mm:ss.xx>` tags, which is the
        // syllable timing karaoke draws from.
        let sample = "[00:10.00]<00:10.00>Hel<00:10.40>lo <00:10.90>world"
        let parsed = LyricsService.shared.parseLRC(sample)
        let line = parsed.first
        let syllableCount = line?.words.reduce(0) { $0 + $1.syllables.count } ?? 0
        capture.report.append("lyrics.lines=\(parsed.count)")
        capture.report.append("lyrics.words=\(line?.words.count ?? 0)")
        capture.report.append("lyrics.syllables=\(syllableCount)")
        capture.report.append("lyrics.text=\(line?.text ?? "")")
        if let line = line {
            let early = line.revealedChars(at: line.time + 0.2)
            let late = line.revealedChars(at: line.time + 0.95)
            capture.report.append("lyrics.revealAdvance=\(late > early)")
        } else {
            capture.report.append("lyrics.revealAdvance=false")
        }
        let live = PlayerService.shared.lyrics
        capture.report.append("lyrics.liveLines=\(live.count)")
        capture.report.append("lyrics.liveWordLines=\(live.filter { $0.isWordSynced }.count)")
        capture.checkpoint()

        let player = NowPlayingViewController()
        addOverlay(player, to: capture.root)
        after(1.2) {
            player.showLyricsForScreenshots()
            after(1.2) {
                if let timed = live.first(where: { $0.isWordSynced }) ?? live.first {
                    PlayerService.shared.seek(to: timed.time + 0.4)
                    after(0.8) {
                        capture.shot("lyrics-karaoke")
                        removeOverlay(player)
                        after(0.8) { artistProbe(capture) }
                    }
                } else {
                    capture.shot("lyrics-karaoke")
                    removeOverlay(player)
                    after(0.8) { artistProbe(capture) }
                }
            }
        }
    }

    private static func artistProbe(_ capture: DownloadCapture) {
        capture.report.append("artist.probeStart=true")
        capture.checkpoint()
        loadArtist(capture, attempt: 1)
    }

    /// The catalogue occasionally leaves a search request unanswered on the
    /// simulator (a stale connection in its URL session). Bound each attempt
    /// and try again instead of holding every later screenshot behind it.
    private static func loadArtist(_ capture: DownloadCapture, attempt: Int) {
        // Use the same catalogue search the Artists tab uses. JioSaavn's
        // artist page is the one with releases, a biography and related
        // artists; the YouTube browse fallback only has the song list.
        var fetched: [CatalogueArtist] = []
        var answered = false
        CatalogueSearch.shared.artists("Taylor Swift") { artists in
            fetched = artists
            answered = true
        }
        waitUntil({ answered }, timeout: 20) { met in
            guard met else {
                if attempt < 2 {
                    capture.report.append("artist.searchRetry=\(attempt)")
                    loadArtist(capture, attempt: attempt + 1)
                } else {
                    capture.report.append("artist.searchTimeout=true")
                    capture.checkpoint()
                    moodsProbe(capture)
                }
                return
            }
            guard let item = fetched.first else {
                capture.report.append("artist.tracks=0")
                capture.checkpoint()
                moodsProbe(capture)
                return
            }
            capture.report.append("artist.name=\(item.name)")
            capture.report.append("artist.source=live")
            capture.checkpoint()
            let page = ArtistPage.make(artist: item)
            presentArtistPage(capture, page: page, attempt: 1)
        }
    }

    /// Add the artist page above every existing screen. This keeps the capture
    /// deterministic even if the download flow still owns a modal.
    private static func presentArtistPage(_ capture: DownloadCapture,
                                          page: ArtistViewController,
                                          attempt: Int) {
        let modal = capture.root.presentedViewController.map { String(describing: type(of: $0)) }
        capture.report.append("artist.rootModal=\(modal ?? "none")")
        capture.report.append("artist.pageConstructed=true")
        capture.checkpoint()
        addOverlay(chrome(page), to: capture.root)
        capture.report.append("artist.overlayAdded=true")
        capture.checkpoint()
        after(0.8) {
            capture.report.append("artist.presented=\(page.viewIfLoaded?.window != nil)")
            capture.checkpoint()
            startArtistPage(capture, page: page)
        }
    }

    private static func startArtistPage(_ capture: DownloadCapture, page: ArtistViewController) {
        waitUntil({ page.loadedTrackCount > 0 }, timeout: 25) { _ in
            after(1.0) {
                capture.shot("artist")
                capture.report.append("artist.loaded=\(page.loadedTrackCount)")
                capture.report.append("artist.summary=\(page.reportSummary)")
                capture.checkpoint()
                artistRadioProbe(capture, page: page) {
                    removeOverlay(page.navigationController ?? page)
                    after(0.3) { artistEmptyProbe(capture) }
                }
            }
        }
    }

    /// Starts the artist's own radio action without presenting Now Playing, then
    /// waits for the normal PlayerService path to own the queue and play.
    private static func artistRadioProbe(_ capture: DownloadCapture,
                                         page: ArtistViewController,
                                         completion: @escaping () -> Void) {
        var delivered: [Track] = []
        page.startRadio(presentPlayer: false) { tracks in
            delivered = tracks ?? []
        }
        waitUntil({ !delivered.isEmpty }, timeout: 45) { met in
            waitUntil({ PlayerService.shared.isPlaying }, timeout: 12) { playing in
                capture.report.append("artistRadio.tracks=\(delivered.count)")
                capture.report.append("artistRadio.first=\(delivered.first?.title ?? "")")
                capture.report.append("artistRadio.queued=\(PlayerService.shared.queue.count)")
                capture.report.append("artistRadio.playing=\(met && playing)")
                capture.checkpoint()
                completion()
            }
        }
    }

    /// Empty and missing-copy pages must go through the same layout without
    /// sections, empty headers or a crash.
    private static func artistEmptyProbe(_ capture: DownloadCapture) {
        let emptyArtist = CatalogueArtist(id: "probe-empty", name: "Empty Artist", artwork: nil)
        let empty = ArtistViewController(artist: emptyArtist)
        addOverlay(chrome(empty), to: capture.root)
        after(0.2) {
            let emptyProfile = ArtistProfile(name: "Empty Artist", artwork: nil, listenerText: nil,
                                             bio: nil, topSongs: [], albums: [], related: [])
            empty.applyProfileForProbe(emptyProfile)
            after(0.5) {
                capture.report.append("artist.emptySummary=\(empty.reportSummary)")
                capture.report.append("artist.emptyRendered=\(empty.viewIfLoaded != nil)")
                capture.shot("artist-empty")
                let partial = ArtistProfile(name: "Partial Artist", artwork: nil,
                                            listenerText: nil, bio: nil,
                                            topSongs: [Track(videoID: "probe-partial",
                                                             title: "Partial song",
                                                             artist: "Partial Artist",
                                                             durationSeconds: 180)],
                                            albums: [], related: [])
                empty.applyProfileForProbe(partial)
                capture.report.append("artist.partialSummary=\(empty.reportSummary)")
                capture.shot("artist-partial")
                capture.checkpoint()
                removeOverlay(empty.navigationController ?? empty)
                after(0.3) { artistFallbackProbe(capture) }
            }
        }
    }

    /// Turn off the primary catalogue and prove the YouTube browse fallback
    /// still renders a usable artist page with songs and no invented shelves.
    private static func artistFallbackProbe(_ capture: DownloadCapture) {
        let store = SettingsStore.shared
        let old = store.bool("BitChord.Source.JioSaavn", true)
        store.set(false, for: "BitChord.Source.JioSaavn")
        InnerTube.shared.searchCollections("The Weeknd", filter: .artists) { items in
            guard let item = items.first else {
                store.set(old, for: "BitChord.Source.JioSaavn")
                capture.report.append("artist.fallback=false")
                capture.checkpoint()
                moodsProbe(capture)
                return
            }
            let artist = CatalogueArtist(id: item.browseID, name: item.title,
                                         artwork: item.artworkURL)
            CatalogueSearch.shared.artistProfile(id: artist.id, name: artist.name,
                                                 artwork: artist.artwork) { profile in
                store.set(old, for: "BitChord.Source.JioSaavn")
                capture.report.append("artist.fallbackSongs=\(profile.topSongs.count)")
                capture.report.append("artist.fallbackAlbums=\(profile.albums.count)")
                capture.report.append("artist.fallbackRelated=\(profile.related.count)")
                capture.report.append("artist.fallbackBio=\(profile.bio?.isEmpty == false)")
                let fallback = ArtistViewController(artist: artist)
                addOverlay(chrome(fallback), to: capture.root)
                after(0.2) {
                    fallback.applyProfileForProbe(profile)
                    after(0.6) {
                        capture.shot("artist-fallback")
                        capture.report.append("artist.fallbackSummary=\(fallback.reportSummary)")
                        capture.checkpoint()
                        removeOverlay(fallback.navigationController ?? fallback)
                        after(0.3) { artistDiscographyProbe(capture) }
                    }
                }
            }
        }
    }

    /// A synthetic mixed discography drives the same table the live catalogue
    /// feeds: all three release kinds, both sort orders, a filter and the
    /// expandable biography. Empty/partial/fallback already ran before it.
    private static func artistDiscographyProbe(_ capture: DownloadCapture) {
        let store = SettingsStore.shared
        let keys = ["BitChord.Artist.AlbumFilter", "BitChord.Artist.AlbumSort",
                    "BitChord.Artist.TrackSort", "BitChord.Artist.BioExpanded"]
        let old = keys.map { UserDefaults.standard.object(forKey: $0) }
        store.set("All", for: keys[0])
        store.set("Newest", for: keys[1])
        store.set("A–Z", for: keys[2])
        store.set(false, for: keys[3])

        let longBio = "A discography fixture long enough to need more than three lines on a phone. "
            + "It keeps writing so the expandable biography has a real collapsed state, then opens "
            + "to show the full editorial note without a blank or clipped section. "
            + "Every release below carries the same artwork and metadata the catalogue supplies."
        let profile = ArtistProfile(
            name: "Discography Artist", artwork: nil, listenerText: "1,200,000 listeners",
            bio: longBio,
            topSongs: [
                Track(videoID: "probe-z", title: "Zebra Nights", artist: "Discography Artist",
                      album: "Night", durationSeconds: 201),
                Track(videoID: "probe-a", title: "Afterglow", artist: "Discography Artist",
                      album: "Night", durationSeconds: 188)
            ],
            albums: [
                CatalogueAlbum(id: "probe-album", title: "Night", artist: "Discography Artist",
                               year: "2024", artwork: nil, songCount: 11, kind: .album),
                CatalogueAlbum(id: "probe-single", title: "First Light", artist: "Discography Artist",
                               year: "2023", artwork: nil, songCount: 1, kind: .single),
                CatalogueAlbum(id: "probe-compilation", title: "The Collection",
                               artist: "Discography Artist", year: "2022", artwork: nil,
                               songCount: 18, kind: .compilation)
            ],
            related: [CatalogueArtist(id: "probe-related", name: "Related Artist", artwork: nil)])

        let artist = CatalogueArtist(id: "probe-discography", name: "Discography Artist", artwork: nil)
        let page = ArtistViewController(artist: artist)
        addOverlay(chrome(page), to: capture.root)
        after(0.2) {
            page.applyProfileForProbe(profile)
            after(0.6) {
                page.scrollToDiscographyForProbe()
                after(0.6) {
                    capture.shot("artist-discography")
                    capture.report.append("artist.discography=\(page.discographySummary)")
                    page.setAlbumFilterForProbe("Singles")
                    page.scrollToDiscographyForProbe()
                    after(0.5) {
                        capture.shot("artist-discography-filtered")
                        capture.report.append("artist.discographyFiltered=\(page.discographySummary)")
                        page.setAlbumFilterForProbe("All")
                        page.setBioExpandedForProbe(true)
                        page.scrollToAboutForProbe()
                        after(0.5) {
                            capture.shot("artist-bio-expanded")
                            capture.report.append("artist.bioExpanded=\(page.discographySummary)")
                            capture.checkpoint()
                            for (index, key) in keys.enumerated() {
                                if let value = old[index] {
                                    UserDefaults.standard.set(value, forKey: key)
                                } else {
                                    UserDefaults.standard.removeObject(forKey: key)
                                }
                            }
                            removeOverlay(page.navigationController ?? page)
                            after(0.3) { moodsProbe(capture) }
                        }
                    }
                }
            }
        }
    }

    private static func moodsProbe(_ capture: DownloadCapture) {
        capture.root.showTab(1)
        after(0.8) {
            // Tabs are wrapped in navigation controllers, so reach the Explore
            // screen through its navigation stack rather than by child index.
            let explore = capture.root.children.compactMap { $0 as? UINavigationController }
                .compactMap { $0.viewControllers.first as? ExploreViewController }
                .first
            guard let explore = explore, let tile = firstMoodTile(in: explore.view) else {
                capture.report.append("moods.tracks=0")
                capture.finish()
                return
            }
            tile.sendActions(for: .touchUpInside)
            let moodList: () -> TrackListViewController? = {
                return explore.navigationController?.viewControllers.compactMap { $0 as? TrackListViewController }.last
            }
            waitUntil({ (moodList()?.tracks.count ?? 0) > 0 }, timeout: 25) { _ in
                after(0.8) {
                    capture.shot("moods")
                    capture.report.append("moods.title=\(moodList()?.title ?? "")")
                    capture.report.append("moods.tracks=\(moodList()?.tracks.count ?? 0)")
                    capture.checkpoint()
                    menuProbe(capture)
                }
            }
        }
    }

    // MARK: - Song menu, playlists, queue edits, history, info, autoplay

    private static func menuProbe(_ capture: DownloadCapture) {
        guard let track = capture.seedTrack ?? capture.store.saved.first?.track else {
            cacheProbe(capture)
            return
        }
        // The same builder the sheet uses, so an action that disappeared from
        // the app cannot stay in the report.
        let titles = TrackActions.titles(for: track)
        capture.report.append("menu.items=\(titles.joined(separator: "|"))")
        capture.report.append("menu.hasPlayNext=\(titles.contains("Play next"))")
        capture.report.append("menu.hasAddToQueue=\(titles.contains("Add to queue"))")
        capture.report.append("menu.hasPlaylist=\(titles.contains("Add to playlist"))")
        capture.report.append("menu.hasSongInfo=\(titles.contains("Song info"))")
        capture.report.append("menu.hasShare=\(titles.contains("Share"))")
        capture.report.append("menu.hasArtist=\(titles.contains("Open artist"))")
        capture.report.append("menu.hasAlbum=\(titles.contains("Open album"))")
        capture.report.append("menu.hasLike=\(titles.contains("Like") || titles.contains("Unlike"))")

        let list = TrackListViewController()
        list.tracks = [track]
        list.title = "Song"
        capture.root.present(chrome(list), animated: false) {
            after(0.8) {
                TrackActions.present(for: track, from: list, sourceView: nil)
                after(0.9) {
                    capture.shot("song-actions")
                    capture.root.dismiss(animated: false) {
                        playlistProbe(capture, track: track)
                    }
                }
            }
        }
    }

    private static func playlistProbe(_ capture: DownloadCapture, track: Track) {
        var playlist = LibraryStore.shared.playlists.first(where: { $0.title == "Menu Test" })
        if playlist == nil {
            playlist = LibraryStore.shared.createPlaylist(title: "Menu Test")
        }
        guard let playlist = playlist else {
            capture.report.append("menu.playlistTracks=0")
            queueEditProbe(capture)
            return
        }
        let before = playlist.tracks.count
        let list = TrackListViewController()
        list.tracks = [track]
        list.title = "Song"
        capture.root.present(chrome(list), animated: false) {
            after(0.8) {
                PlaylistPicker.present(for: track, from: list)
                after(0.9) {
                    capture.shot("add-to-playlist")
                    let after = PlaylistPicker.add(track, to: playlist.id)
                    capture.report.append("menu.playlistBefore=\(before)")
                    capture.report.append("menu.playlistTracks=\(after)")
                    capture.report.append("menu.playlistGrew=\(after == before + 1)")
                    capture.root.dismiss(animated: false) {
                        queueEditProbe(capture)
                    }
                }
            }
        }
    }

    private static func queueEditProbe(_ capture: DownloadCapture) {
        guard let first = capture.seedTrack ?? capture.store.saved.first?.track,
              let second = capture.extraTrack else {
            historyPageProbe(capture)
            return
        }
        PlayerService.shared.setRepeatMode(.off)
        PlayerService.shared.play(tracks: [first, second], startingAt: 0)
        after(1.2) {
            let before = PlayerService.shared.queue.count
            PlayerService.shared.addToQueue(first)
            let added = PlayerService.shared.queue.count
            PlayerService.shared.removeFromQueue(at: PlayerService.shared.queue.count - 1)
            let removed = PlayerService.shared.queue.count
            PlayerService.shared.playNext(second)
            let index = PlayerService.shared.currentIndex
            let queued = PlayerService.shared.queue
            let nextIsSecond = index + 1 < queued.count && queued[index + 1].videoID == second.videoID
            capture.report.append("queue.before=\(before)")
            capture.report.append("queue.afterAdd=\(added)")
            capture.report.append("queue.afterRemove=\(removed)")
            capture.report.append("queue.playNext=\(nextIsSecond)")
            PlayerService.shared.moveInQueue(from: 0, to: 2)
            let moved = PlayerService.shared.queue.map { $0.videoID }
            capture.report.append("queue.afterMove=\(moved.count)")
            capture.report.append("queue.moved=\(moved.count == 3 && moved[2] == first.videoID)")
            capture.checkpoint()
            let sheet = QueueViewController()
            sheet.modalPresentationStyle = .fullScreen
            capture.root.present(sheet, animated: false) {
                after(1.0) {
                    capture.shot("queue-edit")
                    sheet.dismiss(animated: false) { historyPageProbe(capture) }
                }
            }
        }
    }

    private static func historyPageProbe(_ capture: DownloadCapture) {
        let history = HistoryViewController()
        capture.root.present(chrome(history), animated: false) {
            after(0.9) {
                capture.report.append("historyPage.rows=\(history.rowCount)")
                capture.shot("history")
                history.clearForCapture()
                after(0.6) {
                    capture.report.append("historyPage.afterClear=\(history.rowCount)")
                    capture.shot("history-empty")
                    // The relaunch proof reads this store back; keep it populated.
                    if let first = capture.seedTrack, let second = capture.extraTrack {
                        PlayerService.shared.play(tracks: [first, second], startingAt: 0)
                    }
                    after(1.2) {
                        capture.report.append("historyPage.restored=\(history.rowCount)")
                        history.dismiss(animated: false) { replayProbe(capture) }
                    }
                }
            }
        }
    }

    private static func replayProbe(_ capture: DownloadCapture) {
        let replay = ReplayViewController()
        capture.root.present(chrome(replay), animated: false) {
            after(1.0) {
                let entries = ReplayViewController.entries()
                capture.report.append("replay.entries=\(entries.count)")
                capture.report.append("replay.plays=\(entries.reduce(0) { $0 + $1.plays })")
                capture.report.append("replay.top=\(entries.first?.track.title ?? "")")
                capture.shot("replay")
                capture.checkpoint()
                replay.dismiss(animated: false) { songInfoProbe(capture) }
            }
        }
    }

    private static func songInfoProbe(_ capture: DownloadCapture) {
        guard let track = PlayerService.shared.currentTrack else {
            cacheProbe(capture)
            return
        }
        let rows = SongInfoViewController.rows(for: track)
        let value: (String) -> String = { label in
            return rows.first(where: { $0.label == label })?.value ?? ""
        }
        capture.report.append("info.rows=\(rows.count)")
        capture.report.append("info.title=\(track.title)")
        capture.report.append("info.album=\(value("Album"))")
        let info = SongInfoViewController(track: track)
        info.modalPresentationStyle = .fullScreen
        capture.root.present(info, animated: false) {
            // The watch page answers a second or two after the card appears.
            // Wait for that answer instead of photographing placeholders, but
            // stop waiting if the network refuses so the run still finishes.
            func captureWhenSettled(_ remaining: Int) {
                if info.isLoaded || remaining <= 0 {
                    capture.shot("song-info")
                    capture.checkpoint()
                    info.dismiss(animated: false) { autoplayProbe(capture) }
                } else {
                    after(0.5) { captureWhenSettled(remaining - 1) }
                }
            }
            after(0.5) { captureWhenSettled(10) }
        }
    }

    private static func autoplayProbe(_ capture: DownloadCapture) {
        SettingsStore.shared.set(true, for: "BitChord.Audio.AutoPlay")
        capture.report.append("autoplay.setting=\(PlayerService.shared.autoplayEnabled)")
        guard let seed = capture.seedTrack else {
            cacheProbe(capture)
            return
        }
        PlayerService.shared.setRepeatMode(.off)
        let before = PlayerService.shared.autoplayCount
        PlayerService.shared.play(tracks: [seed], startingAt: 0)
        after(1.2) {
            // The queue has one song, so this is the end-of-queue branch.
            PlayerService.shared.advance()
            waitUntil({ PlayerService.shared.autoplayCount > before }, timeout: 45) { met in
                capture.report.append("autoplay.started=\(met)")
                capture.report.append("autoplay.tracks=\(PlayerService.shared.queue.count)")
                capture.report.append("autoplay.first=\(PlayerService.shared.currentTrack?.title ?? "")")
                capture.checkpoint()
                if met {
                    capture.shot("autoplay")
                }
                webdavProbe(capture)
            }
        }
    }

    /// A real WebDAV server (started by CI on the runner) reached from the
    /// simulator: list, browse, stream, then the wrong-password path.
    private static func webdavProbe(_ capture: DownloadCapture) {
        writeDeepLinkIDs(capture)
        let environment = ProcessInfo.processInfo.environment
        guard let base = environment["BC_WEBDAV_URL"], !base.isEmpty else {
            capture.report.append("webdav.env=false")
            cacheProbe(capture)
            return
        }
        let username = environment["BC_WEBDAV_USER"] ?? ""
        let password = environment["BC_WEBDAV_PASS"] ?? ""
        let sources = SourcesViewController()
        capture.root.present(chrome(sources), animated: false) {
            after(0.5) {
                sources.connectForCapture(url: base, username: username, password: password)
                waitUntil({ !sources.isBusy && !sources.entryNames.isEmpty }, timeout: 20) { listed in
                    capture.report.append("webdav.listed=\(listed)")
                    capture.report.append("webdav.root=\(sources.entryNames.joined(separator: "|"))")
                    capture.report.append("webdav.hasMusic=\(sources.entryNames.contains("Music"))")
                    capture.shot("webdav-tree")
                    guard let folder = sources.browseForCapture(named: "Music") else {
                        capture.report.append("webdav.folder=false")
                        capture.checkpoint()
                        capture.root.dismiss(animated: false) { cacheProbe(capture) }
                        return
                    }
                    waitUntil({ !folder.isBusy && !folder.entryNames.isEmpty }, timeout: 20) { nested in
                        capture.report.append("webdav.folder=\(nested) \(folder.entryNames.joined(separator: "|"))")
                        capture.report.append("webdav.hasTrack=\(folder.entryNames.contains("track.m4a"))")
                        folder.playForCapture(named: "track.m4a")
                        waitUntil({ PlayerService.shared.currentTrack?.videoID.hasPrefix("webdav:") == true }, timeout: 20) { started in
                            capture.report.append("webdav.playing=\(started)")
                            capture.report.append("webdav.title=\(PlayerService.shared.currentTrack?.title ?? "")")
                            waitUntil({ PlayerService.shared.isPlaying }, timeout: 20) { audible in
                                capture.report.append("webdav.isPlaying=\(audible)")
                                capture.shot("webdav-playing")
                                capture.checkpoint()
                                capture.root.dismiss(animated: false) {
                                    let bad = SourcesViewController()
                                    capture.root.present(chrome(bad), animated: false) {
                                        bad.connectForCapture(url: base, username: username, password: "wrong-password")
                                        waitUntil({ !bad.isBusy && !bad.errorText.isEmpty }, timeout: 20) { failed in
                                            capture.report.append("webdav.authErrorShown=\(failed)")
                                            capture.report.append("webdav.authError=\(bad.errorText)")
                                            capture.shot("webdav-error")
                                            capture.checkpoint()
                                            bad.dismiss(animated: false) { jellyfinProbe(capture) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// A real Jellyfin server on the runner: sign in, libraries, folder, album,
    /// a streamed track, then expired, wrong-password and unreachable paths.
    private static func jellyfinProbe(_ capture: DownloadCapture) {
        let environment = ProcessInfo.processInfo.environment
        guard let base = environment["BC_JELLYFIN_URL"], !base.isEmpty else {
            capture.report.append("jellyfin.env=false")
            cacheProbe(capture)
            return
        }
        let username = environment["BC_JELLYFIN_USER"] ?? ""
        let password = environment["BC_JELLYFIN_PASS"] ?? ""
        let controller = JellyfinViewController()
        capture.root.present(chrome(controller), animated: false) {
            after(0.5) {
                controller.signInForCapture(url: base, username: username, password: password)
                waitUntil({ !controller.isBusy && controller.entryNames.contains("Music") }, timeout: 25) { listed in
                    capture.report.append("jellyfin.listed=\(listed)")
                    capture.report.append("jellyfin.libraries=\(controller.entryNames.joined(separator: "|"))")
                    capture.shot("jellyfin-tree")
                    guard let library = controller.browseForCapture(named: "Music") else {
                        capture.report.append("jellyfin.folder=false")
                        capture.checkpoint()
                        capture.root.dismiss(animated: false) { cacheProbe(capture) }
                        return
                    }
                    waitUntil({ !library.isBusy && library.entryNames.contains("Album One") }, timeout: 20) { libraryLoaded in
                        capture.report.append("jellyfin.folder=\(libraryLoaded) \(library.entryNames.joined(separator: "|"))")
                        guard let album = library.browseForCapture(named: "Album One") else {
                            capture.report.append("jellyfin.album=false")
                            capture.checkpoint()
                            capture.root.dismiss(animated: false) { cacheProbe(capture) }
                            return
                        }
                        waitUntil({ !album.isBusy && album.entryNames.contains("track.m4a") }, timeout: 20) { albumLoaded in
                            capture.report.append("jellyfin.album=\(albumLoaded) \(album.entryNames.joined(separator: "|"))")
                            album.playForCapture(named: "track.m4a")
                            waitUntil({ PlayerService.shared.currentTrack?.videoID.hasPrefix("jellyfin:") == true }, timeout: 20) { started in
                                capture.report.append("jellyfin.playing=\(started)")
                                capture.report.append("jellyfin.title=\(PlayerService.shared.currentTrack?.title ?? "")")
                                waitUntil({ PlayerService.shared.isPlaying }, timeout: 20) { audible in
                                    capture.report.append("jellyfin.isPlaying=\(audible)")
                                    capture.shot("jellyfin-playing")
                                    capture.checkpoint()
                                    capture.root.dismiss(animated: false) {
                                        checkJellyfinErrors(capture, base: base, username: username, password: password)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func checkJellyfinErrors(_ capture: DownloadCapture,
                                            base: String,
                                            username: String,
                                            password: String) {
        // Expired token: a signed-in browser whose stored token is no longer valid.
        let expired = JellyfinViewController()
        capture.root.present(chrome(expired), animated: false) {
            after(0.4) {
                expired.signInForCapture(url: base, username: username, password: password)
                waitUntil({ !expired.isBusy && expired.entryNames.contains("Music") }, timeout: 20) { _ in
                    expired.expireForCapture()
                    waitUntil({ !expired.isBusy && expired.errorText.contains("expired") }, timeout: 15) { shown in
                        capture.report.append("jellyfin.expiredShown=\(shown)")
                        capture.report.append("jellyfin.expiredError=\(expired.errorText)")
                        capture.checkpoint()
                        capture.root.dismiss(animated: false) {
                            jellyfinAuthError(capture, base: base, username: username)
                        }
                    }
                }
            }
        }
    }

    private static func jellyfinAuthError(_ capture: DownloadCapture, base: String, username: String) {
        let wrong = JellyfinViewController()
        capture.root.present(chrome(wrong), animated: false) {
            after(0.4) {
                wrong.signInForCapture(url: base, username: username, password: "wrong-password")
                waitUntil({ !wrong.isBusy && !wrong.errorText.isEmpty }, timeout: 15) { shown in
                    capture.report.append("jellyfin.authErrorShown=\(shown)")
                    capture.report.append("jellyfin.authError=\(wrong.errorText)")
                    capture.shot("jellyfin-error")
                    capture.checkpoint()
                    capture.root.dismiss(animated: false) {
                        jellyfinUnreachable(capture)
                    }
                }
            }
        }
    }

    private static func jellyfinUnreachable(_ capture: DownloadCapture) {
        let unreachable = JellyfinViewController()
        capture.root.present(chrome(unreachable), animated: false) {
            after(0.4) {
                unreachable.signInForCapture(url: "http://127.0.0.1:8793/", username: "demo", password: "secret")
                waitUntil({ !unreachable.isBusy && unreachable.errorText.contains("reach") }, timeout: 20) { shown in
                    capture.report.append("jellyfin.unreachableShown=\(shown)")
                    capture.report.append("jellyfin.unreachable=\(unreachable.errorText)")
                    capture.checkpoint()
                    capture.root.dismiss(animated: false) { cacheProbe(capture) }
                }
            }
        }
    }

    /// Real catalogue ids for the deep-link run; CI opens the scheme with them
    /// once the capture has finished.
    private static func writeDeepLinkIDs(_ capture: DownloadCapture) {
        var lines: [String] = []
        if let playlist = LibraryStore.shared.playlists.first {
            lines.append("playlist=\(playlist.id.replacingOccurrences(of: "remote:", with: ""))")
        }
        // A track link is a video id; the seed download's id is a JioSaavn one.
        InnerTube.shared.search("Blinding Lights The Weeknd", filter: .songs) { songs, _ in
            if let id = songs?.first?.videoID { lines.append("track=\(id)") }
            InnerTube.shared.searchCollections("Ed Sheeran", filter: .artists) { artists in
                if let id = artists.first?.browseID { lines.append("artist=\(id)") }
                InnerTube.shared.searchCollections("Divide", filter: .albums) { albums in
                    if let id = albums.first?.browseID { lines.append("album=\(id)") }
                    writeText(lines.joined(separator: "\n") + "\n",
                              name: "deeplink-ids.txt",
                              directory: capture.directory)
                }
            }
        }
    }

    private static func cacheProbe(_ capture: DownloadCapture) {
        // A known megabyte in the cache directory, so "cleared" is a measured
        // number rather than a code path that ran.
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? Data(repeating: 7, count: 1024 * 1024)
                .write(to: caches.appendingPathComponent("bc-cache-probe.bin"))
        }
        CacheStore.shared.configure()
        capture.report.append("cache.limit=\(CacheStore.shared.limitText)")
        let before = CacheStore.shared.sizeBytes
        let freed = CacheStore.shared.clearImageCache()
        capture.report.append("cache.size=\(before)")
        capture.report.append("cache.freed=\(freed)")
        capture.report.append("cache.cleared=\(freed >= 1024 * 1024)")
        let settings = SettingsViewController()
        capture.root.present(chrome(settings), animated: false) {
            after(0.8) {
                settings.scrollToDownloadSection()
                after(0.8) {
                    capture.shot("settings-cache")
                    capture.checkpoint()
                    capture.finish()
                }
            }
        }
    }

    /// Presents a screen the way the app reaches it: inside a navigation bar.
    private static func chrome(_ controller: UIViewController) -> UIViewController {
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        navigation.navigationBar.barTintColor = Theme.background
        navigation.navigationBar.tintColor = Theme.accent
        navigation.navigationBar.isTranslucent = false
        navigation.navigationBar.titleTextAttributes = [.foregroundColor: Theme.primaryText]
        navigation.navigationBar.largeTitleTextAttributes = [.foregroundColor: Theme.primaryText]
        navigation.navigationBar.prefersLargeTitles = true
        return navigation
    }

    private static func firstMoodTile(in view: UIView) -> MoodTileView? {
        if let tile = view as? MoodTileView { return tile }
        for child in view.subviews {
            if let found = firstMoodTile(in: child) { return found }
        }
        return nil
    }

    // MARK: - Background transfer launches

    /// Starts a download and hands the app back to CI while it is still running.
    ///
    /// In `keep` mode the process stays alive: the app is then sent to the
    /// background by CI and brought back, and the harness reports what happened
    /// while it was not frontmost. Without it the process exits at once, so CI
    /// can force-quit it mid-transfer and test the recovery path instead.
    private static func backgroundStart(directory: URL, keep: Bool) {
        let base = ["background.started=true", "background.mode=\(keep ? "keep" : "quit")"]
        SettingsStore.shared.set(DownloadQuality.high.rawValue, for: "BitChord.Download.Quality")
        SettingsStore.shared.set("Unlimited", for: DownloadStore.storageLimitKey)
        SettingsStore.shared.set(false, for: "BitChord.Download.WifiOnly")
        if let fixture = ProcessInfo.processInfo.environment["BC_DOWNLOAD_FIXTURE_URL"],
           !fixture.isEmpty {
            let track = Track(videoID: "background-fixture", title: "Background Fixture",
                              artist: "BitChord CI", album: "Fixture", durationSeconds: 40)
            DownloadStore.shared.remove(track.videoID)
            var reportBase = base
            reportBase.append("background.fixture=true")
            tryBackgroundStart([track], index: 0, base: reportBase,
                               directory: directory, keep: keep)
            return
        }
        CatalogueSearch.shared.songs("Can't Feel My Face The Weeknd") { tracks in
            // Anything already on disk would short-circuit, so take a fresh one.
            var fresh = tracks.filter { !DownloadStore.shared.isDownloaded($0.videoID) }
            if fresh.isEmpty {
                // The live search occasionally returns nothing; the transfer
                // fixture still has known catalogue songs to fall back on.
                let known = [
                    Track(videoID: "saavn:fW-Mxsnu", title: "Blinding Lights",
                          artist: "The Weeknd", album: "After Hours",
                          durationSeconds: 200),
                    Track(videoID: "XXYlFuWEuKI", title: "Save Your Tears",
                          artist: "The Weeknd", album: "After Hours",
                          durationSeconds: 215),
                    Track(videoID: "34Na4j8AVgA", title: "Starboy",
                          artist: "The Weeknd", album: "Starboy",
                          durationSeconds: 230),
                    Track(videoID: "KEI4qSrkPAs", title: "Can't Feel My Face",
                          artist: "The Weeknd", album: "Beauty Behind the Madness",
                          durationSeconds: 215),
                    Track(videoID: "qFLhGq0060w", title: "I Feel It Coming",
                          artist: "The Weeknd", album: "Starboy",
                          durationSeconds: 269),
                ]
                fresh = known.filter { !DownloadStore.shared.isDownloaded($0.videoID) }
            }
            // Screenshot passes seed and download other fixtures, so every
            // known song can already be on disk by the time this launch runs.
            // Recycle one saved row rather than reporting there is nothing to
            // transfer: the row is restored by the background download and the
            // later cold-launch assertions still see a populated locker.
            if fresh.isEmpty {
                // Recycle several saved rows so the retry loop has real
                // candidates instead of one resolver attempt deciding the run.
                let existing = Array(DownloadStore.shared.saved.prefix(4))
                for item in existing {
                    DownloadStore.shared.remove(item.track.videoID)
                }
                fresh = existing.map { $0.track }
            }
            tryBackgroundStart(fresh, index: 0, base: base, directory: directory, keep: keep)
        }
    }

    /// Starts a real background transfer. A resolver that hands back no URL
    /// produces no task at all; that is retried with the next fresh result so
    /// the scenario always begins from a transfer the system owns.
    private static func tryBackgroundStart(_ tracks: [Track],
                                           index: Int,
                                           base: [String],
                                           directory: URL,
                                           keep: Bool) {
        guard index < min(8, tracks.count) else {
            var report = base
            report.append("background.track=false")
            writeText(report.joined(separator: "\n"), name: "background-report.txt", directory: directory)
            exit(0)
            return
        }
        let track = tracks[index]
        var report = base
        report.append("background.track=\(track.videoID)")
        report.append("background.title=\(track.title)")
        DownloadStore.shared.download(track) { _, _ in }
        waitUntil({ DownloadStore.shared.isDownloading(track.videoID) }, timeout: 25) { started in
            after(1.2) {
                let live = started && DownloadStore.shared.pendingCount > 0
                guard live else {
                    report.append("background.retry=\(index) failure=\(DownloadStore.shared.failure(for: track.videoID) ?? "")")
                    writeText(report.joined(separator: "\n"),
                              name: "background-retry-\(index).txt", directory: directory)
                    var nextBase = base
                    nextBase.append("background.lastFailure=\(DownloadStore.shared.failure(for: track.videoID) ?? "none")")
                    nextBase.append("background.lastTrack=\(track.videoID)")
                    tryBackgroundStart(tracks, index: index + 1, base: nextBase, directory: directory, keep: keep)
                    return
                }
                report.append("background.live=\(started)")
                report.append("background.transport=\(DownloadStore.shared.transport[track.videoID] ?? "") (start)")
                report.append("background.pending=\(DownloadStore.shared.pendingCount)")
                report.append("background.progress=\(DownloadStore.shared.progress(for: track.videoID) ?? 0)")
                report.append("background.failure=\(DownloadStore.shared.failure(for: track.videoID) ?? "")")
                report.append("background.saved=\(DownloadStore.shared.saved.count)")
                report.append("background.limit=\(DownloadStore.shared.storageLimitBytes)")
                report.append("background.wifiOnly=\(SettingsStore.shared.bool("BitChord.Download.WifiOnly", true))")
                report.append("background.playing=\(PlayerService.shared.isPlaying)")
                writeText(report.joined(separator: "\n"), name: "background-report.txt", directory: directory)
                if keep {
                    waitForReturn(directory: directory, videoID: track.videoID)
                } else {
                    // Leave without finishing: the transfer belongs to the system now.
                    exit(0)
                }
            }
        }
    }

    /// Reports once the app has been away and is frontmost again, so the file
    /// on disk and the index are read after the interruption, not before it.
    private static func waitForReturn(directory: URL, videoID: String) {
        var leftForeground = false
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil, queue: .main) { _ in
            leftForeground = true
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            guard leftForeground else { return }
            var report = readBackgroundReport(directory: directory)
            report.append("background.resumedAfterLeave=true")
            waitUntil({ DownloadStore.shared.pendingCount == 0 }, timeout: 90) { _ in
                report.append(contentsOf: settleLines(videoID: videoID, directory: directory))
                writeText(report.joined(separator: "\n"),
                          name: "background-resumed.txt", directory: directory)
                try? "done".write(to: directory.appendingPathComponent("background-resumed-done.txt"),
                                  atomically: true, encoding: .utf8)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
            }
        }
    }

    /// Relaunched after the process was force-quit: adopt whatever the system
    /// delivered, or report the interruption, and never leave a phantom entry.
    private static func backgroundVerify(directory: URL, label: String) {
        var report: [String] = ["background.label=\(label)"]
        let started = readBackgroundReport(directory: directory)
        let videoID = started.first(where: { $0.hasPrefix("background.track=") })?
            .replacingOccurrences(of: "background.track=", with: "")
        report.append(contentsOf: started.filter { $0.hasPrefix("background.transport=") })
        report.append("verify.pendingAtLaunch=\(DownloadStore.shared.pendingCount)")
        report.append("verify.savedAtLaunch=\(DownloadStore.shared.saved.count)")
        // Read-back of the playlist the previous process synced: a fresh launch
        // reads it off disk, so this is the relaunch proof, not memory.
        report.append("verify.playlists=\(LibraryStore.shared.playlists.count)")
        // A fresh process after the first-run flow must not show it again.
        report.append("verify.onboardingCompleted=\(OnboardingViewController.hasCompleted)")
        report.append("verify.onboardingPresented=\(UIApplication.shared.keyWindow?.rootViewController?.presentedViewController is OnboardingViewController)")
        if let playlist = LibraryStore.shared.playlists.first(where: { $0.id.hasPrefix("remote:") }) {
            report.append("verify.playlistTitle=\(playlist.title)")
            report.append("verify.playlistTracks=\(playlist.tracks.count)")
            report.append("verify.playlistFirst=\(playlist.tracks.first?.title ?? "")")
            report.append("verify.playlistLast=\(playlist.tracks.last?.title ?? "")")
        }
        guard let id = videoID, !id.isEmpty else {
            report.append("background.settled=true")
            report.append("background.reason=no-track-in-start-report")
            report.append("background.phantom=false")
            writeText(report.joined(separator: "\n"), name: "background-\(label).txt", directory: directory)
            try? "done".write(to: directory.appendingPathComponent("background-\(label)-done.txt"),
                              atomically: true, encoding: .utf8)
            exit(0)
        }
        report.append("verify.track=\(id)")
        if DownloadStore.shared.isDownloaded(id) {
            report.append("background.deliveredBeforeCheck=true")
        }
        waitUntil({ DownloadStore.shared.pendingCount == 0 }, timeout: 150) { _ in
            report.append("background.settled=true")
            report.append(contentsOf: settleLines(videoID: id, directory: directory))
            // A fresh process reading the locker and the queue history back off
            // disk is the relaunch proof for both.
            extrasReadBack { extra in
                report.append(contentsOf: extra)
                writeText(report.joined(separator: "\n"), name: "background-\(label).txt", directory: directory)
                try? "done".write(to: directory.appendingPathComponent("background-\(label)-done.txt"),
                                  atomically: true, encoding: .utf8)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
            }
        }
    }

    private static func extrasReadBack(_ completion: @escaping ([String]) -> Void) {
        LocalMusicStore.shared.scan { songs in
            var lines: [String] = []
            lines.append("verify.localTracks=\(songs.count)")
            lines.append("verify.localTitle=\(songs.first?.track.title ?? "")")
            let history = PlaybackHistoryStore.shared.items
            lines.append("verify.history=\(history.count)")
            lines.append("verify.historyTop=\(history.first?.title ?? "")")
            completion(lines)
        }
    }

    /// The shared tail of both background reports: did the track land, was the
    /// interruption reported instead, and is every index entry backed by a file.
    private static func settleLines(videoID: String, directory: URL) -> [String] {
        let store = DownloadStore.shared
        let indexed = store.isDownloaded(videoID)
        let reason = store.failure(for: videoID) ?? ""
        let phantom = store.saved.contains { store.localURL(for: $0.track.videoID) == nil }
        return [
            "background.indexed=\(indexed)",
            "background.reported=\(!reason.isEmpty)",
            "background.reason=\(reason)",
            "background.pendingAfter=\(store.pendingCount)",
            "background.saved=\(store.saved.count)",
            "background.bytes=\(store.totalBytes)",
            "background.failed=\(store.failedItems.count)",
            "background.phantom=\(phantom)",
            "background.ok=\(indexed || !reason.isEmpty)"
        ]
    }

    private static func readBackgroundReport(directory: URL) -> [String] {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("background-report.txt"),
                                     encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    /// Exercises the URL forms upstream's Android intent filters expose. The
    /// custom scheme is still the only one the OS can associate on iOS 12;
    /// this proves the parser and router that the universal-link callback
    /// shares accept the web shapes without making `simctl launch` carry a
    /// query-bearing URL through argv.
    private static func captureWebLinks(directory: URL) {
        let urls: [(String, String)] = [
            ("watch", "https://music.youtube.com/watch?v=J7p4bzqLvCw"),
            ("short", "https://youtu.be/J7p4bzqLvCw"),
            ("playlist", "https://music.youtube.com/playlist?list=PLP32wGpgzmIlDFQuxl1qeH33hJJSq8wfe"),
            ("search", "https://music.youtube.com/search?q=Blinding+Lights")
        ]
        var report: [String] = []
        for (name, raw) in urls {
            guard let url = URL(string: raw), let route = DeepLink.parse(url) else {
                report.append("web.\(name)=invalid")
                continue
            }
            report.append("web.\(name)=\(DeepLinkRouter.describe(route))")
        }
        report.append("web.done=true")
        writeText(report.joined(separator: "\n"), name: "web-links-report.txt", directory: directory)
        exit(0)
    }

    fileprivate static func writeReport(_ text: String, directory: URL) {
        writeText(text, name: "download-report.txt", directory: directory)
    }

    fileprivate static func writeText(_ text: String, name: String, directory: URL) {
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        try? text.write(to: directory.appendingPathComponent(name),
                        atomically: true, encoding: .utf8)
    }

    fileprivate static func write(window: UIWindow, name: String, directory: URL) {
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

/// Shared state for the download capture steps. It also writes the `done` marker
/// the CI job waits for instead of guessing how long the sequence takes.
private final class DownloadCapture {
    let window: UIWindow
    let root: RootViewController
    let directory: URL
    let store = DownloadStore.shared
    var report: [String] = []
    var seedTrack: Track?
    var extraTrack: Track?
    var spareTrack: Track?
    var highBytes: Int64 = 0
    var saverBytes: Int64 = 0
    var syncedTitle = ""
    var syncedTracks: [Track] = []

    init(window: UIWindow, root: RootViewController, directory: URL) {
        self.window = window
        self.root = root
        self.directory = directory
    }

    func shot(_ name: String) {
        ScreenshotHarness.write(window: window, name: name, directory: directory)
    }

    func checkpoint() {
        ScreenshotHarness.writeReport(report.joined(separator: "\n"), directory: directory)
    }

    func finish() {
        report.append("done=true")
        checkpoint()
        try? "done".write(to: directory.appendingPathComponent("done.txt"),
                          atomically: true, encoding: .utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
    }
}
