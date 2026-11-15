import Foundation

/// Bilingual-lyrics translation using the public MyMemory endpoint (no key for
/// its anonymous quota). Results are cached per language and source line; a
/// failed request leaves the original line in place rather than hiding the
/// lyrics.
final class TranslationService {
    static let shared = TranslationService()

    private var cache: [String: String] = [:]
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    static func code(for language: String) -> String? {
        switch language {
        case "English": return "en"
        case "हिन्दी": return "hi"
        case "Español": return "es"
        case "Français": return "fr"
        default: return nil
        }
    }

    func translate(lines: [String], to language: String,
                   completion: @escaping ([String]) -> Void) {
        guard let code = TranslationService.code(for: language), !lines.isEmpty else {
            completion(lines)
            return
        }
        let group = DispatchGroup()
        var output = lines
        let lock = NSLock()
        for (index, line) in lines.enumerated() where !line.isEmpty {
            let key = "\(code)|\(line)"
            if let cached = cache[key] {
                output[index] = cached
                continue
            }
            group.enter()
            translateOne(line, code: code) { translated in
                if let translated = translated {
                    lock.lock()
                    self.cache[key] = translated
                    output[index] = translated
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(output)
        }
    }

    private func translateOne(_ text: String, code: String,
                              completion: @escaping (String?) -> Void) {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "en|\(code)")
        ]
        guard let url = components.url else {
            completion(nil)
            return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let response = json["responseData"] as? [String: Any],
                  let translated = response["translatedText"] as? String,
                  !translated.isEmpty else {
                completion(nil)
                return
            }
            completion(translated)
        }.resume()
    }

    func selfTest() -> String {
        let codes = ["English", "हिन्दी", "Español", "Français"].compactMap(TranslationService.code(for:))
        return "targets=\(codes.joined(separator: ",")) cache=\(cache.count)"
    }
}
