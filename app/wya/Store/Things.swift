import Foundation
import simd

/// THINGS (Part 7.1, D5): the places to go in a country that are not towns (museums, castles, lakes, parks, beaches,
/// stations ...), each in one of the twelve kinds, read from the data server per country (`native/things/
/// things-<cc>-3.wyth`: rows [Wikidata id, name, kind, lat, lon, fame, description, photo], famous first; built from the
/// server's Wikidata places by data/pipeline d5_things.py) the first time the country opens in Places, kept for the
/// session. Fame: 3 World Heritage or known in 40+ Wikipedias, 2 from 12, 1 from 4, 0.
@MainActor
@Observable
final class ThingStore {
    static let shared = ThingStore()
    static let kinds = ["city", "area", "landmark", "mountain", "water", "nature", "spot", "stay", "station", "route", "event", "other"]
    struct Thing: Hashable {
        let id: String
        let name: String
        let kind: Int
        let at: SIMD2<Float>
        let fame: Int
        let line: String
        let photo: String
        /// `m:wd:Q1234` (Part 0.2.2's thing key, its source's id)
        var key: PlaceKey { PlaceKey(.thing, "wd:" + id) }
        var kindName: String { ThingStore.kinds[min(max(kind, 0), 11)] }
    }
    private(set) var version = 0
    @ObservationIgnored private var byCC: [String: [Thing]] = [:]
    @ObservationIgnored private var loading = Set<String>()

    func things(_ cc: String) -> [Thing]? { byCC[cc] }
    /// one thing by its key's id ("wd:Q1234") among the countries read
    func thing(_ id: String) -> (cc: String, thing: Thing)? {
        let q = id.hasPrefix("wd:") ? String(id.dropFirst(3)) : id
        for (cc, all) in byCC { if let t = all.first(where: { $0.id == q }) { return (cc, t) } }
        return nil
    }

    /// countries whose file could not be had, and when (a pan over them doesn't ask again for a minute)
    @ObservationIgnored private var failedAt: [String: Date] = [:]

    /// `opened`: the country itself opened in Places, which always asks again
    func load(_ cc: String, opened: Bool = false) {
        guard byCC[cc] == nil, !loading.contains(cc) else { return }
        if !opened, let t = failedAt[cc], Date().timeIntervalSince(t) < 60 { return }
        loading.insert(cc)
        Task.detached(priority: .userInitiated) {
            var out: [Thing] = []
            // nil: the file could not be had now (no network, or the server failed): nothing is kept, so the country
            // is asked for again (an empty country, or one the server has no file for, is kept as empty)
            let path = "native/things/things-\(cc)-3.wyth"
            var read = false
            switch await Servers.data.file(path) {
            case .missing: read = true
            case .offline, .failed: break
            case .ok(let d):
                guard let all = try? JSONSerialization.jsonObject(with: d) as? [[Any]] else {
                    // kept but unreadable: it goes, so the next ask downloads it again
                    DevDataClient.forget(path)
                    break
                }
                read = true
                for r in all {
                    guard r.count >= 8, let id = r[0] as? String, let n = r[1] as? String,
                          let lat = (r[3] as? NSNumber)?.doubleValue, let lon = (r[4] as? NSNumber)?.doubleValue else { continue }
                    out.append(Thing(id: id, name: n, kind: (r[2] as? NSNumber)?.intValue ?? 11,
                                     at: EqualEarth.project(lon: lon, lat: lat), fame: (r[5] as? NSNumber)?.intValue ?? 0,
                                     line: r[6] as? String ?? "", photo: r[7] as? String ?? ""))
                }
            }
            let found = read ? out : nil
            await MainActor.run {
                let me = ThingStore.shared
                me.loading.remove(cc)
                guard let found else { me.failedAt[cc] = Date(); return }
                me.failedAt[cc] = nil
                me.byCC[cc] = found
                me.version += 1
            }
        }
    }
}
