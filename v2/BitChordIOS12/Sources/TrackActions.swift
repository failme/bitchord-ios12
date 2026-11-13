import UIKit

/// The per-track action sheet. iOS 12 has no context-menu API, so a long press
/// plus an action sheet is what the real app's track menu becomes here.
///
/// One builder serves the rows and the capture harness, so what the screenshots
/// show is the sheet the app really presents — not a mock of it.
enum TrackActions {
    static func present(for track: Track, from host: UIViewController, sourceView: UIView?) {
        let store = DownloadStore.shared
        let sheet = UIAlertController(title: track.title, message: track.artist,
                                      preferredStyle: .actionSheet)
        if store.isDownloaded(track.videoID) {
            sheet.addAction(UIAlertAction(title: "Delete download", style: .destructive) { _ in
                store.remove(track.videoID)
            })
        } else if store.isDownloading(track.videoID) {
            sheet.addAction(UIAlertAction(title: "Cancel download", style: .cancel) { _ in
                store.cancel(track.videoID)
            })
        } else {
            sheet.addAction(UIAlertAction(title: "Download", style: .default) { _ in
                store.download(track) { ok, message in
                    guard !ok, let presenter = topController() else { return }
                    let alert = UIAlertController(title: "Download", message: message,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    presenter.present(alert, animated: true)
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = sourceView ?? host.view
            pop.sourceRect = sourceView?.bounds ?? host.view.bounds
        }
        host.present(sheet, animated: true)
    }

    static func topController() -> UIViewController? {
        var node = UIApplication.shared.keyWindow?.rootViewController
        while let presented = node?.presentedViewController {
            node = presented
        }
        return node
    }
}
