import Foundation

enum TrackSource: String, Codable {
    case youtube = "YouTube"
    case library = "Library"
    case addon = "Addons"
}

/// Mirrors the upstream `Track` model so library, playlist and player code can share one shape.
struct Track: Codable, Hashable {
    var videoID: String
    var title: String
    var artist: String
    var album: String = ""
    var durationSeconds: Double?
    var isLossless: Bool = false
    var sampleRate: Double?
    var bitDepth: Int?
    var source: TrackSource?
    var sourceId: String?

    var id: String { return videoID }

    var durationText: String {
        return formattedDuration
    }

    var formattedDuration: String {
        let total = Int(durationSeconds ?? 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Matches the badge strings upstream shows under the artwork.
    var audioBadge: String {
        guard isLossless else { return "AAC" }
        if let rate = sampleRate, let depth = bitDepth, rate > 48000 {
            return String(format: "HI-RES LOSSLESS %d-bit/%.1f kHz", depth, rate / 1000.0)
        }
        return "LOSSLESS"
    }

    var displayAudioQualityBadge: String {
        guard isLossless else { return "High Quality" }
        if (sampleRate ?? 0) > 48000 || (bitDepth ?? 0) > 16 {
            return "Hi-Res Lossless"
        }
        return "Lossless"
    }

    var artworkURL: URL? {
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
    }

    var largeArtworkURL: URL? {
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }
}
