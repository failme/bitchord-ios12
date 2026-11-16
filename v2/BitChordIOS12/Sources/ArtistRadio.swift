import Foundation

/// Artist radio. A profile with popular songs seeds directly from the first
/// one; an empty or pending profile searches the artist name first, so the
/// Radio action still works when the catalogue has no songs to show.
enum ArtistRadio {
    static func mix(artistName: String,
                    topSongs: [Track],
                    completion: @escaping ([Track]?) -> Void) {
        if let seed = topSongs.first {
            RadioService.mix(from: seed, completion: completion)
            return
        }
        let name = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            completion(nil)
            return
        }
        InnerTube.shared.search(name, filter: .songs) { tracks, _ in
            guard let seed = tracks?.first(where: { RadioService.isYouTubeVideoID($0.videoID) })
                ?? tracks?.first else {
                completion(nil)
                return
            }
            RadioService.mix(from: seed, completion: completion)
        }
    }
}
