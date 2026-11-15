import UIKit

/// Turns whatever the user pasted into a playlist id: a bare id, a YouTube or
/// YouTube Music link, or a link with the id in a `list` parameter.
enum PlaylistSync {
    /// Refreshes every saved remote playlist when the listener has asked for
    /// downloads to stay current. Runs one at a time so a slow catalogue does
    /// not stampede the network or replace the local array out of order.
    static func autoUpdate(completion: (() -> Void)? = nil) {
        guard SettingsStore.shared.keepDownloadsUpdated else {
            completion?()
            return
        }
        let remote = LibraryStore.shared.playlists
            .map { $0.id }
            .filter { $0.hasPrefix("remote:") }
        func next(_ index: Int) {
            guard index < remote.count else {
                completion?()
                return
            }
            let identifier = remote[index].replacingOccurrences(of: "remote:", with: "")
            LibraryStore.shared.syncPlaylist(remoteID: identifier) { _, _ in
                next(index + 1)
            }
        }
        next(0)
    }

    static func identifier(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let components = URLComponents(string: trimmed),
           let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
           !list.isEmpty {
            return clean(list)
        }
        if let url = URL(string: trimmed), url.scheme != nil {
            let last = url.lastPathComponent
            if !last.isEmpty { return clean(last) }
        }
        return clean(trimmed)
    }

    /// The one failure surface, used by the Library and by the capture run so
    /// both show exactly what the user sees when the remote side is unavailable.
    static func presentFailure(on host: UIViewController, message: String) {
        let alert = UIAlertController(title: "Couldn't sync playlist",
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        host.present(alert, animated: true, completion: nil)
    }

    static func dismissFailure(on host: UIViewController) {
        host.presentedViewController?.dismiss(animated: false, completion: nil)
    }

    private static func clean(_ value: String) -> String {
        var id = value
        // Web browse ids carry a VL prefix; the callers add it back as needed.
        if id.hasPrefix("VL") { id = String(id.dropFirst(2)) }
        return id.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
