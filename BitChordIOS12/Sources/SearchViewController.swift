import UIKit

final class SearchViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyLabel = UILabel()
    private let spinner = UIActivityIndicatorView(activityIndicatorStyle: .white)

    private var results: [Track] = []
    private var pendingWork: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "BitChord"
        view.backgroundColor = Theme.background

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Source",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(editSource))

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = true
        searchController.searchBar.searchBarStyle = .minimal
        searchController.searchBar.placeholder = "Songs, albums, artists"
        searchController.searchBar.keyboardAppearance = .dark
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.keyboardDismissMode = .onDrag
        tableView.tableFooterView = UIView()
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.font = Theme.font(14)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = "Search YouTube Music"
        view.addSubview(emptyLabel)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 16)
        ])
    }

    @objc private func editSource() {
        let current = StreamResolver.shared.sourceTemplate ?? ""
        let alert = UIAlertController(
            title: "Audio source",
            message: "Optional. A URL that returns {\"url\": \"…\"} or a bare URL for a video id. Use {videoId} in the template. Leave empty to ask YouTube directly.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = current
            field.placeholder = "https://example.com/stream?id={videoId}"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.keyboardType = .URL
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            StreamResolver.shared.sourceTemplate = alert.textFields?.first?.text
        })
        present(alert, animated: true, completion: nil)
    }

    private func runSearch(_ query: String) {
        spinner.startAnimating()
        emptyLabel.isHidden = true
        InnerTube.shared.search(query) { [weak self] tracks, error in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            self.results = tracks ?? []
            self.tableView.reloadData()
            if self.results.isEmpty {
                self.emptyLabel.text = error ?? "No results."
                self.emptyLabel.isHidden = false
            } else {
                self.emptyLabel.isHidden = true
            }
        }
    }
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        pendingWork?.cancel()

        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
            results = []
            tableView.reloadData()
            emptyLabel.text = "Search YouTube Music"
            emptyLabel.isHidden = false
            spinner.stopAnimating()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.runSearch(text)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath)
        if let trackCell = cell as? TrackCell {
            trackCell.configure(with: results[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        searchController.isActive = false
        PlayerService.shared.play(tracks: results, startingAt: indexPath.row)
        if let root = navigationController?.parent as? RootViewController {
            root.presentNowPlaying()
        }
    }
}
