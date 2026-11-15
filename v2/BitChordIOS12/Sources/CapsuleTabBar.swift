import UIKit

/// The floating capsule tab bar. Upstream draws SF Symbols here; those do not exist on iOS 12,
/// so each tab shows a hand-drawn icon from `Icons` above its label, with the same labels and
/// selection treatment.
final class CapsuleTabBar: UIView {
    var onSelect: ((Int) -> Void)?

    private let stack = UIStackView()
    private let selectionPill = UIView()
    private var selectedIndex = 0
    private var pillPlaced = false
    private var controls: [UIControl] = []
    private var iconViews: [UIImageView] = []
    private var labels: [UILabel] = []
    private var items: [(title: String, icon: Icons.Kind)] {
        return [(L10n.t("Home"), .house), (L10n.t("Explore"), .grid),
                (L10n.t("Library"), .books), (L10n.t("Search"), .search)]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        // The real bar is tinted glass in both palettes: nearly black on
        // Midnight, near-white on Light, with the page still visible through it.
        backgroundColor = Theme.isDark
            ? UIColor(red: 0.055, green: 0.055, blue: 0.065, alpha: 0.97)
            : UIColor(red: 0.965, green: 0.965, blue: 0.973, alpha: 0.98)
        layer.cornerRadius = 28
        layer.borderWidth = 1
        layer.borderColor = (Theme.isDark ? UIColor(white: 1, alpha: 0.07)
                                          : UIColor(white: 0, alpha: 0.08)).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)

        // The selection is a lifted capsule with foreground contents in the
        // matching palette, not a fixed charcoal block.
        selectionPill.backgroundColor = Theme.isDark
            ? UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1)
            : UIColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1)
        selectionPill.layer.cornerRadius = 28
        selectionPill.isUserInteractionEnabled = false
        addSubview(selectionPill)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            // The real selection capsule fills the bar's full height.
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
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

            let icon = UIImageView(image: Icons.image(item.icon, size: 22))
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 22),
                icon.heightAnchor.constraint(equalToConstant: 22)
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

    /// The pill's on-screen frame during a spring, for the motion capture.
    func motionPillFrame() -> CGRect {
        if let presented = selectionPill.layer.presentation() {
            return presented.frame
        }
        return selectionPill.frame
    }

    @objc private func tapped(_ sender: UIControl) {
        setSelectedIndex(sender.tag)
        onSelect?(sender.tag)
    }

    func setSelectedIndex(_ index: Int) {
        selectedIndex = index
        UIView.transition(with: self, duration: 0.22,
                          options: [.transitionCrossDissolve, .allowUserInteraction]) {
            for (position, _) in self.controls.enumerated() {
                let active = position == index
                let activeColor = Theme.primaryText
                let inactiveColor = Theme.isDark
                    ? UIColor(white: 1, alpha: 0.52)
                    : UIColor(white: 0, alpha: 0.48)
                self.iconViews[position].tintColor = active ? activeColor : inactiveColor
                self.labels[position].textColor = active ? activeColor : inactiveColor
            }
        }
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard controls.indices.contains(selectedIndex) else { return }
        let control = controls[selectedIndex]
        let target = control.convert(control.bounds, to: self)
        guard target.width > 0, target.height > 0 else { return }
        if !pillPlaced {
            selectionPill.frame = target
            pillPlaced = true
        } else if selectionPill.frame != target {
            UIView.animate(withDuration: 0.42,
                           delay: 0,
                           usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0.3,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.selectionPill.frame = target
            }
        }
        selectionPill.layer.cornerRadius = target.height / 2
        bringSubviewToFront(stack)
    }
}
