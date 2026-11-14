import UIKit

/// The per-track menu. iOS 12 has no context-menu API, so a long press opens the
/// same kind of floating iOS panel upstream draws for Android.
///
/// One builder serves the rows and the capture harness, so what the screenshots
/// show is the menu the app really presents — not a mock of it.
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
        let liked = LibraryStore.shared.isLiked(track)

        // The two the real menu lifts to the top as tiles: rating and sharing.
        let quick = [
            TrackMenuAction(title: liked ? "Unlike" : "Like",
                            icon: liked ? .heartFilled : .heart) {
                LibraryStore.shared.toggleLike(track)
            },
            TrackMenuAction(title: "Share", icon: .share) {
                share(track, from: host)
            },
        ]

        let playlistRows = [
            TrackMenuAction(title: "Add to playlist", icon: .plus) {
                PlaylistPicker.present(for: track, from: host)
            },
        ]

        var transportRows = [TrackMenuAction]()
        // Upstream's menu starts a radio from any song; a local file has no
        // catalogue id to seed one, so the row only appears for catalogue songs.
        if !track.videoID.hasPrefix(LocalMusicStore.idPrefix) {
            transportRows.append(TrackMenuAction(title: "Start radio", icon: .radio) {
                RadioService.start(from: track, host: topController())
            })
        }
        transportRows.append(TrackMenuAction(title: "Play next", icon: .next) {
            PlayerService.shared.playNext(track)
        })
        transportRows.append(TrackMenuAction(title: "Add to queue", icon: .queue) {
            PlayerService.shared.addToQueue(track)
        })
        if store.isDownloaded(track.videoID) {
            transportRows.append(TrackMenuAction(title: "Delete download", icon: .trash,
                                                 destructive: true) {
                store.remove(track.videoID)
            })
        } else if store.isDownloading(track.videoID) {
            transportRows.append(TrackMenuAction(title: "Cancel download", icon: .close) {
                store.cancel(track.videoID)
            })
        } else {
            transportRows.append(TrackMenuAction(title: "Download", icon: .download) {
                store.download(track) { ok, message in
                    guard !ok, let presenter = topController() else { return }
                    let alert = UIAlertController(title: "Download", message: message,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    presenter.present(alert, animated: true)
                }
            })
        }

        var infoRows = [TrackMenuAction]()
        if canOpenArtist(track) {
            infoRows.append(TrackMenuAction(title: "Go to artist", icon: .personOutline) {
                openArtist(for: track, from: host)
            })
        }
        infoRows.append(TrackMenuAction(title: "Song info", icon: .info) {
            let info = SongInfoViewController(track: track)
            info.modalPresentationStyle = .pageSheet
            topController()?.present(info, animated: true, completion: nil)
        })

        let menu = TrackActionsMenuViewController(quickActions: quick,
                                                  groups: [playlistRows, transportRows, infoRows],
                                                  anchorView: sourceView)
        host.present(menu, animated: false)
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
        let sheet = PlaylistPickerSheetViewController(
            track: track,
            playlists: LibraryStore.shared.playlists,
            onAdd: { ids in
                for id in ids {
                    PlaylistPicker.add(track, to: id)
                }
            },
            onCreate: { name in
                let playlist = LibraryStore.shared.createPlaylist(title: name)
                PlaylistPicker.add(track, to: playlist.id)
            })
        host.present(sheet, animated: false)
    }

    /// The store work behind a playlist row. The sheet and the harness both go
    /// through it, so a tapped row and an asserted row are the same code.
    @discardableResult
    static func add(_ track: Track, to playlistID: String) -> Int {
        LibraryStore.shared.add(track, toPlaylistWith: playlistID)
        return LibraryStore.shared.playlists.first { $0.id == playlistID }?.tracks.count ?? 0
    }

}
