import Foundation

/// Resolves a playable audio URL for a track.
///
/// YouTube now requires a signed-in session for anonymous `player` requests from most
/// clients, so a user-configured source is tried first. The contract is deliberately loose:
/// point the template at any URL that returns `{"url": "..."}` or a bare URL, or that serves
/// audio directly. `{videoId}` / `{id}` are substituted with the track's video id.
final class StreamResolver {
    static let shared = StreamResolver()

    private let defaults = UserDefaults.standard
    private let templateKey = "bitios.source.template"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    var sourceTemplate: String? {
        get { return defaults.string(forKey: templateKey) }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed = trimmed, !trimmed.isEmpty {
                defaults.set(trimmed, forKey: templateKey)
            } else {
                defaults.removeObject(forKey: templateKey)
            }
        }
    }

    var hasSource: Bool {
        guard let template = sourceTemplate else { return false }
        return !template.isEmpty
    }

    func resolve(track: Track, completion: @escaping (URL?, String?) -> Void) {
        guard let template = sourceTemplate, !template.isEmpty else {
            resolveFromYouTube(track: track, completion: completion)
            return
        }
        resolveFromSource(template: template, track: track) { [weak self] url, sourceError in
            if let url = url {
                completion(url, nil)
                return
            }
            self?.resolveFromYouTube(track: track) { fallbackURL, youtubeError in
                if let fallbackURL = fallbackURL {
                    completion(fallbackURL, nil)
                } else {
                    completion(nil, sourceError ?? youtubeError ?? "Could not resolve this track.")
                }
            }
        }
    }

    private func resolveFromYouTube(track: Track, completion: @escaping (URL?, String?) -> Void) {
        InnerTube.shared.resolveStreamURL(videoID: track.videoID) { url, reason in
            if let url = url {
                completion(url, nil)
            } else {
                completion(nil, reason)
            }
        }
    }

    private func resolveFromSource(template: String,
                                   track: Track,
                                   completion: @escaping (URL?, String?) -> Void) {
        let expanded = template
            .replacingOccurrences(of: "{videoId}", with: track.videoID)
            .replacingOccurrences(of: "{id}", with: track.videoID)
            .replacingOccurrences(of: "{title}", with: StreamResolver.encode(track.title))
            .replacingOccurrences(of: "{artist}", with: StreamResolver.encode(track.artist))

        guard let requestURL = URL(string: expanded) else {
            completion(nil, "The saved source URL is not valid.")
            return
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 20
        request.setValue("BitChordIOS12/1.0", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(nil, "Source request failed: \(error.localizedDescription)")
                }
                return
            }

            let mime = ((response as? HTTPURLResponse)?.allHeaderFields["Content-Type"] as? String) ?? ""
            if mime.hasPrefix("audio/") || mime.hasPrefix("application/octet-stream") {
                DispatchQueue.main.async {
                    completion(requestURL, nil)
                }
                return
            }

            var resolved: URL?
            if let data = data {
                if let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] {
                    let candidates = [json["url"], json["streamUrl"], json["stream_url"], json["link"]]
                    for candidate in candidates {
                        if let string = candidate as? String, let url = URL(string: string) {
                            resolved = url
                            break
                        }
                    }
                }
                if resolved == nil, let text = String(data: data, encoding: .utf8) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("http"), let url = URL(string: trimmed) {
                        resolved = url
                    }
                }
            }

            DispatchQueue.main.async {
                if let resolved = resolved {
                    completion(resolved, nil)
                } else {
                    completion(nil, "The source did not return a playable URL.")
                }
            }
        }.resume()
    }

    private static func encode(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
