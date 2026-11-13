import Foundation

/// One row from a Jellyfin library or folder.
struct JellyfinItem {
    let id: String
    let name: String
    let isFolder: Bool
    let type: String
    let album: String
    let artists: String
    let runTimeTicks: Int64?

    var durationSeconds: Double? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        return Double(ticks) / 10_000_000
    }

    var isAudio: Bool {
        return type == "Audio" || type == "AudioBook"
    }
}

struct JellyfinSession {
    let base: URL
    let userID: String
    let token: String
    let userName: String
}

enum JellyfinError: Error {
    case auth
    case expired
    case unreachable(String)
    case http(Int)
    case malformed

    var message: String {
        switch self {
        case .auth: return "Wrong username or password."
        case .expired: return "Your Jellyfin session expired. Sign in again."
        case .unreachable(let host): return "Couldn't reach \(host)."
        case .http(let code): return "The server answered \(code)."
        case .malformed: return "The server sent something that isn't Jellyfin."
        }
    }
}

/// Jellyfin's HTTP API: `AuthenticateByName`, the user's views, folder items
/// and the audio stream. iOS 12 has URLSession but nothing Jellyfin-specific,
/// so the request shapes and JSON walking live here.
final class JellyfinClient {
    static let shared = JellyfinClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    static let clientName = "BitChord"
    static let clientVersion = "2.0.0"

    static func authorizationHeader(deviceId: String) -> String {
        return "MediaBrowser Client=\"\(clientName)\", Device=\"iPhone\", DeviceId=\"\(deviceId)\", Version=\"\(clientVersion)\""
    }

    static func deviceId() -> String {
        let key = "BitChord.Jellyfin.DeviceId"
        if let stored = SettingsStore.shared.string(key, "") as String?, !stored.isEmpty {
            return stored
        }
        let generated = UUID().uuidString
        SettingsStore.shared.set(generated, for: key)
        return generated
    }

    func authenticate(base: URL,
                      username: String,
                      password: String,
                      completion: @escaping (Result<JellyfinSession, JellyfinError>) -> Void) {
        guard let url = JellyfinClient.url(base: base, path: "Users/AuthenticateByName") else {
            finish(.failure(.unreachable(base.host ?? base.absoluteString)), completion)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(JellyfinClient.authorizationHeader(deviceId: JellyfinClient.deviceId()),
                         forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "Username": username,
            "Pw": password
        ])

        send(request, authPath: true) { result in
            switch result {
            case .failure(let error):
                self.finish(.failure(error), completion)
            case .success(let json):
                guard let token = json["AccessToken"] as? String,
                      let user = json["User"] as? [String: Any],
                      let userID = user["Id"] as? String else {
                    self.finish(.failure(.malformed), completion)
                    return
                }
                let name = (user["Name"] as? String) ?? username
                let session = JellyfinSession(base: base, userID: userID, token: token, userName: name)
                self.finish(.success(session), completion)
            }
        }
    }

    func views(session: JellyfinSession,
               completion: @escaping (Result<[JellyfinItem], JellyfinError>) -> Void) {
        let path = "Users/\(session.userID)/Views"
        guard let url = JellyfinClient.url(base: session.base, path: path, token: session.token) else {
            finish(.failure(.malformed), completion)
            return
        }
        send(URLRequest(url: url), authPath: false) { result in
            self.mapItems(result, completion)
        }
    }

    func items(session: JellyfinSession,
               parentID: String,
               completion: @escaping (Result<[JellyfinItem], JellyfinError>) -> Void) {
        var components = URLComponents(url: session.base, resolvingAgainstBaseURL: false)
        let root = session.base.absoluteString.hasSuffix("/") ? session.base.absoluteString : session.base.absoluteString + "/"
        components = URLComponents(string: root + "Users/\(session.userID)/Items")
        components?.queryItems = [
            URLQueryItem(name: "ParentId", value: parentID),
            URLQueryItem(name: "IncludeItemTypes", value: "Folder,Audio,MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "false"),
            URLQueryItem(name: "Fields", value: "Artists,Album,RunTimeTicks"),
            URLQueryItem(name: "api_key", value: session.token)
        ]
        guard let url = components?.url else {
            finish(.failure(.malformed), completion)
            return
        }
        send(URLRequest(url: url), authPath: false) { result in
            self.mapItems(result, completion)
        }
    }

    static func streamURL(base: URL, itemID: String, token: String) -> URL? {
        let root = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        var components = URLComponents(string: root + "Audio/\(itemID)/stream")
        components?.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: token)
        ]
        return components?.url
    }

    static func url(base: URL, path: String, token: String? = nil) -> URL? {
        let root = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        guard var components = URLComponents(string: root + path) else { return nil }
        if let token = token {
            components.queryItems = [URLQueryItem(name: "api_key", value: token)]
        }
        return components.url
    }

    // MARK: - Transport

    private func send(_ request: URLRequest,
                      authPath: Bool,
                      completion: @escaping (Result<[String: Any], JellyfinError>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            let finish: (Result<[String: Any], JellyfinError>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }
            if let error = error as NSError? {
                let host = request.url?.host ?? "the server"
                finish(.failure(.unreachable("\(host) (\(error.code))")))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                finish(.failure(.malformed))
                return
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                finish(.failure(authPath ? .auth : .expired))
                return
            }
            guard http.statusCode == 200, let data = data else {
                finish(.failure(.http(http.statusCode)))
                return
            }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                finish(.failure(.malformed))
                return
            }
            finish(.success(json))
        }.resume()
    }

    private func mapItems(_ result: Result<[String: Any], JellyfinError>,
                          _ completion: @escaping (Result<[JellyfinItem], JellyfinError>) -> Void) {
        switch result {
        case .failure(let error):
            finish(.failure(error), completion)
        case .success(let json):
            guard let raw = json["Items"] as? [[String: Any]] else {
                finish(.failure(.malformed), completion)
                return
            }
            let items = raw.compactMap { JellyfinClient.item(from: $0) }
            finish(.success(items), completion)
        }
    }

    static func item(from json: [String: Any]) -> JellyfinItem? {
        guard let id = json["Id"] as? String, let name = json["Name"] as? String else { return nil }
        let type = (json["Type"] as? String) ?? ""
        let folder = (json["IsFolder"] as? Bool) ?? (type == "Folder" || type == "CollectionFolder" || type == "MusicAlbum")
        let artists = (json["Artists"] as? [String])?.joined(separator: ", ") ?? ""
        return JellyfinItem(id: id,
                            name: name,
                            isFolder: folder,
                            type: type,
                            album: (json["Album"] as? String) ?? "",
                            artists: artists,
                            runTimeTicks: (json["RunTimeTicks"] as? NSNumber)?.int64Value)
    }

    private func finish<T>(_ result: Result<T, JellyfinError>,
                           _ completion: @escaping (Result<T, JellyfinError>) -> Void) {
        DispatchQueue.main.async { completion(result) }
    }
}
