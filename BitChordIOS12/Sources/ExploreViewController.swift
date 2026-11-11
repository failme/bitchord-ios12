import UIKit

/// Explore surfaces moods and genres. Upstream renders these as coloured strip cards backed by
/// YouTube Music browse params; here each one runs a catalog search and pushes the results.
final class ExploreViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)

    private let moods: [String] = [
        "Chill", "Energy", "Workout", "Focus", "Party", "Romance",
        "Sad", "Sleep", "Commute", "Feel good", "Pop", "Hip-hop",
        "Rock", "R&B", "Jazz", "Classical", "Electronic", "Indie"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Explore"
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
    }

    private func open(mood: String) {
        let list = TrackListViewController()
        list.title = mood
        list.emptyText = "Searching \(mood)\u{2026}"
        navigationController?.pushViewController(list, animated: true)

        InnerTube.shared.search("\(mood) music") { tracks, error in
            if let tracks = tracks, !tracks.isEmpty {
                list.setTracks(tracks)
            } else {
                list.emptyText = error ?? "No results for \(mood)."
                list.setTracks([])
            }
        }
    }
}

extension ExploreViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return moods.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "MoodRow"
        var cell = tableView.dequeueReusableCell(withIdentifier: identifier)
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: identifier)
        }
        guard let moodCell = cell else { return UITableViewCell() }
        moodCell.backgroundColor = Theme.background
        moodCell.textLabel?.text = moods[indexPath.row]
        moodCell.textLabel?.textColor = Theme.primaryText
        moodCell.textLabel?.font = Theme.font(15, weight: .medium)
        moodCell.accessoryType = .disclosureIndicator
        return moodCell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(mood: moods[indexPath.row])
    }
}
