import Foundation

/// One row of a WebDAV collection.
struct WebDAVEntry {
    let name: String
    let url: URL
    let isDirectory: Bool
    let size: Int64?

    var isAudio: Bool {
        let extensionName = url.pathExtension.lowercased()
        return ["mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "alac", "ogg", "opus"].contains(extensionName)
    }
}

enum WebDAVError: Error {
    case auth
    case unreachable(String)
    case http(Int)
    case malformed

    var message: String {
        switch self {
        case .auth: return "Wrong username or password."
        case .unreachable(let host): return "Couldn't reach \(host)."
        case .http(let code): return "The server answered \(code)."
        case .malformed: return "The server sent something that isn't WebDAV."
        }
    }
}

/// PROPFIND + GET against a WebDAV server. iOS 12 has URLSession and `XMLParser`
/// but no `URLSession` WebDAV API, so the request and the `multistatus` parse
/// are both written here.
final class WebDAVClient {
    static let shared = WebDAVClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    func list(_ url: URL,
              username: String,
              password: String,
              completion: @escaping (Result<[WebDAVEntry], WebDAVError>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.setValue(WebDAVClient.basic(username: username, password: password),
                         forHTTPHeaderField: "Authorization")
        request.httpBody = WebDAVClient.propfindBody.data(using: .utf8)

        session.dataTask(with: request) { data, response, error in
            let finish: (Result<[WebDAVEntry], WebDAVError>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }
            if let error = error as NSError? {
                finish(.failure(.unreachable(url.host ?? url.absoluteString + " (\(error.code))")))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                finish(.failure(.malformed))
                return
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                finish(.failure(.auth))
                return
            }
            guard http.statusCode == 207 || http.statusCode == 200, let data = data else {
                finish(.failure(.http(http.statusCode)))
                return
            }
            let parsed = WebDAVMultistatusParser(base: url).parse(data)
            guard !parsed.isEmpty else {
                finish(.failure(.malformed))
                return
            }
            finish(.success(WebDAVClient.sorted(parsed, base: url)))
        }.resume()
    }

    static func basic(username: String, password: String) -> String {
        let token = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""
        return "Basic \(token)"
    }

    private static let propfindBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <D:propfind xmlns:D="DAV:">
      <D:prop>
        <D:resourcetype/>
        <D:getcontentlength/>
        <D:getcontenttype/>
        <D:displayname/>
      </D:prop>
    </D:propfind>
    """

    private static func sorted(_ entries: [WebDAVEntry], base: URL) -> [WebDAVEntry] {
        let selfPath = base.path
        return entries
            .filter { $0.url.path != selfPath && $0.url.path != selfPath + "/" }
            .sorted { left, right in
                if left.isDirectory != right.isDirectory { return left.isDirectory }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }
}

/// Parses the `D:multistatus` document the PROPFIND answers with.
final class WebDAVMultistatusParser: NSObject, XMLParserDelegate {
    private let base: URL
    private var entries: [WebDAVEntry] = []
    private var currentHref: String?
    private var currentIsCollection = false
    private var currentLength: Int64?
    private var currentText = ""
    private var depth = 0

    init(base: URL) {
        self.base = base
        super.init()
    }

    func parse(_ data: Data) -> [WebDAVEntry] {
        entries = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        if name == "response" {
            currentHref = nil
            currentIsCollection = false
            currentLength = nil
        }
        if name == "collection" {
            currentIsCollection = true
        }
        currentText = ""
        depth += 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "href" {
            currentHref = text
        } else if name == "getcontentlength" {
            currentLength = Int64(text)
        } else if name == "response" {
            appendEntry()
        }
        currentText = ""
        depth = max(0, depth - 1)
    }

    private func appendEntry() {
        guard let href = currentHref, !href.isEmpty,
              let url = WebDAVMultistatusParser.resolve(href, against: base) else { return }
        let name = (url.path as NSString).lastPathComponent.removingPercentEncoding
            ?? url.lastPathComponent
        guard !name.isEmpty else { return }
        entries.append(WebDAVEntry(name: name,
                                   url: url,
                                   isDirectory: currentIsCollection,
                                   size: currentLength))
    }

    static func resolve(_ href: String, against base: URL) -> URL? {
        if let url = URL(string: href), url.scheme != nil {
            return url
        }
        guard let host = base.host else { return nil }
        let scheme = base.scheme ?? "http"
        let port = base.port.map { ":\($0)" } ?? ""
        let encoded = href.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? href
        return URL(string: "\(scheme)://\(host)\(port)\(encoded)")
    }
}
