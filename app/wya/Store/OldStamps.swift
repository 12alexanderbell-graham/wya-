import Foundation

/// THE OLD APP'S STAMPS (Part 10 Step 3: "a reader for the old app's stamps.json"): its StampBook as the old app
/// saved it (Foundation's JSONEncoder, dates as seconds since 2001), read into the rows the store keeps, with the old
/// app's own key moves applied on the way (StampBook.renamed and townsMoved: a region on a replaced level, a town whose
/// key changed), so every old stamp lands on the place the data has now.
///
/// What it carries: country stamps (times, lived, how, when, note, the date, via, the proof), wishes (how badly, and
/// the wish's details), when a wish came true, region, town and thing stamps with their names, countries and levels,
/// every place's details and proofs kept whole as JSON until Details and Verify are built (Steps 5 and 7).
/// What waits for its own step: your places, pins and routes (Pins, Step 13), lists and plans (Lists).
nonisolated struct OldBook: Sendable {
    struct Row: Sendable {
        var key: PlaceKey
        var stamped = false
        var wished = false
        var want = 0
        var times = 1
        var lived = false
        var how: String?
        var when: String?
        var note = ""
        var at = Date()
        var via: String?
        var came: Date?
        var name = ""
        var cc = ""
        var level = 0
        var details: Data?
        var wishDetails: Data?
        var verification: Data?
    }
    var rows: [Row] = []
    /// what the reader saw and could not carry yet (your places, pins, routes), by kind
    var waiting: [String: Int] = [:]

    enum Failure: Error { case notABook }

    init(json data: Data) throws {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.notABook }
        func dict(_ k: String) -> [String: Any] { o[k] as? [String: Any] ?? [:] }
        func date(_ v: Any?) -> Date? { (v as? NSNumber).map { Date(timeIntervalSinceReferenceDate: $0.doubleValue) } }
        func blob(_ v: Any?) -> Data? {
            guard let v, JSONSerialization.isValidJSONObject(v) else { return nil }
            return try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys])
        }
        func text(_ v: Any?) -> String? { (v as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let details = dict("details"), wishDetails = dict("wishDetails"), proofs = dict("proofs"), came = dict("came")
        var out: [String: Row] = [:]

        // countries, territories and entities
        for (id, v) in dict("stamps") {
            guard let s = v as? [String: Any] else { continue }
            let key = PlaceKey.country(id)
            var r = Row(key: key)
            r.stamped = true
            r.times = max(1, (s["visits"] as? Int) ?? 1)
            r.lived = (s["lived"] as? Bool) ?? false
            r.how = text(s["how"]); r.when = text(s["when"]); r.note = (s["note"] as? String) ?? ""
            r.at = date(s["at"]) ?? Date()
            r.via = text(s["via"])
            r.came = date(came[id])
            r.details = blob(details[key.description])
            r.verification = blob(s["verified"])
            out[key.description] = r
        }
        for (id, v) in dict("wish") {
            let key = PlaceKey.country(id)
            // a country is never stamped and wished (the old rule); a book that has both keeps the stamp
            guard out[key.description] == nil else { continue }
            var r = Row(key: key)
            r.wished = true
            r.want = min(5, max(1, (v as? Int) ?? 3))
            r.wishDetails = blob(wishDetails[key.description])
            out[key.description] = r
        }

        // regions, with the old renames and the moves off replaced levels (StampBook.renamed), in the ids' order
        var regions: [String: [String: Any]] = [:]
        for (id, v) in dict("regions") { if let s = v as? [String: Any] { regions[id] = s } }
        func merge(_ a: inout [String: Any], _ b: [String: Any]) {
            a["visits"] = ((a["visits"] as? Int) ?? 1) + ((b["visits"] as? Int) ?? 1)
            if let x = date(a["at"]), let y = date(b["at"]), y < x { a["at"] = b["at"] }
        }
        let moves = Self.table("region-moves")
        for old in regions.keys.filter({ moves[$0] != nil }).sorted() {
            guard let m = moves[old], var s = regions.removeValue(forKey: old) else { continue }
            if m.count == 3, let l = Int(m[1]), l >= 0 { s["lvl"] = l; s["n"] = m[2] }
            if let t = regions[m[0]] { merge(&s, t); s["n"] = t["n"] ?? s["n"] }
            regions[m[0]] = s
        }
        for (id, s) in regions {
            let key = PlaceKey(.region, id)
            var r = Row(key: key)
            r.stamped = true
            r.times = max(1, (s["visits"] as? Int) ?? 1)
            r.at = date(s["at"]) ?? Date()
            r.name = (s["n"] as? String) ?? ""; r.cc = (s["cc"] as? String) ?? ""; r.level = (s["lvl"] as? Int) ?? 0
            r.details = blob(details[key.description]); r.verification = blob(proofs[key.description])
            out[key.description] = r
        }

        // towns, with the old key moves (StampBook.townsMoved)
        var towns: [String: [String: Any]] = [:]
        for (id, v) in dict("towns") { if let s = v as? [String: Any] { towns[id] = s } }
        let tmoves = Self.table("town-moves")
        for old in towns.keys.filter({ tmoves[$0] != nil }).sorted() {
            guard let m = tmoves[old], m.count == 3, var s = towns.removeValue(forKey: old) else { continue }
            s["n"] = m[1]; s["cc"] = m[2]
            if let t = towns[m[0]] { merge(&s, t) }
            towns[m[0]] = s
        }
        for (id, s) in towns {
            let key = PlaceKey(.town, id)
            var r = Row(key: key)
            r.stamped = true
            r.times = max(1, (s["visits"] as? Int) ?? 1)
            r.at = date(s["at"]) ?? Date()
            r.name = (s["n"] as? String) ?? ""; r.cc = (s["cc"] as? String) ?? ""
            r.details = blob(details[key.description]); r.verification = blob(proofs[key.description])
            out[key.description] = r
        }

        // things (the Places map's marks); a thing across several countries keeps them all, comma-separated
        for (id, v) in dict("marks") {
            guard let s = v as? [String: Any] else { continue }
            let key = PlaceKey(.thing, id)
            var r = Row(key: key)
            r.stamped = true
            r.times = max(1, (s["visits"] as? Int) ?? 1)
            r.at = date(s["at"]) ?? Date()
            r.name = (s["n"] as? String) ?? ""
            r.cc = ((s["cc"] as? [String]) ?? []).joined(separator: ",")
            r.details = blob(details[key.description]); r.verification = blob(proofs[key.description])
            out[key.description] = r
        }

        rows = out.values.sorted { $0.key < $1.key }
        for k in ["places", "pins", "routes"] { if let a = o[k] as? [Any], !a.isEmpty { waiting[k] = a.count } }
    }

    /// a moves table from Resources/Store (old id, then its columns), read once per import
    static func table(_ name: String) -> [String: [String]] {
        guard let u = Bundle.main.url(forResource: name, withExtension: "tsv"),
              let s = try? String(contentsOf: u, encoding: .utf8) else { return [:] }
        var out: [String: [String]] = [:]
        for line in s.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 2 else { continue }
            out[f[0]] = Array(f.dropFirst())
        }
        return out
    }
}
