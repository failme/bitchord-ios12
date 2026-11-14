import UIKit

/// One row or tile in the custom track menu.
struct TrackMenuAction {
    let title: String
    let icon: Icons.Kind?
    let value: String?
    let destructive: Bool
    let handler: () -> Void

    init(title: String, icon: Icons.Kind?, value: String? = nil,
         destructive: Bool = false, handler: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.value = value
        self.destructive = destructive
        self.handler = handler
    }
}

/// The real app's song menu is not a system action sheet: it is a 256pt
/// floating iOS panel with a 30pt continuous corner, grouped rows, a pair of
/// quick-action tiles, and a spring that grows out of the corner nearest the
/// button that opened it. This reproduces that panel on iOS 12.
final class TrackActionsMenuViewController: UIViewController {
    private let quickActions: [TrackMenuAction]
    private let groups: [[TrackMenuAction]]
    private weak var anchorView: UIView?

    private let scrim = UIView()
    private let shadowPlate = UIView()
    private let panel = UIView()
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    private var panelWidth: CGFloat = 256
    private var placed = false
    private var closing = false
    private var hangsDown = false

    /// Upstream's IosMenuPalette: #1C1C1E slab, 10% white rim, 75% label.
    private let labelColor = UIColor(white: 1, alpha: 0.78)
    private let secondaryColor = UIColor(white: 1, alpha: 0.60)

    init(quickActions: [TrackMenuAction], groups: [[TrackMenuAction]], anchorView: UIView?) {
        self.quickActions = quickActions
        self.groups = groups
        self.anchorView = anchorView
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false

        scrim.backgroundColor = UIColor.black.withAlphaComponent(0.30)
        scrim.alpha = 0
        scrim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tappedOutside)))
        view.addSubview(scrim)

        shadowPlate.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)
        shadowPlate.layer.cornerRadius = 30
        shadowPlate.layer.shadowColor = UIColor.black.cgColor
        shadowPlate.layer.shadowOpacity = 0.5
        shadowPlate.layer.shadowRadius = 24
        shadowPlate.layer.shadowOffset = CGSize(width: 0, height: 10)
        shadowPlate.alpha = 0
        view.addSubview(shadowPlate)

        panel.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)
        panel.layer.cornerRadius = 30
        panel.layer.borderWidth = 0.5
        panel.layer.borderColor = UIColor(white: 1, alpha: 0.10).cgColor
        panel.layer.masksToBounds = true
        panel.alpha = 0
        view.addSubview(panel)

        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        panel.addSubview(scroll)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 0
        scroll.addSubview(stack)

        buildContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrim.frame = view.bounds
        guard !placed, view.bounds.width > 0 else { return }
        placed = true
        placePanel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard panel.alpha == 0 else { return }
        panel.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        shadowPlate.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        let animator = UIViewPropertyAnimator(duration: 0.36, dampingRatio: 1) {
            self.scrim.alpha = 1
            self.panel.alpha = 1
            self.shadowPlate.alpha = 1
            self.panel.transform = .identity
            self.shadowPlate.transform = .identity
        }
        animator.startAnimation()
    }

    private func buildContent() {
        if !quickActions.isEmpty {
            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false
            let tiles = UIStackView()
            tiles.axis = .horizontal
            tiles.distribution = .fillEqually
            tiles.spacing = 4
            tiles.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(tiles)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 66),
                tiles.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                tiles.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
                tiles.topAnchor.constraint(equalTo: row.topAnchor),
                tiles.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            ])
            for action in quickActions {
                let tile = TrackMenuQuickAction(action: action, labelColor: labelColor)
                tile.onTap = { [weak self] in self?.perform(action) }
                tiles.addArrangedSubview(tile)
            }
            stack.addArrangedSubview(row)
        }

        for (index, group) in groups.enumerated() where !group.isEmpty {
            if index > 0 || !quickActions.isEmpty {
                stack.addArrangedSubview(makeSeparator())
            }
            for action in group {
                let row = TrackMenuRow(action: action, labelColor: labelColor,
                                       secondaryColor: secondaryColor)
                row.onTap = { [weak self] in self?.perform(action) }
                stack.addArrangedSubview(row)
            }
        }
    }

    private func makeSeparator() -> UIView {
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        let line = UIView()
        line.backgroundColor = UIColor(white: 1, alpha: 0.10)
        line.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(line)
        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(equalToConstant: 17),
            line.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 18),
            line.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -18),
            line.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
        return holder
    }

    private func placePanel() {
        panelWidth = min(256, view.bounds.width - 28)
        stack.frame = CGRect(x: 0, y: 0, width: panelWidth, height: 0)
        stack.layoutIfNeeded()
        let fit = stack.systemLayoutSizeFitting(CGSize(width: panelWidth, height: 0),
                                                withHorizontalFittingPriority: .required,
                                                verticalFittingPriority: .fittingSizeLevel)
        let insets = UIApplication.shared.keyWindow?.safeAreaInsets ?? view.safeAreaInsets
        let top = max(12, insets.top + 8)
        let bottomLimit = view.bounds.height - max(12, insets.bottom + 12)
        let maxHeight = max(120, bottomLimit - top)
        let contentHeight = fit.height + 16
        let panelHeight = min(contentHeight, maxHeight)

        var anchorRect: CGRect?
        if let anchor = anchorView, anchor.window != nil {
            anchorRect = anchor.convert(anchor.bounds, to: view)
        }
        hangsDown = anchorRect.map { $0.midY < view.bounds.midY } ?? false
        let right = anchorRect.map { $0.maxX } ?? (view.bounds.width - 14)
        let x = min(max(14, right - panelWidth), view.bounds.width - 14 - panelWidth)
        var y = hangsDown ? (anchorRect?.minY ?? top) : (bottomLimit - panelHeight)
        y = min(max(top, y), max(top, bottomLimit - panelHeight))

        panel.layer.anchorPoint = CGPoint(x: 1, y: hangsDown ? 0 : 1)
        panel.bounds = CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        panel.layer.position = CGPoint(x: x + panelWidth,
                                       y: hangsDown ? y : y + panelHeight)
        shadowPlate.layer.anchorPoint = panel.layer.anchorPoint
        shadowPlate.bounds = panel.bounds
        shadowPlate.layer.position = panel.layer.position

        scroll.frame = CGRect(x: 0, y: 8, width: panelWidth, height: panelHeight - 16)
        scroll.contentSize = CGSize(width: panelWidth, height: fit.height)
        stack.frame = CGRect(x: 0, y: 0, width: panelWidth, height: fit.height)

        // The tiles and rows are laid out by the stack; this makes their
        // intrinsic heights participate even though the panel itself is
        // frame-driven.
        stack.layoutIfNeeded()
    }

    private func perform(_ action: TrackMenuAction) {
        closeMenu(then: action.handler)
    }

    private func closeMenu(then completion: (() -> Void)? = nil) {
        guard !closing else { return }
        closing = true
        UIView.animate(withDuration: 0.17, delay: 0, options: [.curveEaseIn],
                       animations: {
            self.scrim.alpha = 0
            self.panel.alpha = 0
            self.shadowPlate.alpha = 0
            self.panel.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            self.shadowPlate.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        }, completion: { _ in
            self.dismiss(animated: false, completion: completion)
        })
    }

    @objc private func tappedOutside() {
        closeMenu()
    }
}

/// A tile across the top of the panel: glyph over a short label.
private final class TrackMenuQuickAction: UIControl {
    var onTap: (() -> Void)?
    private let highlight = UIView()

    init(action: TrackMenuAction, labelColor: UIColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        highlight.backgroundColor = UIColor(white: 1, alpha: 0.10)
        highlight.layer.cornerRadius = 16
        highlight.isUserInteractionEnabled = false
        highlight.alpha = 0
        addSubview(highlight)

        let icon = UIImageView(image: action.icon.map { Icons.image($0, size: 23) })
        icon.tintColor = labelColor
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = action.title
        label.font = Theme.font(12, weight: .medium)
        label.textColor = labelColor
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 23),
            icon.heightAnchor.constraint(equalToConstant: 23),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 6),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(self, action: #selector(pressed), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(released), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds
    }

    @objc private func tapped() { onTap?() }
    @objc private func pressed() { highlight.alpha = 1 }
    @objc private func released() { highlight.alpha = 0 }
}

/// One line of the menu: 28pt icon column, 10pt gap, 17pt label, optional value.
private final class TrackMenuRow: UIControl {
    var onTap: (() -> Void)?
    private let highlight = UIView()

    init(action: TrackMenuAction, labelColor: UIColor, secondaryColor: UIColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        highlight.backgroundColor = UIColor(white: 1, alpha: 0.10)
        highlight.layer.cornerRadius = 14
        highlight.isUserInteractionEnabled = false
        highlight.alpha = 0
        addSubview(highlight)

        let icon = UIImageView(image: action.icon.map { Icons.image($0, size: 21) })
        icon.tintColor = action.destructive ? UIColor(red: 1, green: 0.27, blue: 0.23, alpha: 1) : labelColor
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = action.title
        label.font = Theme.font(17)
        label.textColor = action.destructive ? UIColor(red: 1, green: 0.27, blue: 0.23, alpha: 1) : labelColor
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)

        var trailing = trailingAnchor
        if let value = action.value {
            let valueLabel = UILabel()
            valueLabel.text = value
            valueLabel.font = Theme.font(15)
            valueLabel.textColor = secondaryColor
            valueLabel.textAlignment = .right
            valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            valueLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(valueLabel)
            NSLayoutConstraint.activate([
                valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
                valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 10),
            ])
            trailing = valueLabel.leadingAnchor
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 21),
            icon.heightAnchor.constraint(equalToConstant: 21),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailing, constant: -10),
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(self, action: #selector(pressed), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(released), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds.insetBy(dx: 8, dy: 0)
    }

    @objc private func tapped() { onTap?() }
    @objc private func pressed() { highlight.alpha = 1 }
    @objc private func released() { highlight.alpha = 0 }
}
