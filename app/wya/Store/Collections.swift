import Foundation
import simd

/// COLLECTIONS (7.2, D7): named lists people tick off, each from its authoritative source, read once from the data server
/// (`native/collections/collections-2.wyco`). Each item is a place (a thing's key, `m:wd:Q…`) with its point; an event
/// collection's items are dated stops ("12 Jul 2026 · Silverstone"). Only the easy ones for now (29 Oct 20:30:
/// "Just do the easy stuff for now. So like, for example, F1 is easy").
@MainActor
@Observable
final class CollectionStore {
    static let shared = CollectionStore()
    struct Item: Hashable {
        let id: String
        let name: String
        let cc: String
        let at: SIMD2<Float>
        /// an event stop's day ("2026-07-05") and its name ("British Grand Prix"), or ""
        let date: String
        let label: String
        var key: PlaceKey { PlaceKey(.thing, "wd:" + id) }
    }
    struct Collection: Hashable {
        let id: String
        let title: String
        /// "world", or a country's id its places are all in
        let scope: String
        let event: Bool
        let source: String
        let items: [Item]
    }
    private(set) var all: [Collection] = []
    private(set) var ready = false
    @ObservationIgnored private var loading = false

    func collection(_ id: String) -> Collection? { all.first { $0.id == id } }

    func load() {
        guard !ready, !loading else { return }
        loading = true
        Task.detached(priority: .utility) {
            var out: [Collection] = []
            if case .ok(let d) = await Servers.data.file("native/collections/collections-2.wyco"),
               let raw = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
                for c in raw {
                    guard let id = c["id"] as? String, let t = c["title"] as? String, let items = c["items"] as? [[String: Any]] else { continue }
                    let its: [Item] = items.compactMap { i in
                        guard let q = i["q"] as? String, let n = i["n"] as? String, let ll = i["ll"] as? [NSNumber], ll.count == 2 else { return nil }
                        return Item(id: q, name: n, cc: (i["cc"] as? String ?? "").lowercased(),
                                    at: EqualEarth.project(lon: ll[1].doubleValue, lat: ll[0].doubleValue),
                                    date: i["d"] as? String ?? "", label: i["l"] as? String ?? "")
                    }
                    out.append(Collection(id: id, title: t, scope: c["scope"] as? String ?? "world", event: c["event"] as? Bool ?? false,
                                          source: c["source"] as? String ?? "", items: its))
                }
            }
            await MainActor.run {
                let me = CollectionStore.shared
                me.all = out
                me.loading = false
                me.ready = true
            }
        }
    }

    /// a stop's line ("5 Jul 2026 · British Grand Prix")
    static func line(_ i: Item) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "yyyy-MM-dd"
        let day = f.date(from: i.date).map { $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? ""
        return [day, i.label].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
