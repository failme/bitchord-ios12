import Foundation
import UIKit
import WebKit

enum BridgePlaybackState {
    case playing
    case paused
    case loading
    case ended
}

/// Plays audio through YouTube's embedded player inside a WKWebView.
///
/// This is the mechanism the upstream BitChord iOS app uses, and it is the only anonymous
/// playback path that actually produces sound: the InnerTube `player` endpoint refuses
/// unauthenticated requests, but the embed player will happily play while it believes it is
/// visible and focused. The injected scripts force the page-visibility APIs to report
/// `visible`, and neutralise the `visibilitychange` / `pagehide` listeners YouTube registers
/// to suspend itself in the background. A silent WebAudio oscillator keeps WebKit's audio
/// thread alive so playback survives the app leaving the foreground.
///
/// Everything here is available on iOS 12: WKWebView, WKUserScript, WKScriptMessageHandler and
/// the callback form of evaluateJavaScript.
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
    private(set) var lastReferrer: String = ""
    private(set) var currentVideoId: String?

    private var webView: WKWebView?
    private var pendingVideoId: String?
    private var consecutiveReloads = 0

    private override init() {
        super.init()
        setupWebView()
    }

    // MARK: - Web view

    /// The host view hierarchy needs this on screen for WebKit to grant it audio; it is shown
    /// behind the UI at a small size and never receives touches.
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

        // Runs in the top frame and in YouTube's iframes.
        let spoof = """
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
        controller.addUserScript(WKUserScript(source: spoof,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        config.userContentController = controller

        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 240), configuration: config)
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1"
        view.isOpaque = true
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .black
        view.navigationDelegate = self
        webView = view

        loadPlayerHTML()
    }

    private func loadPlayerHTML() {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          body, html { margin:0; padding:0; width:100%; height:100%; background-color:#000; overflow:hidden; }
          #player { width:100%; height:100%; border:none; display:block; }
        </style>
        <script>
        try {
          Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: false });
          Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: false });
          Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: false });
        } catch(e) {}

        window.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
        document.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
        window.addEventListener('pagehide', function(e) { e.stopImmediatePropagation(); }, true);

        if (window.navigator && window.navigator.audioSession) {
          try { window.navigator.audioSession.type = 'playback'; } catch(e) {}
        }

        try {
          var AudioCtx = window.AudioContext || window.webkitAudioContext;
          if (AudioCtx) {
            var aCtx = new AudioCtx();
            window._aCtx = aCtx;
            var osc = aCtx.createOscillator();
            var g = aCtx.createGain();
            g.gain.value = 0.00001;
            osc.connect(g);
            g.connect(aCtx.destination);
            osc.start(0);
          }
        } catch(e) {}
        </script>
        </head>
        <body>
        <iframe id="player"
                src=""
                allow="autoplay *; encrypted-media *; picture-in-picture *"
                allowfullscreen
                referrerpolicy="strict-origin-when-cross-origin"
                playsinline>
        </iframe>
        <script>
        var isReady = true;
        var pendingId = null;
        var currentLoadedId = null;
        var isUserPlaying = false;
        var playWatchdog = null;
        var lastDuration = 0;
        var lastKnownCurrentTime = 0;
        var lastTimeUpdateStamp = 0;
        var timeTicker = null;
        var pendingSeekTarget = null;
        var pendingSeekTime = 0;
        var seekConfirmed = true;
        var seekVerifyTimer = null;

        // YouTube requires the embedding app to identify itself through the HTTP Referer
        // header; without it the player refuses with error 153 and never becomes ready.
        // The document is loaded with baseURL https://com.bitchord.ios12 so the iframe
        // request carries that origin, and the same value is passed as `origin`.
        var EMBED_ORIGIN = 'https%3A%2F%2Fcom.bitchord.ios12';

        function embedURL(vId, startSeconds) {
          var url = 'https://www.youtube.com/embed/' + vId +
            '?autoplay=1&playsinline=1&controls=0&rel=0&enablejsapi=1&iv_load_policy=3' +
            '&origin=' + EMBED_ORIGIN +
            '&widget_referrer=' + EMBED_ORIGIN;
          if (startSeconds) {
            url += '&start=' + Math.floor(startSeconds);
          }
          return url;
        }

        function postToHost(payload) {
          window.webkit.messageHandlers.bridge.postMessage(payload);
        }

        function startTimeTicker() {
          if (timeTicker) clearInterval(timeTicker);
          timeTicker = setInterval(function() {
            if (!isUserPlaying) return;
            postCommand('listening');
            if (lastTimeUpdateStamp > 0) {
              var elapsed = (Date.now() - lastTimeUpdateStamp) / 1000.0;
              var est = lastKnownCurrentTime + elapsed;
              if (lastDuration > 0 && est > lastDuration) est = lastDuration;
              postToHost({ type: 'time', current: est, duration: lastDuration });
            }
          }, 250);
        }

        function stopTimeTicker() {
          if (timeTicker) {
            clearInterval(timeTicker);
            timeTicker = null;
          }
        }

        function postCommand(command, args) {
          var iframe = document.getElementById('player');
          if (iframe && iframe.contentWindow) {
            if (command === 'listening') {
              // The channel name is part of the handshake; the player only answers a
              // listener that registered a channel and then subscribed to events.
              iframe.contentWindow.postMessage(JSON.stringify({ event: 'listening', id: 1, channel: 'bitchord' }), '*');
              iframe.contentWindow.postMessage(JSON.stringify({ event: 'command', func: 'addEventListener', args: ['onReady'], id: 1 }), '*');
              iframe.contentWindow.postMessage(JSON.stringify({ event: 'command', func: 'addEventListener', args: ['onStateChange'], id: 1 }), '*');
            } else {
              iframe.contentWindow.postMessage(JSON.stringify({
                event: 'command',
                func: command,
                args: args || []
              }), '*');
            }
          }
        }

        function startPlayWatchdog() {
          if (playWatchdog) clearInterval(playWatchdog);
          var attempts = 0;
          playWatchdog = setInterval(function() {
            if (!isUserPlaying) {
              clearInterval(playWatchdog);
              playWatchdog = null;
              return;
            }
            attempts++;
            if (attempts > 30) {
              clearInterval(playWatchdog);
              playWatchdog = null;
              return;
            }
            postCommand('listening');
            postCommand('unMute');
            postCommand('playVideo');
          }, 450);
        }

        function playVideoId(vId) {
          isUserPlaying = true;
          lastKnownCurrentTime = 0;
          lastTimeUpdateStamp = 0;
          try {
            if (window._aCtx && window._aCtx.state === 'suspended') {
              window._aCtx.resume();
            }
          } catch(e) {}
          if ('mediaSession' in navigator) {
            try { navigator.mediaSession.playbackState = 'playing'; } catch(e) {}
          }

          var iframe = document.getElementById('player');
          if (!iframe) {
            pendingId = vId;
            return;
          }

          if (currentLoadedId === vId) {
            postCommand('unMute');
            postCommand('playVideo');
            startPlayWatchdog();
          } else {
            currentLoadedId = vId;
            iframe.src = embedURL(vId);
            startPlayWatchdog();
          }
        }

        function pauseVideo() {
          isUserPlaying = false;
          stopTimeTicker();
          if (playWatchdog) {
            clearInterval(playWatchdog);
            playWatchdog = null;
          }
          if ('mediaSession' in navigator) {
            try { navigator.mediaSession.playbackState = 'paused'; } catch(e) {}
          }
          postCommand('pauseVideo');
        }

        function resumeVideo() {
          isUserPlaying = true;
          try {
            if (window._aCtx && window._aCtx.state === 'suspended') {
              window._aCtx.resume();
            }
          } catch(e) {}
          if ('mediaSession' in navigator) {
            try { navigator.mediaSession.playbackState = 'playing'; } catch(e) {}
          }
          postCommand('unMute');
          postCommand('playVideo');
          startPlayWatchdog();
        }

        function seekTo(seconds) {
          seconds = Math.max(0, Number(seconds) || 0);
          lastKnownCurrentTime = seconds;
          lastTimeUpdateStamp = Date.now();
          pendingSeekTarget = seconds;
          pendingSeekTime = Date.now();

          postCommand('listening');
          postCommand('seekTo', [seconds, true]);
          postToHost({ type: 'time', current: seconds, duration: lastDuration });

          if (isUserPlaying) {
            postCommand('unMute');
            postCommand('playVideo');
          }

          seekConfirmed = false;
          if (seekVerifyTimer) clearTimeout(seekVerifyTimer);
          var target = seconds;
          seekVerifyTimer = setTimeout(function() {
            postCommand('seekTo', [target, true]);
            seekVerifyTimer = setTimeout(function() {
              seekVerifyTimer = null;
              if (seekConfirmed || pendingSeekTarget !== target || !currentLoadedId) return;
              var iframe = document.getElementById('player');
              if (!iframe) return;
              iframe.src = embedURL(currentLoadedId, target);
              pendingSeekTime = Date.now();
              if (isUserPlaying) startPlayWatchdog();
            }, 1200);
          }, 900);
        }

        function setVolume(vol) {
          postCommand('setVolume', [vol * 100]);
        }

        function setPlaybackRate(rate) {
          postCommand('setPlaybackRate', [rate]);
        }

        window.addEventListener('message', function(event) {
          try {
            var data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
            if (!data) return;

            if (data.event === 'onReady' || data.event === 'initialDelivery') {
              postToHost({ type: 'apiReady' });
              postCommand('listening');
              if (isUserPlaying) {
                postCommand('unMute');
                postCommand('setVolume', [100]);
                postCommand('playVideo');
              }
              if (pendingSeekTarget !== null) {
                postCommand('seekTo', [pendingSeekTarget, true]);
              }
            }

            if (data.event === 'onStateChange') {
              var st = data.info;
              if (st === 1) {
                if (playWatchdog) {
                  clearInterval(playWatchdog);
                  playWatchdog = null;
                }
                startTimeTicker();
              } else if (st === 2 || st === 0) {
                stopTimeTicker();
              }
              if ((st === 5 || st === -1 || st === 2) && isUserPlaying) {
                postCommand('unMute');
                postCommand('playVideo');
              }
              postToHost({ type: 'state', state: st });
            } else if (data.event === 'infoDelivery' && data.info) {
              if (data.info.playerState !== undefined) {
                var st2 = data.info.playerState;
                if (st2 === 1) {
                  if (playWatchdog) {
                    clearInterval(playWatchdog);
                    playWatchdog = null;
                  }
                  startTimeTicker();
                } else if (st2 === 2 || st2 === 0) {
                  stopTimeTicker();
                }
                if ((st2 === 5 || st2 === -1 || st2 === 2) && isUserPlaying) {
                  postCommand('unMute');
                  postCommand('playVideo');
                }
                postToHost({ type: 'state', state: data.info.playerState });
              }
              if (data.info.duration !== undefined && data.info.duration > 0) {
                lastDuration = data.info.duration;
              }
              if (data.info.currentTime !== undefined) {
                var cur = Number(data.info.currentTime) || 0;
                if (pendingSeekTarget !== null) {
                  if (Date.now() - pendingSeekTime < 4000) {
                    if (Math.abs(cur - pendingSeekTarget) > 2.5) {
                      return;
                    } else {
                      seekConfirmed = true;
                      pendingSeekTarget = null;
                    }
                  } else {
                    pendingSeekTarget = null;
                  }
                }
                lastKnownCurrentTime = cur;
                lastTimeUpdateStamp = Date.now();
                postToHost({ type: 'time', current: lastKnownCurrentTime, duration: lastDuration });
              }
            } else if (data.event === 'onError') {
              var err = data.info || -1;
              if (playWatchdog) {
                clearInterval(playWatchdog);
                playWatchdog = null;
              }
              postToHost({ type: 'error', code: err });
            }
          } catch(e) {}
        });

        window.onload = function() {
          // Report what identity the page actually presents. If YouTube refuses the
          // embed, this is the value that explains why.
          postToHost({ type: 'ready', referrer: document.referrer || '', origin: location.origin || '' });
          if (pendingId) {
            var p = pendingId;
            pendingId = null;
            playVideoId(p);
          }
        };
        </script>
        </body>
        </html>
        """#

        // The base URL is the app's identity as far as YouTube is concerned. Loading the
        // document without one (or with a YouTube host) means no Referer is sent, and
        // YouTube answers embed requests with error 153 instead of a player.
        webView?.loadHTMLString(html, baseURL: URL(string: "https://com.bitchord.ios12"))
    }

    // MARK: - Control

    func play(videoId: String) {
        isPausedByUser = false
        currentVideoId = videoId
        guard isReady else {
            pendingVideoId = videoId
            return
        }
        webView?.evaluateJavaScript("playVideoId('\(videoId)');", completionHandler: nil)
    }

    func pause() {
        isPausedByUser = true
        webView?.evaluateJavaScript("pauseVideo();", completionHandler: nil)
    }

    func resume() {
        isPausedByUser = false
        webView?.evaluateJavaScript("resumeVideo();", completionHandler: nil)
    }

    func seek(to seconds: TimeInterval) {
        webView?.evaluateJavaScript("seekTo(\(seconds));", completionHandler: nil)
    }

    func setVolume(_ volume: Float) {
        webView?.evaluateJavaScript("setVolume(\(volume));", completionHandler: nil)
    }

    func setPlaybackRate(_ rate: Double) {
        webView?.evaluateJavaScript("setPlaybackRate(\(rate));", completionHandler: nil)
    }

    func refreshSession() {
        isReady = false
        loadPlayerHTML()
    }

    // MARK: - Recovery

    // The embed page is heavy; on 1 GB devices WebKit can jettison the content process
    // (jetsam) with no callback into the JS inside. Without this the bridge would sit at
    // `isReady == true` forever while every command vanishes into a dead page.
    // Reload the player and resume the current video instead.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if !isPausedByUser, let videoId = currentVideoId {
            pendingVideoId = videoId
        }
        consecutiveReloads += 1
        isReady = false
        onBridgeRecovering?()
        loadPlayerHTML()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard consecutiveReloads < 2 else { return }
        consecutiveReloads += 1
        isReady = false
        onBridgeRecovering?()
        loadPlayerHTML()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // The player page is fully JS-driven; the top frame must never navigate away
        // (consent walls, popups) or the session is lost. The embed iframe may load.
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            return
        }
        if let frame = navigationAction.targetFrame, frame.isMainFrame,
           let host = navigationAction.request.url?.host,
           !host.contains("youtube") {
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
        case "ready":
            isReady = true
            consecutiveReloads = 0
            if let referrer = body["referrer"] as? String {
                lastReferrer = referrer
            }
            if let pending = pendingVideoId {
                pendingVideoId = nil
                play(videoId: pending)
            }

        case "state":
            guard let state = body["state"] as? Int else { return }
            switch state {
            case 0:
                onStateChanged?(.ended)
                onPlaybackEnded?()
            case 1:
                if isPausedByUser {
                    pause()
                } else {
                    onStateChanged?(.playing)
                }
            case 2:
                if isPausedByUser {
                    onStateChanged?(.paused)
                } else {
                    // Transient pause while the embed cues the next video.
                    resume()
                }
            case 3:
                if !isPausedByUser {
                    onStateChanged?(.loading)
                }
            default:
                break
            }

        case "time":
            let current = body["current"] as? Double ?? 0
            let duration = body["duration"] as? Double ?? 0
            onTimeUpdated?(current, duration)

        case "apiReady":
            // The embed handshake completed: playback is authorised, so a stall from here
            // is a real media problem rather than a missing player.
            onApiReady?()

        case "error":
            onPlaybackError?(body["code"] as? Int ?? -1)

        default:
            break
        }
    }
}
