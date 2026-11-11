import Foundation

/// Parses the Apple Music TTML that lrc.red serves.
///
/// The document is a sequence of `<p begin="…" end="…">` lines, each holding
/// either plain text or `<span begin="…" end="…">` syllables — Apple splits
/// long words, so `"e"` and `"nough"` arrive as two spans of one word and are
/// drawn as one. Those spans are what makes the karaoke follow the voice rather
/// than a guess across the line.
enum TTMLLyrics {

    static func parse(_ document: String) -> [WordLyricLine] {
        var lines: [WordLyricLine] = []
        let pattern = "<p\\b([^>]*)>(.*?)</p>"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = document as NSString
        for match in regex.matches(in: document, options: [], range: NSRange(location: 0, length: ns.length)) {
            let attributes = ns.substring(with: match.range(at: 1))
            let body = ns.substring(with: match.range(at: 2))
            guard let begin = seconds(in: attributes, key: "begin") else { continue }
            let end = seconds(in: attributes, key: "end")
            if let line = line(begin: begin, end: end, body: body) {
                lines.append(line)
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private static func line(begin: Double, end: Double?, body: String) -> WordLyricLine? {
        let syllables = spans(in: body)
        if syllables.isEmpty {
            let text = decode(stripTags(body)).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return WordLyricLine(time: begin, text: text, words: [], end: end)
        }
        return LyricsService.line(fromSyllables: syllables.map { $0.asDictionary },
                                  startMs: begin * 1000)
    }

    /// `<span begin="1.2" end="1.6">e</span>` plus any loose text between them.
    private static func spans(in body: String) -> [(begin: Double, end: Double, text: String, asDictionary: [String: Any])] {
        var result: [(Double, Double, String, [String: Any])] = []
        let pattern = "<span\\b([^>]*)>(.*?)</span>"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = body as NSString
        for match in regex.matches(in: body, options: [], range: NSRange(location: 0, length: ns.length)) {
            let attributes = ns.substring(with: match.range(at: 1))
            guard let begin = seconds(in: attributes, key: "begin"),
                  let finish = seconds(in: attributes, key: "end") else { continue }
            let text = decode(stripTags(ns.substring(with: match.range(at: 2))))
            guard !text.isEmpty else { continue }
            result.append((begin, finish, text,
                           ["time": begin * 1000, "duration": max(0, finish - begin) * 1000, "text": text]))
        }
        return result
    }

    private static func seconds(in attributes: String, key: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "\(key)=\"([^\"]+)\"") else { return nil }
        let ns = attributes as NSString
        guard let match = regex.firstMatch(in: attributes, options: [],
                                           range: NSRange(location: 0, length: ns.length)) else { return nil }
        let raw = ns.substring(with: match.range(at: 1))
        // Apple writes either `12.345` or `00:00:12.345`.
        let pieces = raw.split(separator: ":")
        if pieces.count == 3 {
            guard let hours = Double(pieces[0]), let minutes = Double(pieces[1]),
                  let seconds = Double(pieces[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        }
        if pieces.count == 2 {
            guard let minutes = Double(pieces[0]), let seconds = Double(pieces[1]) else { return nil }
            return minutes * 60 + seconds
        }
        return Double(raw)
    }

    private static func stripTags(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func decode(_ text: String) -> String {
        var out = text
        let entities = [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                        ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " ")]
        for (entity, value) in entities {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        return out
    }
}
