import UIKit

/// Port of upstream `SettingsView`. Every upstream key appears; rows whose machinery is not
/// ported are disabled and say why, instead of silently doing nothing.
final class SettingsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let sections = SettingsCatalog.sections

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = Theme.background

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(close))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.tableFooterView = UIView()
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        guard let key = sender.accessibilityIdentifier else { return }
        SettingsStore.shared.set(sender.isOn, for: key)
    }

    @objc private func stepperChanged(_ sender: UIStepper) {
        guard let key = sender.accessibilityIdentifier else { return }
        SettingsStore.shared.set(sender.value, for: key)
        tableView.reloadData()
    }

    private func detailText(for value: Double, unit: String) -> String {
        if unit == "\u{00D7}" {
            return String(format: "%.2g%@", value, unit)
        }
        return "\(Int(value))\(unit)"
    }

    private func chooseOption(for item: SettingItem, options: [String], current: String) {
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
        return sections.count + 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == sections.count {
            return "About"
        }
        return sections[section].title
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = Theme.secondaryText
            header.textLabel?.font = Theme.font(13, weight: .semibold)
            header.contentView.backgroundColor = Theme.background
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == sections.count {
            return 3
        }
        return sections[section].items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == sections.count {
            return aboutCell(indexPath.row)
        }

        let item = sections[indexPath.section].items[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.surface
        cell.textLabel?.text = item.title
        cell.textLabel?.textColor = Theme.primaryText
        cell.textLabel?.font = Theme.font(15, weight: .medium)
        cell.detailTextLabel?.text = item.detail
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.detailTextLabel?.font = Theme.font(12)
        cell.detailTextLabel?.numberOfLines = 0
        cell.selectionStyle = .none

        switch item.kind {
        case .toggle(let fallback):
            let toggle = UISwitch()
            toggle.onTintColor = Theme.accent
            toggle.isOn = SettingsStore.shared.bool(item.key, fallback)
            toggle.accessibilityIdentifier = item.key
            toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle

        case .stepper(let fallback, let minimum, let maximum, let step, let unit):
            let stepper = UIStepper()
            stepper.minimumValue = minimum
            stepper.maximumValue = maximum
            stepper.stepValue = step
            stepper.value = SettingsStore.shared.double(item.key, fallback)
            stepper.tintColor = Theme.accent
            stepper.accessibilityIdentifier = item.key
            stepper.addTarget(self, action: #selector(stepperChanged(_:)), for: .valueChanged)
            cell.accessoryView = stepper
            cell.detailTextLabel?.text = detailText(for: stepper.value, unit: unit)

        case .choice(let fallback, _):
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.detailTextLabel?.text = SettingsStore.shared.string(item.key, fallback)

        case .unavailable(let reason):
            cell.textLabel?.textColor = Theme.secondaryText
            cell.detailTextLabel?.text = reason
        }
        return cell
    }

    private func aboutCell(_ row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.surface
        cell.textLabel?.textColor = Theme.primaryText
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.detailTextLabel?.numberOfLines = 0
        cell.selectionStyle = .none

        switch row {
        case 0:
            cell.textLabel?.text = "BitChord for iOS 12"
            cell.detailTextLabel?.text = "Version 1.0 (build 1)"
        case 1:
            cell.textLabel?.text = "Licence"
            cell.detailTextLabel?.text = "GPL-3.0, derived from rzrinanda/bitchord-ios"
        default:
            cell.textLabel?.text = "Settings keys"
            cell.detailTextLabel?.text = "\(SettingsCatalog.keyCount) upstream keys present; unavailable rows state why."
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section < sections.count else { return }
        let item = sections[indexPath.section].items[indexPath.row]
        if case .choice(let fallback, let options) = item.kind {
            let current = SettingsStore.shared.string(item.key, fallback)
            chooseOption(for: item, options: options, current: current)
        }
    }
}
