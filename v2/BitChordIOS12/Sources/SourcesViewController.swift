import UIKit

/// The sources area: add a WebDAV server, browse its folders and stream a file
/// through the same player as a downloaded or catalogue track.
final class SourcesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private var server: WebDAVServer?
    private var password: String = ""
    private var path: String = "/"
    private var entries: [WebDAVEntry] = []

    private let titleField = UILabel()
    private let jellyfinButton = UIButton(type: .system)
    private let urlField = UITextField()
    private let userField = UITextField()
    private let passField = UITextField()
    private let connect = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let statusLabel = UILabel()
    private let table = UITableView(frame: .zero, style: .plain)

    /// Capture hooks read these.
    private(set) var errorText = ""
    private(set) var isBusy = false
    var entryNames: [String] { return entries.map { $0.name } }

    init(server: WebDAVServer? = nil, path: String = "/") {
        self.server = server
        self.path = path
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Sources"

        titleField.font = Theme.font(20, weight: .bold)
        titleField.textColor = Theme.primaryText
        titleField.numberOfLines = 0
        titleField.text = "WebDAV"

        configure(urlField, placeholder: "https://server/dav/", keyboard: .URL)
        configure(userField, placeholder: "Username", keyboard: .default)
        configure(passField, placeholder: "Password", keyboard: .default)
        passField.isSecureTextEntry = true

        connect.setTitle("Connect", for: .normal)
        connect.titleLabel?.font = Theme.font(15, weight: .semibold)
        connect.setTitleColor(Theme.background, for: .normal)
        connect.backgroundColor = Theme.accent
        connect.layer.cornerRadius = 18
        connect.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)

        errorLabel.font = Theme.font(13, weight: .medium)
        errorLabel.textColor = UIColor(red: 1.0, green: 0.45, blue: 0.42, alpha: 1)
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        statusLabel.font = Theme.font(12)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.numberOfLines = 0

        jellyfinButton.setTitle("Jellyfin…", for: .normal)
        jellyfinButton.titleLabel?.font = Theme.font(15, weight: .semibold)
        jellyfinButton.setTitleColor(Theme.accent, for: .normal)
        jellyfinButton.contentHorizontalAlignment = .left
        jellyfinButton.addTarget(self, action: #selector(jellyfinTapped), for: .touchUpInside)

        let form = UIStackView(arrangedSubviews: [titleField, jellyfinButton, urlField, userField, passField, connect, errorLabel, statusLabel])
        form.axis = .vertical
        form.spacing = 8
        form.translatesAutoresizingMaskIntoConstraints = false

        table.dataSource = self
        table.delegate = self
        table.backgroundColor = Theme.background
        table.separatorColor = Theme.surface
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        table.translatesAutoresizingMaskIntoConstraints = false
        table.tableFooterView = UIView()
        view.addSubview(form)
        view.addSubview(table)

        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            form.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            form.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            urlField.heightAnchor.constraint(equalToConstant: 38),
            userField.heightAnchor.constraint(equalToConstant: 38),
            passField.heightAnchor.constraint(equalToConstant: 38),
            connect.heightAnchor.constraint(equalToConstant: 38),
            table.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 10),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        if let server = server {
            urlField.text = server.url
            userField.text = server.username
            password = WebDAVStore.shared.password(for: server)
            passField.text = password
            load(path)
        } else if let first = WebDAVStore.shared.servers.first {
            urlField.text = first.url
            userField.text = first.username
            password = WebDAVStore.shared.password(for: first)
            passField.text = password
        } else if let environment = ProcessInfo.processInfo.environment["BC_WEBDAV_URL"], !environment.isEmpty {
            urlField.text = environment
            userField.text = ProcessInfo.processInfo.environment["BC_WEBDAV_USER"] ?? ""
            password = ProcessInfo.processInfo.environment["BC_WEBDAV_PASS"] ?? ""
            passField.text = password
        }
        statusLabel.text = "PROPFIND a folder, then tap an audio file to stream it."
    }

    private func configure(_ field: UITextField, placeholder: String, keyboard: UIKeyboardType) {
        field.placeholder = placeholder
        field.keyboardType = keyboard
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.textColor = Theme.primaryText
        field.font = Theme.font(14)
        field.backgroundColor = Theme.surfaceVariant
        field.layer.cornerRadius = 8
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.leftViewMode = .always
        field.delegate = self
        field.returnKeyType = .done
    }

    // MARK: - Loading

    @objc private func jellyfinTapped() {
        navigationController?.pushViewController(JellyfinViewController(), animated: true)
    }

    @objc private func connectTapped() {
        view.endEditing(true)
        guard let raw = urlField.text, !raw.isEmpty, let url = URL(string: raw) else {
            show(error: "Enter a server URL.")
            return
        }
        let username = userField.text ?? ""
        self.password = passField.text ?? ""
        WebDAVStore.shared.add(url: raw, username: username, password: password)
        server = WebDAVServer(url: raw, username: username)
        load("/", base: url)
    }

    private func load(_ path: String, base: URL? = nil) {
        guard let server = server ?? WebDAVStore.shared.servers.first,
              let root = base ?? URL(string: server.url) else {
            show(error: "Enter a server URL.")
            return
        }
        self.path = path
        let target = SourcesViewController.url(root: root, path: path)
        isBusy = true
        statusLabel.text = "Loading \(path)…"
        errorLabel.isHidden = true
        let credentials = password.isEmpty ? WebDAVStore.shared.password(for: server) : password
        WebDAVClient.shared.list(target,
                                 username: server.username,
                                 password: credentials) { [weak self] result in
            guard let self = self else { return }
            self.isBusy = false
            switch result {
            case .success(let entries):
                self.entries = entries
                self.errorText = ""
                self.errorLabel.isHidden = true
                self.statusLabel.text = "\(entries.count) items in \(path)"
                self.table.reloadData()
            case .failure(let error):
                self.entries = []
                self.table.reloadData()
                self.show(error: error.message)
            }
        }
    }

    private func show(error message: String) {
        errorText = message
        errorLabel.text = message
        errorLabel.isHidden = false
        statusLabel.text = ""
        isBusy = false
    }

    static func url(root: URL, path: String) -> URL {
        guard path != "/", !path.isEmpty else { return root }
        var base = root.absoluteString
        if !base.hasSuffix("/") { base += "/" }
        let suffix = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: base + suffix) ?? root
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let entry = entries[indexPath.row]
        cell.textLabel?.text = entry.isDirectory ? "📁 \(entry.name)" : "🎵 \(entry.name)"
        cell.textLabel?.font = Theme.font(15)
        cell.textLabel?.textColor = Theme.primaryText
        cell.backgroundColor = Theme.background
        cell.textLabel?.numberOfLines = 1
        let selected = UIView()
        selected.backgroundColor = Theme.surface
        cell.selectedBackgroundView = selected
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = entries[indexPath.row]
        if entry.isDirectory {
            navigationController?.pushViewController(SourcesViewController(server: server, path: entry.url.path), animated: true)
            return
        }
        guard entry.isAudio else {
            show(error: "That file isn't audio.")
            return
        }
        play(entry)
    }

    private func play(_ entry: WebDAVEntry) {
        guard let server = server else { return }
        let credentials = password.isEmpty ? WebDAVStore.shared.password(for: server) : password
        WebDAVStore.shared.add(url: server.url, username: server.username, password: credentials)
        let track = Track(videoID: "webdav:" + entry.url.absoluteString,
                          title: entry.name,
                          artist: server.url,
                          durationSeconds: nil,
                          source: .addon)
        PlayerService.shared.play(tracks: [track], startingAt: 0)
        statusLabel.text = "Streaming \(entry.name)"
        let nowPlaying = NowPlayingViewController()
        nowPlaying.modalPresentationStyle = .fullScreen
        present(nowPlaying, animated: true, completion: nil)
    }

    // MARK: - Capture hooks

    func connectForCapture(url: String, username: String, password: String) {
        urlField.text = url
        userField.text = username
        passField.text = password
        self.password = password
        connectTapped()
    }

    func playForCapture(named name: String) {
        guard let entry = entries.first(where: { $0.name == name }) else { return }
        play(entry)
    }

    func browseForCapture(named name: String) -> SourcesViewController? {
        guard let entry = entries.first(where: { $0.name == name && $0.isDirectory }) else { return nil }
        let next = SourcesViewController(server: server, path: entry.url.path)
        navigationController?.pushViewController(next, animated: false)
        return next
    }
}
