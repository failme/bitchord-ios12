import UIKit

/// Upstream's "Start radio": the seed song asks InnerTube's `next` for a mix,
/// which replaces the queue and starts playing. A failure is shown, never
/// swallowed — a menu row that appears to do nothing is worse than an error.
enum RadioService {
    static func start(from track: Track, host: UIViewController?) {
        let presenter = host ?? TrackActions.topController()
        InnerTube.shared.radio(seedVideoID: track.videoID) { tracks, error in
            DispatchQueue.main.async {
                guard let tracks = tracks, !tracks.isEmpty else {
                    presentFailure(error ?? "This track has no radio.", on: presenter)
                    return
                }
                PlayerService.shared.play(tracks: tracks, startingAt: 0)
                let player = NowPlayingViewController()
                player.modalPresentationStyle = .fullScreen
                presenter?.present(player, animated: true, completion: nil)
            }
        }
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
