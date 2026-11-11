import AVFoundation
import MediaPlayer
import UIKit

extension Notification.Name {
    static let playerDidChange = Notification.Name("BitChordPlayerDidChange")
    static let playerTimeDidChange = Notification.Name("BitChordPlayerTimeDidChange")
}

enum RepeatMode: Int {
    case off
    case all
    case one
}

/// Drives playback through `AudioEngine`, which plays with AVFoundation when a stream URL can be
/// resolved and falls back to the embedded web player when it cannot. Either way this class owns
/// the queue and the user-facing state; position reports arrive through the engine's callbacks.
final class PlayerService: NSObject {
    static let shared = PlayerService()

    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int = -1
    private(set) var lyrics: [LyricLine] = []
    private(set) var lyricsAreSynced = false
    private(set) var statusText: String = ""
    private(set) var isLoading = false
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isShuffled = false
    private(set) var repeatMode: RepeatMode = .off

    var isScrubbing = false

    private var unshuffledQueue: [Track] = []
    private var observers: [NSObjectProtocol] = []
    private var consecutiveErrors = 0
    private var sleepTimer: Timer?
    private var loadStartedAt: Date?
    private var stallTimer: Timer?
    private var sessionReloads = 0

    var currentTrack: Track? {
        guard currentIndex >= 0, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    private override init() {
        super.init()
        configureAudioSession()
        configureBridge()
        configureRemoteCommands()
        observeInterruptions()
        observeSettings()
        startStallWatchdog()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    private func configureBridge() {
        let bridge = AudioEngine.shared

        bridge.onTimeUpdated = { [weak self] position, total in
            guard let self = self else { return }
            if position > 0 || total > 0 {
                self.loadStartedAt = nil
            }
            if !self.isScrubbing {
                self.currentTime = position
            }
            if total > 0 {
                self.duration = total
                LibraryStore.shared.updateProgress(position: position, duration: total)
            }
            NotificationCenter.default.post(name: .playerTimeDidChange, object: nil)
        }

        bridge.onStateChanged = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .playing:
                self.isPlaying = true
                self.loadStartedAt = nil
                self.isLoading = false
                self.statusText = ""
            case .paused:
                self.isPlaying = false
            case .loading:
                self.isLoading = true
            case .ended:
                self.isPlaying = false
            }
            self.updateNowPlaying()
            self.postChange()
        }

        bridge.onPlaybackEnded = { [weak self] in
            self?.advance()
        }

        bridge.onBridgeRecovering = { [weak self] in
            guard let self = self else { return }
            self.isLoading = true
            self.statusText = "Reloading player…"
            self.postChange()
        }

        bridge.onPlaybackError = { [weak self] code in
            guard let self = self else { return }
            self.isLoading = false
            self.isPlaying = false
            self.consecutiveErrors += 1
            let diagnostic = AudioEngine.shared.lastDiagnostic
            self.statusText = diagnostic.isEmpty
                ? "Playback failed (\(code))."
                : "Playback failed (\(code)): " + String(diagnostic.prefix(120))
            self.postChange()
            if self.consecutiveErrors < 3 {
                self.advance()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.advance()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: event.positionTime)
            return .success
        }
    }

    private func observeInterruptions() {
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.pause()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Re-assert the session so the web audio thread is not torn down.
            try? AVAudioSession.sharedInstance().setActive(true)
        })
    }

    // MARK: - Settings

    private func observeSettings() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySettings()
        })
        applySettings()
    }

    private func applySettings() {
        let store = SettingsStore.shared
        AudioEngine.shared.setPlaybackRate(store.playbackRate)
        scheduleSleepTimer(minutes: store.sleepTimerMinutes)
    }

    private func scheduleSleepTimer(minutes: Double) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        guard minutes > 0 else { return }
        sleepTimer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.pause()
            self.statusText = "Sleep timer ended playback."
            self.postChange()
        }
    }

    // MARK: - Stall watchdog

    private func startStallWatchdog() {
        stallTimer?.invalidate()
        stallTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkForStall()
        }
    }

    // The embed sometimes fires no event at all: a video that never starts, or one that starts
    // and then wedges. Both used to be silent. Measure the element itself and heal it once.
    private func checkForStall() {
        guard let track = currentTrack, !AudioEngine.shared.isPausedByUser else { return }
        let bridge = AudioEngine.shared
        let sinceLoad = loadStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let waiting = max(bridge.secondsSinceProgress, sinceLoad)
        guard waiting > 15 else { return }
        if sessionReloads < 1 {
            sessionReloads += 1
            loadStartedAt = Date()
            isLoading = true
            statusText = "Reloading player…"
            postChange()
            bridge.refreshSession()
            return
        }
        loadStartedAt = nil
        isLoading = false
        isPlaying = false
        let diagnostic = bridge.lastDiagnostic
        statusText = diagnostic.isEmpty
            ? "Playback stalled (" + bridge.diagnosticsSummary + ")"
            : "Playback stalled: " + String(diagnostic.prefix(100))
        postChange()
    }

    // MARK: - Queue

    func play(tracks: [Track], startingAt index: Int) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        unshuffledQueue = tracks
        isShuffled = false
        currentIndex = max(0, min(index, tracks.count - 1))
        consecutiveErrors = 0
        loadCurrent()
    }

    func play() {
        guard currentTrack != nil else { return }
        AudioEngine.shared.resume()
        isPlaying = true
        updateNowPlaying()
        postChange()
    }

    func pause() {
        AudioEngine.shared.pause()
        isPlaying = false
        updateNowPlaying()
        postChange()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func advance() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one {
            replayCurrent()
            return
        }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            loadCurrent()
            return
        }
        if repeatMode == .all {
            currentIndex = 0
            loadCurrent()
            return
        }
        isPlaying = false
        postChange()
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
            loadCurrent()
        } else {
            seek(to: 0)
        }
    }

    func playTrack(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        currentIndex = index
        loadCurrent()
    }

    func replayCurrent() {
        loadCurrent()
    }

    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            if queue.isEmpty { return }
            let head = currentIndex >= 0 ? Array(queue.prefix(currentIndex + 1)) : []
            let tail = currentIndex >= 0 ? Array(queue.suffix(from: currentIndex + 1)) : queue
            queue = head + tail.shuffled()
            currentIndex = head.isEmpty ? 0 : currentIndex
        } else if !unshuffledQueue.isEmpty {
            let track = currentTrack
            queue = unshuffledQueue
            if let track = track, let index = queue.firstIndex(where: { $0.videoID == track.videoID }) {
                currentIndex = index
            }
        }
        postChange()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        postChange()
    }

    func clearQueue() {
        queue = []
        unshuffledQueue = []
        currentIndex = -1
        currentTime = 0
        duration = 0
        isPlaying = false
        lyrics = []
        lyricsAreSynced = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        postChange()
    }

    // MARK: - Transport

    func seek(to time: TimeInterval) {
        let limit = duration > 0 ? duration : time
        let clamped = max(0, min(time, limit))
        AudioEngine.shared.seek(to: clamped)
        currentTime = clamped
        updateNowPlaying()
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        seek(to: duration * max(0, min(fraction, 1)))
    }

    // MARK: - Loading

    private func loadCurrent() {
        guard let track = currentTrack else { return }
        isLoading = true
        loadStartedAt = Date()
        sessionReloads = 0
        isPlaying = false
        statusText = ""
        currentTime = 0
        duration = track.durationSeconds ?? 0
        lyrics = []
        lyricsAreSynced = false
        consecutiveErrors = 0
        updateNowPlaying()
        postChange()

        LibraryStore.shared.recordPlayback(track)
        AudioEngine.shared.play(videoId: track.videoID)
        loadLyrics(for: track)
    }

    private func loadLyrics(for track: Track) {
        LyricsService.shared.fetch(track: track) { [weak self] result, _ in
            guard let self = self else { return }
            guard let current = self.currentTrack, current.videoID == track.videoID else { return }
            self.lyrics = result?.lines ?? []
            self.lyricsAreSynced = result?.isSynced ?? false
            self.postChange()
        }
    }

    // MARK: - Now Playing

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if !track.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = track.album
        }
        if let image = ArtworkLoader.shared.cached(track.largeArtworkURL) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else {
            ArtworkLoader.shared.load(track.largeArtworkURL) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateNowPlaying()
                }
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func postChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .playerDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .playerDidChange, object: nil)
            }
        }
    }
}
