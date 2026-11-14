import UIKit

/// Upstream's Local Music screen: the folders that hold audio, then the songs
/// inside the one you open. The files are read from the app's LocalMusic
/// folder, so the list survives relaunch without anything being copied.
final class LocalMusicViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let hero = UIView()
    private var folders: [(name: String, songs: [LocalSong])] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Local Music"
        buildHeader()

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
        emptyLabel.text = "No audio files found on this device"
        emptyLabel.font = Theme.font(15)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 71),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func buildHeader() {
        let safe = view.safeAreaLayoutGuide

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.backgroundColor = UIColor(white: 1, alpha: 0.06)
        backButton.layer.cornerRadius = 22
        backButton.tintColor = Theme.primaryText
        backButton.setImage(Icons.image(.chevronLeft, size: 20), for: .normal)
        backButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(backButton)

        hero.translatesAutoresizingMaskIntoConstraints = false
        hero.backgroundColor = Theme.surfaceVariant
        hero.layer.cornerRadius = 16
        view.addSubview(hero)

        let folder = UIImageView(image: Icons.image(.folder, size: 128))
        folder.tintColor = UIColor(white: 0.46, alpha: 1)
        folder.translatesAutoresizingMaskIntoConstraints = false
        hero.addSubview(folder)

        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = Theme.surfaceVariant
        pill.layer.cornerRadius = 22
        view.addSubview(pill)

        let filter = UIImageView(image: Icons.image(.sliders, size: 20))
        filter.tintColor = Theme.secondaryText
        filter.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(filter)

        let account = UIButton(type: .system)
        account.backgroundColor = Theme.outline
        account.layer.cornerRadius = 15
        account.tintColor = Theme.secondaryText
        account.setImage(Icons.image(.personOutline, size: 17), for: .normal)
        account.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        account.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(account)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Local Music"
        titleLabel.font = Theme.font(20, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        view.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Audio files on device"
        subtitleLabel.font = Theme.font(15)
        subtitleLabel.textColor = Theme.secondaryText
        view.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: -10),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            pill.topAnchor.constraint(equalTo: backButton.topAnchor),
            pill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            pill.widthAnchor.constraint(equalToConstant: 100),
            pill.heightAnchor.constraint(equalToConstant: 44),

            filter.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 18),
            filter.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            filter.widthAnchor.constraint(equalToConstant: 20),
            filter.heightAnchor.constraint(equalToConstant: 20),

            account.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
            account.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            account.widthAnchor.constraint(equalToConstant: 30),
            account.heightAnchor.constraint(equalToConstant: 30),

            hero.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 15),
            hero.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hero.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.76),
            hero.heightAnchor.constraint(equalTo: hero.widthAnchor, multiplier: 0.96),

            folder.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            folder.centerYAnchor.constraint(equalTo: hero.centerYAnchor),
            folder.widthAnchor.constraint(equalToConstant: 128),
            folder.heightAnchor.constraint(equalToConstant: 128),

            titleLabel.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 25),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        reload()
    }

    @objc private func close() {
        if let nav = navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true, completion: nil)
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
            self.tableView.isHidden = self.folders.isEmpty
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
