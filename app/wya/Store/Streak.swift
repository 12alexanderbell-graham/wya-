import Foundation

/// THE STREAK (Part 20.1): weeks in a row with at least one act. Weeks run Monday to Sunday in your time zone
/// (proposal). This week counts once it has an act; until then the streak still stands on last week (it breaks only
/// when a whole week passes with none). Acts today: stamps and wishes; lists, plans, books, pins, routes, drawings and
/// moments report theirs as their steps land.
enum Streak {
    static func weeks(acts: [Date], now: Date = Date(), calendar: Calendar = .current) -> Int {
        var cal = calendar
        cal.firstWeekday = 2
        func week(_ d: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d }
        let active = Set(acts.map(week))
        var w = week(now)
        if !active.contains(w) { w = cal.date(byAdding: .weekOfYear, value: -1, to: w) ?? w }
        var n = 0
        while active.contains(w) {
            n += 1
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: w) else { break }
            w = prev
        }
        return n
    }
}
