import Foundation

/// A PLACE IN A PLAN, OPENED: the place under a thing tapped goes to the Map and opens it: the town's page when the
/// town is one of ours (in that country first), else the country on the map. The plan stays as it was in Lists.
@MainActor
enum PlanPlaces {
    static func open(_ place: String, cc: String?) {
        guard let map = AIContext.map else { return }
        Feel.tap()
        Task {
            var url: URL?
            let name = place.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? place
            if !name.isEmpty {
                TownIndex.shared.load()
                for _ in 0 ..< 50 where !TownIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                let hits = TownIndex.shared.hits(name, open: cc, limit: 12)
                let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
                let inCountry = hits.filter { cc == nil || $0.file.lowercased() == cc!.lowercased() }
                let page = { (k: PlaceKey) in URL(string: "wya://page/" + (k.description.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")) }
                // (a town of some size: "Pasta" in a list of dishes is not the hamlet of Pasta near Turin, as the list's map)
                if let t = inCountry.first(where: { fold($0.name) == fold(name) && $0.people >= 1_000 }) {
                    url = page(PlaceKey(.town, t.id))
                } else {
                    // A SIGHT OF THAT NAME IN THAT COUNTRY: its own page, before a town that only starts like it
                    ThingIndex.shared.load()
                    for _ in 0 ..< 80 where !ThingIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    let things = ThingIndex.shared.hits(name, open: cc, limit: 6, near: false)
                    if let h = things.first(where: { (cc == nil || $0.file.lowercased() == cc!.lowercased()) && fold($0.name) == fold(name) }) {
                        url = page(PlaceKey(.thing, "wd:" + h.id))
                    } else if let t = inCountry.first(where: { $0.people >= 1_000 }) {
                        url = page(PlaceKey(.town, t.id))
                    }
                }
            }
            if url == nil, let cc, !cc.isEmpty { url = URL(string: "wya://country/\(cc.lowercased())") }
            guard let u = url else { Feel.refuse(); return }
            NotificationCenter.default.post(name: Notification.Name("wyaTestTab"), object: 0)
            try? await Task.sleep(for: .milliseconds(350))
            await DeepLink.open(u, map: map) {}
        }
    }
}
