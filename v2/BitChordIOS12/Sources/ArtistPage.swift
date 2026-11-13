import Foundation

/// Upstream's artist screen: `BrowseType.ARTIST` on YouTube Music, which fills
/// the page with the artist's best-known songs. The browse id comes from the
/// artist rows search already fetched, so opening a page is one request.
enum ArtistPage {
    static func make(artist: CatalogueArtist) -> CollectionViewController {
        let controller = CollectionViewController(title: artist.name,
                                                  subtitle: "Artist",
                                                  artwork: artist.artwork)
        controller.loader = { completion in
            InnerTube.shared.fetchCollection(artist.id) { tracks, _ in
                completion(tracks ?? [])
            }
        }
        return controller
    }
}
