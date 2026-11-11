import Foundation

/// Parses the Apple Music TTML that lrc.red serves.
///
/// A document is a sequence of `<p begin="…" end="…">` lines, each holding
/// `<span begin="…" end="…">` runs. Apple writes one span per word, and splits
/// long words into several spans (`"e"` then `"nough"`); the whitespace that
/// separates two words is loose text *between* the spans, not inside them, so
/// it has to be carried over explicitly or the line comes out as "Theclub".
///
/// Those span timings are the whole point: they are what lets the sweep follow
/// the voice instead of guessing at a pace across the line.
enum TTMLLyrics {

    static func parse(_ document: String) -> [WordLyricLine] {
        var lines: [WordLyricLine] = []
        let pattern = "<p\b([^>]*)>(.*?)</p>"
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
        let runs = spans(in: body)
        if runs.isEmpty {
            let text = decode(stripTags(body)).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return WordLyricLine(time: begin, text: text, words: [], end: end)
        }
        return LyricsService.line(fromSyllables: runs, startMs: begin * 1000)
    }

    /// Each timed run, with the document's own inter-span whitespace appended
    /// to the run it follows — that separator is what marks a word boundary.
    private static func spans(in body: String) -> [[String: Any]] {
        let pattern = "<span\b([^>]*)>(.*?)</span>"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = body as NSString
        let matches = regex.matches(in: body, options: [],
                                    range: NSRange(location: 0, length: ns.length))
        var runs: [(time: Double, duration: Double, text: String)] = []
        var cursor = 0

        for match in matches {
            let gap: String
            if cursor < match.range.location {
                gap = ns.substring(with: NSRange(location: cursor,
                                                 length: match.range.location - cursor))
            } else {
                gap = ""
            }
            cursor = match.range.location + match.range.length

            let attributes = ns.substring(with: match.range(at: 1))
            guard let begin = seconds(in: attributes, key: "begin"),
                  let finish = seconds(in: attributes, key: "end") else { continue }
            let piece = decode(stripTags(ns.substring(with: match.range(at: 2))))
            if piece.isEmpty { continue }

            if gap.rangeOfCharacter(from: .whitespacesAndNewlines) != nil, !runs.isEmpty {
                if !runs[runs.count - 1].text.hasSuffix(" ") {
                    runs[runs.count - 1].text += " "
                }
            }
            runs.append((begin, max(0, finish - begin), piece))
        }

        if cursor < ns.length, !runs.isEmpty {
            let tail = ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
            if tail.rangeOfCharacter(from: .whitespacesAndNewlines) != nil,
               !runs[runs.count - 1].text.hasSuffix(" ") {
                runs[runs.count - 1].text += " "
            }
        }

        var output: [[String: Any]] = []
        for run in runs {
            output.append(["time": run.time * 1000,
                           "duration": run.duration * 1000,
                           "text": run.text])
        }
        return output
    }

    private static func seconds(in attributes: String, key: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "\(key)=\"([^\"]+)\"") else {
            // The interpolation above is written out below; this branch only
            // exists so a bad pattern fails closed rather than crashing.
            return nil
        }
        let ns = attributes as NSString
        guard let match = regex.firstMatch(in: attributes, options: [],
                                           range: NSRange(location: 0, length: ns.length)) else { return nil }
        let raw = ns.substring(with: match.range(at: 1))
        // Apple writes either a plain second count or `hh:mm:ss.sss`.
        let pieces = raw.split(separator: ":")
        if pieces.count == 3 {
            guard let hours = Double(pieces[0]), let minutes = Double(pieces[1]),
                  let secs = Double(pieces[2]) else { return nil }
            return hours * 3600 + minutes * 60 + secs
        }
        if pieces.count == 2 {
            guard let minutes = Double(pieces[0]), let secs = Double(pieces[1]) else { return nil }
            return minutes * 60 + secs
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
