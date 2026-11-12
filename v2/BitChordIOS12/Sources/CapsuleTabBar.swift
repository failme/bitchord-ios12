import UIKit

/// The floating capsule tab bar. Upstream draws SF Symbols here; those do not exist on iOS 12,
/// so each tab shows a hand-drawn icon from `Icons` above its label, with the same labels and
/// selection treatment.
final class CapsuleTabBar: UIView {
    var onSelect: ((Int) -> Void)?

    private let stack = UIStackView()
    private var controls: [UIControl] = []
    private var iconViews: [UIImageView] = []
    private var labels: [UILabel] = []
    private let items: [(title: String, icon: Icons.Kind)] = [
        ("Home", .house),
        ("Explore", .grid),
        ("Library", .books),
        ("Search", .search)
    ]

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

        for (index, item) in items.enumerated() {
            let control = UIControl()
            control.tag = index
            control.layer.cornerRadius = 28
            control.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)

            let cell = UIStackView()
            cell.axis = .vertical
            cell.alignment = .center
            cell.spacing = 2
            cell.isUserInteractionEnabled = false
            cell.translatesAutoresizingMaskIntoConstraints = false

            let icon = UIImageView(image: Icons.image(item.icon, size: 23))
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 23),
                icon.heightAnchor.constraint(equalToConstant: 23)
            ])

            let label = UILabel()
            label.text = item.title
            label.font = Theme.font(10, weight: .semibold)

            cell.addArrangedSubview(icon)
            cell.addArrangedSubview(label)
            control.addSubview(cell)
            NSLayoutConstraint.activate([
                cell.centerXAnchor.constraint(equalTo: control.centerXAnchor),
                cell.centerYAnchor.constraint(equalTo: control.centerYAnchor)
            ])

            stack.addArrangedSubview(control)
            controls.append(control)
            iconViews.append(icon)
            labels.append(label)
        }
        setSelectedIndex(0)
    }

    @objc private func tapped(_ sender: UIControl) {
        setSelectedIndex(sender.tag)
        onSelect?(sender.tag)
    }

    func setSelectedIndex(_ index: Int) {
        for (position, control) in controls.enumerated() {
            let active = position == index
            // The selected tab is a solid white pill with black content.
            control.backgroundColor = active ? UIColor.white : UIColor.clear
            iconViews[position].tintColor = active ? UIColor.black : UIColor(white: 1, alpha: 0.6)
            labels[position].textColor = active ? UIColor.black : UIColor(white: 1, alpha: 0.6)
        }
    }
}
