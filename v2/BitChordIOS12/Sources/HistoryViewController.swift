import UIKit

/// Upstream's History screen (`AppRoute.History`): every song playback has
/// recorded, newest first, with a way to clear it. The queue sheet shows the
/// same store in a section; this is the screen the Library route opens.
final class HistoryViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let accountButton = UIButton(type: .system)

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Like Downloads and Local Music, this route draws its own round
        // header instead of the navigation bar's large title.
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        view.backgroundColor = Theme.background

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.backgroundColor = UIColor(white: 1, alpha: 0.06)
        backButton.layer.cornerRadius = 22
        backButton.tintColor = Theme.primaryText
        backButton.setImage(Icons.image(.chevronLeft, size: 20), for: .normal)
        backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(backButton)

        accountButton.translatesAutoresizingMaskIntoConstraints = false
        accountButton.backgroundColor = UIColor(white: 1, alpha: 0.06)
        accountButton.layer.cornerRadius = 22
        accountButton.tintColor = Theme.secondaryText
        accountButton.setImage(Icons.image(.personOutline, size: 20), for: .normal)
        accountButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        view.addSubview(accountButton)

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

        // Signed out, the real History is the account feed's error state:
        // the explanation, then a white retry pill.
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Sign in to see what you have been listening to"
        emptyLabel.font = Theme.font(14)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = !PlaybackHistoryStore.shared.items.isEmpty
        view.addSubview(emptyLabel)

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("Try Again", for: .normal)
        retryButton.setTitleColor(.black, for: .normal)
        retryButton.titleLabel?.font = Theme.font(15, weight: .semibold)
        retryButton.backgroundColor = .white
        retryButton.layer.cornerRadius = 20
        retryButton.isHidden = emptyLabel.isHidden
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        view.addSubview(retryButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -10),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            accountButton.topAnchor.constraint(equalTo: backButton.topAnchor),
            accountButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            accountButton.widthAnchor.constraint(equalToConstant: 44),
            accountButton.heightAnchor.constraint(equalToConstant: 44),

            clearButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: accountButton.leadingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 64),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 20),
            retryButton.widthAnchor.constraint(equalToConstant: 104),
            retryButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        reload()
    }

    @objc private func closeTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func retryTapped() {
        let alert = UIAlertController(title: "Sign in to YouTube Music",
                                      message: "Google sign-in is not available in this build.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }

    @objc private func clearTapped() {
        PlaybackHistoryStore.shared.clear()
        reload()
    }

    func reload() {
        let empty = PlaybackHistoryStore.shared.items.isEmpty
        tableView.reloadData()
        tableView.isHidden = empty
        emptyLabel.isHidden = !empty
        retryButton.isHidden = !empty
        clearButton.isHidden = empty
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
