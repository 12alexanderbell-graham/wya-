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

/// ROUGH WORDS TO A SORT DAY (Part 9.9's time model): a time typed in words sorts by a small fixed parser, no AI.
/// "2019" -> 2019-01-01, "Aug 2026" -> 2026-08-01, "12 Aug 2024" -> 2024-08-12, "Summer 2019" -> 2019-06-01 (seasons
/// start on their first meteorological month, flipped for a southern-hemisphere home base). Words with no year
/// ("a few days") have no sort day and stay out of the history lines.
nonisolated enum RoughDay {
    static func sortDay(_ words: String, southern: Bool = false) -> LocalDay? {
        let t = words.lowercased().replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ".", with: " ")
        if let p = PartialDate(t.trimmingCharacters(in: .whitespaces)), (1000 ... 2999).contains(p.y) { return p.first }
        let words = t.split(whereSeparator: { $0 == " " || $0 == "/" }).map(String.init)
        guard let y = words.compactMap({ Int($0) }).first(where: { (1900 ... 2100).contains($0) }) else { return nil }
        // a season: its first month (north: spring Mar, summer Jun, autumn Sep, winter Dec; south: six months on)
        let seasons: [String: Int] = ["spring": 3, "summer": 6, "autumn": 9, "fall": 9, "winter": 12]
        if let m = words.compactMap({ seasons[$0] }).first {
            return LocalDay(y: y, m: southern ? (m + 5) % 12 + 1 : m, d: 1)
        }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let m = words.compactMap({ w in months.firstIndex(where: { w.hasPrefix($0) }) }).first.map({ $0 + 1 }) else {
            return LocalDay(y: y, m: 1, d: 1)
        }
        // a day: a number from 1 to 31 that is not the year ("12", "12th")
        let d = words.compactMap { w -> Int? in
            let n = Int(w.filter(\.isNumber)) ?? 0
            return w.first?.isNumber == true && (1 ... 31).contains(n) && n != y ? n : nil
        }.first ?? 1
        return LocalDay(y: y, m: m, d: d)
    }
}
