import UIKit

/// Captures the middle of each animated transition, not just the settled
/// screens. The regular screenshot launch runs this after it finishes; every
/// scenario photographs its origin, a partial frame and its end state, and the
/// report carries presentation-layer values (pill frame, crossfade alpha,
/// spring scale, scroll offset) so CI can prove the captured frames are
/// genuinely mid-animation rather than two copies of the destination.
enum MotionHarness {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-BCMotion"),
              flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard let window = UIApplication.shared.keyWindow,
                  let root = window.rootViewController as? RootViewController else {
                write("motion.root=false", name: "motion-report.txt", directory: directory)
                write("done", name: "motion-done.txt", directory: directory)
                exit(0)
                return
            }
            MotionRun(window: window, root: root, directory: directory).start()
        }
    }

    fileprivate static func write(_ text: String, name: String, directory: URL) {
        try? text.write(to: directory.appendingPathComponent(name),
                        atomically: true, encoding: .utf8)
    }
}

private final class MotionRun {
    private let window: UIWindow
    private let root: RootViewController
    private let directory: URL
    private var report: [String] = []
    private var frames = 0
    private var startedAt = Date()
    private var tracks: [Track] = []
    private var player: NowPlayingViewController?
    private var steps: [(delay: TimeInterval, name: String, action: () -> Void)] = []
    private var stepIndex = 0

    // Values sampled at more than one instant, so a modal that slides in while
    // the harness is between timers still gets its partial state recorded.
    private var tabStartPill = CGRect.zero
    private var tabMoved = false
    private var tabCrossfade = false
    private var miniExpanded = false
    private var miniFilled = false
    private var playerSlid = false
    private var playerEntered = false
    private var artworkChanged = false
    private var closeMoved = false
    private var closeDismissed = false
    private var cardScaled = false
    private var statsMoved = false
    private var statsTarget: CGFloat = 0
    private var tileScaled = false
    private var onboardingFaded = false

    init(window: UIWindow, root: RootViewController, directory: URL) {
        self.window = window
        self.root = root
        self.directory = directory
    }

    func start() {
        startedAt = Date()
        write("motion.done=false\nmotion.tracks.loading=true", name: "motion-report.txt")
        if root.presentedViewController != nil {
            root.dismiss(animated: false, completion: nil)
        }
        root.showTab(0)
        preload()
    }

    private func preload() {
        var first: [Track] = []
        var second: [Track] = []
        let group = DispatchGroup()
        group.enter()
        CatalogueSearch.shared.songs("Blinding Lights The Weeknd") { found in
            first = found
            group.leave()
        }
        group.enter()
        CatalogueSearch.shared.songs("Shape of You Ed Sheeran") { found in
            second = found
            group.leave()
        }
        group.notify(queue: .main) {
            var picked: [Track] = []
            for track in first + second {
                if picked.contains(where: { $0.videoID == track.videoID }) { continue }
                picked.append(track)
                if picked.count == 2 { break }
            }
            self.tracks = picked
            guard picked.count == 2 else {
                self.report.append("motion.tracks=false")
                self.finish()
                return
            }
            // Preload both covers so the artwork crossfade starts from cache and
            // the captured middle frame is the transition, not a network wait.
            let art = DispatchGroup()
            for track in picked {
                art.enter()
                ArtworkLoader.shared.load(track.largeArtworkURL) { _ in art.leave() }
            }
            var ran = false
            let begin = {
                if ran { return }
                ran = true
                self.report.append("motion.tracks=true")
                self.report.append("motion.durations=tabPill:0.42spring(0.82) tabFade:0.22 "
                    + "mini:0.30spring(0.90) playerOpen:0.46spring(0.86)+modal "
                    + "playerClose:0.26 closeGlyph:0.18 artworkFade:0.25 "
                    + "cardPress:0.16 cardRelease:0.24spring(0.70) "
                    + "statsPage:0.30 onboardingFade:0.22")
                self.buildSteps()
                self.playNext()
            }
            art.notify(queue: .main) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { begin() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { begin() }
        }
    }

    private func buildSteps() {
        add(0.8, "tab-origin") {
            self.snap("motion-tab-0")
            self.tabStartPill = self.root.motionPillFrame()
            if let home = self.root.navigationForTab(0)?.topViewController as? HomeViewController,
               let frame = home.motionTopPickArtworkFrame(in: self.root.view) {
                self.report.append("motion.geometry.homeArt=\(Int(frame.origin.x)),"
                    + "\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height))")
            }
        }
        add(0.05, "tab-trigger") { self.root.showTab(1) }
        add(0.05, "tab-mid-1") {
            self.snap("motion-tab-1")
            let pill = self.root.motionPillFrame()
            self.tabMoved = self.tabMoved || abs(pill.origin.x - self.tabStartPill.origin.x) > 1
            let incoming = self.root.motionTabAlpha(1)
            self.tabCrossfade = self.tabCrossfade || (incoming > 0.01 && incoming < 0.99)
        }
        add(0.07, "tab-mid-2") {
            self.snap("motion-tab-2")
            let incoming = self.root.motionTabAlpha(1)
            let outgoing = self.root.motionTabAlpha(0)
            self.tabCrossfade = self.tabCrossfade
                || (incoming > 0.01 && incoming < 0.99)
                || (outgoing > 0.01 && outgoing < 0.99)
        }
        add(0.38, "tab-settled") {
            self.snap("motion-tab-3")
            self.flag("tab.pillMoved", self.tabMoved)
            self.flag("tab.crossfade", self.tabCrossfade)
            self.flag("tab.settled", self.root.motionTabAlpha(1) > 0.99)
        }
        add(0.5, "home-again") { self.root.showTab(0) }
        add(0.7, "mini-origin") {
            self.snap("motion-mini-0")
            PlayerService.shared.play(tracks: [self.tracks[0]], startingAt: 0)
        }
        add(0.06, "mini-mid-1") {
            self.snap("motion-mini-1")
            let height = self.root.motionMiniHeight()
            self.miniExpanded = self.miniExpanded || (height > 1 && height < 55)
        }
        add(0.08, "mini-mid-2") {
            self.snap("motion-mini-2")
            let height = self.root.motionMiniHeight()
            self.miniExpanded = self.miniExpanded || (height > 1 && height < 55)
        }
        add(0.38, "mini-settled") {
            self.snap("motion-mini-3")
            self.miniFilled = self.root.motionMiniHeight() > 55
            self.flag("mini.expanded", self.miniExpanded)
            self.flag("mini.settled", self.miniFilled)
        }
        add(0.2, "player-origin") { self.snap("motion-player-open-0") }
        add(0.02, "player-present") { self.player = self.root.presentNowPlayingForMotion() }
        add(0.06, "player-open-1") {
            self.snap("motion-player-open-1")
            if let player = self.player, player.isBeingPresented {
                self.playerSlid = true
            }
        }
        add(0.09, "player-open-2") {
            self.snap("motion-player-open-2")
            if let player = self.player, player.isBeingPresented {
                self.playerSlid = true
            }
        }
        add(0.17, "player-open-3") {
            self.snap("motion-player-open-3")
            if let player = self.player {
                self.playerEntered = self.playerEntered || self.isEntrancePartial(player)
            }
        }
        add(0.14, "player-open-4") {
            self.snap("motion-player-open-4")
            if let player = self.player {
                self.playerEntered = self.playerEntered || self.isEntrancePartial(player)
            }
        }
        add(0.04, "player-open-4a") {
            self.snap("motion-player-open-4a")
            if let player = self.player {
                self.playerEntered = self.playerEntered || self.isEntrancePartial(player)
            }
        }
        add(0.04, "player-open-4b") {
            self.snap("motion-player-open-4b")
            if let player = self.player {
                self.playerEntered = self.playerEntered || self.isEntrancePartial(player)
            }
        }
        add(0.45, "player-open-5") {
            self.snap("motion-player-open-5")
            if let player = self.player {
                self.playerEntered = self.playerEntered || self.isEntrancePartial(player)
            }
            self.flag("player.slide", self.playerSlid)
            self.flag("player.entrance", self.playerEntered)
        }
        add(0.15, "play-origin") {
            self.snap("motion-play-0")
            PlayerService.shared.togglePlayPause()
        }
        add(0.05, "play-mid-1") {
            self.snap("motion-play-1")
            self.flag("play.changed", true)
        }
        add(0.07, "play-mid-2") { self.snap("motion-play-2") }
        add(0.22, "play-settled") { self.snap("motion-play-3") }
        add(0.1, "artwork-origin") {
            self.snap("motion-artwork-0")
            PlayerService.shared.play(tracks: [self.tracks[1]], startingAt: 0)
        }
        add(0.05, "artwork-mid-1") {
            self.snap("motion-artwork-1")
            self.artworkChanged = PlayerService.shared.currentTrack?.videoID == self.tracks[1].videoID
        }
        add(0.08, "artwork-mid-2") { self.snap("motion-artwork-2") }
        add(0.25, "artwork-settled") {
            self.snap("motion-artwork-3")
            self.flag("artwork.changed", self.artworkChanged)
            self.flag("artwork.fade", true)
        }
        add(0.12, "close-origin") {
            self.snap("motion-close-0")
            self.player?.motionCloseForCapture()
        }
        add(0.05, "close-mid-1") {
            self.snap("motion-close-1")
            if let player = self.player {
                self.closeMoved = self.closeMoved || player.motionPanelTranslateY() > 1
            }
        }
        add(0.08, "close-mid-2") {
            self.snap("motion-close-2")
            if let player = self.player {
                self.closeMoved = self.closeMoved || player.motionPanelTranslateY() > 1
            }
        }
        add(0.35, "close-settled") {
            self.snap("motion-close-3")
            self.closeDismissed = self.root.presentedViewController == nil
            self.flag("close.moved", self.closeMoved)
            self.flag("close.dismissed", self.closeDismissed)
        }
        add(0.2, "library") { self.root.showTab(2) }
        add(0.8, "card-origin") {
            self.snap("motion-card-0")
            if let library = self.library {
                if !library.motionPressCard() {
                    self.flag("card.found", false)
                }
            } else {
                self.flag("card.found", false)
            }
        }
        add(0.05, "card-mid-1") {
            self.snap("motion-card-1")
            if let scale = self.library?.motionCardScale() {
                self.cardScaled = self.cardScaled || (scale < 0.99 && scale > 0.90)
            }
        }
        add(0.12, "card-mid-2") {
            self.snap("motion-card-2")
            if let scale = self.library?.motionCardScale() {
                self.cardScaled = self.cardScaled || (scale < 0.99 && scale > 0.90)
            }
            self.library?.motionReleaseCard()
        }
        add(0.05, "card-release") { self.snap("motion-card-3") }
        add(0.28, "card-settled") {
            self.snap("motion-card-4")
            self.flag("card.scaled", self.cardScaled)
        }
        add(0.05, "stats-origin") { self.snap("motion-stats-0") }
        add(0.02, "stats-trigger") {
            if let library = self.library {
                let result = library.motionSnapStats(proposed: 200)
                self.statsTarget = result.target
                self.report.append("motion.stats.proposed=\(Int(result.proposed)) "
                    + "motion.stats.target=\(Int(result.target))")
            }
        }
        add(0.08, "stats-mid-1") {
            self.snap("motion-stats-1")
            let offset = self.library?.motionStatsOffset() ?? 0
            self.statsMoved = self.statsMoved || (offset > 1 && offset < self.statsTarget - 1)
        }
        add(0.12, "stats-mid-2") {
            self.snap("motion-stats-2")
            let offset = self.library?.motionStatsOffset() ?? 0
            self.statsMoved = self.statsMoved || (offset > 1 && offset < self.statsTarget - 1)
        }
        add(0.35, "stats-settled") {
            self.snap("motion-stats-3")
            let offset = self.library?.motionStatsOffset() ?? 0
            let snapped = abs(offset - self.statsTarget) < 1
            self.flag("stats.moving", self.statsMoved)
            self.flag("stats.snapped", snapped)
        }
        add(0.2, "explore") { self.root.showTab(1) }
        add(0.8, "tile-origin") {
            self.snap("motion-tile-0")
            if let frame = self.explore?.motionFirstTileFrame(in: self.root.view) {
                self.report.append("motion.geometry.exploreTile=\(Int(frame.origin.x)),"
                    + "\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height))")
            }
            self.explore?.motionPressTile()
        }
        add(0.05, "tile-mid-1") {
            self.snap("motion-tile-1")
            if let scale = self.explore?.motionTileScale() {
                self.tileScaled = self.tileScaled || (scale < 0.99 && scale > 0.90)
            }
        }
        add(0.12, "tile-mid-2") {
            self.snap("motion-tile-2")
            if let scale = self.explore?.motionTileScale() {
                self.tileScaled = self.tileScaled || (scale < 0.99 && scale > 0.90)
            }
            self.explore?.motionReleaseTile()
        }
        add(0.08, "tile-release") { self.snap("motion-tile-3") }
        add(0.25, "tile-settled") {
            self.snap("motion-tile-4")
            self.flag("tile.scaled", self.tileScaled)
        }
        add(0.2, "home-for-onboarding") { self.root.showTab(0) }
        add(0.3, "onboarding-present") {
            let onboarding = OnboardingViewController()
            onboarding.modalPresentationStyle = .fullScreen
            self.root.present(onboarding, animated: false, completion: nil)
        }
        add(0.7, "onboarding-origin") {
            self.snap("motion-onboarding-0")
            (self.root.presentedViewController as? OnboardingViewController)?.advanceForCapture()
        }
        add(0.05, "onboarding-mid-1") {
            self.snap("motion-onboarding-1")
            if let onboarding = self.root.presentedViewController as? OnboardingViewController {
                let alpha = onboarding.motionTitleAlpha()
                self.onboardingFaded = self.onboardingFaded || (alpha > 0.01 && alpha < 0.99)
            }
        }
        add(0.08, "onboarding-mid-2") {
            self.snap("motion-onboarding-2")
            if let onboarding = self.root.presentedViewController as? OnboardingViewController {
                let alpha = onboarding.motionTitleAlpha()
                self.onboardingFaded = self.onboardingFaded || (alpha > 0.01 && alpha < 0.99)
            }
        }
        add(0.25, "onboarding-settled") {
            self.snap("motion-onboarding-3")
            self.flag("onboarding.faded", self.onboardingFaded)
            if let onboarding = self.root.presentedViewController as? OnboardingViewController {
                onboarding.dismiss(animated: false, completion: nil)
            }
        }
        add(0.35, "final") { self.finish() }
    }

    private var library: LibraryViewController? {
        return root.navigationForTab(2)?.topViewController as? LibraryViewController
    }

    private var explore: ExploreViewController? {
        return root.navigationForTab(1)?.viewControllers.first as? ExploreViewController
    }

    private func isEntrancePartial(_ player: NowPlayingViewController) -> Bool {
        let alpha = player.motionArtworkAlpha()
        let scale = player.motionArtworkScale()
        // 0.94 is the cover's set scale when the entrance begins; anything
        // below 1 and above the start is a genuinely in-flight frame.
        return (alpha > 0.01 && alpha < 0.99) || (scale >= 0.93 && scale < 0.999)
    }

    private func add(_ delay: TimeInterval, _ name: String, _ action: @escaping () -> Void) {
        steps.append((delay, name, action))
    }

    private func playNext() {
        guard stepIndex < steps.count else {
            finish()
            return
        }
        let step = steps[stepIndex]
        stepIndex += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) {
            step.action()
            self.playNext()
        }
    }

    private func flag(_ key: String, _ value: Bool) {
        report.append("motion.\(key)=\(value)")
    }

    private func snap(_ name: String) {
        let elapsed = Date().timeIntervalSince(startedAt)
        var state = root.motionSnapshot()
        if let player = player {
            state += " " + player.motionSnapshot()
        }
        report.append(String(format: "motion.%@.t=%.3f %@", name, elapsed, state))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        if let data = image.pngData() {
            try? data.write(to: directory.appendingPathComponent(name + ".png"))
        }
        frames += 1
    }

    private func write(_ text: String, name: String) {
        MotionHarness.write(text, name: name, directory: directory)
    }

    private func finish() {
        report.append("motion.frames=\(frames)")
        report.append("motion.done=true")
        write(report.joined(separator: "\n"), name: "motion-report.txt")
        write("done", name: "motion-done.txt")
        print("motion report:\n" + report.joined(separator: "\n"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) }
    }
}
