import Foundation

// THE TIME RECORDS (Part 0.2.2): every date the store keeps is one of these four. A visit's day is the day where it
// happened (a Tokyo photo at 1 am is the Tokyo day, whatever zone the phone is in later); a rough date stays as rough
// as it was given; a stay can still be going.

/// A day with no clock: the calendar day where it happened.
nonisolated struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    var y: Int, m: Int, d: Int

    init(y: Int, m: Int, d: Int) { self.y = y; self.m = m; self.d = d }

    /// the day an instant falls on in a time zone
    init(_ date: Date, in zone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(y: c.year ?? 1970, m: c.month ?? 1, d: c.day ?? 1)
    }

    /// "2023-04-01"
    init?(_ s: String) {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
        self.init(y: p[0], m: p[1], d: p[2])
    }

    var description: String { String(format: "%04d-%02d-%02d", y, m, d) }

    /// the day `n` days on (negative: before)
    func plus(_ n: Int) -> LocalDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let base = cal.date(from: DateComponents(year: y, month: m, day: d))!
        return LocalDay(cal.date(byAdding: .day, value: n, to: base)!, in: cal.timeZone)
    }

    static func < (a: LocalDay, b: LocalDay) -> Bool { (a.y, a.m, a.d) < (b.y, b.m, b.d) }

    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(description) }
    init(from dec: Decoder) throws {
        let s = try dec.singleValueContainer().decode(String.self)
        guard let v = LocalDay(s) else { throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: s)) }
        self = v
    }
}

/// A date as precise as it was given: a year, a month, or a day ("2019", "2023-04", "2023-04-01").
nonisolated struct PartialDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    var y: Int
    var m: Int?
    var d: Int?

    init(y: Int, m: Int? = nil, d: Int? = nil) { self.y = y; self.m = m; self.d = m == nil ? nil : d }
    init(_ day: LocalDay) { self.init(y: day.y, m: day.m, d: day.d) }
    init?(_ s: String) {
        let p = s.split(separator: "-").map { Int($0) }
        guard let y = p.first ?? nil else { return nil }
        let m = p.count > 1 ? p[1] : nil, d = p.count > 2 ? p[2] : nil
        if let m, !(1...12).contains(m) { return nil }
        if let d, !(1...31).contains(d) { return nil }
        self.init(y: y, m: m, d: d)
    }

    var description: String {
        guard let m else { return String(format: "%04d", y) }
        guard let d else { return String(format: "%04d-%02d", y, m) }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
    /// the whole day, when it was given to the day
    var day: LocalDay? { m.flatMap { m in d.map { LocalDay(y: y, m: m, d: $0) } } }
    /// the first day it can mean (for ordering)
    var first: LocalDay { LocalDay(y: y, m: m ?? 1, d: d ?? 1) }

    static func < (a: PartialDate, b: PartialDate) -> Bool { a.first < b.first || (a.first == b.first && a.description.count > b.description.count) }

    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(description) }
    init(from dec: Decoder) throws {
        let s = try dec.singleValueContainer().decode(String.self)
        guard let v = PartialDate(s) else { throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: s)) }
        self = v
    }
}

/// A stay: from, to, still going, or only rough words ("summer 2019", "a few days").
nonisolated struct Span: Hashable, Codable, Sendable {
    var from: PartialDate?
    var to: PartialDate?
    /// still there (no end yet)
    var ongoing = false
    /// what was typed when no dates were given
    var rough: String?
}

/// An instant and the time zone it happened in.
nonisolated struct Moment: Hashable, Codable, Sendable {
    var at: Date
    var zone: String

    init(at: Date, zone: TimeZone) { self.at = at; self.zone = zone.identifier }
    /// the day where it happened
    var day: LocalDay { LocalDay(at, in: TimeZone(identifier: zone) ?? .current) }
}
