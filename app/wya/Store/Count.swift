import Foundation

/// WHAT THE COUNT COUNTS (Part 5's Count setting; the old MapSettings.Count): every stamp, or countries only. Stamps
/// by default. Kept in UserDefaults "mapCount" until the Map settings sheet (Step 4) writes it.
nonisolated enum CountKind: String, Sendable {
    case stamps, countries
    static var current: CountKind {
        CountKind(rawValue: UserDefaults.standard.string(forKey: "mapCount") ?? "") ?? .stamps
    }
}

/// THE COUNT SERVICE (Part 20.1 "Count"; the old app's MapCounts.shares, ported): your places and how many there are,
/// for the world and for each continent, under the borders view and the Count setting.
///
/// Worked out from the view's own answers (Positions: drawn, counts, countedAs) rather than from a fixed table, so a
/// dispute given to a side by hand on the Disputes page (Step 4) counts at once. This replaces Part 17 D18's
/// `counts.json` as the source; the D18 table becomes its check (the test driver's `counts` command prints the totals per view).
///
/// The old rules, as they were:
/// - Stamps: every place drawn on its own in the view counts (the three not-real places, Clipperton, the Coral Sea
///   Islands, Ashmore and Cartier, never count).
/// - Countries: a country, or a breakaway drawn on its own (a dotted one counts, a merged one does not).
/// - Antarctica always counts its territories, whatever the setting.
/// - A stamp counts for the place the view gives its land to (Taiwan on China's map counts as China).
nonisolated enum MapCounts {
    struct Share: Equatable, Sendable {
        var have = 0
        var total = 0
    }

    /// "World" and every continent's name
    /// `positions`: another view's answers (the check); the world's own view when nil
    static func shares(stamped: Set<String>, world w: World, count: CountKind, positions: Positions? = nil) -> [String: Share] {
        let pos = positions ?? w.positions
        let mine = Set(stamped.map { pos?.countedAs($0) ?? $0 })
        var out: [String: Share] = ["World": Share()]
        for (i, p) in w.places.enumerated() where !p.junk {
            let id = p.id
            guard pos?.drawn(id) ?? true else { continue }
            let counts = count == .stamps || (pos?.counts(id) ?? (p.k == "country" || p.k == "entity"))
            let has = mine.contains(id)
            if counts {
                out["World"]!.total += 1
                if has { out["World"]!.have += 1 }
            }
            for k in w.placeConts[i] where counts || k == "Antarctica" {
                out[k, default: Share()].total += 1
                if has { out[k]!.have += 1 }
            }
        }
        return out
    }
}
