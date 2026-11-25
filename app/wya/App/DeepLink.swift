import Foundation
import CoreGraphics

/// LINKS INTO THE MAP (Part 19.6): `wya://place/<id>` and `wya://country/<id>` open the Map and fly to the place
/// exactly as a search result does, through the same action (`map.show`, source `link`). Everything transient closes
/// first, keeping its changes, as a tab change does; a locked map still flies (looking is allowed); no haptic (no
/// finger touched the app). From a cold launch the camera is framed on the place before the loading screen lifts, so
/// no flight from home is seen. An unknown id or kind leaves the app where it was and is logged.
/// `wya://list|plan|tier|book/<id>` open that one in Lists. Not here yet (logged): settings links, universal links.
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
        // A LIST'S, PLAN'S, TIER LIST'S OR BOOK'S LINK (`wya://plan/<id>`, the lock screen's plan tapped, PlanLive;
        // `wya://list/<id>`, Siri's Open a list; `wya://tier/<id>`, `wya://book/<id>`): Lists, that kind, that one open
        if url.scheme?.lowercased() == "wya", let host = url.host?.lowercased(), ["list", "plan", "tier", "book"].contains(host) {
            let id = url.pathComponents.dropFirst().first ?? ""
            let b = ListsStore.shared.book
            let kind: Int? = switch host {
            case "list": b.lists.contains { $0.id == id } ? 0 : nil
            case "plan": b.plans.contains { $0.id == id } ? 1 : nil
            case "tier": b.tiers.contains { $0.id == id } ? 2 : nil
            default: b.books.contains { $0.id == id } ? 3 : nil
            }
            guard let kind else {
                NSLog("wya link not opened: %@", url.absoluteString)
                return false
            }
            close()
            NotificationCenter.default.post(name: Notification.Name("wyaTestTab"), object: 1)
            ListsState.shared.kind = kind
            ListsState.shared.open = id
            return true
        }
        // A PAGE'S LINK (16.6's Share, 19.6): `wya://page/<key>` (c:it, t:de/2925533, m:wd:Q19675): the page opened over
        // the Map as it is, growing from the screen's middle
        if url.scheme?.lowercased() == "wya", url.host?.lowercased() == "page" {
            let raw = url.pathComponents.dropFirst().joined(separator: "/")
            guard let key = PlaceKey(raw.removingPercentEncoding ?? raw), let w = map.world else { return false }
            let from = CGRect(x: map.view.width / 2 - 22, y: map.view.height / 2 - 22, width: 44, height: 44)
            switch key.kind {
            case .country:
                guard let i = w.placeIndex[key.id.lowercased()] else { return false }
                close(); await PlacePageState.shared.closeAllAndWait()
                PlacePageState.shared.open(key, name: w.places[i].n, country: w.places[i].id, from: from)
            case .town:
                TownIndex.shared.load()
                for _ in 0 ..< 150 where !TownIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                guard let t = TownIndex.shared.hit(key.id) else { return false }
                let country = w.placeIndex[t.file].map { w.places[$0].n } ?? ""
                close(); await PlacePageState.shared.closeAllAndWait()
                PlacePageState.shared.open(key, name: t.name, what: t.region.isEmpty ? "Town in \(country)" : "Town in \(t.region), \(country)",
                                           country: t.file, from: from)
            case .thing:
                ThingIndex.shared.load()
                for _ in 0 ..< 150 where !ThingIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                guard let h = ThingIndex.shared.hit(key.id) else { return false }
                ThingStore.shared.load(h.file)
                close(); await PlacePageState.shared.closeAllAndWait()
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
