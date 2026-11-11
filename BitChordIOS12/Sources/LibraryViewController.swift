import UIKit

/// Port of upstream `LibraryView`: liked songs, playlists, recently played and recent searches.
final class LibraryViewController: UIViewController {
    private enum Row {
        case liked
        case recentlyPlayed
        case recentSearches
        case playlist(Playlist)
        case newPlaylist
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var sections: [[Row]] = [[], []]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Library"
        view.backgroundColor = Theme.background

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.tableFooterView = UIView()
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(reload),
                                              name: .libraryDidChange,
                                              object: nil)
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reload() {
        let store = LibraryStore.shared
        sections = [
            [.liked, .recentlyPlayed, .recentSearches],
            store.playlists.map { Row.playlist($0) } + [.newPlaylist]
        ]
        tableView.reloadData()
    }

    private func makeCell(_ tableView: UITableView, title: String, detail: String?) -> UITableViewCell {
        let identifier = "LibraryRow"
        var cell = tableView.dequeueReusableCell(withIdentifier: identifier)
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        }
        guard let row = cell else { return UITableViewCell() }
        row.backgroundColor = Theme.background
        row.textLabel?.text = title
        row.textLabel?.textColor = Theme.primaryText
        row.textLabel?.font = Theme.font(15, weight: .medium)
        row.detailTextLabel?.text = detail
        row.detailTextLabel?.textColor = Theme.secondaryText
        row.detailTextLabel?.font = Theme.font(12)
        row.accessoryType = .disclosureIndicator
        return row
    }

    private func push(_ tracks: [Track], title: String, playlistID: String? = nil, empty: String) {
        let list = TrackListViewController()
        list.title = title
        list.tracks = tracks
        list.playlistID = playlistID
        list.emptyText = empty
        navigationController?.pushViewController(list, animated: true)
    }

    private func createPlaylist() {
        let alert = UIAlertController(title: "New playlist", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Playlist name"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { _ in
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            LibraryStore.shared.createPlaylist(title: name)
        })
        present(alert, animated: true, completion: nil)
    }
}

extension LibraryViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 1 ? "Playlists" : nil
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = Theme.secondaryText
            header.textLabel?.font = Theme.font(13, weight: .semibold)
            header.contentView.backgroundColor = Theme.background
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section][indexPath.row] {
        case .liked:
            let count = LibraryStore.shared.likedTracks.count
            return makeCell(tableView, title: "Liked Songs", detail: "\(count) songs")

        case .recentlyPlayed:
            let count = LibraryStore.shared.recentTracks.count
            return makeCell(tableView, title: "Recently Played", detail: "\(count) songs")

        case .recentSearches:
            let count = LibraryStore.shared.recentSearches.count
            return makeCell(tableView, title: "Recent Searches", detail: "\(count) songs")

        case .playlist(let playlist):
            return makeCell(tableView, title: playlist.title, detail: "\(playlist.tracks.count) songs")

        case .newPlaylist:
            return makeCell(tableView, title: "New playlist", detail: nil)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let store = LibraryStore.shared

        switch sections[indexPath.section][indexPath.row] {
        case .liked:
            push(store.likedTracks, title: "Liked Songs", empty: "Songs you like appear here.")
        case .recentlyPlayed:
            push(store.recentTracks, title: "Recently Played", empty: "Nothing played yet.")
        case .recentSearches:
            push(store.recentSearches, title: "Recent Searches", empty: "Nothing searched yet.")
        case .playlist(let playlist):
            push(playlist.tracks, title: playlist.title, playlistID: playlist.id,
                 empty: "This playlist is empty. Long-press a song to add it.")
        case .newPlaylist:
            createPlaylist()
        }
    }
}
