import Foundation

/// One separately timed piece of a word: characters `startChar..<endChar` sung
/// from `start` to `end`. Apple's TTML splits long words into these.
struct LyricSyllable {
    let start: TimeInterval
    let end: TimeInterval
    let startChar: Int
    let endChar: Int
}

/// A word of a line with its own stretch of the song, and the syllables it was
/// split into where the provider supplied them.
struct LyricWord {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let startChar: Int
    let endChar: Int
    let syllables: [LyricSyllable]
}

struct WordLyricLine {
    let time: TimeInterval
    let text: String
    let words: [LyricWord]
    var end: TimeInterval?

    var isWordSynced: Bool { return !words.isEmpty }

    /// Fractional character index revealed at `position` — every character
    /// counted only once it is actually sung, following the syllable timings
    /// where there are any. No interpolation across the line.
    func revealedChars(at position: TimeInterval) -> Double {
        guard !words.isEmpty else {
            return position >= time ? Double(text.count) : 0
        }
        var revealed = 0.0
        for word in words {
            if position <= word.start { break }
            if position >= word.end {
                revealed = Double(word.endChar)
                continue
            }
            if word.syllables.isEmpty {
                let span = max(0.001, word.end - word.start)
                let through = (position - word.start) / span
                revealed = Double(word.startChar) + through * Double(word.endChar - word.startChar)
                return revealed
            }
            for syllable in word.syllables {
                if position < syllable.start { return Double(syllable.startChar) }
                if position < syllable.end {
                    let span = max(0.001, syllable.end - syllable.start)
                    let through = (position - syllable.start) / span
                    return Double(syllable.startChar)
                        + through * Double(syllable.endChar - syllable.startChar)
                }
                revealed = Double(syllable.endChar)
            }
            // The gap after a word fills as the singer moves to the next one.
            if let next = words.first(where: { $0.startChar > word.startChar }) {
                if position < next.start {
                    let pause = max(0.001, next.start - word.end)
                    let through = (position - word.end) / pause
                    return Double(word.endChar)
                        + through * Double(max(0, next.startChar - word.endChar))
                }
            }
        }
        return revealed
    }
}

struct LyricsResult {
    let lines: [WordLyricLine]
    let isSynced: Bool
    let source: String
}

/// Lyrics from the same providers upstream's `LyricsRepository` asks, in its
/// default order: lrc.red first (Apple Music TTML, syllable timing, filed by
/// ISRC), then LyricsPlus (Apple/QQ syllables from community mirrors), then
/// Unison (contributed, any of TTML/LRC/plain), and finally LRCLIB for
/// whole-line LRC when none of them has the track.
///
/// Word timing is the point: a line that only knows when it starts can only
/// light up whole, and faking a sweep across it is not the same thing.
final class LyricsService {
    static let shared = LyricsService()

    private let session: URLSession
    private let lrcRedBase = "https://lrc.red"
    private static let lyricsPlusMirrors = [
        "https://lyricsplus.binimum.org",
        "https://lyricsplus.prjktla.my.id",
        "https://lyricsplus.atomix.one",
        "https://lyricsplus.prjktla.workers.dev"
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    // MARK: - Entry point

    func fetch(track: Track, completion: @escaping (LyricsResult?, String?) -> Void) {
        let duration = track.durationSeconds ?? 0
        let title = LyricsService.searchTitle(track.title)
        let artist = LyricsService.searchArtist(track.artist)

        lrcRed(title: title, artist: artist, duration: duration) { [weak self] result in
            if let result = result, !result.lines.isEmpty {
                completion(result, nil)
                return
            }
            self?.lyricsPlus(title: title, artist: artist, duration: duration) { result in
                if let result = result, !result.lines.isEmpty {
                    completion(result, nil)
                    return
                }
                self?.unison(title: title, artist: artist, duration: duration) { result in
                    if let result = result, !result.lines.isEmpty {
                        completion(result, nil)
                        return
                    }
                    self?.lrcLib(track: track, completion: completion)
                }
            }
        }
    }

    // MARK: - lrc.red (Apple TTML)

    private func lrcRed(title: String,
                        artist: String,
                        duration: Double,
                        completion: @escaping (LyricsResult?) -> Void) {
        let query = "\(title) \(artist)".trimmingCharacters(in: .whitespaces)
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(lrcRedBase)/search.json?q=\(encoded)") else {
            completion(nil)
            return
        }
        getJSON(url) { [weak self] json in
            guard let self = self,
                  let object = json as? [String: Any],
                  let hits = object["hits"] as? [[String: Any]] else {
                completion(nil)
                return
            }
            guard let hit = self.bestHit(hits, title: title, artist: artist, duration: duration),
                  let isrc = hit["isrc"] as? String,
                  let documentURL = URL(string: "\(self.lrcRedBase)/s/\(isrc.uppercased()).ttml") else {
                completion(nil)
                return
            }
            self.getText(documentURL) { ttml in
                guard let ttml = ttml else {
                    completion(nil)
                    return
                }
                let lines = TTMLLyrics.parse(ttml)
                completion(lines.isEmpty ? nil : LyricsResult(lines: lines, isSynced: true, source: "lrc.red"))
            }
        }
    }

    /// The hit that is this recording. A wrong-word match scrolling in time with
    /// the right song is worse than no lyrics, so title, version and artist must
    /// all agree; length only breaks ties.
    private func bestHit(_ hits: [[String: Any]],
                         title: String,
                         artist: String,
                         duration: Double) -> [String: Any]? {
        let wantTitle = LyricsService.normalized(title)
        let wantArtist = LyricsService.normalized(artist)
        var best: [String: Any]?
        var bestDistance = Double.greatestFiniteMagnitude
        for hit in hits {
            guard let isrc = hit["isrc"] as? String, !isrc.isEmpty,
                  let hitTitle = hit["title"] as? String,
                  LyricsService.normalized(hitTitle) == wantTitle else { continue }
            if !wantArtist.isEmpty {
                let hitArtist = LyricsService.normalized(hit["artist"] as? String ?? "")
                if !hitArtist.contains(wantArtist) && !wantArtist.contains(hitArtist) { continue }
            }
            let hitDuration = (hit["duration"] as? Double) ?? -1
            let distance = (duration > 0 && hitDuration > 0) ? abs(hitDuration - duration) : 0
            if duration > 0 && hitDuration > 0 && distance > 4 { continue }
            if distance < bestDistance {
                bestDistance = distance
                best = hit
            }
        }
        return best
    }

    // MARK: - LyricsPlus (Apple/QQ syllables via community mirrors)

    private func lyricsPlus(title: String,
                            artist: String,
                            duration: Double,
                            completion: @escaping (LyricsResult?) -> Void) {
        attemptMirror(index: 0, title: title, artist: artist, duration: duration, completion: completion)
    }

    private func attemptMirror(index: Int,
                               title: String,
                               artist: String,
                               duration: Double,
                               completion: @escaping (LyricsResult?) -> Void) {
        let mirrors = LyricsService.lyricsPlusMirrors
        guard index < mirrors.count else {
            completion(nil)
            return
        }
        var components = URLComponents(string: mirrors[index] + "/v2/lyrics/get")
        var items = [URLQueryItem(name: "title", value: title),
                     URLQueryItem(name: "artist", value: artist)]
        if duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            completion(nil)
            return
        }
        getJSON(url) { [weak self] json in
            guard let self = self else { return }
            if let object = json as? [String: Any],
               let lines = object["lyrics"] as? [[String: Any]] {
                let parsed = self.parseLyricsPlus(lines)
                if !parsed.isEmpty {
                    completion(LyricsResult(lines: parsed, isSynced: true, source: "LyricsPlus"))
                    return
                }
            }
            self.attemptMirror(index: index + 1, title: title, artist: artist,
                               duration: duration, completion: completion)
        }
    }

    private func parseLyricsPlus(_ lines: [[String: Any]]) -> [WordLyricLine] {
        var output: [WordLyricLine] = []
        for line in lines {
            guard let startMs = line["time"] as? Double else { continue }
            let syllables = (line["syllabus"] as? [[String: Any]]) ?? []
            if !syllables.isEmpty {
                if let built = LyricsService.line(fromSyllables: syllables, startMs: startMs) {
                    output.append(built)
                }
            } else if let text = line["text"] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                let duration = (line["duration"] as? Double) ?? 0
                output.append(WordLyricLine(time: startMs / 1000,
                                            text: text.trimmingCharacters(in: .whitespaces),
                                            words: [],
                                            end: duration > 0 ? (startMs + duration) / 1000 : nil))
            }
        }
        return output.sorted { $0.time < $1.time }
    }

    /// Syllables carry the spacing: `"e"` then `"nough "` is one word, so a
    /// syllable ending in whitespace closes the word it belongs to.
    static func line(fromSyllables syllables: [[String: Any]], startMs: Double) -> WordLyricLine? {
        var text = ""
        var words: [LyricWord] = []
        var wordStart = -1.0
        var wordEnd = -1.0
        var wordStartChar = 0
        var wordText = ""
        var wordSyllables: [LyricSyllable] = []

        for syllable in syllables {
            guard let piece = syllable["text"] as? String, !piece.isEmpty else { continue }
            guard let started = syllable["time"] as? Double, started >= 0 else { continue }
            let duration = (syllable["duration"] as? Double) ?? 0

            if wordStart < 0 {
                wordStart = started
                wordStartChar = text.count
                wordText = ""
                wordSyllables = []
            }

            let startChar = text.count
            text += piece
            wordText += piece
            wordEnd = started + duration
            wordSyllables.append(LyricSyllable(start: started / 1000,
                                               end: (started + duration) / 1000,
                                               startChar: startChar,
                                               endChar: text.count))

            if piece.last?.isWhitespace == true {
                words.append(LyricWord(start: wordStart / 1000,
                                       end: max(wordStart, wordEnd) / 1000,
                                       text: wordText,
                                       startChar: wordStartChar,
                                       endChar: text.count,
                                       syllables: wordSyllables))
                wordStart = -1
                wordText = ""
                wordSyllables = []
            }
        }

        if wordStart >= 0, !wordText.isEmpty {
            words.append(LyricWord(start: wordStart / 1000,
                                   end: max(wordStart, wordEnd) / 1000,
                                   text: wordText,
                                   startChar: wordStartChar,
                                   endChar: text.count,
                                   syllables: wordSyllables))
        }

        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var end = startMs / 1000
        for syllable in syllables {
            if let started = syllable["time"] as? Double {
                end = max(end, (started + ((syllable["duration"] as? Double) ?? 0)) / 1000)
            }
        }
        return WordLyricLine(time: startMs / 1000, text: text, words: words, end: end)
    }

    // MARK: - Unison (contributed)

    private func unison(title: String,
                        artist: String,
                        duration: Double,
                        completion: @escaping (LyricsResult?) -> Void) {
        var components = URLComponents(string: "https://unison.boidu.dev/lyrics")
        var items = [URLQueryItem(name: "song", value: title),
                     URLQueryItem(name: "artist", value: artist)]
        if duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            completion(nil)
            return
        }
        getJSON(url) { [weak self] json in
            guard let self = self,
                  let object = json as? [String: Any],
                  (object["success"] as? Bool) == true,
                  let data = object["data"] as? [String: Any],
                  let text = data["lyrics"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(nil)
                return
            }
            let format = ((data["format"] as? String) ?? "").lowercased()
            let lines = format.contains("ttml")
                ? TTMLLyrics.parse(text)
                : self.parseLRC(text)
            completion(lines.isEmpty
                ? nil
                : LyricsResult(lines: lines, isSynced: true, source: "Unison"))
        }
    }

    // MARK: - LRCLIB (whole lines)

    private func lrcLib(track: Track, completion: @escaping (LyricsResult?, String?) -> Void) {
        var items = [URLQueryItem(name: "track_name", value: track.title)]
        if !track.artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: track.artist))
        }
        if let duration = track.durationSeconds {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = items
        guard let url = components?.url else {
            completion(nil, "No lyrics found.")
            return
        }
        getJSON(url) { [weak self] json in
            guard let self = self else { return }
            let object = json as? [String: Any]
            if let synced = object?["syncedLyrics"] as? String, !synced.isEmpty {
                let lines = self.parseLRC(synced)
                if !lines.isEmpty {
                    completion(LyricsResult(lines: lines, isSynced: true, source: "LRCLIB"), nil)
                    return
                }
            }
            if let plain = object?["plainLyrics"] as? String, !plain.isEmpty {
                let lines = plain.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .map { WordLyricLine(time: 0, text: $0, words: [], end: nil) }
                if !lines.isEmpty {
                    completion(LyricsResult(lines: lines, isSynced: false, source: "LRCLIB"), nil)
                    return
                }
            }
            self.searchLrcLib(track: track, completion: completion)
        }
    }

    private func searchLrcLib(track: Track, completion: @escaping (LyricsResult?, String?) -> Void) {
        let query = "\(track.title) \(track.artist)".trimmingCharacters(in: .whitespaces)
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else {
            completion(nil, "No lyrics found.")
            return
        }
        getJSON(url) { [weak self] json in
            guard let self = self, let entries = json as? [[String: Any]] else {
                completion(nil, "No lyrics found.")
                return
            }
            for entry in entries {
                if let synced = entry["syncedLyrics"] as? String, !synced.isEmpty {
                    let lines = self.parseLRC(synced)
                    if !lines.isEmpty {
                        completion(LyricsResult(lines: lines, isSynced: true, source: "LRCLIB"), nil)
                        return
                    }
                }
            }
            completion(nil, "No lyrics found.")
        }
    }

    // MARK: - LRC

    func parseLRC(_ text: String) -> [WordLyricLine] {
        var lines: [WordLyricLine] = []
        let pattern = "\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let nsLine = line as NSString
            let matches = regex.matches(in: line, options: [],
                                        range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }

            var body = regex.stringByReplacingMatches(in: line, options: [],
                                                      range: NSRange(location: 0, length: nsLine.length),
                                                      withTemplate: "")
            // Enhanced LRC word tags are stripped: this path is line-synced only.
            body = body.replacingOccurrences(of: "<\\d{1,3}:\\d{2}(?:[.:]\\d{1,3})?>",
                                             with: "", options: .regularExpression)
            body = body.trimmingCharacters(in: .whitespaces)
            if body.isEmpty { continue }

            for match in matches {
                guard let minutes = Double(nsLine.substring(with: match.range(at: 1))),
                      let seconds = Double(nsLine.substring(with: match.range(at: 2))) else { continue }
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let value = Double(nsLine.substring(with: match.range(at: 3))) {
                    fraction = value / pow(10.0, Double(nsLine.substring(with: match.range(at: 3)).count))
                }
                lines.append(WordLyricLine(time: minutes * 60 + seconds + fraction,
                                           text: body, words: [], end: nil))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    // MARK: - Text helpers

    /// Strips the noise a catalogue title carries that the lyrics database does
    /// not: bracketed suffixes and trailing "feat." credits.
    static func searchTitle(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[[^]]*\\]", with: " ", options: .regularExpression)
        if let range = text.range(of: " - ", options: .literal) {
            text = String(text[text.startIndex..<range.lowerBound])
        }
        return text.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    static func searchArtist(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        if let range = text.range(of: " & ", options: .literal) {
            text = String(text[text.startIndex..<range.lowerBound])
        }
        if let range = text.range(of: ", ", options: .literal) {
            text = String(text[text.startIndex..<range.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func normalized(_ text: String) -> String {
        let lower = text.lowercased()
        let scalars = lower.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) || $0 == " " ? Character($0) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    // MARK: - Transport

    private func getJSON(_ url: URL, completion: @escaping (Any?) -> Void) {
        session.dataTask(with: url) { data, _, _ in
            var object: Any?
            if let data = data, !data.isEmpty {
                object = try? JSONSerialization.jsonObject(with: data, options: [])
            }
            DispatchQueue.main.async { completion(object) }
        }.resume()
    }

    private func getText(_ url: URL, completion: @escaping (String?) -> Void) {
        session.dataTask(with: url) { data, _, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            DispatchQueue.main.async { completion(text) }
        }.resume()
    }
}
