import Foundation
import UIKit
import WebKit

enum BridgePlaybackState {
    case playing
    case paused
    case loading
    case ended
}

/// Plays audio through YouTube's embed page loaded as the web view's main document.
///
/// Two things make this work where the previous iframe approach did not:
///
/// 1. **Identity.** YouTube requires the embedding app to identify itself in the `Referer`
///    request header and answers "This video is unavailable" (error 153) without one.
///    Loading local HTML and letting the iframe fetch itself means WebKit decides whether to
///    send a referrer at all; loading the embed URL directly as a request lets this class set
///    the header itself, which is the route YouTube documents for apps.
///
/// 2. **Control.** With the embed as the main document there is no cross-origin iframe, so the
///    page's own `<video>` element can be driven through `evaluateJavaScript` — play, pause,
///    seek, volume, rate and position all read and written directly. The postMessage handshake
///    is gone entirely, so a stalled handshake can no longer strand playback.
///
/// Everything used here exists on iOS 12: WKWebView, WKUserScript, WKScriptMessageHandler,
/// WKNavigationDelegate and the callback form of evaluateJavaScript.
final class YouTubeBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = YouTubeBridge()

    var onPlaybackEnded: (() -> Void)?
    var onStateChanged: ((BridgePlaybackState) -> Void)?
    var onTimeUpdated: ((Double, Double) -> Void)?
    var onPlaybackError: ((Int) -> Void)?
    var onBridgeRecovering: (() -> Void)?
    var onApiReady: (() -> Void)?

    private(set) var isReady = false
    private(set) var isPausedByUser = false
    private(set) var currentVideoId: String?
    private(set) var lastReferrer: String = ""
    private(set) var lastDiagnostic: String = ""

    private var webView: WKWebView?
    private var pendingVideoId: String?
    private var consecutiveReloads = 0
    private var probeTimer: Timer?
    private var lastPosition: Double = 0
    private var lastDuration: Double = 0
    private var sawVideo = false

    /// The identity this app presents to YouTube, sent as the `Referer`.
    ///
    /// Measured against the live embed endpoint, this is the only referrer that returns a clean
    /// player page: no referrer yields error 153 ("player configuration error"), and both
    /// `http://127.0.0.1:…` and `https://www.youtube.com/` yield "This video is unavailable".
    ///
    /// There is deliberately no `origin` parameter. It has to name the *embedding* page's origin,
    /// and here the embed is the document itself, so every value we could pass would contradict
    /// the page YouTube is serving.
    private let appOrigin = "https://com.bitchord.ios12"

    /// Safari's user agent for the OS that is actually running.
    ///
    /// YouTube picks the player bundle from the user agent. Claiming a newer iOS than the WebKit
    /// underneath it asks for JavaScript this iOS 12 engine cannot parse, and a parse failure
    /// leaves the player at readyState 0 with no error event and no page text — silence, exactly
    /// as reported. Identifying truthfully gets the bundle that matches the engine.
    private var userAgent: String {
        let version = UIDevice.current.systemVersion
        let underscored = version.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(underscored) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version) Mobile/15E148 Safari/604.1"
    }

    private override init() {
        super.init()
        setupWebView()
    }

    // MARK: - Web view

    func makeWebView() -> WKWebView {
        if let existing = webView {
            return existing
        }
        setupWebView()
        return webView ?? WKWebView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let controller = WKUserContentController()
        controller.add(self, name: "bridge")
        controller.addUserScript(WKUserScript(source: Self.visibilityScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: Self.videoScript,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: false))
        config.userContentController = controller

        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 240), configuration: config)
        view.customUserAgent = userAgent
        view.navigationDelegate = self
        view.isOpaque = true
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .black
        webView = view
        view.loadHTMLString(Self.blankPage, baseURL: URL(string: appOrigin))
    }

    // MARK: - Scripts

    private static let visibilityScript = """
    (function() {
        try {
            Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
            Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
            Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: true });
            document.hasFocus = function() { return true; };
        } catch(e) {}

        var originalAddEventListener = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function(type, listener, options) {
            if (type === 'visibilitychange' || type === 'webkitvisibilitychange' || type === 'pagehide' || type === 'freeze') {
                return;
            }
            return originalAddEventListener.call(this, type, listener, options);
        };
    })();
    """

    /// Finds the player's <video> element, keeps it audible, and reports everything the host
    /// needs without relying on YouTube's postMessage API.
    private static let videoScript = """
    (function() {
        if (window.__bitChordInstalled) { return; }
        window.__bitChordInstalled = true;

        function post(payload) {
            try { window.webkit.messageHandlers.bridge.postMessage(payload); } catch (e) {}
        }

        function pageText() {
            var body = document.body;
            if (!body) { return ''; }
            return (body.innerText || '').replace(/\\s+/g, ' ').slice(0, 180);
        }

        function attach() {
            var v = document.querySelector('video');
            if (!v) { return false; }
            if (v.__bitChordHooked) { return true; }
            v.__bitChordHooked = true;

            try {
                v.setAttribute('playsinline', '');
                v.setAttribute('webkit-playsinline', '');
                v.playsInline = true;
                v.muted = true;
            } catch (e) {}

            v.addEventListener('loadedmetadata', function() {
                post({ type: 'meta', duration: v.duration || 0 });
            });
            v.addEventListener('playing', function() {
                // Autoplay policies allow a muted start; unmute once audio is flowing.
                try { v.muted = false; v.volume = 1.0; } catch (e) {}
                post({ type: 'playing', duration: v.duration || 0 });
            });
            v.addEventListener('play', function() { post({ type: 'playing', duration: v.duration || 0 }); });
            v.addEventListener('pause', function() { post({ type: 'paused' }); });
            v.addEventListener('ended', function() { post({ type: 'ended' }); });
            v.addEventListener('waiting', function() { post({ type: 'buffering' }); });
            v.addEventListener('error', function() {
                post({ type: 'mediaerror', code: v.error ? v.error.code : -1 });
            });

            post({ type: 'videoFound' });

            var result = v.play();
            if (result && result.catch) {
                result.catch(function(err) { post({ type: 'playblocked', reason: String(err) }); });
            }
            return true;
        }

        attach();
        var tries = 0;
        var poll = setInterval(function() {
            tries++;
            if (attach() || tries > 40) { clearInterval(poll); }
        }, 250);

        setTimeout(function() {
            if (!document.querySelector('video')) {
                post({ type: 'novideo', text: pageText(), referrer: document.referrer || '' });
            }
        }, 5000);
    })();
    """

    private static let blankPage = """
    <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width">
    <style>html,body{margin:0;padding:0;background:#000;}</style></head>
    <body></body></html>
    """

    // MARK: - Loading

    private func embedURL(videoId: String, startAt: Double) -> String {
        var url = "https://www.youtube.com/embed/\(videoId)"
        url += "?autoplay=1&playsinline=1&controls=0&rel=0&showinfo=0&iv_load_policy=3"
        if startAt >= 1 {
            url += "&start=\(Int(startAt))"
        }
        return url
    }

    private func load(videoId: String, startAt: Double = 0) {
        guard let url = URL(string: embedURL(videoId: videoId, startAt: startAt)) else { return }
        var request = URLRequest(url: url)
        request.setValue("\(appOrigin)/", forHTTPHeaderField: "Referer")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        isReady = false
        sawVideo = false
        lastPosition = startAt
        lastDuration = 0
        webView?.load(request)
    }

    // MARK: - Control

    func play(videoId: String) {
        isPausedByUser = false
        currentVideoId = videoId
        load(videoId: videoId)
    }

    func pause() {
        isPausedByUser = true
        evaluate("var v=document.querySelector('video'); if(v){v.pause();}")
    }

    func resume() {
        isPausedByUser = false
        evaluate("var v=document.querySelector('video'); if(v){v.muted=false;v.volume=1;v.play();}")
    }

    func seek(to seconds: TimeInterval) {
        lastPosition = seconds
        evaluate("var v=document.querySelector('video'); if(v){v.currentTime=\(seconds);}")
    }

    func setVolume(_ volume: Float) {
        evaluate("var v=document.querySelector('video'); if(v){v.volume=\(volume);v.muted=\(volume <= 0.001 ? "true" : "false");}")
    }

    func setPlaybackRate(_ rate: Double) {
        guard rate > 0 else { return }
        evaluate("var v=document.querySelector('video'); if(v){v.playbackRate=\(rate);}")
    }

    func refreshSession() {
        guard let videoId = currentVideoId else { return }
        load(videoId: videoId, startAt: lastPosition)
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - Position polling

    private func startProbing() {
        probeTimer?.invalidate()
        probeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.probe()
        }
    }

    // Reading the element directly is the ground truth: YouTube's own event API can stay
    // silent while the media element is perfectly happy, and vice versa.
    private func probe() {
        let script = "(function(){var v=document.querySelector('video');" +
            "if(!v){return 'none';}" +
            "return JSON.stringify({t:v.currentTime||0,d:v.duration||0,p:v.paused,w:v.readyState,e:v.error?v.error.code:0,v:v.volume,m:v.muted});})()"
        webView?.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self = self, let raw = result as? String, raw != "none" else { return }
            guard let data = raw.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                return
            }
            let position = dict["t"] as? Double ?? 0
            let duration = dict["d"] as? Double ?? 0
            let paused = dict["p"] as? Bool ?? true
            let readyState = dict["w"] as? Int ?? 0
            let errorCode = dict["e"] as? Int ?? 0

            if duration > 0 { self.lastDuration = duration }
            if position > 0 {
                self.lastPosition = position
                self.isReady = true
                if !self.isPausedByUser && paused && readyState >= 2 {
                    // The embed paused itself (autoplay policy or a stall): ask it again.
                    self.evaluate("var v=document.querySelector('video'); if(v){v.muted=false;v.volume=1;v.play();}")
                }
            }
            if errorCode != 0 {
                self.onPlaybackError?(errorCode)
                return
            }
            if self.isPausedByUser {
                self.onStateChanged?(.paused)
            } else if !paused {
                self.onStateChanged?(.playing)
            } else if readyState < 3 && position == 0 {
                self.onStateChanged?(.loading)
            }
            self.onTimeUpdated?(position, duration)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        evaluate("document.referrer")
        startProbing()
        if !isPausedByUser {
            evaluate("var v=document.querySelector('video'); if(v){v.muted=false;v.volume=1;v.play();}")
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        consecutiveReloads += 1
        isReady = false
        onBridgeRecovering?()
        refreshSession()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard consecutiveReloads < 2 else { return }
        consecutiveReloads += 1
        isReady = false
        onBridgeRecovering?()
        refreshSession()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "videoFound":
            isReady = true
            sawVideo = true
            consecutiveReloads = 0
            onApiReady?()

        case "playing":
            isReady = true
            sawVideo = true
            consecutiveReloads = 0
            let duration = body["duration"] as? Double ?? 0
            if duration > 0 { lastDuration = duration }
            onStateChanged?(.playing)

        case "paused":
            onStateChanged?(isPausedByUser ? .paused : .loading)

        case "buffering":
            if !isPausedByUser { onStateChanged?(.loading) }

        case "ended":
            onStateChanged?(.ended)
            onPlaybackEnded?()

        case "meta":
            let duration = body["duration"] as? Double ?? 0
            if duration > 0 { lastDuration = duration }

        case "mediaerror":
            onPlaybackError?(body["code"] as? Int ?? -1)

        case "playblocked":
            lastDiagnostic = body["reason"] as? String ?? "play() was rejected"

        case "novideo":
            lastDiagnostic = body["text"] as? String ?? ""
            if let referrer = body["referrer"] as? String, !referrer.isEmpty {
                lastReferrer = referrer
            }
            if !sawVideo {
                onPlaybackError?(-2)
            }

        default:
            break
        }
    }
}
