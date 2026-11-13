import UIKit

/// Upstream's Local Music screen: the folders that hold audio, then the songs
/// inside the one you open. The files are read from the app's LocalMusic
/// folder, so the list survives relaunch without anything being copied.
final class LocalMusicViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private var folders: [(name: String, songs: [LocalSong])] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Local Music"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.tableFooterView = UIView()
        tableView.register(LocalFolderCell.self, forCellReuseIdentifier: LocalFolderCell.reuseIdentifier)
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = Theme.font(.bodyLarge)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = "No folders with music in them"
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    /// Opens the first folder through the same selection path a tap takes.
    func openFolderForCapture() {
        guard !folders.isEmpty else { return }
        tableView(tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
    }

    private func reload() {
        LocalMusicStore.shared.scan { [weak self] _ in
            guard let self = self else { return }
            self.folders = LocalMusicStore.shared.folders
            self.tableView.reloadData()
            self.emptyLabel.isHidden = !self.folders.isEmpty
        }
    }
}

extension LocalMusicViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return folders.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LocalFolderCell.reuseIdentifier,
                                                 for: indexPath)
        if let row = cell as? LocalFolderCell, indexPath.row < folders.count {
            let folder = folders[indexPath.row]
            row.configure(name: folder.name, count: folder.songs.count)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < folders.count else { return }
        let folder = folders[indexPath.row]
        let list = TrackListViewController()
        list.title = folder.name
        list.tracks = folder.songs.map { $0.track }
        list.emptyText = "No songs in this folder."
        navigationController?.pushViewController(list, animated: true)
    }
}

/// A folder row: music glyph, name, and how many songs are inside.
final class LocalFolderCell: UITableViewCell {
    static let reuseIdentifier = "LocalFolderCell"

    private let glyph = UIImageView()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()
    private let chevron = UIImageView(image: Icons.image(.chevronRight, size: 14))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        let selected = UIView()
        selected.backgroundColor = Theme.surface
        selectedBackgroundView = selected

        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.tintColor = Theme.primaryText
        glyph.contentMode = .scaleAspectFit
        glyph.image = Icons.image(.musicNote, size: 20)
        contentView.addSubview(glyph)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = Theme.font(.titleMedium)
        nameLabel.textColor = Theme.primaryText
        contentView.addSubview(nameLabel)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = Theme.font(.bodyMedium)
        countLabel.textColor = Theme.secondaryText
        contentView.addSubview(countLabel)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = Theme.secondaryText
        contentView.addSubview(chevron)

        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.gutter),
            glyph.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 24),

            nameLabel.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 14),
            nameLabel.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -18),

            countLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            countLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.gutter),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14)
        ])
    }

    func configure(name: String, count: Int) {
        nameLabel.text = name
        countLabel.text = "\(count) song\(count == 1 ? "" : "s")"
    }
}
