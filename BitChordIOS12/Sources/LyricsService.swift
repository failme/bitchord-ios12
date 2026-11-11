import Foundation

struct LyricLine {
    let time: TimeInterval
    let text: String
}

struct LyricsResult {
    let lines: [LyricLine]
    let isSynced: Bool
}

/// Fetches synchronized lyrics from LRCLIB (no key required) and parses LRC.
final class LyricsService {
    static let shared = LyricsService()

    private let session: URLSession
    private let base = "https://lrclib.net"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    func fetch(track: Track, completion: @escaping (LyricsResult?, String?) -> Void) {
        var items = [URLQueryItem(name: "track_name", value: track.title)]
        if !track.artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: track.artist))
        }
        if let duration = track.durationSeconds {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }

        get(path: "/api/get", query: items) { [weak self] object in
            if let result = self?.result(from: object), !result.lines.isEmpty {
                completion(result, nil)
                return
            }
            self?.search(track: track, completion: completion)
        }
    }

    private func search(track: Track, completion: @escaping (LyricsResult?, String?) -> Void) {
        let query = "\(track.title) \(track.artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        get(path: "/api/search", query: [URLQueryItem(name: "q", value: query)]) { [weak self] object in
            guard let self = self else { return }
            let entries = (object as? [[String: Any]]) ?? []
            for entry in entries {
                if let result = self.result(from: entry), result.isSynced, !result.lines.isEmpty {
                    completion(result, nil)
                    return
                }
            }
            for entry in entries {
                if let result = self.result(from: entry), !result.lines.isEmpty {
                    completion(result, nil)
                    return
                }
            }
            completion(nil, "No lyrics found.")
        }
    }

    private func result(from object: Any?) -> LyricsResult? {
        guard let dict = object as? [String: Any] else { return nil }
        if let synced = dict["syncedLyrics"] as? String, !synced.isEmpty {
            let lines = LyricsService.parseLRC(synced)
            if !lines.isEmpty {
                return LyricsResult(lines: lines, isSynced: true)
            }
        }
        if let plain = dict["plainLyrics"] as? String, !plain.isEmpty {
            let lines = plain
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { LyricLine(time: 0, text: $0) }
            if !lines.isEmpty {
                return LyricsResult(lines: lines, isSynced: false)
            }
        }
        return nil
    }

    private func get(path: String, query: [URLQueryItem], completion: @escaping (Any?) -> Void) {
        var components = URLComponents(string: base + path)
        components?.queryItems = query
        guard let url = components?.url else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("BitChordIOS12/1.0", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, _, _ in
            var object: Any?
            if let data = data, !data.isEmpty {
                object = try? JSONSerialization.jsonObject(with: data, options: [])
            }
            DispatchQueue.main.async {
                completion(object)
            }
        }.resume()
    }

    // MARK: - LRC

    static func parseLRC(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = "\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsLine = line as NSString
            let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }

            // Drop every timing tag to get the lyric body.
            var body = regex.stringByReplacingMatches(in: line,
                                                      options: [],
                                                      range: NSRange(location: 0, length: nsLine.length),
                                                      withTemplate: "")
            // Strip word-level timing markers used by enhanced LRC.
            body = body.replacingOccurrences(of: "<\\d{1,3}:\\d{2}(?:[.:]\\d{1,3})?>",
                                             with: "",
                                             options: .regularExpression)
            body = body.trimmingCharacters(in: .whitespaces)
            if body.isEmpty { continue }

            for match in matches {
                guard let minutes = Double(nsLine.substring(with: match.range(at: 1))),
                      let seconds = Double(nsLine.substring(with: match.range(at: 2))) else { continue }
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let digits = nsLine.substring(with: match.range(at: 3))
                    if let value = Double(digits) {
                        fraction = value / pow(10.0, Double(digits.count))
                    }
                }
                lines.append(LyricLine(time: minutes * 60 + seconds + fraction, text: body))
            }
        }

        lines.sort { $0.time < $1.time }
        return lines
    }
}
