import UIKit

/// Port of upstream `SettingsView`, measured off the real screen: a circled back
/// button and a 34pt title over a 52pt search field, then grouped cards with
/// uppercase section labels and 17/14 rows.
final class SettingsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let titleLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let searchField = UITextField()
    private let sections = SettingsCatalog.sections

    private let card = UIColor(red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1E / 255.0, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildHeader()

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor(white: 1, alpha: 0.06)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 16)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 70
        tableView.sectionHeaderHeight = 34
        tableView.tableFooterView = UIView()
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 40, right: 0)
        tableView.register(SettingsCell.self, forCellReuseIdentifier: SettingsCell.reuseIdentifier)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 18),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func buildHeader() {
        let safe = view.safeAreaLayoutGuide

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.backgroundColor = UIColor(white: 1, alpha: 0.06)
        backButton.layer.cornerRadius = 22
        backButton.tintColor = Theme.primaryText
        backButton.setImage(Icons.image(.chevronLeft, size: 20), for: .normal)
        backButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(backButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Settings"
        titleLabel.font = Theme.font(34, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        view.addSubview(titleLabel)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.backgroundColor = card
        searchField.layer.cornerRadius = 12
        searchField.font = Theme.font(16)
        searchField.textColor = Theme.primaryText
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search settings",
            attributes: [.foregroundColor: Theme.secondaryText, .font: Theme.font(16)])
        searchField.leftView = UIImageView(image: Icons.image(.search, size: 18))
        searchField.leftView?.tintColor = Theme.secondaryText
        searchField.leftViewMode = .always
        searchField.leftView?.frame = CGRect(x: 0, y: 0, width: 40, height: 18)
        view.addSubview(searchField)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 6),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 22),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        guard let key = sender.accessibilityIdentifier else { return }
        SettingsStore.shared.set(sender.isOn, for: key)
    }

    private func choose(item: SettingItem, options: [String]) {
        let sheet = UIAlertController(title: item.title, message: nil, preferredStyle: .actionSheet)
        for option in options {
            sheet.addAction(UIAlertAction(title: option, style: .default) { _ in
                SettingsStore.shared.set(option, for: item.key)
                self.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(sheet, animated: true, completion: nil)
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].items.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let holder = UIView()
        holder.backgroundColor = Theme.background
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: sections[section].title.uppercased(),
            attributes: [.font: Theme.font(12, weight: .medium),
                         .foregroundColor: Theme.secondaryText,
                         .kern: 0.6])
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 24),
            label.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -8)
        ])
        return holder
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SettingsCell.reuseIdentifier,
                                                 for: indexPath) as! SettingsCell
        let item = sections[indexPath.section].items[indexPath.row]
        let rows = sections[indexPath.section].items.count
        cell.configure(item: item, card: card,
                       first: indexPath.row == 0,
                       last: indexPath.row == rows - 1)
        if case .toggle(let fallback) = item.kind {
            let toggle = UISwitch()
            toggle.onTintColor = .white
            toggle.tintColor = UIColor(white: 1, alpha: 0.2)
            toggle.isOn = SettingsStore.shared.bool(item.key, fallback)
            toggle.accessibilityIdentifier = item.key
            toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section].items[indexPath.row]
        if case .choice(let fallback, let options) = item.kind {
            choose(item: item, options: options)
            _ = SettingsStore.shared.string(item.key, fallback)
        }
    }
}

/// One settings row: 17pt label, 14pt grey detail, optional chevron.
final class SettingsCell: UITableViewCell {
    static let reuseIdentifier = "SettingsCell"

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let chevron = UIImageView(image: Icons.image(.chevronRight, size: 15))
    private let cardView = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        contentView.backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 14
        cardView.layer.masksToBounds = true
        contentView.addSubview(cardView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(17)
        titleLabel.textColor = Theme.primaryText
        cardView.addSubview(titleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = Theme.font(14)
        detailLabel.textColor = Theme.secondaryText
        detailLabel.numberOfLines = 2
        cardView.addSubview(detailLabel)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = Theme.secondaryText
        chevron.contentMode = .scaleAspectFit
        cardView.addSubview(chevron)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            chevron.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            chevron.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 9),
            chevron.heightAnchor.constraint(equalToConstant: 15)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(item: SettingItem, card: UIColor, first: Bool, last: Bool) {
        titleLabel.text = item.title
        detailLabel.text = item.detail
        var showsChevron = false
        var available = true
        switch item.kind {
        case .choice(let fallback, _):
            detailLabel.text = SettingsStore.shared.string(item.key, fallback)
            showsChevron = true
        case .stepper(let fallback, _, _, _, let unit):
            let value = SettingsStore.shared.double(item.key, fallback)
            detailLabel.text = unit == "\u{00D7}"
                ? String(format: "%.2g%@", value, unit)
                : "\(Int(value))\(unit)"
            showsChevron = true
        case .unavailable(let reason):
            detailLabel.text = reason
            available = false
        case .toggle:
            showsChevron = false
        }
        chevron.isHidden = !showsChevron
        titleLabel.textColor = available ? Theme.primaryText : Theme.secondaryText
        cardView.backgroundColor = card
        // Only the outer corners of a group are rounded, as in the real cards.
        var corners: UIRectCorner = []
        if first { corners.formUnion([.topLeft, .topRight]) }
        if last { corners.formUnion([.bottomLeft, .bottomRight]) }
        let mask = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 400, height: 140),
                                byRoundingCorners: corners,
                                cornerRadii: CGSize(width: 14, height: 14))
        let shape = CAShapeLayer()
        shape.path = mask.cgPath
        cardView.layer.mask = (first || last) ? shape : nil
    }
}
