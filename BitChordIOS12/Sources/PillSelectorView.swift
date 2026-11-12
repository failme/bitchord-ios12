import UIKit

/// Upstream's `PillSegmentedControl`: a squircle track in Apple's tertiary fill
/// with the selected segment a lifted grey pill that slides between the others.
///
/// Measured off the Compose component — track `#767680` at 24% on dark, pill
/// `#636366`, 4pt inset, 18pt of air either side of each label — because the
/// system segmented control here draws its own grey and its own hairline and
/// reads nothing like it.
final class PillSelectorView: UIView {
    var onSelect: ((Int) -> Void)?

    // Sampled from the running app: a near-black track with a lifted grey pill,
    // not Apple's translucent segmented fill.
    private let trackFill = UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
    private let pillFill = UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
    private let inset: CGFloat = 4

    private let pill = UIView()
    private var labels: [UILabel] = []
    private var controls: [UIControl] = []
    private var titles: [String] = []
    private var selectedIndex = 0

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    init() {
        super.init(frame: .zero)
        build()
    }

    private func build() {
        backgroundColor = trackFill
        clipsToBounds = true

        pill.backgroundColor = pillFill
        pill.isUserInteractionEnabled = false
        addSubview(pill)

        for (index, title) in titles.enumerated() {
            let label = UILabel()
            label.text = title
            label.font = Theme.font(.labelMedium)
            label.textColor = .white
            label.textAlignment = .center
            labels.append(label)

            let control = UIControl()
            control.tag = index
            control.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            controls.append(control)

            addSubview(label)
            addSubview(control)
        }
    }

    func select(_ index: Int, animated: Bool = true) {
        guard index >= 0, index < titles.count else { return }
        selectedIndex = index
        let apply = {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0,
                           usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4,
                           options: [.beginFromCurrentState], animations: apply, completion: nil)
        } else {
            apply()
        }
        for (position, label) in labels.enumerated() {
            label.textColor = position == index ? .white : UIColor(white: 1, alpha: 0.65)
        }
    }

    @objc private func tapped(_ sender: UIControl) {
        guard sender.tag != selectedIndex else { return }
        select(sender.tag)
        onSelect?(sender.tag)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !titles.isEmpty else { return }
        let radius = bounds.height / 2
        layer.cornerRadius = radius

        let segment = (bounds.width - inset * 2) / CGFloat(titles.count)
        let pillFrame = CGRect(x: inset + segment * CGFloat(selectedIndex),
                               y: inset,
                               width: segment,
                               height: max(0, bounds.height - inset * 2))
        pill.frame = pillFrame
        pill.layer.cornerRadius = pillFrame.height / 2

        for index in 0..<titles.count {
            let frame = CGRect(x: inset + segment * CGFloat(index), y: 0,
                               width: segment, height: bounds.height)
            labels[index].frame = frame
            controls[index].frame = frame
        }
    }
}
