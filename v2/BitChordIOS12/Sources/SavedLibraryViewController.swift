import UIKit

/// The account's saved playlists, albums and artists, as YouTube Music's
/// library feeds list them. Upstream's LibraryScreen shows these as shelves;
/// this iOS 12 list keeps the same sections and opens each row in the existing
/// collection page.
final class SavedLibraryViewController: UIViewController {
    private struct Feed {
        let title: String
        let browseID: String
    }

    private let feeds: [Feed] = [
        Feed(title: "Playlists", browseID: "FEmusic_liked_playlists"),
        Feed(title: "Albums", browseID: "FEmusic_liked_albums"),
        Feed(title: "Artists", browseID: "FEmusic_library_corpus_track_artists")
    ]

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView(style: .white)
    private let emptyLabel = UILabel()
    private var sections: [[CollectionItem]] = []
    private var loaded = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Saved library"
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SavedCollectionCell.self,
                           forCellReuseIdentifier: SavedCollectionCell.reuseIdentifier)
        view.addSubview(tableView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = Theme.font(15)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 3
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        ])

        sections = Array(repeating: [], count: feeds.count)
        load()
    }

    private func load() {
        let group = DispatchGroup()
        var errors: [String] = []
        let lock = NSLock()
        for (index, feed) in feeds.enumerated() {
            group.enter()
            InnerTube.shared.fetchLibraryCollections(feedID: feed.browseID) { [weak self] items, error in
                lock.lock()
                self?.sections[index] = items
                if let error = error, items.isEmpty { errors.append(error) }
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.loaded = true
            self.spinner.stopAnimating()
            self.tableView.reloadData()
            let total = self.sections.reduce(0) { $0 + $1.count }
            self.emptyLabel.isHidden = total > 0
            self.emptyLabel.text = errors.first ?? "Nothing saved in your YouTube Music library yet."
        }
    }

    private func open(_ item: CollectionItem) {
        let controller = CollectionViewController(title: item.title,
                                                  subtitle: item.subtitle,
                                                  artwork: item.artworkURL)
        controller.loader = { completion in
            InnerTube.shared.fetchCollection(item.browseID) { tracks, _ in
                completion(tracks ?? [])
            }
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}

extension SavedLibraryViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return feeds.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 66
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return sections[section].isEmpty ? 0.5 : 38
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !sections[section].isEmpty else { return nil }
        let holder = UIView()
        holder.backgroundColor = Theme.background
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: feeds[section].title.uppercased(),
            attributes: [.font: Theme.font(12, weight: .medium),
                         .foregroundColor: Theme.secondaryText,
                         .kern: 0.6])
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 20),
            label.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -8)
        ])
        return holder
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SavedCollectionCell.reuseIdentifier,
                                                 for: indexPath) as! SavedCollectionCell
        cell.configure(with: sections[indexPath.section][indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(sections[indexPath.section][indexPath.row])
    }
}

private final class SavedCollectionCell: UITableViewCell {
    static let reuseIdentifier = "SavedCollectionCell"

    private let artwork = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var task: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .default
        let selected = UIView()
        selected.backgroundColor = Theme.surface
        selectedBackgroundView = selected

        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 6
        artwork.backgroundColor = Theme.surfaceVariant
        contentView.addSubview(artwork)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(15, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = Theme.font(13)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            artwork.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artwork.widthAnchor.constraint(equalToConstant: 48),
            artwork.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.leadingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        artwork.image = nil
    }

    func configure(with item: CollectionItem) {
        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
        artwork.image = nil
        task?.cancel()
        guard let url = item.artworkURL else { return }
        if let cached = ArtworkLoader.shared.cached(url) {
            artwork.image = cached
            return
        }
        task = ArtworkLoader.shared.load(url) { [weak self] image in
            self?.artwork.image = image
        }
    }
}
