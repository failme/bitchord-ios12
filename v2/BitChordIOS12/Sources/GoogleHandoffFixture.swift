import Foundation
import WebKit

/// The deterministic Google → YouTube Music handoff used by the screenshot
/// suite. It still runs through the real sign-in controller and the real
/// `WKWebsiteDataStore`; only the pages Google would serve are replaced with
/// local documents carrying the same origins.
struct GoogleHandoffFixture {
    enum Shell: String {
        case rendered
        case blank
    }

    struct Probe {
        var loginOrigin = ""
        var shellOrigin = ""
        var documentCookie = ""
        var documentBlank = true
        var pageConfigRead = false
        var networkFallbackUsed = false
        var networkHadCookie = false
    }

    static let cookieValue = "fixture-sapisid"
    static let dataSyncID = "fixture-page||fixture-account"
    static let normalizedDataSyncID = "fixture-account"
    static let pageID = "fixture-page"
    static let visitorData = "fixture-visitor"
    static let clientVersion = "2.20241111.01.00"

    static var active: GoogleHandoffFixture?
    static var probe = Probe()

    let shell: Shell

    var loginBaseURL: URL { return URL(string: "https://accounts.google.com/")! }
    var musicBaseURL: URL { return URL(string: "https://music.youtube.com/")! }

    /// The password page is not fetched from Google in this fixture. It is a
    /// page with Google's origin that performs the same redirect the real page
    /// performs once the account picker finishes.
    var loginHTML: String {
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { background: #050505; color: #fff; font: 17px -apple-system; }
          </style>
        </head>
        <body>
          <p>Google sign-in fixture</p>
          <script>
            setTimeout(function () {
              window.location.href = "https://music.youtube.com/";
            }, 120);
          </script>
        </body>
        </html>
        """
    }

    /// `rendered` has the shell's ytcfg and a non-empty body. `blank` has
    /// neither, which is the page a real iOS 12 WKWebView can leave behind
    /// after the redirect.
    var shellHTML: String {
        switch shell {
        case .rendered:
            return """
            <!doctype html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <script>
                window.ytcfg = {
                  get: function (key) {
                    var values = {
                      LOGGED_IN: "true",
                      SESSION_INDEX: "0",
                      DATASYNC_ID: "\(GoogleHandoffFixture.dataSyncID)",
                      DELEGATED_SESSION_ID: "\(GoogleHandoffFixture.pageID)",
                      VISITOR_DATA: "\(GoogleHandoffFixture.visitorData)",
                      INNERTUBE_CLIENT_VERSION: "\(GoogleHandoffFixture.clientVersion)"
                    };
                    return values[key];
                  }
                };
              </script>
            </head>
            <body>
              <main>YouTube Music</main>
              <script>
                document.body.setAttribute("data-shell", "rendered");
              </script>
            </body>
            </html>
            """
        case .blank:
            return """
            <!doctype html>
            <html>
            <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
            <body></body>
            </html>
            """
        }
    }

    /// The HTML body returned for the authenticated `music.youtube.com` read.
    /// The fallback must parse this without JavaScript or a rendered shell.
    var networkHTML: String {
        return """
        <!doctype html>
        <html>
        <head>
          <script>
            window.ytcfg = {
              "LOGGED_IN": "true",
              "SESSION_INDEX": "0",
              "DATASYNC_ID": "\(GoogleHandoffFixture.dataSyncID)",
              "DELEGATED_SESSION_ID": "\(GoogleHandoffFixture.pageID)",
              "VISITOR_DATA": "\(GoogleHandoffFixture.visitorData)",
              "INNERTUBE_CLIENT_VERSION": "\(GoogleHandoffFixture.clientVersion)"
            };
          </script>
        </head>
        <body>YouTube Music</body>
        </html>
        """
    }

    /// Seeded into the web view's own data store before the browser loads
    /// Google. `BC_VISIBLE` is readable by the music page, while `GOOGLE_ONLY`
    /// is scoped to accounts.google.com and must not become visible there.
    var cookies: [HTTPCookie] {
        return [
            cookie(name: "SAPISID", value: GoogleHandoffFixture.cookieValue, domain: ".youtube.com"),
            cookie(name: "BC_VISIBLE", value: "1", domain: ".youtube.com"),
            cookie(name: "GOOGLE_ONLY", value: "1", domain: ".google.com")
        ].compactMap { $0 }
    }

    func seedCookies(completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { completion() }
    }

    private func cookie(name: String, value: String, domain: String) -> HTTPCookie? {
        return HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
            .expires: Date(timeIntervalSinceNow: 3600)
        ])
    }
}
