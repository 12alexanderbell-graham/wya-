import Foundation

/// SEARCH OVER EVERY TOWN (Part 1.10 in Places, D12's towns part): every town of every place (228,388, D3), biggest
/// first, read once from the data server (`native/towns/towns-index-2.wyti`: rows [name, file, GeoNames id, people,
/// lat, lon, kind, region]) the first time Places is searched, folded off the main thread. A search lists names starting with what
/// was typed, then (from three letters) names holding it; the open country's towns before everywhere else's.
@MainActor
@Observable
final class TownIndex {
    static let shared = TownIndex()
    struct Hit: Hashable {
        let name: String
        let file: String
        let id: String
        let people: Int
        let lat: Double
        let lon: Double
        /// its first-level division's name ("Hessen"), or ""
        let region: String
        var key: String { "t:" + id }
    }
    private(set) var ready = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var rows: [(folded: String, hit: Hit)] = []
    @ObservationIgnored private var last: (q: String, open: String?, hits: [Hit])?

    /// read the index once (in the background)
    func load() {
        guard !ready, !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            var out: [(String, Hit)] = []
            if case .ok(let d) = await Servers.data.file("native/towns/towns-index-2.wyti"),
               let all = try? JSONSerialization.jsonObject(with: d) as? [[Any]] {
                out.reserveCapacity(all.count)
                for r in all {
                    guard r.count >= 6, let n = r[0] as? String, let f = r[1] as? String else { continue }
                    let gid = (r[2] as? NSNumber)?.intValue ?? 0
                    let h = Hit(name: n, file: f, id: gid != 0 ? "\(f)/\(gid)" : "\(f)/\(n)",
                                people: (r[3] as? NSNumber)?.intValue ?? 0,
                                lat: (r[4] as? NSNumber)?.doubleValue ?? 0, lon: (r[5] as? NSNumber)?.doubleValue ?? 0,
                                region: r.count > 7 ? r[7] as? String ?? "" : "")
                    out.append((n.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil), h))
                }
            }
            await MainActor.run {
                let me = TownIndex.shared
                me.rows = out
                me.loading = false
                me.ready = !out.isEmpty
                #if DEBUG
                NSLog("wya town index: %d towns", out.count)
                #endif
            }
        }
    }

    /// at most `limit` towns for what was typed: the open country's first (`open`, its file), then everywhere
    func hits(_ query: String, open: String?, limit: Int = 6) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard ready, !q.isEmpty else { return [] }
        if let l = last, l.q == q, l.open == open { return l.hits }
        var home: [Hit] = [], away: [Hit] = [], homeIn: [Hit] = [], awayIn: [Hit] = []
        for r in rows {
            let mine = r.hit.file == open
            if r.folded.hasPrefix(q) {
                if mine { home.append(r.hit) } else if away.count < limit { away.append(r.hit) }
            } else if q.count >= 3, r.folded.contains(q) {
                if mine { if homeIn.count < limit { homeIn.append(r.hit) } } else if awayIn.count < limit { awayIn.append(r.hit) }
            }
            if home.count >= limit { break }
        }
        let h = Array((home + homeIn + away + awayIn).prefix(limit))
        last = (q, open, h)
        return h
    }
}
