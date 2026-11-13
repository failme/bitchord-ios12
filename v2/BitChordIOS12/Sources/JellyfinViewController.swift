import UIKit

/// Sign in to Jellyfin, browse the user's libraries and folders, and stream a
/// track through the same player as every other source.
final class JellyfinViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private var session: JellyfinSession?
    private var items: [JellyfinItem] = []
    private var currentParent = ""

    private let urlField = UITextField()
    private let userField = UITextField()
    private let passField = UITextField()
    private let signIn = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let statusLabel = UILabel()
    private let table = UITableView(frame: .zero, style: .plain)
    private let header = UILabel()

    private(set) var errorText = ""
    private(set) var isBusy = false
    var entryNames: [String] { return items.map { $0.name } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Jellyfin"

        header.font = Theme.font(20, weight: .bold)
        header.textColor = Theme.primaryText
        header.text = "Jellyfin"

        configure(urlField, placeholder: "http://server:8096/", keyboard: .URL)
        configure(userField, placeholder: "Username", keyboard: .default)
        configure(passField, placeholder: "Password", keyboard: .default)
        passField.isSecureTextEntry = true

        signIn.setTitle("Sign in", for: .normal)
        signIn.titleLabel?.font = Theme.font(15, weight: .semibold)
        signIn.setTitleColor(Theme.background, for: .normal)
        signIn.backgroundColor = Theme.accent
        signIn.layer.cornerRadius = 18
        signIn.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)

        errorLabel.font = Theme.font(13, weight: .medium)
        errorLabel.textColor = UIColor(red: 1.0, green: 0.45, blue: 0.42, alpha: 1)
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        statusLabel.font = Theme.font(12)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.numberOfLines = 0

        let form = UIStackView(arrangedSubviews: [header, urlField, userField, passField, signIn, errorLabel, statusLabel])
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
            signIn.heightAnchor.constraint(equalToConstant: 38),
            table.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 10),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        let environment = ProcessInfo.processInfo.environment
        if let server = JellyfinStore.shared.server {
            urlField.text = server.url
            userField.text = server.username
        } else if let url = environment["BC_JELLYFIN_URL"], !url.isEmpty {
            urlField.text = url
            userField.text = environment["BC_JELLYFIN_USER"] ?? ""
            passField.text = environment["BC_JELLYFIN_PASS"] ?? ""
        }
        statusLabel.text = "Sign in, then pick a library."
        if let stored = JellyfinStore.shared.session() {
            session = stored
            loadViews()
        }
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

    @objc private func signInTapped() {
        view.endEditing(true)
        guard let raw = urlField.text, !raw.isEmpty, let base = URL(string: raw) else {
            show(error: "Enter a server URL.")
            return
        }
        let username = userField.text ?? ""
        let password = passField.text ?? ""
        isBusy = true
        statusLabel.text = "Signing in…"
        errorLabel.isHidden = true
        JellyfinClient.shared.authenticate(base: base, username: username, password: password) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let session):
                self.session = session
                JellyfinStore.shared.save(url: raw,
                                          username: username,
                                          userID: session.userID,
                                          userName: session.userName,
                                          token: session.token)
                self.loadViews()
            case .failure(let error):
                self.isBusy = false
                self.show(error: error.message)
            }
        }
    }

    private func loadViews() {
        guard let session = session else {
            show(error: "Sign in first.")
            return
        }
        isBusy = true
        statusLabel.text = "Loading libraries…"
        JellyfinClient.shared.views(session: session) { [weak self] result in
            guard let self = self else { return }
            self.isBusy = false
            switch result {
            case .success(let items):
                self.currentParent = ""
                self.items = items
                self.errorText = ""
                self.errorLabel.isHidden = true
                self.statusLabel.text = "\(items.count) libraries · \(session.userName)"
                self.table.reloadData()
            case .failure(let error):
                self.items = []
                self.table.reloadData()
                self.show(error: error.message)
            }
        }
    }

    private func loadItems(parentID: String) {
        guard let session = session else { return }
        isBusy = true
        errorLabel.isHidden = true
        JellyfinClient.shared.items(session: session, parentID: parentID) { [weak self] result in
            guard let self = self else { return }
            self.isBusy = false
            switch result {
            case .success(let items):
                self.currentParent = parentID
                self.items = items
                self.errorText = ""
                self.statusLabel.text = "\(items.count) items"
                self.table.reloadData()
            case .failure(let error):
                self.items = []
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

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let item = items[indexPath.row]
        let glyph = item.isFolder ? "📁" : (item.isAudio ? "🎵" : "💿")
        cell.textLabel?.text = "\(glyph) \(item.name)"
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
        let item = items[indexPath.row]
        if item.isFolder {
            let next = JellyfinViewController()
            next.session = session
            next.currentParent = item.id
            navigationController?.pushViewController(next, animated: true)
            next.loadViewIfNeeded()
            next.load(parentID: item.id)
            return
        }
        guard item.isAudio else {
            show(error: "That item isn't audio.")
            return
        }
        play(item)
    }

    private func play(_ item: JellyfinItem) {
        guard let session = session,
              let url = JellyfinClient.streamURL(base: session.base, itemID: item.id, token: session.token) else {
            show(error: "This track has no stream URL.")
            return
        }
        let track = Track(videoID: "jellyfin:" + url.absoluteString,
                          title: item.name,
                          artist: item.artists.isEmpty ? session.userName : item.artists,
                          album: item.album,
                          durationSeconds: item.durationSeconds,
                          source: .addon)
        PlayerService.shared.play(tracks: [track], startingAt: 0)
        statusLabel.text = "Streaming \(item.name)"
        let nowPlaying = NowPlayingViewController()
        nowPlaying.modalPresentationStyle = .fullScreen
        present(nowPlaying, animated: true, completion: nil)
    }

    // MARK: - Capture hooks

    func load(parentID: String) {
        guard isViewLoaded else { return }
        loadItems(parentID: parentID)
    }

    func signInForCapture(url: String, username: String, password: String) {
        urlField.text = url
        userField.text = username
        passField.text = password
        signInTapped()
    }

    func browseForCapture(named name: String) -> JellyfinViewController? {
        guard let item = items.first(where: { $0.name == name && $0.isFolder }),
              let session = session else { return nil }
        let next = JellyfinViewController()
        next.session = session
        next.currentParent = item.id
        navigationController?.pushViewController(next, animated: false)
        next.loadViewIfNeeded()
        next.load(parentID: item.id)
        return next
    }

    func playForCapture(named name: String) {
        guard let item = items.first(where: { $0.name == name && $0.isAudio }) else { return }
        play(item)
    }

    /// Forces the expired-token path with a real request.
    func expireForCapture() {
        guard let current = session else { return }
        session = JellyfinSession(base: current.base,
                                  userID: current.userID,
                                  token: "expired-token",
                                  userName: current.userName)
        loadViews()
    }
}
