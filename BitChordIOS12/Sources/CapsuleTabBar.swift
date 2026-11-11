import UIKit

/// The floating capsule tab bar. Upstream draws SF Symbols here; those do not exist on iOS 12,
/// so each tab uses a text glyph with the same labels and selection treatment.
final class CapsuleTabBar: UIView {
    var onSelect: ((Int) -> Void)?

    private let stack = UIStackView()
    private var buttons: [UIButton] = []
    private let titles = ["Home", "Explore", "Library", "Search"]
    private let glyphs = ["\u{2302}", "\u{25C8}", "\u{25A4}", "\u{2315}"]

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 0.96)
        layer.cornerRadius = 32
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.14).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])

        for (index, title) in titles.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.textAlignment = .center
            button.titleLabel?.font = Theme.font(11, weight: .semibold)
            button.setTitle("\(glyphs[index])\n\(title)", for: .normal)
            button.layer.cornerRadius = 28
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        setSelectedIndex(0)
    }

    @objc private func tapped(_ sender: UIButton) {
        setSelectedIndex(sender.tag)
        onSelect?(sender.tag)
    }

    func setSelectedIndex(_ index: Int) {
        for (position, button) in buttons.enumerated() {
            let active = position == index
            button.backgroundColor = active ? UIColor(white: 1, alpha: 0.18) : UIColor.clear
            button.setTitleColor(active ? UIColor.white : UIColor(white: 1, alpha: 0.6), for: .normal)
        }
    }
}
