import Foundation
import CoreGraphics

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
        // A PAGE'S LINK (16.6's Share, 19.6): `wya://page/<key>` (c:it, t:de/2925533, m:wd:Q19675): the page opened over
        // the Map as it is, growing from the screen's middle
        if url.scheme?.lowercased() == "wya", url.host?.lowercased() == "page" {
            let raw = url.pathComponents.dropFirst().joined(separator: "/")
            guard let key = PlaceKey(raw.removingPercentEncoding ?? raw), let w = map.world else { return false }
            let from = CGRect(x: map.view.width / 2 - 22, y: map.view.height / 2 - 22, width: 44, height: 44)
            switch key.kind {
            case .country:
                guard let i = w.placeIndex[key.id.lowercased()] else { return false }
                close(); PlacePageState.shared.closeAll()
                PlacePageState.shared.open(key, name: w.places[i].n, country: w.places[i].id, from: from)
            case .town:
                TownIndex.shared.load()
                for _ in 0 ..< 150 where !TownIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                guard let t = TownIndex.shared.hit(key.id) else { return false }
                let country = w.placeIndex[t.file].map { w.places[$0].n } ?? ""
                close(); PlacePageState.shared.closeAll()
                PlacePageState.shared.open(key, name: t.name, what: t.region.isEmpty ? "Town in \(country)" : "Town in \(t.region), \(country)",
                                           country: t.file, from: from)
            case .thing:
                ThingIndex.shared.load()
                for _ in 0 ..< 150 where !ThingIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                guard let h = ThingIndex.shared.hit(key.id) else { return false }
                ThingStore.shared.load(h.file)
                close(); PlacePageState.shared.closeAll()
                PlacePageState.shared.open(key, name: h.name, country: h.file, from: from)
            default:
                NSLog("wya link not opened: %@", url.absoluteString)
                return false
            }
            return true
        }
        guard let id = place(url, map: map) else {
            NSLog("wya link not opened: %@", url.absoluteString)
            return false
        }
        close()
        return await Actions.shared.perform("map.show", id, source: .link)
    }
}
