import UIKit

/// Home, shaped like upstream's: large title, then full-width shelves of square
/// artwork cards that scroll sideways, instead of one long table of rows.
final class HomeViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let emptyLabel = UILabel()
    private let greetingLabel = UILabel()

    private var remoteQuickPicks: [Track] = []
    private var shelfViews: [String: ShelfRowView] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: Icons.image(.gear, size: 22),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(openSettings))
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .always

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 28
        stack.alignment = .fill
        scrollView.addSubview(stack)

        greetingLabel.text = greeting()
        greetingLabel.font = Theme.font(15)
        greetingLabel.textColor = Theme.secondaryText
        greetingLabel.numberOfLines = 2
        stack.addArrangedSubview(greetingLabel)

        emptyLabel.text = "Play something and it will show up here."
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.font = Theme.font(14)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        view.addSubview(emptyLabel)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -28),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

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

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<17: part = "Good afternoon"
        case 17..<22: part = "Good evening"
        default: part = "Good night"
        }
        return part
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

    @objc private func openSettings() {
        let settings = SettingsViewController()
        let navigation = UINavigationController(rootViewController: settings)
        navigation.navigationBar.barTintColor = Theme.background
        navigation.navigationBar.tintColor = Theme.accent
        navigation.navigationBar.isTranslucent = false
        navigation.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        settings.modalPresentationStyle = .fullScreen
        present(navigation, animated: true, completion: nil)
    }

    @objc private func rebuild() {
        let store = LibraryStore.shared
        var shelves: [(String, [Track])] = []
        if !remoteQuickPicks.isEmpty {
            shelves.append(("Quick picks", remoteQuickPicks))
        }
        if let continueTrack = store.continueListeningTrack {
            shelves.append(("Continue listening", [continueTrack]))
        }
        if !store.recentTracks.isEmpty {
            shelves.append(("Recently played", store.recentTracks))
        }
        if !store.quickPicks.isEmpty {
            shelves.append(("Your picks", store.quickPicks))
        }
        if !store.likedTracks.isEmpty {
            shelves.append(("Liked songs", store.likedTracks))
        }

        // Rebuild only when the shape changed; reloading on every library event
        // would reset each shelf's horizontal scroll position.
        let signature = shelves.map { $0.0 + ":" + $0.1.map { $0.videoID }.joined(separator: ",") }
        if signature == (stack.arrangedSubviews.compactMap { ($0 as? ShelfRowView)?.accessibilityIdentifier }) {
            return
        }

        for view in stack.arrangedSubviews where view is ShelfRowView {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        shelfViews.removeAll()

        for (title, tracks) in shelves {
            let row = ShelfRowView()
            row.accessibilityIdentifier = title + ":" + tracks.map { $0.videoID }.joined(separator: ",")
            row.configure(title: title, tracks: tracks)
            row.onSelect = { [weak self] index in
                guard let self = self else { return }
                PlayerService.shared.play(tracks: tracks, startingAt: index)
                self.presentNowPlayingFromRoot()
            }
            row.onPlayAll = { [weak self] in
                guard !tracks.isEmpty else { return }
                PlayerService.shared.play(tracks: tracks, startingAt: 0)
                self?.presentNowPlayingFromRoot()
            }
            row.heightAnchor.constraint(equalToConstant: ShelfRowView.rowHeight).isActive = true
            stack.addArrangedSubview(row)
            shelfViews[title] = row
        }

        emptyLabel.isHidden = !shelves.isEmpty
        scrollView.isHidden = shelves.isEmpty
    }
}
