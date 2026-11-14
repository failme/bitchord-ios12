import UIKit

/// Explore as the real app draws it: no shelves, just a two-column grid of
/// 110pt mood tiles, each a tinted gradient with its name in the top-left.
final class ExploreViewController: UIViewController {
    private struct Mood {
        let title: String
        let top: UIColor
        let bottom: UIColor
    }

    // Order and hues read off the running Android app.
    private let moods: [Mood] = [
        Mood(title: "Chill", top: UIColor(red: 0.72, green: 0.82, blue: 0.95, alpha: 1),
             bottom: UIColor(red: 0.55, green: 0.68, blue: 0.88, alpha: 1)),
        Mood(title: "Christmas", top: UIColor(red: 0.16, green: 0.48, blue: 0.22, alpha: 1),
             bottom: UIColor(red: 0.09, green: 0.33, blue: 0.15, alpha: 1)),
        Mood(title: "Commute", top: UIColor(red: 0.88, green: 0.66, blue: 0.24, alpha: 1),
             bottom: UIColor(red: 0.72, green: 0.49, blue: 0.14, alpha: 1)),
        Mood(title: "Diwali", top: UIColor(red: 0.46, green: 0.45, blue: 0.37, alpha: 1),
             bottom: UIColor(red: 0.30, green: 0.29, blue: 0.24, alpha: 1)),
        Mood(title: "Energize", top: UIColor(red: 0.79, green: 0.65, blue: 0.44, alpha: 1),
             bottom: UIColor(red: 0.64, green: 0.49, blue: 0.31, alpha: 1)),
        Mood(title: "Feel good", top: UIColor(red: 0.31, green: 0.64, blue: 0.37, alpha: 1),
             bottom: UIColor(red: 0.20, green: 0.48, blue: 0.26, alpha: 1)),
        Mood(title: "Focus", top: UIColor(red: 0.62, green: 0.64, blue: 0.66, alpha: 1),
             bottom: UIColor(red: 0.45, green: 0.47, blue: 0.49, alpha: 1)),
        Mood(title: "Gaming", top: UIColor(red: 0.36, green: 0.37, blue: 0.48, alpha: 1),
             bottom: UIColor(red: 0.23, green: 0.24, blue: 0.33, alpha: 1)),
        Mood(title: "Party", top: UIColor(red: 0.61, green: 0.42, blue: 0.84, alpha: 1),
             bottom: UIColor(red: 0.45, green: 0.27, blue: 0.68, alpha: 1)),
        Mood(title: "Romance", top: UIColor(red: 0.75, green: 0.22, blue: 0.18, alpha: 1),
             bottom: UIColor(red: 0.56, green: 0.13, blue: 0.11, alpha: 1)),
        Mood(title: "Sleep", top: UIColor(red: 0.26, green: 0.32, blue: 0.52, alpha: 1),
             bottom: UIColor(red: 0.16, green: 0.20, blue: 0.36, alpha: 1)),
        Mood(title: "Workout", top: UIColor(red: 0.80, green: 0.36, blue: 0.26, alpha: 1),
             bottom: UIColor(red: 0.60, green: 0.24, blue: 0.18, alpha: 1)),
        Mood(title: "Sad", top: UIColor(red: 0.34, green: 0.42, blue: 0.55, alpha: 1),
             bottom: UIColor(red: 0.22, green: 0.28, blue: 0.39, alpha: 1)),
        Mood(title: "Classical", top: UIColor(red: 0.55, green: 0.47, blue: 0.35, alpha: 1),
             bottom: UIColor(red: 0.39, green: 0.32, blue: 0.23, alpha: 1)),
        Mood(title: "Jazz", top: UIColor(red: 0.45, green: 0.30, blue: 0.29, alpha: 1),
             bottom: UIColor(red: 0.30, green: 0.19, blue: 0.19, alpha: 1)),
        Mood(title: "Pop", top: UIColor(red: 0.72, green: 0.36, blue: 0.60, alpha: 1),
             bottom: UIColor(red: 0.54, green: 0.22, blue: 0.44, alpha: 1))
    ]

    private let scrollView = UIScrollView()
    private let titleLabel = UILabel()
    private let grid = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        // Like the real Explore, a lone account avatar sits high on the right,
        // above the 34pt page title.
        let avatar = UIButton(type: .system)
        avatar.backgroundColor = Theme.surfaceVariant
        avatar.layer.cornerRadius = 20
        avatar.tintColor = Theme.secondaryText
        avatar.setImage(Icons.image(.person, size: 18), for: .normal)
        avatar.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(avatar)

        titleLabel.text = "Explore"
        titleLabel.font = Theme.font(34, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(titleLabel)

        grid.axis = .vertical
        grid.spacing = 10
        grid.distribution = .fillEqually
        grid.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(grid)

        var row: UIStackView?
        for (index, mood) in moods.enumerated() {
            if index % 2 == 0 {
                let newRow = UIStackView()
                newRow.axis = .horizontal
                newRow.spacing = 10
                newRow.distribution = .fillEqually
                grid.addArrangedSubview(newRow)
                newRow.heightAnchor.constraint(equalToConstant: 110).isActive = true
                row = newRow
            }
            let tile = MoodTileView(mood: mood.title, top: mood.top, bottom: mood.bottom)
            tile.addTarget(self, action: #selector(tileTapped(_:)), for: .touchUpInside)
            tile.addTarget(self, action: #selector(tilePressIn(_:)), for: [.touchDown, .touchDragEnter])
            tile.addTarget(self, action: #selector(tilePressOut(_:)),
                           for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            row?.addArrangedSubview(tile)
            // The real tiles are photo collages, so each one borrows the first
            // cover the catalogue has for its mood.
            CatalogueSearch.shared.albums(mood.title) { albums in
                if let artwork = albums.first?.artwork {
                    tile.setArtwork(artwork)
                }
            }
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            avatar.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: -10),
            avatar.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),

            grid.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            grid.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -110),
            grid.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])
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

    @objc private func tilePressIn(_ sender: UIControl) {
        UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction]) {
            sender.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
    }

    @objc private func tilePressOut(_ sender: UIControl) {
        UIView.animate(withDuration: 0.24, delay: 0, usingSpringWithDamping: 0.7,
                       initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
            sender.transform = .identity
        }
    }

    @objc private func tileTapped(_ sender: MoodTileView) {
        let mood = sender.moodTitle
        let list = TrackListViewController()
        list.title = mood
        list.emptyText = "Searching..."
        navigationController?.pushViewController(list, animated: true)
        InnerTube.shared.search(mood + " music", filter: .songs) { tracks, error in
            if let tracks = tracks, !tracks.isEmpty {
                list.setTracks(tracks)
            } else {
                list.emptyText = error ?? ("No results for " + mood + ".")
                list.setTracks([])
            }
        }
    }
}

/// One gradient mood tile with its name in the top-left corner.
final class MoodTileView: UIButton {
    let moodTitle: String
    private let gradient = CAGradientLayer()
    private let photo = UIImageView()
    private let shade = CAGradientLayer()
    private let label = UILabel()

    init(mood: String, top: UIColor, bottom: UIColor) {
        moodTitle = mood
        super.init(frame: .zero)
        layer.cornerRadius = 12
        layer.masksToBounds = true

        gradient.colors = [top.cgColor, bottom.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradient)

        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.alpha = 0.85
        photo.translatesAutoresizingMaskIntoConstraints = false
        addSubview(photo)
        NSLayoutConstraint.activate([
            photo.topAnchor.constraint(equalTo: topAnchor),
            photo.leadingAnchor.constraint(equalTo: leadingAnchor),
            photo.trailingAnchor.constraint(equalTo: trailingAnchor),
            photo.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        // Darken the photo at the top-left so the mood name stays readable.
        shade.colors = [UIColor(white: 0, alpha: 0.45).cgColor,
                        UIColor(white: 0, alpha: 0.05).cgColor]
        shade.startPoint = CGPoint(x: 0, y: 0)
        shade.endPoint = CGPoint(x: 1, y: 1)
        photo.layer.addSublayer(shade)

        label.text = mood
        label.font = Theme.font(15, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        shade.frame = photo.bounds
    }

    func setArtwork(_ url: URL) {
        ArtworkLoader.shared.load(url) { [weak self] image in
            self?.photo.image = image
        }
    }
}
