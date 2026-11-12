import UIKit

final class ArtworkLoader {
    static let shared = ArtworkLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        cache.countLimit = 200
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .returnCacheDataElseLoad
        // The catalogue's CDN wants a browser agent and referer, otherwise it
        // refuses a good share of the covers.
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
            "Referer": "https://www.jiosaavn.com/",
            "Accept": "image/jpeg,image/png,image/*;q=0.8"
        ]
        session = URLSession(configuration: config)
    }

    /// The URL an image should actually be fetched from.
    ///
    /// The catalogue now hands out `-150x150.webp` for most rows, and iOS 12
    /// has no WebP decoder, so every one of those covers failed to draw. The
    /// same object is served as a 500x500 JPEG under the same path, which every
    /// device here can decode — so the extension is swapped and the size lifted.
    static func normalized(_ url: URL?) -> URL? {
        guard let text = url?.absoluteString else { return nil }
        var out = text
        if out.lowercased().hasSuffix(".webp") {
            out = String(out.dropLast(5)) + ".jpg"
        }
        for size in ["50x50", "150x150", "250x250"] {
            out = out.replacingOccurrences(of: size, with: "500x500")
        }
        return URL(string: out)
    }

    func cached(_ url: URL?) -> UIImage? {
        guard let key = ArtworkLoader.normalized(url)?.absoluteString else { return nil }
        return cache.object(forKey: key as NSString)
    }

    @discardableResult
    func load(_ url: URL?, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        guard let url = ArtworkLoader.normalized(url) else {
            completion(nil)
            return nil
        }
        if let hit = cached(url) {
            completion(hit)
            return nil
        }
        let task = session.dataTask(with: url) { [weak self] data, _, _ in
            var image: UIImage?
            if let data = data, let decoded = UIImage(data: data) {
                image = decoded
                self?.cache.setObject(decoded, forKey: url.absoluteString as NSString)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
        task.resume()
        return task
    }
}
