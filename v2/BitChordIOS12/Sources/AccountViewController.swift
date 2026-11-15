import UIKit

/// The account page Settings opens. It is the only place the app asks for a
/// Google login, and the only place a saved session can be removed.
final class AccountViewController: UIViewController {
    private let avatar = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let statusLabel = UILabel()
    private let signInButton = UIButton(type: .custom)
    private let signOutButton = UIButton(type: .system)
    private let channelButton = UIButton(type: .system)
    private let noteLabel = UILabel()
    private var avatarTask: URLSessionDataTask?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Settings hides the navigation bar because the page draws its own
        // header; this pushed page needs the system bar back for its title and
        // the back button.
        navigationController?.setNavigationBarHidden(false, animated: false)
        refresh()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Account"
        view.backgroundColor = Theme.background

        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 38
        avatar.backgroundColor = Theme.surfaceVariant
        avatar.tintColor = Theme.secondaryText
        view.addSubview(avatar)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(24, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        view.addSubview(titleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = Theme.font(14)
        detailLabel.textColor = Theme.secondaryText
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 3
        view.addSubview(detailLabel)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = Theme.font(12, weight: .semibold)
        statusLabel.textColor = UIColor(red: 0.36, green: 0.78, blue: 0.48, alpha: 1)
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)

        signInButton.translatesAutoresizingMaskIntoConstraints = false
        signInButton.backgroundColor = .white
        signInButton.layer.cornerRadius = 24
        signInButton.addTarget(self, action: #selector(signIn), for: .touchUpInside)
        view.addSubview(signInButton)

        let mark = GoogleMarkView()
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.isUserInteractionEnabled = false
        signInButton.addSubview(mark)

        let buttonTitle = UILabel()
        buttonTitle.translatesAutoresizingMaskIntoConstraints = false
        buttonTitle.text = "Sign in with Google"
        buttonTitle.font = Theme.font(16, weight: .semibold)
        buttonTitle.textColor = UIColor(white: 0.15, alpha: 1)
        buttonTitle.isUserInteractionEnabled = false
        signInButton.addSubview(buttonTitle)

        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: signInButton.leadingAnchor, constant: 24),
            mark.centerYAnchor.constraint(equalTo: signInButton.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 20),
            mark.heightAnchor.constraint(equalToConstant: 20),
            buttonTitle.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 12),
            buttonTitle.centerYAnchor.constraint(equalTo: signInButton.centerYAnchor)
        ])

        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        signOutButton.setTitle("Sign out", for: .normal)
        signOutButton.setTitleColor(Theme.secondaryText, for: .normal)
        signOutButton.titleLabel?.font = Theme.font(15, weight: .medium)
        signOutButton.addTarget(self, action: #selector(signOut), for: .touchUpInside)
        view.addSubview(signOutButton)

        channelButton.translatesAutoresizingMaskIntoConstraints = false
        channelButton.setTitle("Switch channel", for: .normal)
        channelButton.setTitleColor(Theme.primaryText, for: .normal)
        channelButton.titleLabel?.font = Theme.font(14, weight: .semibold)
        channelButton.addTarget(self, action: #selector(switchChannel), for: .touchUpInside)
        channelButton.isHidden = true
        view.addSubview(channelButton)

        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.font = Theme.font(12)
        noteLabel.textColor = UIColor(white: 1, alpha: 0.38)
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0
        noteLabel.text = "BitChord opens Google's own sign-in page. Your password and two-factor codes are entered there, never in the app."
        view.addSubview(noteLabel)

        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            avatar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 76),
            avatar.heightAnchor.constraint(equalToConstant: 76),

            titleLabel.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            detailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            statusLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            signInButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 26),
            signInButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            signInButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            signInButton.heightAnchor.constraint(equalToConstant: 48),

            signOutButton.topAnchor.constraint(equalTo: signInButton.bottomAnchor, constant: 14),
            signOutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signOutButton.heightAnchor.constraint(equalToConstant: 36),

            channelButton.topAnchor.constraint(equalTo: signOutButton.bottomAnchor, constant: 2),
            channelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            channelButton.heightAnchor.constraint(equalToConstant: 34),

            noteLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            noteLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            noteLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(accountChanged),
                                              name: .googleAccountDidChange,
                                              object: nil)
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        avatarTask?.cancel()
    }

    private var signedIn: Bool { return GoogleAccountStore.shared.isSignedIn }

    private func refresh() {
        let store = GoogleAccountStore.shared
        avatarTask?.cancel()
        avatar.image = Icons.image(.personOutline, size: 34)
        if signedIn {
            titleLabel.text = store.displayName
            detailLabel.text = store.email.isEmpty ? "YouTube Music session saved on this device" : store.email
            statusLabel.text = "SIGNED IN"
            signInButton.isHidden = true
            signOutButton.isHidden = false
            channelButton.isHidden = false
            noteLabel.text = "BitChord uses this session for your YouTube Music library, likes and history. Signing out here does not sign you out of Google."
            if let url = store.avatarURL {
                avatarTask = ArtworkLoader.shared.load(url) { [weak self] image in
                    self?.avatar.image = image ?? Icons.image(.personOutline, size: 34)
                }
            }
        } else {
            titleLabel.text = "YouTube Music"
            detailLabel.text = "Sign in to bring your library, likes and listening history into BitChord."
            statusLabel.text = "NOT SIGNED IN"
            statusLabel.textColor = Theme.secondaryText
            signInButton.isHidden = false
            signOutButton.isHidden = true
            channelButton.isHidden = true
            noteLabel.text = "BitChord opens Google's own sign-in page. Your password and two-factor codes are entered there, never in the app."
        }
        if signedIn {
            statusLabel.textColor = UIColor(red: 0.36, green: 0.78, blue: 0.48, alpha: 1)
        }
    }

    @objc private func accountChanged() {
        refresh()
    }

    @objc private func signIn() {
        GoogleAccountStore.shared.presentSignIn(from: self)
    }

    @objc private func switchChannel() {
        guard signedIn else { return }
        channelButton.isEnabled = false
        channelButton.setTitle("Loading channels…", for: .normal)
        GoogleAccountStore.shared.fetchChannels { [weak self] channels, error in
            guard let self = self else { return }
            self.channelButton.isEnabled = true
            self.channelButton.setTitle("Switch channel", for: .normal)
            guard !channels.isEmpty else {
                let alert = UIAlertController(title: "Switch channel",
                                              message: error ?? "This login lists no channels.",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
                return
            }
            let sheet = UIAlertController(title: "Switch channel", message: nil, preferredStyle: .actionSheet)
            for channel in channels {
                let mark = channel.isSelected ? " ✓" : ""
                let label = channel.subtitle.isEmpty ? channel.name + mark : "\(channel.name)\(mark)  ·  \(channel.subtitle)"
                sheet.addAction(UIAlertAction(title: label, style: .default) { _ in
                    GoogleAccountStore.shared.selectChannel(channel)
                    self.refresh()
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            sheet.popoverPresentationController?.sourceView = self.channelButton
            sheet.popoverPresentationController?.sourceRect = self.channelButton.bounds
            self.present(sheet, animated: true)
        }
    }

    @objc private func signOut() {
        let alert = UIAlertController(title: "Sign out of YouTube Music?",
                                      message: "Your downloads and playlists on this device stay where they are.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Sign out", style: .destructive) { [weak self] _ in
            GoogleAccountStore.shared.signOut()
            self?.refresh()
        })
        present(alert, animated: true, completion: nil)
    }

    /// Snapshots used by the compact-layout capture.
    var isShowingSignedOut: Bool { return !signedIn }

    var isShowingSignIn: Bool { return !signedIn && !signInButton.isHidden }

    /// The handoff harness signs out through the same store call as the alert,
    /// without waiting for a person to tap the destructive action.
    func signOutForCapture() {
        GoogleAccountStore.shared.signOut()
        refresh()
    }
}
