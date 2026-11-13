import UIKit

/// Upstream's Replay screen: what has actually been played, most-played first.
/// The counts come from the same play log the Library cards summarise, so the
/// screen needs no server or account.
final class ReplayViewController: UIViewController {
    struct Entry {
        let track: Track
        let plays: Int
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerLabel = UILabel()
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Replay"
        view.backgroundColor = Theme.background

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = Theme.font(13, weight: .medium)
        headerLabel.textColor = Theme.secondaryText
        headerLabel.text = ReplayViewController.summaryText
        view.addSubview(headerLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 60
        tableView.tableFooterView = UIView()
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Play something to start your replay"
        emptyLabel.font = Theme.font(.bodyMedium)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = !ReplayViewController.entries().isEmpty
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            tableView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    /// Aggregated from the persisted play log; ties keep first-play order.
    static func entries() -> [Entry] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        var tracks: [String: Track] = [:]
        for track in LibraryStore.shared.recentTracks {
            if counts[track.videoID] == nil {
                order.append(track.videoID)
                tracks[track.videoID] = track
            }
            counts[track.videoID, default: 0] += 1
        }
        return order.compactMap { id -> Entry? in
            guard let track = tracks[id], let count = counts[id] else { return nil }
            return Entry(track: track, plays: count)
        }.sorted { $0.plays > $1.plays }
    }

    static var summaryText: String {
        let list = entries()
        let plays = list.reduce(0) { $0 + $1.plays }
        let seconds = LibraryStore.shared.recentTracks.reduce(0.0) { $0 + ($1.durationSeconds ?? 0) }
        let minutes = Int((seconds / 60).rounded())
        return "\(plays) plays · \(list.count) songs · \(minutes) min"
    }
}

extension ReplayViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ReplayViewController.entries().count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier,
                                                 for: indexPath)
        let entries = ReplayViewController.entries()
        if let trackCell = cell as? TrackCell, indexPath.row < entries.count {
            trackCell.configure(with: entries[indexPath.row].track)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entries = ReplayViewController.entries()
        guard indexPath.row < entries.count else { return }
        let track = entries[indexPath.row].track
        PlayerService.shared.play(tracks: [track] + PlayerService.shared.queue.filter { $0.videoID != track.videoID },
                                  startingAt: 0)
    }
}
