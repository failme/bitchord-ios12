import Foundation

/// Upstream's artist screen: `BrowseType.ARTIST` on YouTube Music. The page
/// carries the artist photograph, listener count, biography, popular songs,
/// releases and related artists; the catalogue supplies all of it from one
/// artist-page request.
enum ArtistPage {
    static func make(artist: CatalogueArtist) -> ArtistViewController {
        return ArtistViewController(artist: artist)
    }
}
