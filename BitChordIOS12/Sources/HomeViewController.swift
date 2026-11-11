import UIKit

/// Home shelves built from what the library already knows. Upstream additionally pulls the
/// YouTube Music browse feed (mood chips, quick-pick grid, mixes); that arrives with the browse
/// client, and these shelves are the part that works offline today.
final class HomeViewController: UIViewController {
    private struct Shelf {
        let title: String
        let tracks: [Track]
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private var shelves: [Shelf] = []
    private var remoteQuickPicks: [Track] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        view.backgroundColor = Theme.background

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.tableFooterView = UIView()
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Play something and it will show up here."
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
                                              selector: #selector(rebuild),
                                              name: .libraryDidChange,
                                              object: nil)
        rebuild()
        loadQuickPicks()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Live catalog shelf, so Home is not empty on a first launch with no local history.
    private func loadQuickPicks() {
        let year = Calendar.current.component(.year, from: Date())
        InnerTube.shared.search("Top songs \(year)", filter: .songs) { [weak self] tracks, _ in
            guard let self = self, let tracks = tracks, !tracks.isEmpty else { return }
            self.remoteQuickPicks = Array(tracks.prefix(20))
            self.rebuild()
        }
    }

    @objc private func rebuild() {
        let store = LibraryStore.shared
        var built: [Shelf] = []
        if !remoteQuickPicks.isEmpty {
            built.append(Shelf(title: "Quick picks", tracks: remoteQuickPicks))
        }
        if let continueTrack = store.continueListeningTrack {
            built.append(Shelf(title: "Continue listening", tracks: [continueTrack]))
        }
        if !store.recentTracks.isEmpty {
            built.append(Shelf(title: "Recently played", tracks: store.recentTracks))
        }
        let picks = store.quickPicks
        if !picks.isEmpty {
            built.append(Shelf(title: "Your picks", tracks: picks))
        }
        if !store.likedTracks.isEmpty {
            built.append(Shelf(title: "Liked songs", tracks: store.likedTracks))
        }
        shelves = built
        emptyLabel.isHidden = !built.isEmpty
        tableView.reloadData()
    }
}

extension HomeViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return shelves.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return shelves[section].tracks.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return shelves[section].title
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = Theme.secondaryText
            header.textLabel?.font = Theme.font(13, weight: .semibold)
            header.contentView.backgroundColor = Theme.background
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath)
        if let trackCell = cell as? TrackCell {
            trackCell.configure(with: shelves[indexPath.section].tracks[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let tracks = shelves[indexPath.section].tracks
        PlayerService.shared.play(tracks: tracks, startingAt: indexPath.row)
        presentNowPlayingFromRoot()
    }
}
