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
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL?) -> UIImage? {
        guard let key = url?.absoluteString else { return nil }
        return cache.object(forKey: key as NSString)
    }

    @discardableResult
    func load(_ url: URL?, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        guard let url = url else {
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
