import UIKit
import Security

extension Notification.Name {
    static let googleAccountDidChange = Notification.Name("BitChordGoogleAccountDidChange")
}

/// What the in-app Google login captured from YouTube Music's own page.
struct CapturedGoogleSession {
    let cookie: String
    let authUser: String
    let dataSyncId: String?
    let pageId: String?
    let visitorData: String?
    let clientVersion: String?
}

/// The Google account this device is signed in with.
///
/// This is the same session model the Android app uses: the password is typed
/// into Google's own page in a web view, and what the app keeps is the signed
/// YouTube cookie. Nothing here invents an OAuth client or asks the listener
/// for a client secret, which is why it works on an unsigned iOS 12 build.
final class GoogleAccountStore {
    static let shared = GoogleAccountStore()

    private struct Session: Codable {
        var cookie: String
        var authUser: String
        var dataSyncId: String?
        var pageId: String?
        var visitorData: String?
        var clientVersion: String?
        var name: String
        var email: String
        var avatar: String?
    }

    private let keychainKey = "google.session.v1"
    private let simulatorFallbackKey = "BitChord.Google.Session.SimulatorFallback"
    private var session: Session? = nil
    /// An unsigned simulator build has no keychain entitlement, so `SecItemAdd`
    /// can refuse the item. The fallback is simulator-only; a signed device
    /// still has exactly one secure store.
    private(set) var usesSimulatorFallback = false

    private init() {
        var stored = Keychain.get(keychainKey)
        #if targetEnvironment(simulator)
        if stored == nil {
            stored = UserDefaults.standard.string(forKey: simulatorFallbackKey)
            usesSimulatorFallback = stored != nil
        }
        #endif
        if let data = stored?.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Session.self, from: data) {
            session = decoded
        }
    }

    var isSignedIn: Bool {
        guard let cookie = session?.cookie else { return false }
        return GoogleAccountStore.apiSID(in: cookie) != nil
    }

    var displayName: String {
        let name = session?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Google Account" : name
    }

    var email: String { return session?.email ?? "" }

    var avatarURL: URL? {
        guard var raw = session?.avatar, !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") { raw = "https:" + raw }
        return URL(string: raw)
    }

    var authUser: String { return session?.authUser ?? "0" }

    /// The account identity YouTube Music's shell reported. The API needs it
    /// as `context.user.onBehalfOfUser`; without it a request is answered for
    /// whichever Google account owns the first cookie rather than this one.
    var dataSyncId: String? {
        return GoogleAccountStore.normalizeDataSyncID(session?.dataSyncId)
    }

    var pageId: String? {
        guard let value = session?.pageId, !value.isEmpty else { return nil }
        return value
    }

    /// Switches the active library to one of the login's other accounts or
    /// brand channels. The cookie stays the same; only the identity sent with
    /// each later request changes.
    func selectChannel(_ channel: YouTubeChannel) {
        guard var current = session else { return }
        current.pageId = channel.pageId
        current.dataSyncId = channel.dataSyncId
        current.name = channel.name
        if !channel.subtitle.isEmpty { current.email = channel.subtitle }
        if let avatar = channel.avatarURL?.absoluteString { current.avatar = avatar }
        session = current
        persist()
        NotificationCenter.default.post(name: .googleAccountDidChange, object: nil)
        refreshProfile()
    }

    func fetchChannels(completion: @escaping ([YouTubeChannel], String?) -> Void) {
        InnerTube.shared.fetchAccountChannels(completion: completion)
    }

    /// `datasyncIdToken` is sometimes `page||account`; the account half is the
    /// value `onBehalfOfUser` expects.
    static func normalizeDataSyncID(_ raw: String?) -> String? {
        guard let value = raw, !value.isEmpty else { return nil }
        guard value.contains("||") else { return value }
        let after = value.components(separatedBy: "||").last ?? ""
        if !after.isEmpty { return after }
        let before = value.components(separatedBy: "||").first ?? ""
        return before.isEmpty ? nil : before
    }

    /// The cookies are stored as one header, exactly as the page's jar presents
    /// them. The API SID is the signing secret; without it YouTube answers as a
    /// stranger even though the request carries a cookie.
    static func apiSID(in cookie: String) -> String? {
        let names: Set<String> = ["SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID"]
        for entry in cookie.split(separator: ";") {
            let pieces = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { continue }
            let name = pieces[0].trimmingCharacters(in: .whitespaces)
            let value = pieces[1].trimmingCharacters(in: .whitespaces)
            if names.contains(name) && !value.isEmpty { return value }
        }
        return nil
    }

    /// Signs in without asking the listener for anything but Google's page.
    func adopt(_ captured: CapturedGoogleSession) {
        var next = Session(cookie: captured.cookie,
                           authUser: captured.authUser,
                           dataSyncId: captured.dataSyncId,
                           pageId: captured.pageId,
                           visitorData: captured.visitorData,
                           clientVersion: captured.clientVersion,
                           name: "Google Account",
                           email: "",
                           avatar: nil)
        if let old = session, old.cookie == captured.cookie {
            next.name = old.name
            next.email = old.email
            next.avatar = old.avatar
        }
        session = next
        persist()
        NotificationCenter.default.post(name: .googleAccountDidChange, object: nil)
        refreshProfile()
    }

    func signOut(completion: (() -> Void)? = nil) {
        session = nil
        Keychain.delete(keychainKey)
        UserDefaults.standard.removeObject(forKey: simulatorFallbackKey)
        UserDefaults.standard.synchronize()
        usesSimulatorFallback = false
        NotificationCenter.default.post(name: .googleAccountDidChange, object: nil)
        GoogleSignInViewController.clearBrowserSession(completion: completion)
    }

    /// Headers the signed-in InnerTube routes need. The origin is part of the
    /// hash, so it must be the same origin the request is sent to.
    func requestHeaders(origin: String = "https://music.youtube.com") -> [String: String] {
        guard let session = session,
              let sid = GoogleAccountStore.apiSID(in: session.cookie) else { return [:] }
        let timestamp = Int(Date().timeIntervalSince1970)
        let digest = GoogleAccountStore.sha1Hex("\(timestamp) \(sid) \(origin)")
        var headers = [
            "Cookie": session.cookie,
            "Authorization": "SAPISIDHASH \(timestamp)_\(digest)",
            "X-Goog-AuthUser": session.authUser,
            "X-Origin": origin,
            "Referer": origin + "/"
        ]
        if let page = session.pageId, !page.isEmpty {
            headers["X-Goog-PageId"] = page
        }
        return headers
    }

    /// Reads the display name and avatar from the live account rather than
    /// guessing them from the cookie. A failed read leaves the captured
    /// session intact; the account is still usable and the next launch retries.
    func refreshProfile() {
        guard isSignedIn, GoogleHandoffFixture.active == nil else { return }
        InnerTube.shared.accountMenu { [weak self] json in
            guard let self = self, let json = json,
                  let header = GoogleAccountStore.firstDictionary(named: "activeAccountHeaderRenderer",
                                                                  in: json) else { return }
            let name = GoogleAccountStore.text(header["accountName"])
            let email = GoogleAccountStore.text(header["email"])
            let avatar = GoogleAccountStore.bestThumbnail(header["accountPhoto"])
            guard let current = self.session else { return }
            var next = current
            if !name.isEmpty { next.name = name }
            if !email.isEmpty { next.email = email }
            if let avatar = avatar { next.avatar = avatar }
            self.session = next
            self.persist()
            NotificationCenter.default.post(name: .googleAccountDidChange, object: nil)
        }
    }

    /// Paints the account avatar onto any of the app's round header buttons.
    /// Signed out, the same button gets the outline person it always had.
    func updateAvatarButton(_ button: UIButton, size: CGFloat, background: UIColor = Theme.surfaceVariant) {
        button.layer.cornerRadius = size / 2
        button.clipsToBounds = true
        button.backgroundColor = background
        button.setImage(nil, for: .normal)
        button.setBackgroundImage(nil, for: .normal)
        guard isSignedIn, let url = avatarURL else {
            button.setImage(Icons.image(.personOutline, size: size * 0.48), for: .normal)
            return
        }
        if let cached = ArtworkLoader.shared.cached(url) {
            button.setBackgroundImage(cached, for: .normal)
            return
        }
        button.setImage(Icons.image(.personOutline, size: size * 0.48), for: .normal)
        ArtworkLoader.shared.load(url) { [weak self, weak button] image in
            guard let self = self, let button = button, self.isSignedIn, let image = image else { return }
            button.setImage(nil, for: .normal)
            button.setBackgroundImage(image, for: .normal)
        }
    }

    func presentSignIn(from host: UIViewController) {
        let signIn = GoogleSignInViewController()
        let navigation = UINavigationController(rootViewController: signIn)
        navigation.modalPresentationStyle = .fullScreen
        navigation.navigationBar.barTintColor = Theme.background
        navigation.navigationBar.tintColor = Theme.accent
        navigation.navigationBar.isTranslucent = false
        navigation.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        host.present(navigation, animated: true, completion: nil)
    }

    private func persist() {
        guard let session = session,
              let data = try? JSONEncoder().encode(session),
              let text = String(data: data, encoding: .utf8) else { return }
        let status = Keychain.set(text, for: keychainKey)
        #if targetEnvironment(simulator)
        if status == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: simulatorFallbackKey)
            usesSimulatorFallback = false
        } else {
            UserDefaults.standard.set(text, forKey: simulatorFallbackKey)
            usesSimulatorFallback = true
            // The harness exits immediately after adopting a session; make the
            // fallback durable before that process ends.
            UserDefaults.standard.synchronize()
        }
        #endif
    }

    // MARK: - SHA-1

    /// SAPISIDHASH signs a timestamp, the secret cookie and the origin with
    /// SHA-1. CommonCrypto's Swift import is not available to this target, so
    /// the 80-round primitive is kept here rather than adding a dependency.
    static func sha1Hex(_ input: String) -> String {
        var message = Array(input.utf8)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        for chunk in stride(from: 0, to: message.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 80)
            for index in 0..<16 {
                let base = chunk + index * 4
                words[index] = (UInt32(message[base]) << 24)
                    | (UInt32(message[base + 1]) << 16)
                    | (UInt32(message[base + 2]) << 8)
                    | UInt32(message[base + 3])
            }
            for index in 16..<80 {
                words[index] = GoogleAccountStore.rotateLeft(words[index - 3] ^ words[index - 8]
                                                             ^ words[index - 14] ^ words[index - 16], by: 1)
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4
            for index in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch index {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let temp = GoogleAccountStore.rotateLeft(a, by: 5) &+ f &+ e &+ k &+ words[index]
                e = d
                d = c
                c = GoogleAccountStore.rotateLeft(b, by: 30)
                b = a
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }
        return [h0, h1, h2, h3, h4].map { String(format: "%08x", $0) }.joined()
    }

    private static func rotateLeft(_ value: UInt32, by amount: UInt32) -> UInt32 {
        return (value << amount) | (value >> (32 - amount))
    }

    // MARK: - Tiny JSON helpers

    static func firstDictionary(named name: String, in node: Any) -> [String: Any]? {
        if let dictionary = node as? [String: Any] {
            if let match = dictionary[name] as? [String: Any] { return match }
            for (_, child) in dictionary {
                if let found = firstDictionary(named: name, in: child) { return found }
            }
        } else if let array = node as? [Any] {
            for child in array {
                if let found = firstDictionary(named: name, in: child) { return found }
            }
        }
        return nil
    }

    static func text(_ node: Any?) -> String {
        guard let dictionary = node as? [String: Any] else { return "" }
        if let simple = dictionary["simpleText"] as? String { return simple }
        if let runs = dictionary["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    static func bestThumbnail(_ node: Any?) -> String? {
        guard let dictionary = node as? [String: Any],
              let thumbnails = dictionary["thumbnails"] as? [[String: Any]] else { return nil }
        return thumbnails.compactMap { $0["url"] as? String }.last
    }
}
