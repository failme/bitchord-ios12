import UIKit

/// Upstream `DiwaliGate`: one greeting, only on Lakshmi Puja in an Indian
/// timezone, read from the device clock and timezone alone.
enum DiwaliGate {
    private static let seenKey = "BitChord.Festive.Diwali2026Seen"

    static func shouldPresent(now: Date = Date()) -> Bool {
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return false }
        let zone = TimeZone.current
        guard zone.identifier == "Asia/Kolkata" || zone.identifier == "Asia/Calcutta" else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? zone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return parts.year == 2026 && parts.month == 11 && parts.day == 8
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }
}

/// The full-bleed Diwali illustration with the wish at its foot, as upstream's
/// `DiwaliGreetingScreen`.
final class DiwaliGreetingViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.165, green: 0.078, blue: 0.188, alpha: 1)

        let artwork = UIImageView(image: UIImage(named: "DiwaliGreeting"))
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(artwork)

        let scrim = CAGradientLayer()
        scrim.colors = [UIColor.black.withAlphaComponent(0.25).cgColor,
                        UIColor.clear.cgColor,
                        UIColor.clear.cgColor,
                        UIColor(red: 0.10, green: 0.04, blue: 0.12, alpha: 0.72).cgColor,
                        UIColor(red: 0.07, green: 0.02, blue: 0.10, alpha: 0.96).cgColor]
        scrim.locations = [0, 0.12, 0.48, 0.72, 1]
        let scrimView = UIView()
        scrimView.isUserInteractionEnabled = false
        scrimView.translatesAutoresizingMaskIntoConstraints = false
        scrimView.layer.addSublayer(scrim)
        view.addSubview(scrimView)

        let title = UILabel()
        title.text = "BitChord wishes you a Happy Diwali"
        title.font = Theme.font(34, weight: .bold)
        title.textColor = .white
        title.numberOfLines = 0
        title.textAlignment = .center
        let subtitle = UILabel()
        subtitle.text = "May this festival of lights fill your home with joy and your days with music."
        subtitle.font = Theme.font(17)
        subtitle.textColor = UIColor(white: 1, alpha: 0.82)
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center
        let button = UIButton(type: .system)
        button.setTitle("Let's Celebrate", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.titleLabel?.font = Theme.font(17, weight: .semibold)
        button.backgroundColor = .white
        button.layer.cornerRadius = 24
        button.addTarget(self, action: #selector(celebrate), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, subtitle, button])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: view.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            artwork.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrimView.topAnchor.constraint(equalTo: view.topAnchor),
            scrimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])
        self.scrim = scrim
    }

    private var scrim: CAGradientLayer?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrim?.frame = view.bounds
    }

    @objc private func celebrate() {
        DiwaliGate.markSeen()
        dismiss(animated: true, completion: nil)
    }
}
