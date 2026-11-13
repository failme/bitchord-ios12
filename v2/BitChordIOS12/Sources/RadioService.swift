import UIKit

/// Upstream's "Start radio": the seed song asks InnerTube's `next` for a mix,
/// which replaces the queue and starts playing. A failure is shown, never
/// swallowed — a menu row that appears to do nothing is worse than an error.
enum RadioService {
    static func start(from track: Track,
                      host: UIViewController?,
                      onReady: (([Track]) -> Void)? = nil) {
        let presenter = host ?? TrackActions.topController()
        resolveSeed(track) { seed in
            guard let seed = seed else {
                DispatchQueue.main.async {
                    presentFailure("This song isn't on YouTube Music, so it has no radio.", on: presenter)
                }
                return
            }
            InnerTube.shared.radio(seedVideoID: seed) { tracks, error in
                DispatchQueue.main.async {
                    guard let tracks = tracks, !tracks.isEmpty else {
                        presentFailure(error ?? "This track has no radio.", on: presenter)
                        return
                    }
                    onReady?(tracks)
                    PlayerService.shared.play(tracks: tracks, startingAt: 0)
                    let player = NowPlayingViewController()
                    player.modalPresentationStyle = .fullScreen
                    presenter?.present(player, animated: true, completion: nil)
                }
            }
        }
    }

    /// A catalogue row is not a YouTube video (its id carries a `saavn:` prefix),
    /// so the mix is seeded by the YouTube recording of the same song. Upstream
    /// matches the seed on YouTube before it asks for the radio; skipping that
    /// would make every catalogue row fail.
    static func resolveSeed(_ track: Track, completion: @escaping (String?) -> Void) {
        if isYouTubeVideoID(track.videoID) {
            completion(track.videoID)
            return
        }
        let query = "\(track.title) \(track.artist)".trimmingCharacters(in: .whitespaces)
        InnerTube.shared.search(query, filter: .songs) { tracks, _ in
            completion(tracks?.first(where: { isYouTubeVideoID($0.videoID) })?.videoID)
        }
    }

    static func isYouTubeVideoID(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func presentFailure(_ message: String, on host: UIViewController?) {
        guard let host = host else { return }
        let alert = UIAlertController(title: "Couldn't start radio",
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        host.present(alert, animated: true, completion: nil)
    }
}
