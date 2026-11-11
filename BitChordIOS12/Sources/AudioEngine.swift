import Foundation

/// The single audio surface `PlayerService` talks to.
///
/// A track is played with AVFoundation when YouTube returns a stream URL, which is the reliable
/// path on iOS 12. When resolution fails (age-gated or region-gated videos answer `UNPLAYABLE`
/// for every anonymous client), playback falls back to the embedded web player instead of
/// leaving the queue stuck.
///
/// Both players are wired up once, and each forwards only while it is the active one: the web
/// view keeps probing in the background after a switch, and its stale position reports would
/// otherwise overwrite the real clock.
final class AudioEngine {
    static let shared = AudioEngine()

    var onStateChanged: ((BridgePlaybackState) -> Void)?
    var onTimeUpdated: ((Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onPlaybackError: ((Int) -> Void)?
    var onBridgeRecovering: (() -> Void)?
    var onApiReady: (() -> Void)?

    private enum Mode: Equatable {
        case native
        case web
    }

    private var mode: Mode = .native
    private let native = NativeAudioPlayer()
    private let web = YouTubeBridge.shared

    private init() {
        native.onStateChanged = { [weak self] state in
            guard let self = self, self.mode == .native else { return }
            self.onStateChanged?(state)
        }
        native.onTimeUpdated = { [weak self] position, total in
            guard let self = self, self.mode == .native else { return }
            self.onTimeUpdated?(position, total)
        }
        native.onPlaybackEnded = { [weak self] in
            guard let self = self, self.mode == .native else { return }
            self.onPlaybackEnded?()
        }
        native.onPlaybackError = { [weak self] code in
            guard let self = self, self.mode == .native else { return }
            self.onPlaybackError?(code)
        }

        web.onStateChanged = { [weak self] state in
            guard let self = self, self.mode == .web else { return }
            self.onStateChanged?(state)
        }
        web.onTimeUpdated = { [weak self] position, total in
            guard let self = self, self.mode == .web else { return }
            self.onTimeUpdated?(position, total)
        }
        web.onPlaybackEnded = { [weak self] in
            guard let self = self, self.mode == .web else { return }
            self.onPlaybackEnded?()
        }
        web.onPlaybackError = { [weak self] code in
            guard let self = self, self.mode == .web else { return }
            self.onPlaybackError?(code)
        }
        web.onBridgeRecovering = { [weak self] in
            guard let self = self, self.mode == .web else { return }
            self.onBridgeRecovering?()
        }
        web.onApiReady = { [weak self] in
            guard let self = self, self.mode == .web else { return }
            self.onApiReady?()
        }
    }

    // MARK: - State

    var isPausedByUser: Bool {
        mode == .native ? native.isPausedByUser : web.isPausedByUser
    }

    var isReady: Bool {
        mode == .native ? native.isReady : web.isReady
    }

    var currentVideoId: String? {
        mode == .native ? native.currentVideoId : web.currentVideoId
    }

    var lastDiagnostic: String {
        mode == .native ? native.lastDiagnostic : web.lastDiagnostic
    }

    var lastReferrer: String {
        web.lastReferrer
    }

    var diagnosticsSummary: String {
        mode == .native ? native.diagnosticsSummary : web.diagnosticsSummary
    }

    var secondsSinceProgress: TimeInterval {
        mode == .native ? native.secondsSinceProgress : web.secondsSinceProgress
    }

    // MARK: - Control

    func play(videoId: String) {
        web.stop()
        mode = .native
        native.play(videoId: videoId) { [weak self] resolved in
            guard let self = self else { return }
            guard !resolved else { return }
            // No stream URL: fall back to the web player rather than dropping the track.
            self.mode = .web
            self.native.stop()
            self.web.play(videoId: videoId)
        }
    }

    func pause() {
        if mode == .native {
            native.pause()
        } else {
            web.pause()
        }
    }

    func resume() {
        if mode == .native {
            native.resume()
        } else {
            web.resume()
        }
    }

    func seek(to seconds: TimeInterval) {
        if mode == .native {
            native.seek(to: seconds)
        } else {
            web.seek(to: seconds)
        }
    }

    func setVolume(_ volume: Float) {
        native.setVolume(volume)
        web.setVolume(volume)
    }

    func setPlaybackRate(_ rate: Double) {
        native.setPlaybackRate(rate)
        web.setPlaybackRate(rate)
    }

    func refreshSession() {
        if mode == .native {
            native.refreshSession()
        } else {
            web.refreshSession()
        }
    }
}
