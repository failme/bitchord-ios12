import UIKit
import CoreImage

/// Explore as the real app draws it: no shelves, just a two-column grid of
/// 104pt mood sleeves. Each sleeve is a solid 28% colour stripe beside a
/// duotone crop of its artwork, with the name at the top-left.
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
        Mood(title: "Focus", top: UIColor(red: 0.43, green: 0.44, blue: 0.46, alpha: 1),
             bottom: UIColor(red: 0.30, green: 0.31, blue: 0.33, alpha: 1)),
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
    private let avatar = UIButton(type: .system)

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
        avatar.backgroundColor = Theme.surfaceVariant
        avatar.layer.cornerRadius = 20
        avatar.tintColor = Theme.secondaryText
        avatar.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(avatar)

        titleLabel.text = "Explore"
        titleLabel.font = Theme.font(34, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(titleLabel)

        grid.axis = .vertical
        grid.spacing = 12
        grid.distribution = .fillEqually
        grid.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(grid)

        var row: UIStackView?
        for (index, mood) in moods.enumerated() {
            if index % 2 == 0 {
                let newRow = UIStackView()
                newRow.axis = .horizontal
                newRow.spacing = 12
                newRow.distribution = .fillEqually
                grid.addArrangedSubview(newRow)
                // Upstream's mood sleeve is 1.72:1, not a fixed 104pt. At the
                // 320pt width of an SE the old fixed height made every tile
                // square-ish and visibly different from the reference.
                newRow.heightAnchor.constraint(equalTo: newRow.widthAnchor,
                                               multiplier: 1.0 / 3.44,
                                               constant: -3.49).isActive = true
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

        GoogleAccountStore.shared.updateAvatarButton(avatar, size: 40)
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(accountChanged),
                                              name: .googleAccountDidChange,
                                              object: nil)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // The avatar is part of the page's top row. The first pass put it
            // above the scroll view's bounds, where it was clipped away.
            avatar.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8),
            avatar.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),

            grid.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 9),
            grid.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            grid.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -110),
            grid.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])
    }

    @objc private func accountChanged() {
        GoogleAccountStore.shared.updateAvatarButton(avatar, size: 40)
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

    // MARK: - Motion capture hooks

    private func motionTile(in node: UIView) -> MoodTileView? {
        if let tile = node as? MoodTileView { return tile }
        for child in node.subviews {
            if let found = motionTile(in: child) { return found }
        }
        return nil
    }

    func motionPressTile() -> Bool {
        guard let tile = motionTile(in: view) else { return false }
        tilePressIn(tile)
        return true
    }

    func motionReleaseTile() {
        guard let tile = motionTile(in: view) else { return }
        tilePressOut(tile)
    }

    func motionTileScale() -> CGFloat {
        guard let layer = motionTile(in: view)?.layer.presentation() else { return 1 }
        return layer.transform.m11
    }

    func motionFirstTileFrame(in view: UIView) -> CGRect? {
        self.view.layoutIfNeeded()
        guard let tile = motionTile(in: view) else { return nil }
        return tile.convert(tile.bounds, to: view)
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

/// One mood sleeve: the solid colour band, the duotone artwork and the name.
///
/// Upstream tints every cover through a two-colour ramp derived from the
/// category's stripe, so the sleeve reads as one object. A plain photo with a
/// dark gradient, which the first pass drew, looks like a different component.
final class MoodTileView: UIButton {
    let moodTitle: String

    private let artContainer = UIView()
    private let photo = UIImageView()
    private let shade = CAGradientLayer()
    private let label = UILabel()
    private let baseColor: UIColor
    private let shadowColor: UIColor
    private let highlightColor: UIColor

    /// Compose's gradient offsets are 0..255; Core Image vectors work in 0..1.
    private static let ciContext = CIContext(options: nil)

    init(mood: String, top: UIColor, bottom: UIColor) {
        moodTitle = mood
        baseColor = top
        let shadow = MoodTileView.lerp(top, .black, 0.68)
        let highlight = MoodTileView.lerp(top, .white, 0.32)
        shadowColor = shadow
        highlightColor = highlight
        super.init(frame: .zero)

        layer.cornerRadius = 18
        layer.masksToBounds = true
        backgroundColor = MoodTileView.lerp(top, .black, 0.08)

        // A card is a 28% solid stripe and a 72% artwork pane. The placeholder
        // keeps the pane's tone before the cover arrives.
        artContainer.frame = .zero
        artContainer.backgroundColor = MoodTileView.lerp(shadow, highlight, 0.45)
        artContainer.clipsToBounds = true
        addSubview(artContainer)

        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        artContainer.addSubview(photo)

        shade.colors = [UIColor(white: 0, alpha: 0.24).cgColor,
                        UIColor.clear.cgColor]
        shade.locations = [0, 0.62]
        shade.startPoint = CGPoint(x: 0.5, y: 0)
        shade.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(shade)

        label.text = mood
        label.font = Theme.font(15, weight: .bold)
        label.textColor = .white
        label.numberOfLines = 2
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.35
        label.layer.shadowRadius = 4
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The real sleeves give the colour band roughly a fifth of the card,
        // leaving the duotone picture the rest.
        let stripe = bounds.width * 0.20
        artContainer.frame = CGRect(x: stripe, y: 0,
                                    width: max(0, bounds.width - stripe), height: bounds.height)
        photo.frame = artContainer.bounds
        shade.frame = bounds
    }

    func setArtwork(_ url: URL) {
        ArtworkLoader.shared.load(url) { [weak self] image in
            guard let self = self, let image = image else { return }
            let tinted = MoodTileView.duotone(image,
                                              shadow: self.shadowColor,
                                              highlight: self.highlightColor)
            self.photo.image = tinted ?? image
        }
    }

    private static func lerp(_ from: UIColor, _ to: UIColor, _ amount: CGFloat) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        return UIColor(red: fr + (tr - fr) * amount,
                       green: fg + (tg - fg) * amount,
                       blue: fb + (tb - fb) * amount,
                       alpha: fa + (ta - fa) * amount)
    }

    /// Maps luminance onto the shadow-to-highlight ramp, same as Compose's
    /// colour matrix. The result is cached by the image loader, not re-rendered
    /// on every layout pass.
    private static func duotone(_ image: UIImage, shadow: UIColor, highlight: UIColor) -> UIImage? {
        guard let source = CIImage(image: image),
              let filter = CIFilter(name: "CIColorMatrix") else { return nil }
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        var hr: CGFloat = 0, hg: CGFloat = 0, hb: CGFloat = 0, ha: CGFloat = 0
        shadow.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        highlight.getRed(&hr, green: &hg, blue: &hb, alpha: &ha)
        let spanR = hr - sr, spanG = hg - sg, spanB = hb - sb
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: spanR * 0.299, y: spanR * 0.587, z: spanR * 0.114, w: 0),
                        forKey: "inputRVector")
        filter.setValue(CIVector(x: spanG * 0.299, y: spanG * 0.587, z: spanG * 0.114, w: 0),
                        forKey: "inputGVector")
        filter.setValue(CIVector(x: spanB * 0.299, y: spanB * 0.587, z: spanB * 0.114, w: 0),
                        forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: sr, y: sg, z: sb, w: 0), forKey: "inputBiasVector")
        guard let output = filter.outputImage,
              let rendered = ciContext.createCGImage(output, from: source.extent) else { return nil }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: image.imageOrientation)
    }
}
