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
                if let t = inCountry.first(where: { fold($0.name) == fold(name) }) ?? inCountry.first {
                    url = URL(string: "wya://page/" + (PlaceKey(.town, t.id).description.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))
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
