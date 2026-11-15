import Foundation

/// Port of upstream's data export/import: one JSON file carrying the
/// listener's library, playlists, history and preferences.
///
/// Credentials are deliberately excluded. A backup is a portable copy of what
/// the listener made, not a copy of their Google, Last.fm or Spotify secrets.
final class BackupService {
    static let shared = BackupService()

    private let prefix = "BitChord."
    private let secretFragments = ["secret", "token", "password", "cookie", "sessionkey",
                                   "apikey", "accesstoken", "cookiespdc"]

    struct Result {
        let ok: Bool
        let message: String
    }

    func makeBackup() -> (data: Data, name: String)? {
        var stored: [String: Any] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            guard key.hasPrefix(prefix), !isSecret(key) else { continue }
            if value is String || value is NSNumber || value is Data {
                stored[key] = value
            }
        }
        let payload: [String: Any] = [
            "format": "bitchord-backup",
            "version": 1,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "values": stored
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return (data, "BitChord-Backup-\(formatter.string(from: Date())).json")
    }

    func restore(from url: URL) -> Result {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              root["format"] as? String == "bitchord-backup",
              let values = root["values"] as? [String: Any] else {
            return Result(ok: false, message: "That is not a BitChord backup.")
        }
        var imported = 0
        for (key, value) in values {
            guard key.hasPrefix(prefix), !isSecret(key) else { continue }
            if let text = value as? String {
                UserDefaults.standard.set(text, forKey: key)
                imported += 1
            } else if let number = value as? NSNumber {
                UserDefaults.standard.set(number, forKey: key)
                imported += 1
            } else if let data = value as? Data {
                UserDefaults.standard.set(data, forKey: key)
                imported += 1
            }
        }
        UserDefaults.standard.synchronize()
        LibraryStore.shared.reloadFromDisk()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        return Result(ok: imported > 0,
                      message: imported == 0 ? "The backup contained no restorable values."
                                             : "Restored \(imported) settings and library records.")
    }

    private func isSecret(_ key: String) -> Bool {
        let lower = key.lowercased()
        return secretFragments.contains(where: { lower.contains($0) })
    }
}
