import UIKit

/// Upstream's History screen (`AppRoute.History`): every song playback has
/// recorded, newest first, with a way to clear it. The queue sheet shows the
/// same store in a section; this is the screen the Library route opens.
final class HistoryViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let clearButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        view.backgroundColor = Theme.background

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setTitle("Clear", for: .normal)
        clearButton.setTitleColor(Theme.primaryText, for: .normal)
        clearButton.titleLabel?.font = Theme.font(14, weight: .semibold)
        clearButton.backgroundColor = Theme.surfaceVariant
        clearButton.layer.cornerRadius = 14
        clearButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        view.addSubview(clearButton)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 60
        tableView.tableFooterView = UIView()
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Nothing played yet"
        emptyLabel.font = Theme.font(.bodyMedium)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = !PlaybackHistoryStore.shared.items.isEmpty
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            clearButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: clearButton.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func clearTapped() {
        PlaybackHistoryStore.shared.clear()
        reload()
    }

    func reload() {
        tableView.reloadData()
        emptyLabel.isHidden = !PlaybackHistoryStore.shared.items.isEmpty
    }

    /// What the screen is showing; the capture harness asserts on it.
    var rowCount: Int { return PlaybackHistoryStore.shared.items.count }

    func clearForCapture() {
        clearTapped()
    }
}

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return PlaybackHistoryStore.shared.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier,
                                                 for: indexPath)
        let items = PlaybackHistoryStore.shared.items
        if let trackCell = cell as? TrackCell, indexPath.row < items.count {
            trackCell.configure(with: items[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let items = PlaybackHistoryStore.shared.items
        guard indexPath.row < items.count else { return }
        let track = items[indexPath.row]
        let rest = PlayerService.shared.queue.filter { $0.videoID != track.videoID }
        PlayerService.shared.play(tracks: [track] + rest, startingAt: 0)
    }
}
