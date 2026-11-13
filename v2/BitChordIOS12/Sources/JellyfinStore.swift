import Foundation

/// The Jellyfin server this install is signed in to. The token is a credential:
/// Keychain is the durable copy, with the same in-process fallback WebDAV uses
/// because an unsigned simulator build can be refused keychain access.
final class JellyfinStore {
    static let shared = JellyfinStore()
    private let key = "BitChord.Jellyfin.Server"
    private let tokenAccount = "jellyfin-token"

    private(set) var server: JellyfinServer?
    private var sessionToken: String?

    struct JellyfinServer: Codable, Equatable {
        var url: String
        var username: String
        var userID: String
        var userName: String
    }

    private init() {
        if let data = SettingsStore.shared.data(key),
           let decoded = try? JSONDecoder().decode(JellyfinServer.self, from: data) {
            server = decoded
        }
    }

    func save(url: String, username: String, userID: String, userName: String, token: String) {
        let record = JellyfinServer(url: url, username: username, userID: userID, userName: userName)
        server = record
        if let data = try? JSONEncoder().encode(record) {
            SettingsStore.shared.set(data, for: key)
        }
        sessionToken = token
        Keychain.set(token, for: tokenAccount)
    }

    func token() -> String {
        if let cached = sessionToken { return cached }
        let stored = Keychain.get(tokenAccount) ?? ""
        sessionToken = stored
        return stored
    }

    func session() -> JellyfinSession? {
        guard let server = server, let base = URL(string: server.url), !token().isEmpty else { return nil }
        return JellyfinSession(base: base,
                               userID: server.userID,
                               token: token(),
                               userName: server.userName)
    }

    func clear() {
        server = nil
        sessionToken = nil
        SettingsStore.shared.set(Data(), for: key)
        Keychain.delete(tokenAccount)
    }
}
