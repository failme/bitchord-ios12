import AVFoundation
import MediaPlayer
import UIKit

extension Notification.Name {
    static let playerDidChange = Notification.Name("BitChordPlayerDidChange")
    static let playerTimeDidChange = Notification.Name("BitChordPlayerTimeDidChange")
}

final class PlayerService: NSObject {
    static let shared = PlayerService()

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var observers: [NSObjectProtocol] = []
    private var loadToken = 0

    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int = -1
    private(set) var lyrics: [LyricLine] = []
    private(set) var lyricsAreSynced = false
    private(set) var statusText: String = ""
    private(set) var isLoading = false
    var isScrubbing = false

    var currentTrack: Track? {
        guard currentIndex >= 0, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var isPlaying: Bool {
        return player.timeControlStatus == .playing
    }

    var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    var duration: TimeInterval {
        if let item = player.currentItem {
            let seconds = item.duration.seconds
            if seconds.isFinite, seconds > 0 { return seconds }
        }
        return currentTrack?.durationSeconds ?? 0
    }

    private override init() {
        super.init()
        configureAudioSession()
        observePlayback()
        configureRemoteCommands()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .playerTimeDidChange, object: nil)
        }
    }

    // MARK: - Setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    private func observePlayback() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.advance()
        })
        observers.append(center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.statusText = "Playback failed. Try a different source."
            self?.postChange()
        })
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

    // MARK: - Control

    func play(tracks: [Track], startingAt index: Int) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        currentIndex = max(0, min(index, tracks.count - 1))
        loadCurrent()
    }

    func play() {
        guard player.currentItem != nil else { return }
        player.play()
        updateNowPlaying()
        postChange()
    }

    func pause() {
        player.pause()
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
        guard currentIndex + 1 < queue.count else {
            player.pause()
            updateNowPlaying()
            postChange()
            return
        }
        currentIndex += 1
        loadCurrent()
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard currentIndex > 0 else {
            seek(to: 0)
            return
        }
        currentIndex -= 1
        loadCurrent()
    }

    func seek(to time: TimeInterval) {
        let limit = duration > 0 ? duration : time
        let clamped = max(0, min(time, limit))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        updateNowPlaying()
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        seek(to: duration * max(0, min(fraction, 1)))
    }

    // MARK: - Loading

    private func loadCurrent() {
        guard let track = currentTrack else { return }
        loadToken += 1
        let token = loadToken
        isLoading = true
        statusText = "Loading \(track.title)…"
        lyrics = []
        lyricsAreSynced = false
        postChange()

        StreamResolver.shared.resolve(track: track) { [weak self] url, error in
            guard let self = self else { return }
            guard token == self.loadToken else { return }
            self.isLoading = false
            guard let url = url else {
                self.statusText = error ?? "Could not resolve this track."
                self.postChange()
                return
            }
            self.startPlayback(url: url, track: track)
        }
    }

    private func startPlayback(url: URL, track: Track) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        statusText = ""
        updateNowPlaying()
        loadLyrics(for: track)
        postChange()
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
