import Foundation

/// FINDS FROM PRESENCE (Part 9.7 steps 5 and 6; built ahead with Step 7's reading core, used by Step 10's uploads and
/// Verify): presence rows grouped by place into visits, and your home found and kept out of the trips.
/// Step 7 of the pipeline (merging with what you have) waits for the review screens (Step 10).
nonisolated enum Finds {
    struct Visit: Equatable, Sendable {
        var from: LocalDay
        var to: LocalDay
        /// samples behind it
        var count: Int
    }
    struct Find: Equatable, Sendable {
        var place: String
        var visits: [Visit]
        /// your home base: found as a place you can stamp, but with no trips
        var home: Bool
        var count: Int { visits.reduce(0) { $0 + $1.count } }
    }

    /// a gap of more than this many days starts a new visit: photos are sparse (4), history and tracking dense (1)
    static func gap(for source: MarkSource) -> Int { source == .photos ? 4 : 1 }

    /// the rows made into finds, one per place, its visits in order. `home`: your home base from Profile; with none,
    /// the place present in more than 40% of the months that have any evidence (proposal), when one is
    static func finds(_ rows: [HistoryReader.Presence], source: MarkSource, home given: String? = nil) -> [Find] {
        var days: [String: [LocalDay: Int]] = [:]
        for r in rows { days[r.place, default: [:]][r.day, default: 0] += r.count }
        let home = given ?? homeBase(rows)
        let g = gap(for: source)
        var out: [Find] = []
        for (place, byDay) in days {
            let sorted = byDay.keys.sorted()
            var visits: [Visit] = []
            for d in sorted {
                let n = byDay[d] ?? 0
                // the days between this one and the visit's last: more than the gap starts a new visit
                if var last = visits.last, dayCount(last.to, d) - 1 <= g {
                    last.to = d; last.count += n
                    visits[visits.count - 1] = last
                } else {
                    visits.append(Visit(from: d, to: d, count: n))
                }
            }
            let isHome = place == home
            out.append(Find(place: place, visits: isHome ? [] : visits, home: isHome))
        }
        return out.sorted { ($0.visits.first?.from ?? LocalDay(y: 9999, m: 1, d: 1)) < ($1.visits.first?.from ?? LocalDay(y: 9999, m: 1, d: 1)) }
    }

    /// whole days from a to b (b after a): 2024-01-01 to 2024-01-03 is 2
    static func dayCount(_ a: LocalDay, _ b: LocalDay) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let x = cal.date(from: DateComponents(year: a.y, month: a.m, day: a.d))!
        let y = cal.date(from: DateComponents(year: b.y, month: b.m, day: b.d))!
        return cal.dateComponents([.day], from: x, to: y).day ?? 0
    }

    /// the place present in more than 40% of the months with evidence, or nil
    static func homeBase(_ rows: [HistoryReader.Presence]) -> String? {
        var months: [String: Set<String>] = [:]
        var all = Set<String>()
        for r in rows {
            let m = "\(r.day.y)-\(r.day.m)"
            all.insert(m)
            months[r.place, default: []].insert(m)
        }
        guard all.count >= 3 else { return nil }
        let best = months.max { $0.value.count < $1.value.count }
        guard let best, Double(best.value.count) > 0.4 * Double(all.count) else { return nil }
        return best.key
    }
}
