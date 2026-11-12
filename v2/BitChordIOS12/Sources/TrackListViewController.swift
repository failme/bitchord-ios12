import UIKit

/// Reusable list of tracks. Used by Home shelves, Explore results, Library lists and playlists,
/// so selection, swipe actions and playback live in one place.
final class TrackListViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    var tracks: [Track] = []
    var emptyText = "Nothing here yet."
    var playlistID: String?

    func setTracks(_ newTracks: [Track]) {
        tracks = newTracks
        tableView.reloadData()
        updateEmptyState()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = title ?? "Tracks"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.tableFooterView = UIView()
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = emptyText
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.font = Theme.font(14)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(libraryChanged),
                                              name: .libraryDidChange,
                                              object: nil)
        updateEmptyState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func libraryChanged() {
        if let id = playlistID,
           let playlist = LibraryStore.shared.playlists.first(where: { $0.id == id }) {
            tracks = playlist.tracks
            tableView.reloadData()
        }
        updateEmptyState()
    }

    private func updateEmptyState() {
        emptyLabel.text = emptyText
        emptyLabel.isHidden = !tracks.isEmpty
        tableView.isHidden = tracks.isEmpty
    }
}

extension TrackListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tracks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath)
        if let trackCell = cell as? TrackCell {
            trackCell.configure(with: tracks[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        PlayerService.shared.play(tracks: tracks, startingAt: indexPath.row)
        presentNowPlayingFromRoot()
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        let track = tracks[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self = self, let id = self.playlistID else {
                done(false)
                return
            }
            LibraryStore.shared.remove(track, fromPlaylistWith: id)
            done(true)
        }

        let like = UIContextualAction(style: .normal, title: LibraryStore.shared.isLiked(track) ? "Unlike" : "Like") { _, _, done in
            LibraryStore.shared.toggleLike(track)
            done(true)
        }
        like.backgroundColor = Theme.accent

        var actions: [UIContextualAction] = [like]
        if playlistID != nil {
            actions.insert(delete, at: 0)
        }
        return UISwipeActionsConfiguration(actions: actions)
    }
}

extension UIViewController {
    /// Walks up to the container that owns the now-playing presentation.
    func presentNowPlayingFromRoot() {
        var node: UIViewController = self
        while let parent = node.parent {
            node = parent
        }
        if let root = node as? RootViewController {
            root.presentNowPlaying()
        }
    }
}
