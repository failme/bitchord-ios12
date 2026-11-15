import Foundation
import Security

/// Minimal keychain wrapper: WebDAV passwords do not belong in UserDefaults.
enum Keychain {
    private static let service = "com.bitchord.ios12v2.webdav"

    /// The last Security result, exposed so the handoff harness can say whether
    /// an unsigned simulator actually accepted the session item.
    private(set) static var lastStatus: OSStatus = errSecSuccess

    @discardableResult
    static func set(_ value: String, for account: String) -> OSStatus {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        lastStatus = status
        return status
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        lastStatus = status
        guard status == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        lastStatus = SecItemDelete(query as CFDictionary)
    }
}

struct WebDAVServer: Codable, Equatable {
    var url: String
    var username: String
}

/// The servers the user has added, and the credentials used to stream a track
/// that came from one of them.
final class WebDAVStore {
    static let shared = WebDAVStore()
    private let key = "BitChord.WebDAV.Servers"

    private(set) var servers: [WebDAVServer] = []
    /// Passwords for this process. The keychain is the durable copy; an
    /// unsigned simulator build can be refused keychain access, and a listing
    /// must not fail because of that.
    private var sessionPasswords: [String: String] = [:]

    private init() {
        if let data = SettingsStore.shared.data(key),
           let decoded = try? JSONDecoder().decode([WebDAVServer].self, from: data) {
            servers = decoded
        }
    }

    func add(url: String, username: String, password: String) {
        let server = WebDAVServer(url: url, username: username)
        if let index = servers.firstIndex(where: { $0.url == url }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        if let data = try? JSONEncoder().encode(servers) {
            SettingsStore.shared.set(data, for: key)
        }
        sessionPasswords[account(server)] = password
        Keychain.set(password, for: account(server))
    }

    func remove(_ server: WebDAVServer) {
        servers.removeAll { $0 == server }
        if let data = try? JSONEncoder().encode(servers) {
            SettingsStore.shared.set(data, for: key)
        }
        sessionPasswords.removeValue(forKey: account(server))
        Keychain.delete(account(server))
    }

    func password(for server: WebDAVServer) -> String {
        if let cached = sessionPasswords[account(server)] { return cached }
        let stored = Keychain.get(account(server)) ?? ""
        sessionPasswords[account(server)] = stored
        return stored
    }

    /// The most specific server whose URL is a prefix of the track's URL.
    func credentials(for url: URL) -> (String, String)? {
        let absolute = url.absoluteString
        let match = servers
            .filter { absolute.hasPrefix($0.url) }
            .sorted { $0.url.count > $1.url.count }
            .first
        guard let server = match else { return nil }
        return (server.username, password(for: server))
    }

    private func account(_ server: WebDAVServer) -> String {
        return "\(server.url)|\(server.username)"
    }
}
