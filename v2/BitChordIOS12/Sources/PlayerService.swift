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

/// The last queue and position, written only when the listener has asked for
/// resume-on-launch. Persisting the queue (not just its first track) is what
/// lets a restored session keep its next/previous context.
struct PlaybackSession: Codable {
    let queue: [Track]
    let index: Int
    let position: TimeInterval
    let updatedAt: Date
}

final class PlaybackSessionStore {
    static let shared = PlaybackSessionStore()
    private let key = "BitChord.Player.LastSession"

    private init() {}

    func save(queue: [Track], index: Int, position: TimeInterval) {
        guard !queue.isEmpty, index >= 0, index < queue.count else { return }
        let session = PlaybackSession(queue: queue, index: index,
                                      position: max(0, position), updatedAt: Date())
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> PlaybackSession? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let session = try? JSONDecoder().decode(PlaybackSession.self, from: data),
              !session.queue.isEmpty,
              session.index >= 0, session.index < session.queue.count else { return nil }
        return session
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Drives playback through `AudioEngine`, which plays with AVFoundation when a stream URL can be
/// resolved and falls back to the embedded web player when it cannot. Either way this class owns
/// the queue and the user-facing state; position reports arrive through the engine's callbacks.
final class PlayerService: NSObject {
    static let shared = PlayerService()

    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int = -1
    private(set) var lyrics: [WordLyricLine] = []
    /// Which provider the words came from, for the lyrics header.
    private(set) var lyricsSource = ""
    private(set) var lyricsAreSynced = false
    private(set) var statusText: String = ""
    private(set) var isLoading = false
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isShuffled = false
    private(set) var repeatMode: RepeatMode = .off
    /// How many times the queue has been continued by autoplay; the capture
    /// harness reads it as proof the end-of-queue branch ran.
    private(set) var autoplayCount = 0
    private var autoplayInFlight = false
    /// Every song played since launch, so "Don't repeat in session" can keep
    /// radio from suggesting it again even after it leaves the queue.
    private(set) var sessionHistory: Set<String> = []

    var isScrubbing = false

    private var unshuffledQueue: [Track] = []
    private var observers: [NSObjectProtocol] = []
    private var consecutiveErrors = 0
    private var sleepTimer: Timer?
    private var loadStartedAt: Date?
    private var stallTimer: Timer?
    private var sessionReloads = 0
    private var crossfadeStarted = false
    private(set) var crossfadeCount = 0
    private var pendingRestorePosition: TimeInterval = 0
    private var lastSessionWrite = Date.distantPast

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
            self.persistSessionIfNeeded()
            if let track = self.currentTrack {
                ScrobbleService.shared.trackDidAdvance(position: position,
                                                      duration: total > 0 ? total : (track.durationSeconds ?? 0))
            }
            if self.isPlaying,
               AudioDSP.shared.takeSkipSilenceRequest(),
               total <= 0 || position + 1.5 < total {
                self.seek(to: position + 1.5)
                self.statusText = "Skipped silence"
            }
            self.maybeCrossfade(position: position, total: total)
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
        ) { [weak self] _ in
            // Re-assert the session so the web audio thread is not torn down.
            try? AVAudioSession.sharedInstance().setActive(true)
            self?.persistSession()
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            let previous = (note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
                as? AVAudioSessionRouteDescription)?.outputs.map { $0.portType } ?? []
            let current = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType
                ?? AVAudioSession.Port.builtInSpeaker
            let store = SettingsStore.shared
            guard let reasonText = PlayerService.routePauseReason(
                reason: reason, previousOutputs: previous, currentOutput: current,
                pauseOnDisconnect: store.pauseOnHeadphoneDisconnect,
                disableSpeaker: store.bool("BitChord.Audio.DisableOnPhoneSpeaker", false)) else { return }
            self.pause()
            self.statusText = reasonText
            self.postChange()
        })
    }

    static func speakerBlocked(disabled: Bool, portType: String) -> Bool {
        return disabled && portType == AVAudioSession.Port.builtInSpeaker.rawValue
    }

    /// The route notification decides two independent policies: the explicit
    /// speaker guard and the newer headphone-disconnect pause. Returning the
    /// status copy keeps the predicate testable without an audio route.
    static func routePauseReason(reason: AVAudioSession.RouteChangeReason,
                                 previousOutputs: [AVAudioSession.Port],
                                 currentOutput: AVAudioSession.Port,
                                 pauseOnDisconnect: Bool,
                                 disableSpeaker: Bool) -> String? {
        let disconnectPorts: [AVAudioSession.Port] = [
            .headphones, .headsetMic, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
            .carAudio, .airPlay, .usbAudio
        ]
        let disconnected = previousOutputs.contains { disconnectPorts.contains($0) }
        if pauseOnDisconnect && reason == .oldDeviceUnavailable && disconnected {
            return "Headphones disconnected. Playback paused."
        }
        if speakerBlocked(disabled: disableSpeaker,
                          portType: currentOutput.rawValue) && reason != .oldDeviceUnavailable {
            return "Phone speaker output is disabled in Settings."
        }
        return nil
    }

    // MARK: - Resume across launches

    /// Called once at launch before any transport action. It restores the
    /// queue and position but never starts audio on its own: opening the app
    /// must not surprise the listener with sound.
    func restoreLastSessionIfEnabled() {
        guard SettingsStore.shared.resumeOnLaunch,
              queue.isEmpty,
              let session = PlaybackSessionStore.shared.load() else { return }
        queue = session.queue
        unshuffledQueue = session.queue
        currentIndex = session.index
        currentTime = min(session.position, max(0, session.queue[session.index].durationSeconds ?? session.position))
        duration = session.queue[session.index].durationSeconds ?? 0
        pendingRestorePosition = currentTime
        isPlaying = false
        isLoading = false
        updateNowPlaying()
        postChange()
    }

    private func persistSessionIfNeeded() {
        guard SettingsStore.shared.resumeOnLaunch,
              Date().timeIntervalSince(lastSessionWrite) >= 5 else { return }
        persistSession()
    }

    private func persistSession() {
        guard SettingsStore.shared.resumeOnLaunch, !queue.isEmpty, currentIndex >= 0 else { return }
        lastSessionWrite = Date()
        PlaybackSessionStore.shared.save(queue: queue, index: currentIndex,
                                         position: currentTime)
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
        if pendingRestorePosition > 0 {
            let position = pendingRestorePosition
            pendingRestorePosition = 0
            loadCurrent(at: position)
            return
        }
        if PlayerService.speakerBlocked(
            disabled: SettingsStore.shared.bool("BitChord.Audio.DisableOnPhoneSpeaker", false),
            portType: AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "") {
            statusText = "Phone speaker output is disabled in Settings."
            isPlaying = false
            postChange()
            return
        }
        AudioEngine.shared.resume()
        isPlaying = true
        updateNowPlaying()
        postChange()
    }

    func pause() {
        AudioEngine.shared.pause()
        isPlaying = false
        persistSession()
        updateNowPlaying()
        postChange()
    }

    /// Upstream's "Stop when recents close" clears playback with the task, so
    /// nothing resumes from the control centre after the app was swiped away.
    func stopForTermination() {
        persistSession()
        AudioEngine.shared.pause()
        queue = []
        unshuffledQueue = []
        currentIndex = -1
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
        // Upstream keeps playing past the end of the queue: the last song seeds
        // a radio and the mix is appended. A local file has no seed, so the
        // queue simply ends there.
        if autoplayEnabled, let track = currentTrack,
           !track.videoID.hasPrefix(LocalMusicStore.idPrefix) {
            isPlaying = false
            postChange()
            extendWithAutoplay(from: track)
            return
        }
        isPlaying = false
        postChange()
    }

    var autoplayEnabled: Bool {
        return SettingsStore.shared.bool("BitChord.Audio.AutoPlay", true)
    }

    static func autoplayCandidates(mix: [Track], queueIDs: Set<String>,
                                   history: Set<String>, avoidRepeats: Bool) -> [Track] {
        return mix.filter { track in
            guard !queueIDs.contains(track.videoID) else { return false }
            return !avoidRepeats || !history.contains(track.videoID)
        }
    }

    private func extendWithAutoplay(from track: Track) {
        guard !autoplayInFlight else { return }
        autoplayInFlight = true
        statusText = "Finding more music…"
        postChange()
        RadioService.mix(from: track) { [weak self] mix in
            guard let self = self else { return }
            self.autoplayInFlight = false
            self.statusText = ""
            let known = Set(self.queue.map { $0.videoID })
            let fresh = PlayerService.autoplayCandidates(
                mix: mix ?? [], queueIDs: known, history: self.sessionHistory,
                avoidRepeats: SettingsStore.shared.bool("BitChord.Misc.DontRepeatInSession", false))
            guard !fresh.isEmpty else {
                self.isPlaying = false
                self.postChange()
                return
            }
            let start = self.queue.count
            self.queue += fresh
            self.currentIndex = start
            self.autoplayCount += 1
            self.loadCurrent()
            self.postChange()
        }
    }

    // MARK: - Queue editing

    /// "Play next": the song starts after the current one, not at the end.
    func playNext(_ track: Track) {
        guard !queue.isEmpty, currentIndex >= 0 else {
            play(tracks: [track], startingAt: 0)
            return
        }
        queue.insert(track, at: currentIndex + 1)
        postChange()
    }

    func addToQueue(_ track: Track) {
        guard !queue.isEmpty, currentIndex >= 0 else {
            play(tracks: [track], startingAt: 0)
            return
        }
        queue.append(track)
        postChange()
    }

    /// Moving a row keeps the playing song playing: only its index changes.
    /// `to` is the final index, after the removal has happened.
    func moveInQueue(from source: Int, to destination: Int) {
        guard source >= 0, source < queue.count, source != destination else { return }
        let track = queue.remove(at: source)
        let target = max(0, min(destination, queue.count))
        queue.insert(track, at: target)
        if source == currentIndex {
            currentIndex = target
        } else if source < currentIndex && target >= currentIndex {
            currentIndex -= 1
        } else if source > currentIndex && target <= currentIndex {
            currentIndex += 1
        }
        postChange()
    }

    /// Removing the playing row moves playback to whatever took its place.
    func removeFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        let wasCurrent = index == currentIndex
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        }
        if queue.isEmpty {
            currentIndex = -1
            AudioEngine.shared.pause()
            isPlaying = false
            duration = 0
            currentTime = 0
            postChange()
            return
        }
        if wasCurrent {
            currentIndex = min(index, queue.count - 1)
            loadCurrent()
        }
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

    func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
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
        PlaybackSessionStore.shared.clear()
        queue = []
        unshuffledQueue = []
        currentIndex = -1
        currentTime = 0
        duration = 0
        isPlaying = false
        lyrics = []
        lyricsAreSynced = false
        ScrobbleService.shared.trackDidStop()
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

    private func loadCurrent(at startPosition: TimeInterval = 0) {
        guard let track = currentTrack else { return }
        isLoading = true
        loadStartedAt = Date()
        sessionReloads = 0
        isPlaying = false
        crossfadeStarted = false
        statusText = ""
        currentTime = max(0, startPosition)
        duration = track.durationSeconds ?? 0
        lyrics = []
        lyricsAreSynced = false
        consecutiveErrors = 0
        updateNowPlaying()
        postChange()

        LibraryStore.shared.recordPlayback(track)
        PlaybackHistoryStore.shared.record(track)
        sessionHistory.insert(track.videoID)
        ScrobbleService.shared.trackDidStart(track)
        AudioEngine.shared.play(track: track)
        if startPosition > 0 {
            // The resolver is asynchronous, so the seek is re-applied after the
            // item is attached; the restored position is already shown meanwhile.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.AudioEngineSeek(startPosition)
            }
        }
        persistSession()
        if SettingsStore.shared.bool("BitChord.Audio.DirectSourceStream", false),
           repeatMode != .one, currentIndex + 1 < queue.count {
            StreamPrefetcher.shared.prefetch(videoID: queue[currentIndex + 1].videoID)
        }
        loadLyrics(for: track)
    }

    /// Crossfade and Automix share the same fade engine. Automix supplies a
    /// default overlap when the explicit Crossfade row is zero; Fast shortens
    /// the analysis window the way the upstream performance mode does.
    static func crossfadeSeconds(setting: Double, automix: Bool, fast: Bool) -> Double {
        if setting > 0 { return setting }
        guard automix else { return 0 }
        return fast ? 1.5 : 3.0
    }

    private func maybeCrossfade(position: Double, total: Double) {
        guard !crossfadeStarted, isPlaying, total > 2 else { return }
        let store = SettingsStore.shared
        let seconds = PlayerService.crossfadeSeconds(
            setting: store.double("BitChord.Audio.Crossfade", 0),
            automix: store.bool("BitChord.Audio.Automix", false),
            fast: store.string("BitChord.Audio.AutomixPerf", "Balanced") == "Fast")
        guard seconds > 0, position >= total - seconds else { return }
        crossfadeStarted = true
        AudioEngine.shared.fadeOut(seconds: seconds) { [weak self] in
            guard let self = self else { return }
            self.crossfadeCount += 1
            self.advance()
        }
    }

    private func loadLyrics(for track: Track) {
        LyricsService.shared.fetch(track: track) { [weak self] result, _ in
            guard let self = self else { return }
            guard let current = self.currentTrack, current.videoID == track.videoID else { return }
            let preferWords = SettingsStore.shared.prioritizeSyllableSync
            self.lyrics = result.map {
                LyricsService.linesForDisplay($0.lines, preferWordTimings: preferWords)
            } ?? []
            self.lyricsAreSynced = result?.isSynced ?? false
            self.lyricsSource = result?.source ?? ""
            self.postChange()
        }
    }

    private func AudioEngineSeek(_ position: TimeInterval) {
        guard currentTrack != nil else { return }
        AudioEngine.shared.seek(to: position)
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
