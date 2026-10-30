import Foundation

/// SEARCH OVER EVERY PLACE'S REGIONS (Part 1.10, D12's regions part): the first two region levels of every place
/// (52,725 regions, 54,584 names with their English names), read once from the data server (`native/regions/regions-index-2.wyri`: rows [name, place id, row,
/// region id]) the first time the map is searched. Names starting with what was typed, then (from three letters)
/// names holding it.
@MainActor
@Observable
final class RegionIndex {
    static let shared = RegionIndex()
    struct Hit: Hashable {
        let name: String
        let place: String
        let row: Int
        let id: String
        var key: String { "r:\(place)-\(row)|\(id)" }
    }
    private(set) var ready = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var rows: [(folded: String, hit: Hit)] = []
    @ObservationIgnored private var last: (q: String, hits: [Hit])?

    func load() {
        guard !ready, !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            var out: [(String, Hit)] = []
            if case .ok(let d) = await Servers.data.file("native/regions/regions-index-2.wyri"),
               let all = try? JSONSerialization.jsonObject(with: d) as? [[Any]] {
                for r in all {
                    guard r.count >= 4, let n = r[0] as? String, let p = r[1] as? String, let id = r[3] as? String else { continue }
                    let h = Hit(name: n, place: p, row: (r[2] as? NSNumber)?.intValue ?? 1, id: id)
                    out.append((n.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil), h))
                }
            }
            await MainActor.run {
                let me = RegionIndex.shared
                me.rows = out
                me.loading = false
                me.ready = !out.isEmpty
            }
        }
    }

    func hits(_ query: String, limit: Int = 4) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard ready, q.count >= 2 else { return [] }
        if let l = last, l.q == q { return l.hits }
        var starts: [Hit] = [], inside: [Hit] = []
        for r in rows {
            if r.folded.hasPrefix(q) { starts.append(r.hit); if starts.count >= limit { break } }
            else if q.count >= 3, inside.count < limit, r.folded.contains(q) { inside.append(r.hit) }
        }
        let h = Array((starts + inside).prefix(limit))
        last = (q, h)
        return h
    }
}
