import UIKit

/// The per-track action sheet. iOS 12 has no context-menu API, so a long press
/// plus an action sheet is what the real app's track menu becomes here.
///
/// One builder serves the rows and the capture harness, so what the screenshots
/// show is the sheet the app really presents — not a mock of it.
enum TrackActions {
    /// The rows this track offers, in the order upstream's menu shows them.
    /// The harness asserts against this list, so a removed action cannot pass
    /// unnoticed.
    static func titles(for track: Track) -> [String] {
        var titles = ["Play next", "Add to queue", "Add to playlist",
                      LibraryStore.shared.isLiked(track) ? "Unlike" : "Like"]
        if canOpenArtist(track) {
            titles.append("Go to artist")
        }
        let store = DownloadStore.shared
        if store.isDownloaded(track.videoID) {
            titles.append("Delete download")
        } else if store.isDownloading(track.videoID) {
            titles.append("Cancel download")
        } else {
            titles.append("Download")
        }
        if !track.videoID.hasPrefix(LocalMusicStore.idPrefix) {
            titles.append("Start radio")
        }
        titles.append("Share")
        titles.append("Song info")
        return titles
    }

    static func present(for track: Track, from host: UIViewController, sourceView: UIView?) {
        let store = DownloadStore.shared
        let sheet = UIAlertController(title: track.title, message: track.artist,
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Play next", style: .default) { _ in
            PlayerService.shared.playNext(track)
        })
        sheet.addAction(UIAlertAction(title: "Add to queue", style: .default) { _ in
            PlayerService.shared.addToQueue(track)
        })
        sheet.addAction(UIAlertAction(title: "Add to playlist", style: .default) { _ in
            PlaylistPicker.present(for: track, from: host)
        })
        let liked = LibraryStore.shared.isLiked(track)
        sheet.addAction(UIAlertAction(title: liked ? "Unlike" : "Like", style: .default) { _ in
            LibraryStore.shared.toggleLike(track)
        })
        if canOpenArtist(track) {
            sheet.addAction(UIAlertAction(title: "Go to artist", style: .default) { _ in
                openArtist(for: track, from: host)
            })
        }
        if store.isDownloaded(track.videoID) {
            sheet.addAction(UIAlertAction(title: "Delete download", style: .destructive) { _ in
                store.remove(track.videoID)
            })
        } else if store.isDownloading(track.videoID) {
            // Cannot be `.cancel` style: the sheet already ends with a Cancel
            // action, and UIKit asserts when two share that style.
            sheet.addAction(UIAlertAction(title: "Cancel download", style: .default) { _ in
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
        // Upstream's menu starts a radio from any song; a local file has no
        // catalogue id to seed one, so the row only appears for catalogue songs.
        if !track.videoID.hasPrefix(LocalMusicStore.idPrefix) {
            sheet.addAction(UIAlertAction(title: "Start radio", style: .default) { _ in
                RadioService.start(from: track, host: topController())
            })
        }
        sheet.addAction(UIAlertAction(title: "Share", style: .default) { _ in
            share(track, from: host)
        })
        sheet.addAction(UIAlertAction(title: "Song info", style: .default) { _ in
            let info = SongInfoViewController(track: track)
            info.modalPresentationStyle = .pageSheet
            topController()?.present(info, animated: true, completion: nil)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = sourceView ?? host.view
            pop.sourceRect = sourceView?.bounds ?? host.view.bounds
        }
        host.present(sheet, animated: true)
    }

    /// Upstream shares a lyrics card; iOS shares through the system sheet,
    /// which is the share surface iOS 12 gives an app.
    static func share(_ track: Track, from host: UIViewController) {
        var items: [Any] = ["\(track.title) — \(track.artist)"]
        let link: String?
        if track.videoID.hasPrefix("saavn:") {
            link = "https://www.jiosaavn.com/song/\(track.videoID.replacingOccurrences(of: "saavn:", with: ""))"
        } else if !track.videoID.hasPrefix(LocalMusicStore.idPrefix) {
            link = "https://music.youtube.com/watch?v=\(track.videoID)"
        } else {
            link = nil
        }
        if let link = link, let url = URL(string: link) {
            items.append(url)
        }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = host.view
            pop.sourceRect = host.view.bounds
        }
        host.present(sheet, animated: true, completion: nil)
    }

    // MARK: - Go to artist

    static func canOpenArtist(_ track: Track) -> Bool {
        return !track.artist.isEmpty && !track.videoID.hasPrefix(LocalMusicStore.idPrefix)
    }

    /// Upstream opens the artist from the song; this does the same through the
    /// same YouTube Music artist search the search screen uses.
    static func openArtist(for track: Track, from host: UIViewController) {
        InnerTube.shared.searchCollections(track.artist, filter: .artists) { items in
            guard let item = items.first,
                  let navigation = (host.navigationController ?? host as? UINavigationController)
            else { return }
            let page = ArtistPage.make(artist: CatalogueArtist(id: item.browseID,
                                                               name: item.title,
                                                               artwork: item.artworkURL))
            navigation.pushViewController(page, animated: true)
        }
    }

    static func topController() -> UIViewController? {
        var node = UIApplication.shared.keyWindow?.rootViewController
        while let presented = node?.presentedViewController {
            node = presented
        }
        return node
    }
}

/// Upstream's "Add to playlist" half of the song menu: the device's playlists,
/// plus a new one. Adding is the same store call the library buttons use.
enum PlaylistPicker {
    static func present(for track: Track, from host: UIViewController) {
        let sheet = UIAlertController(title: "Add to playlist", message: track.title,
                                      preferredStyle: .actionSheet)
        for playlist in LibraryStore.shared.playlists {
            sheet.addAction(UIAlertAction(title: playlist.title, style: .default) { _ in
                PlaylistPicker.add(track, to: playlist.id)
            })
        }
        sheet.addAction(UIAlertAction(title: "New playlist…", style: .default) { _ in
            createAndAdd(track: track, from: host)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = host.view
            pop.sourceRect = host.view.bounds
        }
        host.present(sheet, animated: true)
    }

    /// The store work behind a playlist row. The sheet and the harness both go
    /// through it, so a tapped row and an asserted row are the same code.
    @discardableResult
    static func add(_ track: Track, to playlistID: String) -> Int {
        LibraryStore.shared.add(track, toPlaylistWith: playlistID)
        return LibraryStore.shared.playlists.first { $0.id == playlistID }?.tracks.count ?? 0
    }

    private static func createAndAdd(track: Track, from host: UIViewController) {
        let alert = UIAlertController(title: "New playlist", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Create", style: .default) { _ in
            let name = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let playlist = LibraryStore.shared.createPlaylist(title: name)
            PlaylistPicker.add(track, to: playlist.id)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        host.present(alert, animated: true)
    }
}
