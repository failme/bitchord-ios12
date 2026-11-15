import UIKit

/// The "Show cache folder" destination. iOS keeps Caches outside the Files
/// browser, so the screen lists what is there and lets the listener share or
/// clear it instead of pretending a Finder-style folder exists.
final class CacheFolderViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private var rows: [(name: String, size: Int64, url: URL)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cache folder"
        view.backgroundColor = Theme.background
        table.backgroundColor = .clear
        table.separatorColor = Theme.surface
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cache")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        reload()
    }

    private func reload() {
        rows = []
        let manager = FileManager.default
        var roots: [URL] = []
        if let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            roots.append(caches)
        }
        roots.append(DownloadStore.shared.directoryURL)
        for root in roots {
            let files = (try? manager.contentsOfDirectory(at: root,
                                                          includingPropertiesForKeys: [.fileSizeKey],
                                                          options: [.skipsHiddenFiles])) ?? []
            for file in files {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                rows.append((file.lastPathComponent, Int64(size), file))
            }
        }
        rows.sort { $0.size > $1.size }
        table.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(rows.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cache", for: indexPath)
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = Theme.primaryText
        cell.detailTextLabel?.textColor = Theme.secondaryText
        if rows.isEmpty {
            cell.textLabel?.text = "The cache is empty."
        } else {
            let row = rows[indexPath.row]
            let size = ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file)
            cell.textLabel?.text = "\(row.name) · \(size)"
        }
        return cell
    }
}
