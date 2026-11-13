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

    /// Brings the download rows into view so the capture can show that they
    /// carry live state (storage used) rather than placeholder copy.
    /// The Settings row and the capture both land here; the row is what a user
    /// taps, so the flow is exercised through the same entry point.
    func showOnboarding() {
        let onboarding = OnboardingViewController()
        onboarding.modalPresentationStyle = .fullScreen
        present(onboarding, animated: true, completion: nil)
    }

    func scrollToDownloadSection() {
        guard let section = sections.firstIndex(where: { section in
            section.items.contains(where: { $0.key == "BitChord.Download.Storage" })
        }) else { return }
        view.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Storage used is live state: it changes as downloads come and go.
        tableView.reloadData()
    }

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
        let magnifier = UIImageView(image: Icons.image(.search, size: 18))
        magnifier.tintColor = Theme.secondaryText
        magnifier.contentMode = .center
        let leftInset = UIView(frame: CGRect(x: 0, y: 0, width: 46, height: 18))
        magnifier.frame = CGRect(x: 14, y: 0, width: 18, height: 18)
        leftInset.addSubview(magnifier)
        searchField.leftView = leftInset
        searchField.leftViewMode = .always
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

    /// The addon is a URL the user owns; the row shows the host once set, and an
    /// empty answer clears it so the app goes back to the standard catalogue.
    private func addonPrompt(item: SettingItem) {
        let current = SettingsStore.shared.string(AddonService.urlKey, "")
        let alert = UIAlertController(title: item.title,
                                      message: "The addon's address, for example http://192.168.1.20:8765. Leave it empty to turn the addon off.",
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "http://host:port"
            field.text = current
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.keyboardType = .URL
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let text = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            SettingsStore.shared.set(text, for: AddonService.urlKey)
            self?.tableView.reloadData()
        })
        present(alert, animated: true, completion: nil)
    }

    /// Clears one of the two caches and says what it freed, in upstream's own
    /// words ("Song cache cleared" / "Image cache cleared").
    private func clearCache(_ which: String) {
        let freed = which == "song"
            ? CacheStore.shared.clearSongCache()
            : CacheStore.shared.clearImageCache()
        tableView.reloadData()
        let size = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
        let alert = UIAlertController(title: which == "song" ? "Song cache cleared" : "Image cache cleared",
                                      message: "Freed \(size).",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true, completion: nil)
    }

    private func choose(item: SettingItem, options: [String]) {
        let sheet = UIAlertController(title: item.title, message: nil, preferredStyle: .actionSheet)
        for option in options {
            sheet.addAction(UIAlertAction(title: option, style: .default) { _ in
                SettingsStore.shared.set(option, for: item.key)
                // The cache bound is applied the moment it changes, not at the
                // next launch, so the size shown is the one just chosen.
                if item.key == CacheStore.limitKey {
                    CacheStore.shared.configure()
                }
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

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // A nil header still reserves sectionHeaderHeight, so the unlabelled
        // opening card would float below a 34pt gap without this.
        return sections[section].title.isEmpty ? 0.5 : 34
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // The opening card has no label; the real page starts straight at it.
        let title = sections[section].title
        guard !title.isEmpty else { return nil }
        let holder = UIView()
        holder.backgroundColor = Theme.background
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: title.uppercased(),
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
            cell.install(toggle)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section].items[indexPath.row]
        if case .storage = item.kind {
            let downloads = DownloadsViewController()
            downloads.modalPresentationStyle = .fullScreen
            present(downloads, animated: true, completion: nil)
        }
        if case .addon = item.kind {
            addonPrompt(item: item)
        }
        if case .cache(let which) = item.kind {
            clearCache(which)
        }
        if case .onboarding = item.kind {
            showOnboarding()
        }
        if case .sources = item.kind {
            navigationController?.pushViewController(SourcesViewController(), animated: true)
        }
        if case .page(let explanation) = item.kind {
            let alert = UIAlertController(title: item.title, message: explanation, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
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
    private let valueLabel = UILabel()
    private let separator = UIView()
    private var titleTop: NSLayoutConstraint!
    private var titleCentered: NSLayoutConstraint!
    private let chevron = UIImageView(image: Icons.image(.chevronRight, size: 15))
    private let cardView = UIView()
    private let iconView = UIImageView()
    private let badgeLabel = SettingsBadgeLabel()
    private var titleLeadingPlain: NSLayoutConstraint!
    private var titleLeadingIcon: NSLayoutConstraint!

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
        detailLabel.numberOfLines = 1
        // The real subtitles are set to fit the row rather than truncate, and
        // the icon inset costs just enough width to clip them otherwise.
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.8
        cardView.addSubview(detailLabel)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = Theme.primaryText
        iconView.isHidden = true
        cardView.addSubview(iconView)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = Theme.font(10, weight: .semibold)
        badgeLabel.textColor = Theme.primaryText
        badgeLabel.backgroundColor = UIColor(white: 1, alpha: 0.16)
        badgeLabel.layer.cornerRadius = 4
        badgeLabel.layer.masksToBounds = true
        badgeLabel.isHidden = true
        cardView.addSubview(badgeLabel)

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = Theme.font(14)
        valueLabel.textColor = Theme.secondaryText
        valueLabel.textAlignment = .right
        valueLabel.isHidden = true
        cardView.addSubview(valueLabel)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = Theme.secondaryText
        chevron.contentMode = .scaleAspectFit
        cardView.addSubview(chevron)

        titleTop = titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14)
        titleCentered = titleLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
        titleLeadingPlain = titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20)
        titleLeadingIcon = titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12)
        titleTop.isActive = true
        titleLeadingPlain.isActive = true
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            iconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            iconView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            badgeLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            badgeLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            badgeLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),

            valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            chevron.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 9),
            chevron.heightAnchor.constraint(equalToConstant: 15)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// Puts a control inside the card, at the trailing edge, where the real
    /// rows keep their switches.
    func install(_ control: UIView) {
        control.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(control)
        NSLayoutConstraint.activate([
            control.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
        ])
    }

    func configure(item: SettingItem, card: UIColor, first: Bool, last: Bool) {
        if separator.superview == nil {
            // The real cards are one surface split by hairlines, not a slab.
            separator.backgroundColor = UIColor.white.withAlphaComponent(0.09)
            separator.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview(separator)
            NSLayoutConstraint.activate([
                separator.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
                separator.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
                separator.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
                separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
            ])
        }
        separator.isHidden = last
        titleLabel.text = item.title
        detailLabel.text = item.detail
        if let icon = item.icon {
            iconView.image = Icons.image(icon, size: 22)
            iconView.isHidden = false
            titleLeadingPlain.isActive = false
            titleLeadingIcon.isActive = true
        } else {
            iconView.isHidden = true
            titleLeadingIcon.isActive = false
            titleLeadingPlain.isActive = true
        }
        if let badge = item.badge {
            badgeLabel.text = "  \(badge)  "
            badgeLabel.isHidden = false
        } else {
            badgeLabel.isHidden = true
        }
        var showsChevron = false
        var trailingValue = false
        var available = true
        switch item.kind {
        case .choice(let fallback, _):
            valueLabel.text = SettingsStore.shared.string(item.key, fallback)
            showsChevron = true
            trailingValue = true
        case .stepper(let fallback, _, _, _, let unit):
            let value = SettingsStore.shared.double(item.key, fallback)
            valueLabel.text = unit == "\u{00D7}"
                ? String(format: "%.2g%@", value, unit)
                : "\(Int(value))\(unit)"
            showsChevron = true
            trailingValue = true
        case .storage:
            detailLabel.text = DownloadStore.shared.storageText()
            showsChevron = true
        case .addon:
            detailLabel.text = AddonService.shared.displayName ?? "Not configured"
            showsChevron = true
        case .cache:
            let size = ByteCountFormatter.string(fromByteCount: CacheStore.shared.sizeBytes, countStyle: .file)
            detailLabel.text = "\(size) cached"
            showsChevron = true
        case .unavailable:
            // The real app greys the row out; a subtitle, where it has one,
            // explains why the row is inert rather than hiding the reason.
            available = false
        case .page, .onboarding, .sources:
            showsChevron = true
        case .toggle:
            showsChevron = false
        }
        valueLabel.isHidden = !trailingValue
        if trailingValue { detailLabel.text = nil }
        titleTop.isActive = !trailingValue
        titleCentered.isActive = trailingValue
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

/// A capsule label with padding, for the real "IN USE" marker.
final class SettingsBadgeLabel: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}
