import Foundation

/// The single audio surface `PlayerService` talks to.
///
/// A track is played with AVFoundation whenever a direct stream URL resolves, which is the
/// reliable path on iOS 12. JioSaavn is resolved first — its CDN URLs need no signature —
/// and YouTube is the fallback. When both fail, playback falls back to the embedded web
/// player instead of leaving the queue stuck.
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
    /// Why the native path was abandoned, kept so the on-screen diagnostic names the cause
    /// instead of silently showing the web player's numbers.
    private var nativeFailure: String = ""

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

    /// The catalogue that served the loaded item, for the quality badge ("" when unknown).
    var currentSourceLabel: String {
        mode == .native ? native.sourceLabel : ""
    }

    /// True when the loaded item is a downloaded file rather than a stream.
    var currentIsLocal: Bool {
        mode == .native ? native.isPlayingLocalFile : false
    }

    /// Whether the loaded item was flagged explicit (Apple-style E badge).
    var currentIsExplicit: Bool {
        mode == .native ? native.lastExplicit : false
    }

    var lastDiagnostic: String {
        mode == .native ? native.lastDiagnostic : web.lastDiagnostic
    }

    var lastReferrer: String {
        web.lastReferrer
    }

    var diagnosticsSummary: String {
        if mode == .native {
            return native.diagnosticsSummary
        }
        guard !nativeFailure.isEmpty else { return web.diagnosticsSummary }
        return "web[fallback: " + String(nativeFailure.prefix(44)) + "] " + web.diagnosticsSummary
    }

    var secondsSinceProgress: TimeInterval {
        mode == .native ? native.secondsSinceProgress : web.secondsSinceProgress
    }

    // MARK: - Control

    func play(track: Track) {
        web.stop()
        mode = .native
        nativeFailure = ""
        // A Jellyfin stream carries its token in the URL, so no extra headers
        // are needed; it still goes through the same player and end handling.
        if track.videoID.hasPrefix("jellyfin:"),
           let url = URL(string: String(track.videoID.dropFirst("jellyfin:".count))) {
            native.playRemote(url: url, headers: [:], track: track, source: "Jellyfin")
            return
        }
        // A WebDAV file streams from its own URL with the stored credentials,
        // through the same player and end-of-item handling as a local file.
        if track.videoID.hasPrefix("webdav:"),
           let url = URL(string: String(track.videoID.dropFirst("webdav:".count))) {
            let credentials = WebDAVStore.shared.credentials(for: url)
            let headers = credentials.map { ["Authorization": WebDAVClient.basic(username: $0.0, password: $0.1)] } ?? [:]
            native.playRemote(url: url, headers: headers, track: track)
            return
        }
        // A downloaded track never touches the network: it is the same engine,
        // queue and lock screen, reading a file instead of a URL.
        if let local = DownloadStore.shared.localURL(for: track.videoID) {
            native.playLocal(url: local, track: track)
            return
        }
        // A song the local scan found is already a file: same engine, no resolve.
        if let local = LocalMusicStore.shared.localURL(for: track.videoID) {
            native.playLocal(url: local, track: track, source: "Local Music")
            return
        }
        // Upstream's Sources switch can take JioSaavn out of the resolver
        // order; with it off, go straight to YouTube/InnerTube. Local, WebDAV
        // and Jellyfin files above still play from their own source.
        guard SettingsStore.shared.jioSaavnEnabled else {
            resolveYouTube(track, position: 0)
            return
        }
        native.play(track: track) { [weak self] resolved in
            guard let self = self else { return }
            guard !resolved else { return }
            // No stream URL: fall back to the web player rather than dropping the track.
            self.nativeFailure = self.native.lastDiagnostic.isEmpty
                ? "no stream url"
                : self.native.lastDiagnostic
            self.mode = .web
            self.native.stop()
            self.web.play(videoId: track.videoID)
        }
    }

    private func resolveYouTube(_ track: Track, position: Double) {
        InnerTube.shared.resolveStreamURL(videoID: track.videoID) { [weak self] url, reason in
            guard let self = self else { return }
            guard let url = url, let scheme = url.scheme, scheme.hasPrefix("http") else {
                self.nativeFailure = reason.isEmpty ? "No stream URL was returned." : reason
                self.mode = .web
                self.web.play(videoId: track.videoID)
                return
            }
            self.native.playResolved(url: url, track: track, at: position, source: "YouTube")
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
