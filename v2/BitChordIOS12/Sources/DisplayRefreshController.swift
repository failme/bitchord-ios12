import UIKit

/// Per-app frame-rate control for the continuously animated surfaces.
///
/// UIKit owns the screen refresh, but a `CADisplayLink` is the public per-app
/// pacing API: setting `preferredFramesPerSecond` makes the app's own frame
/// callback run at that cadence (and the system honours it up to the panel's
/// maximum). The Settings row therefore changes a measured callback rate, not
/// just a stored string.
final class DisplayRefreshController: NSObject {
    static let shared = DisplayRefreshController()

    private(set) var requestedFPS: Int = 60
    private(set) var effectiveFPS: Int = 0
    private(set) var isRunning = false
    private var link: CADisplayLink?
    private var frames = 0
    private var lastSample = Date()

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySettings()
        }
    }

    func start() {
        applySettings()
    }

    private func applySettings() {
        let raw = SettingsStore.shared.string("BitChord.Performance.RefreshRate", "Auto")
        requestedFPS = raw == "30" ? 30 : 60
        if link == nil {
            link = CADisplayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
            isRunning = true
        }
        link?.preferredFramesPerSecond = requestedFPS
    }

    @objc private func tick() {
        frames += 1
        let elapsed = Date().timeIntervalSince(lastSample)
        if elapsed >= 1 {
            effectiveFPS = Int((Double(frames) / elapsed).rounded())
            frames = 0
            lastSample = Date()
        }
    }

    var report: String {
        return "requested=\(requestedFPS) effective=\(effectiveFPS) running=\(isRunning)"
    }
}
