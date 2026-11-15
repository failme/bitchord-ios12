import UIKit
import WebKit

/// Google's own sign-in page inside the app.
///
/// This is deliberately not an OAuth SDK: the listener authenticates directly
/// with Google (password, 2FA and account picker all live on Google's page),
/// and the app takes the resulting YouTube session cookie. It is the same
/// approach the Android app uses, and it needs no client id or secret.
///
/// Google's final redirect lands on YouTube Music. On iOS the music shell can
/// paint a blank page while its JavaScript boots, so reaching that page is no
/// longer a reason to wait for a manual confirmation. The cookie jar is polled
/// as the redirect runs, the page's `ytcfg` is read when it exists, and a
/// network read of `music.youtube.com` supplies the same identity when the
/// shell is blank. Only then does the sheet close.
final class GoogleSignInViewController: UIViewController {
    private struct PageIdentity {
        let loggedIn: Bool
        let authUser: String?
        let dataSyncId: String?
        let pageId: String?
        let visitorData: String?
        let clientVersion: String?
    }

    private let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .white)
    private var doneButton: UIBarButtonItem!
    private var progressObservation: NSKeyValueObservation?
    private var youtubeStage = false
    private var autoCaptureExhausted = false
    private var completed = false
    private var captureInFlight = false
    private var fixtureShellLoaded = false
    private var autoCapture: DispatchWorkItem?

    private static let loginURL = URL(string:
        "https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&prompt=select_account"
        + "&continue=https%3A%2F%2Fmusic.youtube.com%2F")!
    private static let musicOrigin = "https://music.youtube.com"
    private static let musicURL = URL(string: "https://music.youtube.com/")!

    private static var safariUserAgent: String {
        let version = UIDevice.current.systemVersion
        let major = version.split(separator: ".").first.map(String.init) ?? "12"
        let os = version.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(os) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major).0 Mobile/15E148 Safari/604.1"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Google"

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel",
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(cancel))
        doneButton = UIBarButtonItem(title: "Done", style: .done,
                                     target: self, action: #selector(done))
        doneButton.isEnabled = false
        navigationItem.rightBarButtonItem = doneButton

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.trackTintColor = Theme.surfaceVariant
        progress.progressTintColor = Theme.accent
        view.addSubview(progress)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = Theme.font(13)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.numberOfLines = 2
        statusLabel.text = "Sign in with your Google Account. Your password stays with Google."
        view.addSubview(statusLabel)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.startAnimating()
        view.addSubview(spinner)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = Theme.background
        webView.isOpaque = true
        // Google refuses a user agent that identifies an embedded browser. A
        // Safari string is what makes the real page load; the OS and Safari
        // versions are the ones this device actually has, so Google does not
        // serve JavaScript newer than this WebKit can run.
        webView.customUserAgent = GoogleSignInViewController.safariUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2),

            statusLabel.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: spinner.leadingAnchor, constant: -8),

            spinner.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            self?.progress.progress = Float(webView.estimatedProgress)
        }

        // A login can finish with a cookie write but no usable final page. The
        // observer is what makes the sheet react to the session rather than to
        // a white view that happens to have finished loading.
        WKWebsiteDataStore.default().httpCookieStore.add(self)

        // The deterministic handoff uses the same web view, cookie store and
        // controller. Only the pages Google would serve are local documents.
        if let fixture = GoogleHandoffFixture.active {
            loadFixture(fixture)
            return
        }

        // Start with a clean Google jar. Otherwise an account signed out of the
        // app is immediately recognised by accounts.google.com, and the screen
        // cannot be used to choose a different one.
        GoogleSignInViewController.clearBrowserSession {
            self.loadLogin()
        }
    }

    deinit {
        progressObservation?.invalidate()
        autoCapture?.cancel()
        WKWebsiteDataStore.default().httpCookieStore.remove(self)
    }

    private func loadLogin() {
        var request = URLRequest(url: GoogleSignInViewController.loginURL)
        request.timeoutInterval = 30
        webView.load(request)
    }

    private func loadFixture(_ fixture: GoogleHandoffFixture) {
        GoogleHandoffFixture.probe = GoogleHandoffFixture.Probe()
        GoogleHandoffFixture.probe.loginOrigin = fixture.loginBaseURL.absoluteString
        fixture.seedCookies { [weak self] in
            self?.webView.loadHTMLString(fixture.loginHTML, baseURL: fixture.loginBaseURL)
        }
    }

    private func loadFixtureShell(_ fixture: GoogleHandoffFixture) {
        guard !fixtureShellLoaded else { return }
        fixtureShellLoaded = true
        GoogleHandoffFixture.probe.shellOrigin = fixture.musicBaseURL.absoluteString
        GoogleHandoffFixture.probe.documentBlank = fixture.shell == .blank
        webView.loadHTMLString(fixture.shellHTML, baseURL: fixture.musicBaseURL)
    }

    /// Reads the cookies and body from the page that actually loaded, so the
    /// test can prove the music origin saw the YouTube cookie and not the
    /// accounts.google.com one.
    private func probeFixturePage() {
        let script = """
        (function () {
          try {
            return JSON.stringify({
              origin: location.origin,
              cookie: document.cookie || "",
              blank: !(document.body && (document.body.innerText || '').trim())
            });
          } catch (e) { return ""; }
        })();
        """
        webView.evaluateJavaScript(script) { value, _ in
            guard GoogleHandoffFixture.active != nil,
                  let text = value as? String,
                  let data = text.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                return
            }
            GoogleHandoffFixture.probe.documentCookie = json["cookie"] as? String ?? ""
            GoogleHandoffFixture.probe.documentBlank = json["blank"] as? Bool ?? true
            if let origin = json["origin"] as? String,
               origin.hasPrefix("https://") {
                GoogleHandoffFixture.probe.shellOrigin = origin
            }
        }
    }

    @objc private func cancel() {
        autoCapture?.cancel()
        dismiss(animated: true, completion: nil)
    }

    @objc private func done() {
        beginCapture(manual: true)
    }

    /// Starts the capture once a session cookie is visible. Automatic attempts
    /// wait through the music shell's boot; a manual tap gets an immediate
    /// answer if the jar is still empty.
    private func beginCapture(manual: Bool) {
        guard !completed, !captureInFlight else { return }
        if manual { autoCaptureExhausted = false }
        captureInFlight = true
        doneButton.isEnabled = false
        spinner.startAnimating()
        progress.isHidden = false
        statusLabel.textColor = Theme.secondaryText
        statusLabel.text = manual ? "Reading your YouTube Music session..."
                                 : "Google sign-in complete. Finishing sign-in..."
        resolveSession(manual: manual, attempt: 0)
    }

    private func resolveSession(manual: Bool, attempt: Int) {
        guard !completed else { return }
        captureCookies { [weak self] cookies in
            guard let self = self, !self.completed else { return }
            guard let header = GoogleSignInViewController.youtubeCookieHeader(cookies),
                  GoogleAccountStore.apiSID(in: header) != nil else {
                self.retryCapture(manual: manual, attempt: attempt,
                                  message: "Google has not finished signing you in yet.")
                return
            }

            self.readPageConfig { identity in
                guard !self.completed else { return }
                if let identity = identity, identity.loggedIn {
                    self.adopt(header: header, identity: identity)
                    return
                }
                // The music shell can finish loading as a blank surface. Ask
                // the same origin for its shell directly; the cookie is already
                // in hand, so this does not depend on the web view rendering.
                self.fetchNetworkIdentity(cookie: header) { networkIdentity in
                    guard !self.completed else { return }
                    if let networkIdentity = networkIdentity {
                        self.adopt(header: header, identity: networkIdentity)
                        return
                    }
                    self.pageIsBlank { blank in
                        guard !self.completed else { return }
                        // A blank page plus a live API SID is a completed Google
                        // login whose shell did not paint. Adopt it; the profile
                        // request can still correct the display name and avatar.
                        if blank && attempt >= 2 {
                            let fallback = PageIdentity(loggedIn: true,
                                                        authUser: identity?.authUser ?? "0",
                                                        dataSyncId: identity?.dataSyncId,
                                                        pageId: identity?.pageId,
                                                        visitorData: identity?.visitorData,
                                                        clientVersion: identity?.clientVersion)
                            self.adopt(header: header, identity: fallback)
                            return
                        }
                        self.retryCapture(manual: manual, attempt: attempt,
                                          message: "YouTube Music is still loading your account.")
                    }
                }
            }
        }
    }

    private func retryCapture(manual: Bool, attempt: Int, message: String) {
        captureInFlight = false
        guard attempt < (manual ? 3 : 14) else {
            if !manual { autoCaptureExhausted = true }
            doneButton.isEnabled = true
            finishCapture(message: manual
                ? "Google did not return a usable session. Complete the page, then tap Done again."
                : "Sign-in is taking longer than expected. Tap Done when YouTube Music finishes loading.")
            return
        }
        autoCapture?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.captureInFlight = false
            self?.beginCapture(manual: manual)
        }
        autoCapture = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        if manual {
            statusLabel.text = message
        }
    }

    private func captureCookies(completion: @escaping ([HTTPCookie]) -> Void) {
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            DispatchQueue.main.async { completion(cookies) }
        }
    }

    /// The page's own ytcfg is the authoritative answer about which Google
    /// login and which channel this session is acting as.
    private func readPageConfig(completion: @escaping (PageIdentity?) -> Void) {
        let script = """
        (function () {
          try {
            if (!window.ytcfg || !window.ytcfg.get) return "";
            var get = function (key) {
              var value = window.ytcfg.get(key);
              return (value === undefined || value === null || value === '') ? null : String(value);
            };
            return JSON.stringify({
              loggedIn: String(!!window.ytcfg.get('LOGGED_IN')),
              pageId: get('DELEGATED_SESSION_ID'),
              dataSyncId: get('DATASYNC_ID'),
              authUser: get('SESSION_INDEX'),
              visitorData: get('VISITOR_DATA'),
              clientVersion: get('INNERTUBE_CLIENT_VERSION')
            });
          } catch (e) { return ""; }
        })();
        """
        webView.evaluateJavaScript(script) { value, _ in
            guard let text = value as? String,
                  let data = text.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                completion(nil)
                return
            }
            let loggedIn = (json["loggedIn"] as? String) == "true"
            if GoogleHandoffFixture.active != nil {
                GoogleHandoffFixture.probe.pageConfigRead = loggedIn
            }
            func string(_ key: String) -> String? {
                guard let value = json[key] as? String, !value.isEmpty, value != "null" else { return nil }
                return value
            }
            completion(PageIdentity(loggedIn: loggedIn,
                                    authUser: string("authUser"),
                                    dataSyncId: string("dataSyncId"),
                                    pageId: string("pageId"),
                                    visitorData: string("visitorData"),
                                    clientVersion: string("clientVersion")))
        }
    }

    private func pageIsBlank(completion: @escaping (Bool) -> Void) {
        let script = """
        (function () {
          try {
            if (!document.body) return true;
            return !(document.body.innerText || '').trim();
          } catch (e) { return true; }
        })();
        """
        webView.evaluateJavaScript(script) { value, _ in
            completion((value as? Bool) ?? false)
        }
    }

    private func adopt(header: String, identity: PageIdentity) {
        guard !completed else { return }
        completed = true
        captureInFlight = true
        autoCapture?.cancel()
        let captured = CapturedGoogleSession(cookie: header,
                                             authUser: identity.authUser ?? "0",
                                             dataSyncId: identity.dataSyncId,
                                             pageId: identity.pageId,
                                             visitorData: identity.visitorData,
                                             clientVersion: identity.clientVersion)
        GoogleAccountStore.shared.adopt(captured)
        spinner.stopAnimating()
        statusLabel.text = "Signed in. Opening BitChord..."
        dismiss(animated: true, completion: nil)
    }

    private func finishCapture(message: String) {
        captureInFlight = false
        spinner.stopAnimating()
        doneButton.isEnabled = true
        statusLabel.text = message
        statusLabel.textColor = UIColor(red: 1, green: 0.45, blue: 0.42, alpha: 1)
    }

    /// Fetches the music shell with the just-captured cookies. This is the
    /// fallback for the blank WKWebView: the same ytcfg values exist in the
    /// HTML, and the request needs no JavaScript at all.
    private func fetchNetworkIdentity(cookie: String,
                                      completion: @escaping (PageIdentity?) -> Void) {
        // The fixture's authenticated document is returned only when the
        // request carries the seeded YouTube signing cookie. That makes the
        // fallback depend on the same cookie handoff as the real request.
        if let fixture = GoogleHandoffFixture.active {
            GoogleHandoffFixture.probe.networkFallbackUsed = true
            let hadCookie = cookie.contains("SAPISID=\(GoogleHandoffFixture.cookieValue)")
            GoogleHandoffFixture.probe.networkHadCookie = hadCookie
            let identity = hadCookie
                ? GoogleSignInViewController.identity(fromHTML: fixture.networkHTML)
                : nil
            DispatchQueue.main.async { completion(identity) }
            return
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: config)
        var request = URLRequest(url: GoogleSignInViewController.musicURL,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 12)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(GoogleSignInViewController.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        session.dataTask(with: request) { data, _, _ in
            var identity: PageIdentity?
            if let data = data,
               let html = String(data: data, encoding: .utf8) {
                identity = GoogleSignInViewController.identity(fromHTML: html)
            }
            DispatchQueue.main.async { completion(identity) }
        }.resume()
    }

    private static func identity(fromHTML html: String) -> PageIdentity? {
        let loggedIn = firstMatch("\"LOGGED_IN\"\\s*:\\s*\"?(true|false)", in: html)
        guard loggedIn == "true" else { return nil }
        func field(_ name: String) -> String? {
            firstMatch("\"\(name)\"\\s*:\\s*\"([^\"]+)\"", in: html)
        }
        return PageIdentity(loggedIn: true,
                            authUser: firstMatch("\"SESSION_INDEX\"\\s*:\\s*\"?([0-9]+)", in: html),
                            dataSyncId: field("DATASYNC_ID"),
                            pageId: field("DELEGATED_SESSION_ID"),
                            visitorData: field("VISITOR_DATA"),
                            clientVersion: field("INNERTUBE_CLIENT_VERSION"))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1 else { return nil }
        let value = (text as NSString).substring(with: match.range(at: 1))
        return value.isEmpty ? nil : value
    }

    private static func youtubeCookieHeader(_ cookies: [HTTPCookie]) -> String? {
        let now = Date()
        var values: [String: String] = [:]
        for cookie in cookies {
            guard cookie.expiresDate == nil || cookie.expiresDate! > now else { continue }
            let youtube = cookie.domain == "youtube.com" || cookie.domain.hasSuffix(".youtube.com")
            guard youtube else { continue }
            if values[cookie.name] == nil || cookie.path.count > 1 {
                values[cookie.name] = cookie.value
            }
        }
        var header = values.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
        // A partitioned login can leave the signing secret only on Google's
        // own domain. YouTube reads cookies by name, but the account routes
        // also expect the rest of the Google session, so carry the identity
        // cookies across when the YouTube jar did not receive them.
        if GoogleAccountStore.apiSID(in: header) == nil {
            let identityCookies: Set<String> = [
                "SID", "HSID", "SSID", "APISID", "SAPISID",
                "__Secure-1PSID", "__Secure-3PSID",
                "__Secure-1PAPISID", "__Secure-3PAPISID"
            ]
            var seen = Set(values.keys)
            for cookie in cookies {
                let domain = cookie.domain
                guard (domain == "google.com" || domain.hasSuffix(".google.com")),
                      identityCookies.contains(cookie.name),
                      !seen.contains(cookie.name),
                      cookie.expiresDate == nil || cookie.expiresDate! > now else { continue }
                header += (header.isEmpty ? "" : "; ") + "\(cookie.name)=\(cookie.value)"
                seen.insert(cookie.name)
            }
        }
        return header.isEmpty ? nil : header
    }

    /// Google's cookies only, so signing out of BitChord never signs the
    /// listener out of Jellyfin or any other page this app hosts.
    static func clearBrowserSession(completion: (() -> Void)? = nil) {
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            let google = cookies.filter { cookie in
                let domain = cookie.domain.lowercased()
                return domain == "google.com" || domain.hasSuffix(".google.com")
                    || domain == "youtube.com" || domain.hasSuffix(".youtube.com")
            }
            let group = DispatchGroup()
            for cookie in google {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            let domains: Set<String> = ["music.youtube.com", "www.youtube.com", "youtube.com",
                                        "accounts.google.com", "www.google.com", "google.com"]
            let dataStore = WKWebsiteDataStore.default()
            dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                let targets = records.filter { record in
                    let name = record.displayName.lowercased()
                    return domains.contains(name)
                        || domains.contains(where: { name.hasSuffix("." + $0) })
                }
                for record in targets {
                    group.enter()
                    dataStore.removeData(ofTypes: record.dataTypes, for: [record]) {
                        group.leave()
                    }
                }
                group.notify(queue: .main) { completion?() }
            }
        }
    }
}

extension GoogleSignInViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        progress.isHidden = false
        spinner.startAnimating()
        if GoogleSignInViewController.isYouTubeURL(webView.url) {
            enterYouTubeStage()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let fixture = GoogleHandoffFixture.active,
           navigationAction.request.url?.host?.lowercased() == "music.youtube.com" {
            decisionHandler(.cancel)
            DispatchQueue.main.async { [weak self] in
                self?.loadFixtureShell(fixture)
            }
            return
        }
        if GoogleSignInViewController.isYouTubeURL(navigationAction.request.url) {
            enterYouTubeStage()
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if GoogleHandoffFixture.active != nil {
            if fixtureShellLoaded {
                spinner.stopAnimating()
                progress.isHidden = true
                probeFixturePage()
                enterYouTubeStage()
                return
            }
            if let url = webView.url, url.scheme == "https" {
                GoogleHandoffFixture.probe.loginOrigin = url.absoluteString
            }
            return
        }
        spinner.stopAnimating()
        progress.isHidden = true
        // Keep Done reachable on every page. If the jar already has a session,
        // a manual tap can recover from a page this web view cannot render.
        doneButton.isEnabled = true
        if GoogleSignInViewController.isYouTubeURL(webView.url) {
            enterYouTubeStage()
        } else {
            statusLabel.textColor = Theme.secondaryText
            statusLabel.text = "Sign in with your Google Account. Your password stays with Google."
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        finishCapture(message: "Could not reach Google. Check the connection and try again.")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        finishCapture(message: "Could not reach Google. Check the connection and try again.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !completed else { return }
        finishCapture(message: "The Google page stopped responding. Tap Done to retry, or Cancel and reopen it.")
    }

    private func enterYouTubeStage() {
        guard !completed else { return }
        youtubeStage = true
        doneButton.isEnabled = true
        statusLabel.textColor = Theme.secondaryText
        statusLabel.text = "Google sign-in complete. Finishing sign-in..."
        scheduleAutoCapture()
    }

    private func scheduleAutoCapture() {
        guard youtubeStage, !completed, !autoCaptureExhausted else { return }
        autoCapture?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.completed, !self.captureInFlight else { return }
            self.beginCapture(manual: false)
        }
        autoCapture = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private static func isYouTubeURL(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "music.youtube.com" || host == "www.youtube.com"
            || host == "youtube.com" || host == "m.youtube.com"
    }
}

extension GoogleSignInViewController: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

extension GoogleSignInViewController: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        // The redirect can complete before the web view reports its final page.
        // A cookie write during the YouTube stage is enough to start looking.
        guard youtubeStage, !completed, !autoCaptureExhausted else { return }
        scheduleAutoCapture()
    }
}
