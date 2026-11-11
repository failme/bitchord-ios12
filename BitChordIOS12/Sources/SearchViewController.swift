import UIKit

final class SearchViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyLabel = UILabel()
    // The style-taking initializer was renamed to init(style:) in the iOS 13 SDK, and that
    // spelling is unavailable at a 12.0 deployment target, so use the inherited frame form
    // and let the view keep its default style.
    private let spinner = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    private var results: [Track] = []
    private var pendingWork: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "BitChord"
        view.backgroundColor = Theme.background

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
        // Capture the queue first. Deactivating the search controller runs
        // `updateSearchResults` synchronously, which empties `results`; reading it
        // afterwards handed `play` an empty array and the tap did nothing at all.
        let picked = results
        guard indexPath.row < picked.count else { return }
        searchController.isActive = false
        PlayerService.shared.play(tracks: picked, startingAt: indexPath.row)
        // The search controller tears its own presentation down asynchronously;
        // presenting in the same run loop lost the player behind that transition.
        DispatchQueue.main.async { [weak self] in
            self?.presentNowPlayingFromRoot()
        }
    }
}
