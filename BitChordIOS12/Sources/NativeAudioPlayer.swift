import AVFoundation
import Foundation

/// Plays a track's audio with AVFoundation from a resolved direct stream URL.
///
/// The embedded web player is a WebKit media pipeline inside a web view, and on iOS 12 that
/// pipeline stalls: the element reports `paused = false`, `muted = false`, no error, and yet
/// `currentTime` never advances. AVPlayer has no such dependency — it decodes AAC in MP4
/// natively, which is exactly what JioSaavn's CDN serves — so this is the path playback
/// takes whenever a stream URL can be resolved. JioSaavn is tried first and YouTube
/// resolution is the fallback for catalogue gaps.
final class NativeAudioPlayer: NSObject {
    var onStateChanged: ((BridgePlaybackState) -> Void)?
    var onTimeUpdated: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onPlaybackError: ((Int) -> Void)?

    private let player = AVPlayer()
    private var item: AVPlayerItem?
    private var timeObserver: Any?
    private var statusToken: NSKeyValueObservation?
    private var endToken: NSObjectProtocol?
    private var requestTicket = 0
    private var lastProgressDate = Date()
    private var lastKnownPosition: Double = 0
    private var desiredRate: Double = 1
    private var desiredVolume: Float = 1

    private(set) var isPausedByUser = false
    private(set) var isReady = false
    private(set) var currentVideoId: String?
    private var currentTrack: Track?
    /// Which catalogue served the loaded item ("JioSaavn 320kbps", "YouTube", or "").
    private var sourceLabel = "
    private(set) var lastDiagnostic = ""
    private(set) var diagnosticsSummary = "native: idle"
    private(set) var secondsSinceProgress: TimeInterval = 0

    override init() {
        super.init()
        player.actionAtItemEnd = .pause
        // Audio-only playback should never wait for a video pipeline or a screen.
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.handleTick(CMTimeGetSeconds(time))
        }
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        if let token = endToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Loading

    func play(track: Track, at position: Double = 0, completion: @escaping (Bool) -> Void) {
        currentVideoId = track.videoID
        currentTrack = track
        sourceLabel = ""
        isPausedByUser = false
        isReady = false
        lastKnownPosition = position
        lastProgressDate = Date()
        secondsSinceProgress = 0
        requestTicket += 1
        let ticket = requestTicket
        diagnosticsSummary = "native: resolving (saavn)"

        // JioSaavn first: its CDN URLs are direct progressive MP4 that AVPlayer
        // decodes on iOS 12 with no signature to break. YouTube resolution is the
        // fallback for catalogue gaps.
        JioSaavnService.shared.resolve(title: track.title,
                                       artist: track.artist,
                                       durationSeconds: track.durationSeconds) { [weak self] url, _ in
            guard let self = self, self.requestTicket == ticket else { return }
            if let url = url, let scheme = url.scheme, scheme.hasPrefix("http") {
                self.sourceLabel = JioSaavnService.shared.lastQualityLabel
                self.start(url: url, at: position)
                completion(true)
                return
            }
            self.diagnosticsSummary = "native: resolving (youtube)"
            InnerTube.shared.resolveStreamURL(videoID: track.videoID) { [weak self] url, reason in
                guard let self = self, self.requestTicket == ticket else { return }
                guard let url = url, let scheme = url.scheme, scheme.hasPrefix("http") else {
                    self.lastDiagnostic = reason.isEmpty ? "No stream URL was returned." : reason
                    self.diagnosticsSummary = "native: no stream (" + self.lastDiagnostic.prefix(60) + ")"
                    completion(false)
                    return
                }
                self.sourceLabel = "YouTube"
                self.start(url: url, at: position)
                completion(true)
            }
        }
    }

    private func start(url: URL, at position: Double) {
        teardownItem()

        let newItem = AVPlayerItem(url: url)
        item = newItem
        lastProgressDate = Date()
        secondsSinceProgress = 0
        diagnosticsSummary = "native: buffering"
        lastDiagnostic = ""

        statusToken = newItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                self.isReady = true
                if position > 0 {
                    self.player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
                }
                self.applyTransport()
                self.onStateChanged?(.playing)
            case .failed:
                self.isReady = false
                self.lastDiagnostic = item.error?.localizedDescription ?? "The audio stream failed to load."
                self.diagnosticsSummary = "native: failed " + String(self.lastDiagnostic.prefix(60))
                self.onPlaybackError?(-1)
            default:
                break
            }
        }

        endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.onStateChanged?(.ended)
            self.onPlaybackEnded?()
        }

        player.replaceCurrentItem(with: newItem)
    }

    private func teardownItem() {
        statusToken = nil
        if let token = endToken {
            NotificationCenter.default.removeObserver(token)
            endToken = nil
        }
        player.pause()
        item = nil
    }

    // MARK: - Clock

    private func handleTick(_ seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        let duration = currentDuration()

        if seconds > lastKnownPosition + 0.05 {
            lastProgressDate = Date()
            lastKnownPosition = seconds
        }
        secondsSinceProgress = Date().timeIntervalSince(lastProgressDate)

        let source = sourceLabel.isEmpty ? "" : " " + sourceLabel
        diagnosticsSummary = "native" + source + " t=" + String(format: "%.1f", seconds)
            + "/" + String(format: "%.0f", duration)
            + " rate=" + String(format: "%.2f", Double(player.rate))
            + " stale=" + String(Int(secondsSinceProgress)) + "s"

        onTimeUpdated?(seconds, duration)

        // A stalled AVPlayer keeps its item ready but drops its rate to zero. Ask it to go again
        // rather than waiting for a user to notice the silence.
        if !isPausedByUser, player.rate == 0, item?.status == .readyToPlay, isReady {
            player.play()
            player.rate = Float(desiredRate)
        }
    }

    private func currentDuration() -> Double {
        guard let item = item else { return 0 }
        let seconds = CMTimeGetSeconds(item.duration)
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    // MARK: - Transport

    func pause() {
        isPausedByUser = true
        player.pause()
        onStateChanged?(.paused)
    }

    func resume() {
        isPausedByUser = false
        player.play()
        player.rate = Float(desiredRate)
        onStateChanged?(.playing)
    }

    func seek(to seconds: TimeInterval) {
        lastKnownPosition = seconds
        lastProgressDate = Date()
        secondsSinceProgress = 0
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func setVolume(_ volume: Float) {
        desiredVolume = volume
        player.volume = volume
        player.isMuted = volume <= 0.001
    }

    func setPlaybackRate(_ rate: Double) {
        guard rate > 0 else { return }
        desiredRate = rate
        if !isPausedByUser {
            player.rate = Float(rate)
        }
    }

    func refreshSession() {
        guard let track = currentTrack else { return }
        let position = lastKnownPosition
        play(track: track, at: position) { _ in }
    }

    func stop() {
        requestTicket += 1
        isReady = false
        teardownItem()
    }

    private func applyTransport() {
        player.volume = desiredVolume
        player.isMuted = desiredVolume <= 0.001
        guard !isPausedByUser else { return }
        player.play()
        player.rate = Float(desiredRate)
    }
}
