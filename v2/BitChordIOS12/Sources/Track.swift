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
    /// Whether the catalogue flagged the track explicit (Apple-style E badge).
    var isExplicit = false
    /// Catalogue artwork. A JioSaavn row has no YouTube id to derive a
    /// thumbnail from, so the URL travels with the track instead.
    var artwork: String?

    var id: String { return videoID }

    var durationText: String {
        return formattedDuration
    }

    var formattedDuration: String {
        // A catalogue row that states no length shows none. Printing 0:00 for
        // an unknown duration made whole result lists look broken.
        guard let seconds = durationSeconds, seconds > 0 else { return "" }
        let total = Int(seconds)
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
        if let artwork = artwork, let url = URL(string: artwork) { return url }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
    }

    var largeArtworkURL: URL? {
        return artworkURL
    }
}
