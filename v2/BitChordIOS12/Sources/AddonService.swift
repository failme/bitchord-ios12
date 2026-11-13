import Foundation

/// One stream from an addon: the URL to fetch plus the label the row shows.
struct AddonStream {
    let url: URL
    let quality: String
    let kbps: Int?

    var label: String {
        if let kbps = kbps, kbps > 0 { return "\(quality) · \(kbps) kbps" }
        return quality
    }
}

struct AddonManifest: Decodable {
    var name: String
    var lossless: Bool?
}

/// A source addon, shaped like the real project's: an HTTP server the user
/// points the app at. Only the two calls this port needs are spoken, in the same
/// JSON style upstream uses.
///
///     GET <base>/manifest          -> {"name": "Studio", "lossless": true}
///     GET <base>/stream/<videoID>  -> {"url": "...", "quality": "Lossless", "kbps": 900}
///
/// A 404 or an unusable body means "this addon has nothing for that track", and
/// the caller falls back to the standard catalogue rather than failing.
final class AddonService {
    static let shared = AddonService()
    static let urlKey = "BitChord.Sources.AddonURL"

    private var cached: (base: URL, manifest: AddonManifest)?
    /// The last reason the addon gave for having nothing, for the capture run.
    private(set) var lastError: String?

    var baseURL: URL? {
        let text = SettingsStore.shared.string(AddonService.urlKey, "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = URL(string: text), url.scheme != nil else { return nil }
        return url
    }

    var isConfigured: Bool {
        return baseURL != nil
    }

    /// The host to show in Settings, or nil when nothing is configured.
    var displayName: String? {
        guard let base = baseURL else { return nil }
        return base.host ?? base.absoluteString
    }

    func manifest(completion: @escaping (AddonManifest?, String?) -> Void) {
        guard let base = baseURL else {
            completion(nil, "No addon is configured.")
            return
        }
        if let cached = cached, cached.base == base {
            completion(cached.manifest, nil)
            return
        }
        request(base.appendingPathComponent("manifest")) { json, error in
            guard let json = json,
                  let name = json["name"] as? String else {
                completion(nil, error ?? "The addon did not describe itself.")
                return
            }
            let manifest = AddonManifest(name: name, lossless: json["lossless"] as? Bool)
            DispatchQueue.main.async { self.cached = (base, manifest) }
            completion(manifest, nil)
        }
    }

    /// Asks the addon for a stream. `nil` means it has nothing usable for this
    /// track, which is a normal answer and never an error worth stopping for.
    func stream(for track: Track, completion: @escaping (AddonStream?) -> Void) {
        guard let base = baseURL else {
            completion(nil)
            return
        }
        // One component at a time: a combined "stream/<id>" would be escaped as
        // a single component by some Foundation versions and 404 on the addon.
        let url = base.appendingPathComponent("stream").appendingPathComponent(track.videoID)
        request(url) { json, _ in
            guard let json = json,
                  let text = json["url"] as? String,
                  let url = URL(string: text, relativeTo: base)?.absoluteURL,
                  url.scheme != nil else {
                self.lastError = "The addon returned no stream URL."
                completion(nil)
                return
            }
            self.lastError = nil
            completion(AddonStream(url: url,
                                   quality: json["quality"] as? String ?? "Addon",
                                   kbps: json["kbps"] as? Int))
        }
    }

    private func request(_ url: URL, completion: @escaping ([String: Any]?, String?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let status = (response as? HTTPURLResponse)?.statusCode,
                  status == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let message = status == 404 ? "No stream for this track." :
                    (error?.localizedDescription ?? "The addon did not answer.")
                DispatchQueue.main.async { self.lastError = "\(message) [\(status)]" }
                completion(nil, message)
                return
            }
            completion(json, nil)
        }.resume()
    }
}
