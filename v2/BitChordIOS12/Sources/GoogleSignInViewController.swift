import UIKit
import WebKit

/// Google's own sign-in page inside the app.
///
/// This is deliberately not an OAuth SDK: the listener authenticates directly
/// with Google (password, 2FA and account picker all live on Google's page),
/// and the app takes the resulting YouTube session cookie. It is the same
/// approach the Android app uses, and it needs no client id or secret.
final class GoogleSignInViewController: UIViewController {
    private let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(activityIndicatorStyle: .white)
    private var doneButton: UIBarButtonItem!
    private var progressObservation: NSKeyValueObservation?
    private var reachedMusic = false

    private static let loginURL = URL(string:
        "https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&prompt=select_account"
        + "&continue=https%3A%2F%2Fmusic.youtube.com%2F")!
    private static let musicOrigin = "https://music.youtube.com"

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

        // Start with a clean Google jar. Otherwise an account signed out of the
        // app is immediately recognised by accounts.google.com, and the screen
        // cannot be used to choose a different one.
        GoogleSignInViewController.clearBrowserSession {
            self.loadLogin()
        }
    }

    deinit {
        progressObservation?.invalidate()
    }

    private func loadLogin() {
        var request = URLRequest(url: GoogleSignInViewController.loginURL)
        request.timeoutInterval = 30
        webView.load(request)
    }

    @objc private func cancel() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func done() {
        doneButton.isEnabled = false
        spinner.startAnimating()
        statusLabel.text = "Reading your YouTube Music session..."
        captureCookies { [weak self] cookies in
            guard let self = self else { return }
            guard let header = GoogleSignInViewController.youtubeCookieHeader(cookies),
                  GoogleAccountStore.apiSID(in: header) != nil else {
                self.finishCapture(message: "Google has not finished signing you in yet. Complete the page, then tap Done again.")
                return
            }
            self.readPageConfig { authUser, dataSyncID, pageID, visitorData, clientVersion, loggedIn in
                guard self.reachedMusic || loggedIn else {
                    self.finishCapture(message: "Wait until YouTube Music opens, then tap Done.")
                    return
                }
                let captured = CapturedGoogleSession(cookie: header,
                                                     authUser: authUser ?? "0",
                                                     dataSyncId: dataSyncID,
                                                     pageId: pageID,
                                                     visitorData: visitorData,
                                                     clientVersion: clientVersion)
                GoogleAccountStore.shared.adopt(captured)
                self.dismiss(animated: true, completion: nil)
            }
        }
    }

    private func finishCapture(message: String) {
        spinner.stopAnimating()
        doneButton.isEnabled = true
        statusLabel.text = message
        statusLabel.textColor = UIColor(red: 1, green: 0.45, blue: 0.42, alpha: 1)
    }

    private func captureCookies(completion: @escaping ([HTTPCookie]) -> Void) {
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            DispatchQueue.main.async { completion(cookies) }
        }
    }

    /// The page's own ytcfg is the authoritative answer about which Google
    /// login and which channel this session is acting as.
    private func readPageConfig(completion: @escaping (String?, String?, String?, String?, String?, Bool) -> Void) {
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
                completion(nil, nil, nil, nil, nil, false)
                return
            }
            let loggedIn = (json["loggedIn"] as? String) == "true"
            func string(_ key: String) -> String? {
                guard let value = json[key] as? String, !value.isEmpty, value != "null" else { return nil }
                return value
            }
            completion(string("authUser"), string("dataSyncId"), string("pageId"),
                       string("visitorData"), string("clientVersion"), loggedIn)
        }
    }

    private static func youtubeCookieHeader(_ cookies: [HTTPCookie]) -> String? {
        let now = Date()
        let apiNames: Set<String> = ["SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID"]
        var values: [String: String] = [:]
        for cookie in cookies {
            guard cookie.expiresDate == nil || cookie.expiresDate! > now else { continue }
            let youtube = cookie.domain == "youtube.com" || cookie.domain.hasSuffix(".youtube.com")
            let googleSID = (cookie.domain == "google.com" || cookie.domain.hasSuffix(".google.com"))
                && apiNames.contains(cookie.name)
            guard youtube || googleSID else { continue }
            if values[cookie.name] == nil || cookie.path.count > 1 {
                values[cookie.name] = cookie.value
            }
        }
        guard !values.isEmpty else { return nil }
        return values.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
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
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
        progress.isHidden = true
        let url = webView.url?.absoluteString ?? ""
        if url.hasPrefix(GoogleSignInViewController.musicOrigin) {
            reachedMusic = true
            doneButton.isEnabled = true
            statusLabel.textColor = Theme.secondaryText
            statusLabel.text = "Finish choosing your account, then tap Done."
        } else {
            doneButton.isEnabled = false
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishCapture(message: "Could not reach Google. Check the connection and try again.")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishCapture(message: "Could not reach Google. Check the connection and try again.")
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
