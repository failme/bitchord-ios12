import Foundation

struct Track {
    let videoID: String
    let title: String
    let artist: String
    let durationSeconds: Double?

    var durationText: String {
        guard let d = durationSeconds else { return "" }
        return Theme.format(d)
    }

    var artworkURL: URL? {
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
    }

    var largeArtworkURL: URL? {
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }
}
