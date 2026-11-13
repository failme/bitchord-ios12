import UIKit

/// One parser for the `bitchord://` scheme, shared by warm and cold launches.
///
/// Universal links need an associated-domains entitlement and iOS 13-era
/// handling, so the custom scheme is the iOS 12 substitute upstream's Android
/// intent filters map to.
enum DeepLinkRoute: Equatable {
    case home
    case track(String)
    case album(String)
    case artist(String)
    case playlist(String)
    case radio(String)
}

enum DeepLink {
    static func parse(_ url: URL) -> DeepLinkRoute? {
        guard url.scheme?.lowercased() == "bitchord" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let queryValue = { (name: String) in query.first(where: { $0.name == name })?.value }
        let host = (url.host ?? "").lowercased()

        // bitchord://open?type=track&id=... is the generic form.
        if host == "open" {
            guard let type = queryValue("type")?.lowercased(),
                  let id = queryValue("id") ?? parts.first else { return nil }
            return route(type: type, id: id)
        }
        if host.isEmpty || host == "home" {
            return .home
        }
        guard let id = parts.first ?? queryValue("id") else { return nil }
        return route(type: host, id: id)
    }

    static func route(type: String, id: String) -> DeepLinkRoute? {
        switch type {
        case "track", "song": return .track(id)
        case "album": return .album(id)
        case "artist": return .artist(id)
        case "playlist": return .playlist(id)
        case "radio": return .radio(id)
        case "home": return .home
        default: return nil
        }
    }
}

/// Routes a parsed link to the screen the app opens for it, and records what
/// ended up on top so a simulator run can be checked from outside the app.
enum DeepLinkRouter {
    static func record(_ line: String) {
        let manager = FileManager.default
        guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let directory = documents.appendingPathComponent("shots", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let file = directory.appendingPathComponent("deeplinks.txt")
        let text = line + "\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(text.data(using: .utf8) ?? Data())
            handle.closeFile()
        } else {
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    static func handle(_ url: URL, cold: Bool = false) -> String {
        guard let route = DeepLink.parse(url) else {
            record("route=invalid url=\(url.absoluteString) cold=\(cold ? 1 : 0)")
            return "invalid"
        }
        // The window's root may not exist yet on a cold launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            perform(route, cold: cold)
        }
        return describe(route)
    }

    static func describe(_ route: DeepLinkRoute) -> String {
        switch route {
        case .home: return "route=home"
        case .track(let id): return "route=track id=\(id)"
        case .album(let id): return "route=album id=\(id)"
        case .artist(let id): return "route=artist id=\(id)"
        case .playlist(let id): return "route=playlist id=\(id)"
        case .radio(let id): return "route=radio id=\(id)"
        }
    }

    private static func perform(_ route: DeepLinkRoute, cold: Bool, attempt: Int = 0) {
        guard let root = UIApplication.shared.keyWindow?.rootViewController as? RootViewController else {
            // On a cold launch the window's root may not be installed yet.
            if attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    perform(route, cold: cold, attempt: attempt + 1)
                }
            } else {
                record("route=unrouted cold=\(cold ? 1 : 0)")
            }
            return
        }
        root.dismiss(animated: false, completion: nil)
        let suffix = "cold=\(cold ? 1 : 0)"

        switch route {
        case .home:
            root.resetToHome()
            record("route=home screen=Home \(suffix)")
        case .track(let id):
            let track = sharedTrack(id)
            PlayerService.shared.play(tracks: [track], startingAt: 0)
            root.presentNowPlaying()
            record("route=track id=\(id) screen=NowPlaying \(suffix)")
        case .radio(let id):
            RadioService.start(from: sharedTrack(id), host: root)
            record("route=radio id=\(id) screen=Radio \(suffix)")
        case .album(let id):
            let page = CollectionViewController(title: "Album", subtitle: id, artwork: nil)
            page.loader = { completion in
                InnerTube.shared.fetchCollection(id) { tracks, _ in completion(tracks ?? []) }
            }
            push(page, on: root)
            record("route=album id=\(id) screen=Album \(suffix)")
        case .playlist(let id):
            let page = CollectionViewController(title: "Playlist", subtitle: id, artwork: nil)
            page.loader = { completion in
                InnerTube.shared.fetchCollection(id) { tracks, _ in completion(tracks ?? []) }
            }
            push(page, on: root)
            record("route=playlist id=\(id) screen=Playlist \(suffix)")
        case .artist(let id):
            let page = ArtistPage.make(artist: CatalogueArtist(id: id, name: "Artist", artwork: nil))
            push(page, on: root)
            record("route=artist id=\(id) screen=Artist \(suffix)")
        }
    }

    private static func push(_ controller: UIViewController, on root: RootViewController) {
        root.showTab(3)
        root.navigationForTab(3)?.pushViewController(controller, animated: false)
    }

    private static func sharedTrack(_ id: String) -> Track {
        return Track(videoID: id,
                     title: id,
                     artist: "",
                     durationSeconds: nil,
                     source: .youtube)
    }
}
