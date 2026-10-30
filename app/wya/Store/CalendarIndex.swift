import Foundation

/// THE CALENDAR BASE (Part 9.9): one index of every dated thing, so a photo, a visit, a stay and a waiting find agree
/// on what day it was, and every reader (the calendar, plans, history lines, stats, the passport's dates) reads the
/// same days. In memory, built from the store at launch and again after each change (MarkStore.calendar). No screens:
/// the calendar's own screens wait for their design pass.
nonisolated struct CalendarIndex: Sendable {
    enum Kind: String, Sendable { case visit, lived, find }
    /// a dated span on the calendar: a visit (found or typed with dates), a stay where you lived, or a find waiting
    /// for its review
    struct Entry: Hashable, Sendable {
        var kind: Kind
        var key: PlaceKey
        var from: LocalDay
        var to: LocalDay
        var source: String
    }
    /// a visit known only in words ("Summer 2019"): its sort day when the words have one (RoughDay)
    struct Undated: Hashable, Sendable {
        var key: PlaceKey
        var words: String
        var sortDay: LocalDay?
    }
    /// a run of days away (Part 20.1: Trip): visits that overlap or follow on, away from home
    struct Trip: Hashable, Sendable {
        var from: LocalDay
        var to: LocalDay
        var places: [PlaceKey]
    }
    /// what the store hands over: one row per visit record, and the stays kept in a stamp's details
    struct Row: Sendable {
        var key: PlaceKey
        var arrived: String?
        var left: String?
        var rough: String?
        var lived: Bool
        var source: String
    }

    private(set) var spans: [Entry] = []
    private(set) var undated: [Undated] = []

    init() {}
    /// `today`: the end of a stay still going (the phone's day)
    init(rows: [Row], finds: [Entry] = [], southern: Bool = false, today: LocalDay = LocalDay(Date(), in: .current)) {
        var s: [Entry] = []
        var u: [Undated] = []
        for r in rows {
            if let a = r.arrived.flatMap(PartialDate.init) {
                let b = r.left.flatMap(PartialDate.init)
                // a stay with no end is still going; a visit with no end is the arrival's own day, month or year
                let end = b?.last ?? (r.lived && r.left == nil ? today : a.last)
                s.append(Entry(kind: r.lived ? .lived : .visit, key: r.key, from: a.first, to: max(a.first, end), source: r.source))
            } else if let w = r.rough, !w.isEmpty {
                u.append(Undated(key: r.key, words: w, sortDay: RoughDay.sortDay(w, southern: southern)))
            }
        }
        spans = (s + finds).sorted { ($0.from, $0.to, $0.key) < ($1.from, $1.to, $1.key) }
        undated = u
    }

    /// everything on one day
    func entries(on day: LocalDay) -> [Entry] { spans.filter { $0.from <= day && day <= $0.to } }

    /// a month's days that have anything, with what is on each
    func month(_ y: Int, _ m: Int) -> [LocalDay: [Entry]] {
        let first = LocalDay(y: y, m: m, d: 1)
        let last = PartialDate(y: y, m: m).last
        var out: [LocalDay: [Entry]] = [:]
        for e in spans where e.from <= last && first <= e.to {
            var d = max(first, e.from)
            let end = min(last, e.to)
            while d <= end { out[d, default: []].append(e); d = d.plus(1) }
        }
        return out
    }

    /// the runs of days away: visits (not stays, not waiting finds) away from `home`, joined where they overlap or
    /// follow on the next day, newest last
    func trips(home: PlaceKey? = nil) -> [Trip] {
        var out: [Trip] = []
        for e in spans where e.kind == .visit && e.key != home {
            if var t = out.last, e.from <= t.to.plus(1) {
                t.to = max(t.to, e.to)
                if !t.places.contains(e.key) { t.places.append(e.key) }
                out[out.count - 1] = t
            } else {
                out.append(Trip(from: e.from, to: e.to, places: [e.key]))
            }
        }
        return out
    }

    /// a place's first dated visit (the stamp's date and the passport's printed date read this, else when it was
    /// pressed; Part 4.3)
    func earliest(_ key: PlaceKey) -> LocalDay? {
        spans.first { $0.key == key && $0.kind != .find }?.from
    }
}

extension PartialDate {
    /// the last day it can mean: the day itself, the month's last day, or 31 December
    var last: LocalDay {
        guard let m else { return LocalDay(y: y, m: 12, d: 31) }
        if let d { return LocalDay(y: y, m: m, d: d) }
        return LocalDay(y: y, m: m, d: 1).plus(40).firstOfMonth.plus(-1)
    }
}

extension LocalDay {
    var firstOfMonth: LocalDay { LocalDay(y: y, m: m, d: 1) }
}
