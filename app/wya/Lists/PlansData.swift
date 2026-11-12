import Foundation

/// A PLAN'S DAYS AS DATES (the old app's rules): a day's key, a plan's length, its last day moved, its events for the
/// calendar (an .ics file), and the next trip with its countdown

nonisolated enum PlanDates {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func date(_ k: String) -> Date? {
        let p = k.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func key(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1)
    }

    static func key(_ start: String, _ i: Int) -> String {
        guard let d = date(start), let n = cal.date(byAdding: .day, value: i, to: d) else { return start }
        return key(n)
    }

    static func length(_ from: String, _ to: String) -> Int {
        guard let a = date(from), let b = date(to) else { return 0 }
        return (cal.dateComponents([.day], from: a, to: b).day ?? 0) + 1
    }

    static func key(local d: Date, in tz: TimeZone = .current) -> String {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        let x = c.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", x.year ?? 0, x.month ?? 1, x.day ?? 1)
    }
}

nonisolated enum PlanLastDay: Equatable, Sendable {
    case set
    case before
    case cuts(Int)
}

nonisolated extension Plan {
    var undated: Bool { start.isEmpty && !days.isEmpty }

    func dayKey(_ i: Int) -> String { undated ? "day-\(i + 1)" : PlanDates.key(start, i) }

    static func undatedNumber(_ k: String) -> Int? {
        guard k.hasPrefix("day-"), let n = Int(k.dropFirst(4)), n > 0 else { return nil }
        return n
    }

    @discardableResult
    mutating func setUndatedDays(_ n: Int, force: Bool = false) -> PlanLastDay {
        let n = max(0, n)
        let cut = days.dropFirst(n).reduce(0) { $0 + $1.items.count }
        if cut > 0 && !force { return .cuts(cut) }
        start = ""; end = ""
        while days.count < n { days.append(PlanDay()) }
        if days.count > n { days.removeLast(days.count - n) }
        return .set
    }

    mutating func fitDays() {
        guard !start.isEmpty, !end.isEmpty else { return }
        let n = max(1, PlanDates.length(start, end))
        while days.count < n { days.append(PlanDay()) }
        if days.count > n { days.removeLast(days.count - n) }
    }

    mutating func pickFirst(_ v: String, endFirst: inout Bool) {
        guard !v.isEmpty else { return }
        if endFirst && !end.isEmpty && v <= end { endFirst = false; start = v; fitDays(); return }
        endFirst = false
        let n = !start.isEmpty && !end.isEmpty ? PlanDates.length(start, end) : max(1, days.count)
        start = v
        end = PlanDates.key(v, n - 1)
        fitDays()
    }

    @discardableResult
    mutating func pickLast(_ v: String, endFirst: inout Bool, force: Bool = false) -> PlanLastDay {
        guard !v.isEmpty else { return .set }
        if !start.isEmpty && v < start && !endFirst { return .before }
        if start.isEmpty || endFirst { start = v; endFirst = true }
        let n = PlanDates.length(start, v)
        let cut = days.dropFirst(max(0, n)).reduce(0) { $0 + $1.items.count }
        if cut > 0 && !force { return .cuts(cut) }
        end = v
        fitDays()
        return .set
    }

    mutating func sortDay(_ i: Int) {
        guard days.indices.contains(i) else { return }
        days[i].items = days[i].items.enumerated().sorted { a, b in
            a.element.startMinutes != b.element.startMinutes ? a.element.startMinutes < b.element.startMinutes : a.offset < b.offset
        }.map(\.element)
    }

    func dayIndex(_ k: String) -> Int? {
        if let n = Self.undatedNumber(k) { return undated && days.indices.contains(n - 1) ? n - 1 : nil }
        guard !start.isEmpty, k >= start, end.isEmpty || k <= end else { return nil }
        let i = PlanDates.length(start, k) - 1
        return days.indices.contains(i) ? i : nil
    }
}

nonisolated struct PlanEvent: Equatable, Sendable {
    var day: String
    var at: String?
    var until: String?
    var what: String
    var place: String
    var link: String
    var note: String
    init(day: String, at: String?, until: String? = nil, what: String, place: String = "", link: String = "", note: String = "") {
        self.day = day; self.at = at; self.until = until; self.what = what; self.place = place; self.link = link; self.note = note
    }
}

nonisolated extension Plan {
    var events: [PlanEvent] {
        guard !start.isEmpty else { return [] }
        var out: [PlanEvent] = []
        for (i, d) in days.enumerated() {
            for it in d.items {
                out.append(PlanEvent(day: PlanDates.key(start, i), at: it.at, until: it.until,
                                     what: it.what.isEmpty ? "Something" : it.what, place: it.place, link: it.link, note: it.note))
            }
        }
        return out
    }

    @discardableResult
    mutating func merge(_ evs: [PlanEvent]) -> (added: Int, outside: Int) {
        guard !evs.isEmpty else { return (0, 0) }
        if start.isEmpty || end.isEmpty {
            let ds = evs.map(\.day).sorted()
            start = ds.first!; end = ds.last!
            fitDays()
        }
        var added = 0, outside = 0
        var touched = Set<Int>()
        for e in evs {
            guard let i = dayIndex(e.day) else { outside += 1; continue }
            days[i].items.append(PlanItem(at: e.at, until: e.until, what: e.what.isEmpty ? "Something" : e.what,
                                          place: e.place, link: e.link, note: e.note))
            touched.insert(i); added += 1
        }
        for i in touched { sortDay(i) }
        return (added, outside)
    }
}

nonisolated enum PlanICS {
    static func stamp(_ d: Date) -> String {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let x = c.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d%02d%02dT%02d%02d00Z", x.year!, x.month!, x.day!, x.hour!, x.minute!)
    }
    static func esc(_ t: String) -> String {
        t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: "\n", with: "\\n")
    }
    static func ymd(_ k: String) -> String { k.replacingOccurrences(of: "-", with: "") }

    static func write(_ p: Plan, now: Date) -> String {
        var out = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//wya?!//plan//EN", "CALSCALE:GREGORIAN"]
        let ts = stamp(now)
        for (i, d) in p.days.enumerated() {
            let day = PlanDates.key(p.start, i)
            for (k, it) in d.items.enumerated() {
                out.append("BEGIN:VEVENT")
                out.append("UID:\(p.id)-\(i)-\(k)@wya")
                out.append("DTSTAMP:\(ts)")
                if let a = PlanItem.minutes(it.at) {
                    let u = PlanItem.minutes(it.until).flatMap { $0 > a ? $0 : nil } ?? a + 60
                    func t(_ m: Int) -> String {
                        String(format: "%@T%02d%02d00", ymd(PlanDates.key(day, m / (24 * 60))), (m % (24 * 60)) / 60, m % 60)
                    }
                    out.append("DTSTART:" + t(a))
                    out.append("DTEND:" + t(u))
                } else {
                    out.append("DTSTART;VALUE=DATE:" + ymd(day))
                    out.append("DTEND;VALUE=DATE:" + ymd(PlanDates.key(day, 1)))
                }
                out.append("SUMMARY:" + esc(it.what.isEmpty ? "Something" : it.what))
                if !it.place.isEmpty { out.append("LOCATION:" + esc(it.place)) }
                if !it.link.isEmpty { out.append("URL:" + it.link.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")) }
                if !it.note.isEmpty { out.append("DESCRIPTION:" + esc(it.note)) }
                out.append("END:VEVENT")
            }
        }
        out.append("END:VCALENDAR")
        return out.joined(separator: "\r\n")
    }

    static func read(_ text: String, timeZone: TimeZone = .current) -> [PlanEvent] {
        var lines: [String] = []
        for l in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
            if (l.hasPrefix(" ") || l.hasPrefix("\t")), !lines.isEmpty { lines[lines.count - 1] += String(l.dropFirst()) } else { lines.append(l) }
        }
        func un(_ v: String) -> String {
            var s = "", it = v.makeIterator()
            while let ch = it.next() {
                if ch == "\\", let n = it.next() { s.append(n == "n" || n == "N" ? "\n" : n) } else { s.append(ch) }
            }
            return s
        }
        var evs: [[String: String]] = []
        var ev: [String: String]? = nil
        for l in lines {
            let up = l.uppercased()
            if up.hasPrefix("BEGIN:VEVENT") { ev = [:]; continue }
            if up.hasPrefix("END:VEVENT") { if let e = ev { evs.append(e) }; ev = nil; continue }
            guard ev != nil, let colon = l.firstIndex(of: ":") else { continue }
            let head = String(l[..<colon]), val = String(l[l.index(after: colon)...])
            let key = String(head.split(separator: ";").first ?? "").uppercased()
            switch key {
            case "DTSTART", "DTEND": ev![key] = val.trimmingCharacters(in: .whitespaces)
            case "SUMMARY": ev!["what"] = un(val)
            case "LOCATION": ev!["where"] = un(val)
            case "URL": ev!["link"] = val.trimmingCharacters(in: .whitespaces)
            case "DESCRIPTION": ev!["note"] = String(un(val).prefix(300))
            default: break
            }
        }
        var out: [PlanEvent] = []
        let re = try! NSRegularExpression(pattern: #"^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$"#)
        func parts(_ v: String) -> [String?]? {
            guard let m = re.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)) else { return nil }
            return (1...7).map { i in Range(m.range(at: i), in: v).map { String(v[$0]) } }
        }
        for e in evs {
            guard let s = e["DTSTART"], let p = parts(s) else { continue }
            let what = e["what"] ?? "", place = e["where"] ?? "", link = e["link"] ?? "", note = e["note"] ?? ""
            if p[3] == nil {
                let day = "\(p[0]!)-\(p[1]!)-\(p[2]!)"
                var n = 1
                if let ee = e["DTEND"], let q = parts(ee), q[3] == nil {
                    n = max(1, PlanDates.length(day, "\(q[0]!)-\(q[1]!)-\(q[2]!)") - 1)
                }
                for i in 0..<min(n, 60) { out.append(PlanEvent(day: PlanDates.key(day, i), at: nil, what: what, place: place, link: link, note: note)) }
                continue
            }
            var day = "\(p[0]!)-\(p[1]!)-\(p[2]!)", at = "\(p[3]!):\(p[4]!)"
            if p[6] != nil {
                var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
                if let d = c.date(from: DateComponents(year: Int(p[0]!), month: Int(p[1]!), day: Int(p[2]!), hour: Int(p[3]!), minute: Int(p[4]!))) {
                    var l = Calendar(identifier: .gregorian); l.timeZone = timeZone
                    let x = l.dateComponents([.year, .month, .day, .hour, .minute], from: d)
                    day = String(format: "%04d-%02d-%02d", x.year!, x.month!, x.day!)
                    at = String(format: "%02d:%02d", x.hour!, x.minute!)
                }
            }
            out.append(PlanEvent(day: day, at: at, what: what, place: place, link: link, note: note))
        }
        return out
    }
}

nonisolated struct NextTrip: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case before(Int)
        case during(Int, Int)
        case after
    }
    let plan: String
    let phase: Phase
    let place: String
    let stops: [String]
    let countries: [String]

    static let afterDays = 7

    static func pick(_ plans: [Plan], today: String, booked: Set<String> = []) -> NextTrip? {
        let live = plans.filter { !$0.arch && !$0.hid && !$0.start.isEmpty && !$0.end.isEmpty }
        if let on = live.filter({ $0.start <= today && today <= $0.end }).min(by: { $0.start < $1.start }) {
            return make(on, .during(PlanDates.length(on.start, today), PlanDates.length(on.start, on.end)))
        }
        if let next = live.filter({ $0.start > today }).min(by: { $0.start < $1.start }) {
            return make(next, .before(PlanDates.length(today, next.start) - 1))
        }
        let just = live.filter { $0.end < today && PlanDates.length($0.end, today) - 1 <= afterDays && !booked.contains($0.id) }
        if let back = just.max(by: { $0.end < $1.end }) { return make(back, .after) }
        return nil
    }

    static func make(_ p: Plan, _ phase: Phase) -> NextTrip {
        var stops: [String] = [], seen = Set<String>(), ccs: [String] = [], seenC = Set<String>()
        var goesTo: String? = nil
        func add(_ name: String, _ cc: String?) {
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty, seen.insert(n.lowercased()).inserted { stops.append(n) }
            if let c = cc, seenC.insert(c).inserted { ccs.append(c) }
        }
        for d in p.days {
            for it in d.items.sorted(by: { $0.startMinutes < $1.startMinutes }) {
                if let g = it.go {
                    if goesTo == nil, !g.to.isEmpty { goesTo = g.to }
                    add(g.to, g.toCC)
                } else {
                    add(it.place, it.cc)
                }
            }
        }
        let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return NextTrip(plan: p.id, phase: phase, place: goesTo ?? stops.first ?? name, stops: stops, countries: ccs)
    }
}
