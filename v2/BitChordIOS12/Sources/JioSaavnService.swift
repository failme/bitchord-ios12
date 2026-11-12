import CommonCrypto
import Foundation

/// JioSaavn catalogue client, ported from the Android app's `JioSaavnService` /
/// `JioSaavnSource` (same project family, GPL-3.0).
///
/// Why this exists: every anonymous YouTube route is either bot-gated
/// (`LOGIN_REQUIRED`) or ciphered, and iOS 12's WebKit has no MediaSource, so the
/// embedded player can never produce sound there. JioSaavn answers plain JSON over
/// HTTPS, and its `encrypted_media_url` decrypts with a fixed DES key into a direct
/// progressive `aac.saavncdn.com` MP4 URL — no signature dance, no login. AVPlayer
/// decodes those natively on iOS 12, which makes this the primary audio source;
/// YouTube resolution is kept only as a fallback.
final class JioSaavnService {
    static let shared = JioSaavnService()

    /// Human-readable quality of the last resolved stream, e.g. "JioSaavn 320kbps".
    private(set) var lastQualityLabel = ""
    /// Whether the last resolved stream was flagged explicit.
    private(set) var lastIsExplicit = false

    private let session: URLSession
    private let endpoint = URL(string: "https://www.jiosaavn.com/api.php")!
    /// Fixed DES key the catalogue encrypts media URLs with (as in the Android client).
    private let desKey = Data("38346591".utf8)

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // The India-facing headers are what defeat the catalogue's geo-blocking;
        // without `X-Forwarded-For` the API answers empty outside India.
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
            "X-Forwarded-For": "49.36.0.1",
            "X-Real-IP": "49.36.0.1",
            "Accept-Language": "en-IN,en;q=0.9",
            "Cookie": "explicit_content=1",
            "Accept": "application/json"
        ]
        session = URLSession(configuration: config)
    }

    // MARK: - Resolution

    /// Finds the catalogue row matching `title`/`artist` and returns its direct CDN URL.
    func resolve(title: String,
                 artist: String,
                 durationSeconds: Double?,
                 completion: @escaping (URL?, String) -> Void) {
        let parts = [title, artist].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let query = parts.joined(separator: " ")
        guard !query.isEmpty else {
            completion(nil, "Empty search query.")
            return
        }
        get(call: "search.getResults", params: ["q": query, "p": "1", "n": "10"]) { [weak self] json, error in
            guard let self = self else { return }
            guard let json = json, let results = json["results"] as? [[String: Any]], !results.isEmpty else {
                completion(nil, error ?? "JioSaavn returned no results.")
                return
            }
            var match = self.pickBest(in: results, title: title, artist: artist, durationSeconds: durationSeconds)
            // A catalogue row's artist string often carries credits the Saavn
            // catalogue files differently. Falling back to the title alone still
            // requires an exact title match, so it cannot pick the wrong song.
            if match == nil, !artist.isEmpty {
                match = self.pickBest(in: results, title: title, artist: "", durationSeconds: durationSeconds)
            }
            guard let match = match else {
                completion(nil, "JioSaavn had no close match.")
                return
            }
            self.lastIsExplicit = match.isExplicit
            self.details(for: match.id, completion: completion)
        }
    }

    /// Picks the result that is actually the requested song. The catalogue holds
    /// different recordings under the same title, so a wrong title is never accepted
    /// no matter how well the artist matches.
    private func pickBest(in results: [[String: Any]],
                          title: String,
                          artist: String,
                          durationSeconds: Double?) -> (id: String, isExplicit: Bool)? {
        let wantTitle = normalized(title)
        let wantArtist = normalized(artist)
        var best: (id: String, isExplicit: Bool)?
        // An exact title plus the artist or the duration clears this; anything less
        // than a solid title match with corroboration does not.
        var bestScore = 4
        for row in results {
            guard let songId = row["id"] as? String, !songId.isEmpty else { continue }
            let info = row["more_info"] as? [String: Any] ?? [:]
            let gotTitle = normalized(row["title"] as? String ?? "")
            var artists: [String] = []
            if let map = info["artistMap"] as? [String: Any],
               let primary = map["primary_artists"] as? [[String: Any]] {
                artists = primary.compactMap { $0["name"] as? String }.map { normalized($0) }
            }
            let titleScore: Int
            if !wantTitle.isEmpty, gotTitle == wantTitle {
                titleScore = 4
            } else if !wantTitle.isEmpty, gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle) {
                titleScore = 3
            } else if tokenOverlap(wantTitle, gotTitle) >= 0.6 {
                titleScore = 2
            } else {
                continue
            }
            var score = titleScore
            if !wantArtist.isEmpty, artists.contains(where: { $0.contains(wantArtist) || wantArtist.contains($0) }) {
                score += 2
            }
            if let want = durationSeconds, want > 0,
               let raw = info["duration"] as? String, let got = Double(raw),
               abs(got - want) <= 8 {
                score += 1
            }
            if score > bestScore {
                bestScore = score
                let flag = (row["explicit_content"] as? String ?? "").lowercased()
                best = (songId, flag == "1" || flag == "true")
            }
        }
        return best
    }

    private func details(for songId: String, completion: @escaping (URL?, String) -> Void) {
        get(call: "song.getDetails", params: ["pids": songId]) { [weak self] json, error in
            guard let self = self else { return }
            guard let json = json else {
                completion(nil, error ?? "JioSaavn details failed.")
                return
            }
            // `song.getDetails` answers with a map keyed by the requested id
            // (`{"<id>":{...}}`), not the `{"songs":[...]}` envelope search uses.
            // Both shapes are read so neither endpoint changing its mind breaks this.
            var song = (json["songs"] as? [[String: Any]])?.first
            if song == nil {
                song = json.values.compactMap { $0 as? [String: Any] }.first
            }
            guard let row = song,
                  let info = row["more_info"] as? [String: Any],
                  let encrypted = info["encrypted_media_url"] as? String, !encrypted.isEmpty,
                  let stream = self.bestStream(encrypted: encrypted,
                                              supports320: (info["320kbps"] as? String ?? "").lowercased() == "true"),
                  let url = URL(string: stream.url), url.scheme?.hasPrefix("http") == true else {
                completion(nil, "JioSaavn had no stream URL.")
                return
            }
            self.lastQualityLabel = "JioSaavn " + (stream.kbps.map { "\($0)kbps" } ?? "audio")
                // The details row is authoritative; fall back to the search row otherwise.
                let flag = (row["explicit_content"] as? String ?? "").lowercased()
                if flag == "1" || flag == "true" || flag == "0" || flag == "false" {
                    self.lastIsExplicit = flag == "1" || flag == "true"
                }
                completion(url, "")
        }
    }

    /// Decrypts to the catalogue's rendition URL and upgrades to 320kbps when the
    /// catalogue states that rendition exists. Deliberately no minimum-bitrate
    /// refusal (unlike Android): on iOS 12 any playable stream beats silence.
    private func bestStream(encrypted: String, supports320: Bool) -> (url: String, kbps: Int?)? {
        guard let decrypted = decrypt(encrypted), !decrypted.isEmpty else { return nil }
        guard let match = renditionMatch(in: decrypted) else { return (decrypted, nil) }
        guard supports320 else { return (decrypted, match.kbps) }
        return (decrypted.replacingCharacters(in: match.range, with: "_320." + match.ext), 320)
    }

    private func renditionMatch(in url: String) -> (range: Range<String.Index>, kbps: Int, ext: String)? {
        guard let regex = try? NSRegularExpression(pattern: "_(48|96|160|320)\\.(mp4|aac|mp3)(?=[?#]|$)",
                                                   options: [.caseInsensitive]),
              let m = regex.firstMatch(in: url, options: [], range: NSRange(url.startIndex..., in: url)),
              m.numberOfRanges == 3,
              let full = Range(m.range(at: 0), in: url),
              let kbpsRange = Range(m.range(at: 1), in: url),
              let extRange = Range(m.range(at: 2), in: url),
              let kbps = Int(url[kbpsRange]) else { return nil }
        return (full, kbps, String(url[extRange]))
    }

    /// DES/ECB/PKCS7 with the catalogue's fixed key, via CommonCrypto (present on iOS 12).
    private func decrypt(_ encrypted: String) -> String? {
        guard let data = Data(base64Encoded: encrypted, options: .ignoreUnknownCharacters),
              !data.isEmpty else { return nil }
        var out = Data(count: data.count + kCCBlockSizeDES)
        var moved: size_t = 0
        let key = desKey
        let capacity = out.count
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    CCCrypt(CCOperation(UInt32(kCCDecrypt)), CCAlgorithm(UInt32(kCCAlgorithmDES)),
                            CCOptions(UInt32(kCCOptionPKCS7Padding) | UInt32(kCCOptionECBMode)),
                            keyPtr.baseAddress, size_t(kCCKeySizeDES),
                            nil,
                            dataPtr.baseAddress, size_t(data.count),
                            outPtr.baseAddress, size_t(capacity),
                            &moved)
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.count = Int(moved)
        return String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Matching helpers

    private func normalized(_ s: String) -> String {
        var text = s.lowercased()
        text = text.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[[^]]*\\]", with: " ", options: .regularExpression)
        let scalars = text.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    private func tokenOverlap(_ a: String, _ b: String) -> Double {
        let ta = Set(a.split(separator: " ").map(String.init))
        let tb = Set(b.split(separator: " ").map(String.init))
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        return Double(ta.intersection(tb).count) / Double(min(ta.count, tb.count))
    }

    // MARK: - Transport

    private func get(call: String,
                     params: [String: String],
                     completion: @escaping ([String: Any]?, String?) -> Void) {
        var items = [
            URLQueryItem(name: "__call", value: call),
            URLQueryItem(name: "_format", value: "json"),
            URLQueryItem(name: "_marker", value: "0"),
            URLQueryItem(name: "api_version", value: "4"),
            URLQueryItem(name: "ctx", value: "android")
        ]
        for (name, value) in params {
            items.append(URLQueryItem(name: name, value: value))
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        guard let url = components.url else {
            completion(nil, "Bad request URL.")
            return
        }
        // Completions land on the main queue, matching `InnerTube.post`.
        session.dataTask(with: url) { data, response, error in
            if let error = error {
                let message = error.localizedDescription
                DispatchQueue.main.async { completion(nil, message) }
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                DispatchQueue.main.async { completion(nil, "JioSaavn request failed.") }
                return
            }
            DispatchQueue.main.async { completion(json, nil) }
        }.resume()
    }
}
