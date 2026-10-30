import Foundation

/// LINKS INTO THE MAP (Part 19.6): `wya://place/<id>` and `wya://country/<id>` open the Map and fly to the place
/// exactly as a search result does, through the same action (`map.show`, source `link`). Everything transient closes
/// first, keeping its changes, as a tab change does; a locked map still flies (looking is allowed); no haptic (no
/// finger touched the app). From a cold launch the camera is framed on the place before the loading screen lifts, so
/// no flight from home is seen. An unknown id or kind leaves the app where it was and is logged.
/// Not here yet (logged): `wya://page/<id>` (place pages, Step 12), plans, lists and books (Lists), settings links,
/// universal links.
@MainActor
enum DeepLink {
    /// a link that came before the map was ready (a cold launch): opened once it is, under the loading screen
    static var waiting: URL?

    /// the place's index for a link the Map can open, or nil
    static func place(_ url: URL, map: MapController) -> String? {
        guard url.scheme?.lowercased() == "wya", let kind = url.host?.lowercased(), kind == "place" || kind == "country",
              let id = url.pathComponents.dropFirst().first?.lowercased(), map.world?.placeIndex[id] != nil else { return nil }
        return id
    }

    /// open it now (the map is ready): `close` puts away whatever is out; true when it was opened
    @discardableResult
    static func open(_ url: URL, map: MapController, close: () -> Void) async -> Bool {
        guard map.ready else { waiting = url; return false }
        guard let id = place(url, map: map) else {
            NSLog("wya link not opened: %@", url.absoluteString)
            return false
        }
        close()
        return await Actions.shared.perform("map.show", id, source: .link)
    }
}
