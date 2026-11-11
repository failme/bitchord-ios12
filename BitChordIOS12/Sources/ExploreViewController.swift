import UIKit

/// Explore mirrors upstream's sections: trending songs, new albums and top chart playlists, all
/// fetched from the same filtered InnerTube searches upstream uses, plus the mood strip.
final class ExploreViewController: UIViewController {
    private enum Row {
        case track(Track)
        case collection(CollectionItem)
        case mood(String)
    }

    private struct Section {
        let title: String
        var rows: [Row]
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    private let moods: [String] = [
        "Chill", "Energy", "Workout", "Focus", "Party", "Romance",
        "Sad", "Sleep", "Commute", "Feel good", "Pop", "Hip-hop",
        "Rock", "R&B", "Jazz", "Classical", "Electronic", "Indie"
    ]

    private var sections: [Section] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Explore"
        view.backgroundColor = Theme.background

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.tableFooterView = UIView()
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        view.addSubview(tableView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        sections = [
            Section(title: "Trending now", rows: []),
            Section(title: "New albums", rows: []),
            Section(title: "Top charts", rows: []),
            Section(title: "Moods & genres", rows: moods.map { Row.mood($0) })
        ]

        load()
    }

    private func load() {
        spinner.startAnimating()
        let year = Calendar.current.component(.year, from: Date())

        InnerTube.shared.search("Trending songs today \(year)", filter: .songs) { [weak self] tracks, _ in
            guard let self = self, let tracks = tracks, !tracks.isEmpty else { return }
            self.sections[0].rows = tracks.prefix(20).map { Row.track($0) }
            self.tableView.reloadData()
            self.spinner.stopAnimating()
        }

        InnerTube.shared.searchCollections("New album releases \(year)", filter: .albums) { [weak self] items in
            guard let self = self, !items.isEmpty else { return }
            self.sections[1].rows = items.prefix(20).map { Row.collection($0) }
            self.tableView.reloadData()
            self.spinner.stopAnimating()
        }

        InnerTube.shared.searchCollections("Top charts \(year)", filter: .playlists) { [weak self] items in
            guard let self = self, !items.isEmpty else { return }
            self.sections[2].rows = items.prefix(20).map { Row.collection($0) }
            self.tableView.reloadData()
            self.spinner.stopAnimating()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.spinner.stopAnimating()
        }
    }

    private func tracks(in section: Int) -> [Track] {
        return sections[section].rows.compactMap { row in
            if case .track(let track) = row { return track }
            return nil
        }
    }

    private func openCollection(_ item: CollectionItem) {
        let list = TrackListViewController()
        list.title = item.title
        list.emptyText = "Loading \(item.title)\u{2026}"
        navigationController?.pushViewController(list, animated: true)

        InnerTube.shared.fetchCollection(item.browseID) { tracks, error in
            if let tracks = tracks, !tracks.isEmpty {
                list.setTracks(tracks)
            } else {
                list.emptyText = error ?? "Could not open \(item.title)."
                list.setTracks([])
            }
        }
    }

    private func openMood(_ mood: String) {
        let list = TrackListViewController()
        list.title = mood
        list.emptyText = "Searching \(mood)\u{2026}"
        navigationController?.pushViewController(list, animated: true)

        InnerTube.shared.search("\(mood) music", filter: .songs) { tracks, error in
            if let tracks = tracks, !tracks.isEmpty {
                list.setTracks(tracks)
            } else {
                list.emptyText = error ?? "No results for \(mood)."
                list.setTracks([])
            }
        }
    }

    private func subtitleCell(_ tableView: UITableView, title: String, subtitle: String) -> UITableViewCell {
        let identifier = "ExploreRow"
        var cell = tableView.dequeueReusableCell(withIdentifier: identifier)
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        }
        guard let row = cell else { return UITableViewCell() }
        row.backgroundColor = Theme.background
        row.textLabel?.text = title
        row.textLabel?.textColor = Theme.primaryText
        row.textLabel?.font = Theme.font(15, weight: .medium)
        row.detailTextLabel?.text = subtitle
        row.detailTextLabel?.textColor = Theme.secondaryText
        row.detailTextLabel?.font = Theme.font(12)
        row.accessoryType = .disclosureIndicator
        return row
    }
}

extension ExploreViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.filter { !$0.rows.isEmpty }.count
    }

    private func visibleSection(_ index: Int) -> Section {
        return sections.filter { !$0.rows.isEmpty }[index]
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return visibleSection(section).rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return visibleSection(section).title
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = Theme.secondaryText
            header.textLabel?.font = Theme.font(13, weight: .semibold)
            header.contentView.backgroundColor = Theme.background
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch visibleSection(indexPath.section).rows[indexPath.row] {
        case .track(let track):
            let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier,
                                                     for: indexPath)
            if let trackCell = cell as? TrackCell {
                trackCell.configure(with: track)
            }
            return cell

        case .collection(let item):
            return subtitleCell(tableView, title: item.title, subtitle: item.subtitle)

        case .mood(let mood):
            return subtitleCell(tableView, title: mood, subtitle: "Songs, albums and playlists")
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let visible = sections.filter { !$0.rows.isEmpty }
        switch visible[indexPath.section].rows[indexPath.row] {
        case .track:
            let queue = tracks(in: indexOfSection(title: visible[indexPath.section].title))
            PlayerService.shared.play(tracks: queue, startingAt: indexPath.row)
            presentNowPlayingFromRoot()

        case .collection(let item):
            openCollection(item)

        case .mood(let mood):
            openMood(mood)
        }
    }

    private func indexOfSection(title: String) -> Int {
        return sections.firstIndex(where: { $0.title == title }) ?? 0
    }
}
