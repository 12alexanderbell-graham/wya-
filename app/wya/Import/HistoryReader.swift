import Foundation

/// THE HISTORY READER (Part 9.7 steps 1, 2 and 4; Part 10 Step 7, shared with Step 10's uploads): a location history
/// file made into dated samples, then into presence rows (a day, a place, how many samples, the first and last instant,
/// the 1 km cell). Everything is read on the phone; nothing here has a screen.
///
/// The four shapes (the old app's TravelImport, with what it missed added):
/// - A. Takeout `Records.json`: `locations[]` with `latitudeE7`, `longitudeE7`, `accuracy`, `timestamp` or `timestampMs`.
///   Accuracy 2,000 m or more is dropped (the old `Tracking.accept`).
/// - B. Takeout Semantic Location History monthly files: `timelineObjects[]` with `placeVisit` (its `location` and
///   `duration`) and `activitySegment` (`startLocation`, `endLocation`, `duration`). The duration's
///   `startTimestamp` / `endTimestamp` (and `...Ms`) were missed by the old code: read here.
/// - C. Android's on-device `Timeline.json`: `semanticSegments[]` (`startTime`, `endTime`,
///   `startTimeTimezoneUtcOffsetMinutes`, a visit's `topCandidate.placeLocation.latLng` "48.1°, 11.5°", an activity's
///   `start` / `end`, `timelinePath[]` points with their `time`), and `rawSignals[]` positions.
/// - D. iPhone's on-device export: a top-level array of segments, "geo:48.1,11.5", ISO times with their offsets,
///   `timelinePath[]` points timed by `durationMinutesOffsetFromStartTime` (the old code gave every point the segment's
///   start: fixed).
/// A visit (B, C, D) covers every day from its start to its end; points are single instants.
///
/// A Records.json over 50 MB is scanned byte by byte from a memory-mapped file (only each location's coordinate,
/// accuracy and time keys), never parsed whole; a C or D file over 50 MB is cut into its segments (and C's raw signals)
/// by the same kind of byte pass, each parsed on its own. Not here yet (logged): the level-1 region (step 3's second
/// half). Photos: PhotosReader.
nonisolated enum HistoryReader {
    enum Shape: String, Sendable { case records = "A", semantic = "B", android = "C", iphone = "D" }

    /// one sample: where, when, the zone offset its source gave (minutes east of UTC) if it gave one, and for a
    /// visit the instant it ended
    struct Sample: Equatable, Sendable {
        var lat: Double
        var lon: Double
        var at: Date
        var offset: Int?
        var end: Date?
        /// a photo's asset id when the sample came from the library (PhotosReader)
        var asset: String? = nil
    }

    struct Result: Sendable {
        var shape: Shape
        var samples: [Sample]
        /// points left out: no time, 0,0, out of range, or too inaccurate
        var dropped: Int
    }

    /// the file's samples, or nil when it is not a location history in any of the four shapes
    static func read(_ data: Data) -> Result? {
        // a big Records.json (years of points, hundreds of MB) is scanned, never parsed whole
        if data.count > streamOver, isRecords(data) { return scanRecords(data) }
        // so is a big Timeline.json (C) or iPhone export (D): one segment parsed at a time
        if data.count > streamOver, let r = scanSegments(data) { return r }
        guard let j = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var r: Result
        if let o = j as? [String: Any], let locs = o["locations"] as? [[String: Any]] {
            r = Result(shape: .records, samples: [], dropped: 0)
            for l in locs {
                guard let la = num(l["latitudeE7"]), let lo = num(l["longitudeE7"]),
                      let at = date(l["timestamp"]) ?? num(l["timestampMs"]).map({ Date(timeIntervalSince1970: $0 / 1000) })
                else { r.dropped += 1; continue }
                if let a = num(l["accuracy"]), a >= 2000 { r.dropped += 1; continue }
                add(&r, la / 1e7, lo / 1e7, at, nil, nil)
            }
        } else if let o = j as? [String: Any], let objs = o["timelineObjects"] as? [[String: Any]] {
            r = Result(shape: .semantic, samples: [], dropped: 0)
            for t in objs {
                if let v = t["placeVisit"] as? [String: Any] {
                    let (a, b) = span(v["duration"])
                    guard let ll = latLng(v["location"]), let a else { r.dropped += 1; continue }
                    add(&r, ll.0, ll.1, a, nil, b)
                }
                if let s = t["activitySegment"] as? [String: Any] {
                    let (a, b) = span(s["duration"])
                    if let ll = latLng(s["startLocation"]), let a { add(&r, ll.0, ll.1, a, nil, nil) } else { r.dropped += 1 }
                    if let ll = latLng(s["endLocation"]), let e = b ?? a { add(&r, ll.0, ll.1, e, nil, nil) } else { r.dropped += 1 }
                }
            }
        } else if let o = j as? [String: Any], let segs = o["semanticSegments"] as? [[String: Any]] {
            r = Result(shape: .android, samples: [], dropped: 0)
            segments(segs, &r)
            signals((o["rawSignals"] as? [[String: Any]]) ?? [], &r)
        } else if let a = j as? [[String: Any]], a.contains(where: { $0["startTime"] != nil }) {
            r = Result(shape: .iphone, samples: [], dropped: 0)
            segments(a, &r)
        } else {
            return nil
        }
        return r
    }

    /// a file read from Files: memory-mapped, so a big one is never all in memory
    static func read(url: URL) -> Result? {
        guard let d = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return read(d)
    }

    // MARK: the streaming scanner (files over 50 MB)

    /// above this a Records.json is scanned instead of parsed (Part 9.7)
    nonisolated(unsafe) static var streamOver = 50 * 1024 * 1024

    /// A's top-level "locations" key within the file's first 4 KB
    static func isRecords(_ d: Data) -> Bool {
        let head = d.prefix(4096)
        return head.range(of: Data("\"locations\"".utf8)) != nil
    }

    /// A RECORDS.JSON READ WITHOUT PARSING IT: one pass over the bytes, keeping only each location's own latitudeE7,
    /// longitudeE7, accuracy and timestamp / timestampMs (the keys inside its nested objects, an activity's timestamp,
    /// are not its own and are skipped); strings are stepped over whole, so a brace inside one never counts.
    static func scanRecords(_ d: Data) -> Result {
        var r = Result(shape: .records, samples: [], dropped: 0)
        d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let b = raw.bindMemory(to: UInt8.self)
            let n = b.count
            var i = 0
            var depth = 0            // braces and brackets
            var entryDepth = -1      // the depth inside one location object, once "locations" has been seen
            var sawLocations = false
            var lastKey: [UInt8] = []
            var lat: Double?, lon: Double?, acc: Double?, ts: Date?
            func reset() { lat = nil; lon = nil; acc = nil; ts = nil }
            while i < n {
                let c = b[i]
                if c == 0x22 { // a string: a key when a ':' follows it
                    var j = i + 1
                    while j < n && b[j] != 0x22 { if b[j] == 0x5C { j += 1 }; j += 1 }
                    let s = Array(b[(i + 1) ..< min(j, n)])
                    var k = j + 1
                    while k < n && (b[k] == 0x20 || b[k] == 0x0A || b[k] == 0x0D || b[k] == 0x09) { k += 1 }
                    if k < n && b[k] == 0x3A { // ':' : a key
                        lastKey = s
                        if !sawLocations && depth == 1 && s == Array("locations".utf8) { sawLocations = true }
                        i = k + 1
                        continue
                    }
                    // a string value: the time, when it belongs to the location itself
                    if depth == entryDepth && lastKey == Array("timestamp".utf8) {
                        ts = date(String(decoding: s, as: UTF8.self))
                    } else if depth == entryDepth && lastKey == Array("timestampMs".utf8) {
                        ts = Double(String(decoding: s, as: UTF8.self)).map { Date(timeIntervalSince1970: $0 / 1000) }
                    }
                    i = j + 1
                    continue
                }
                switch c {
                case 0x7B, 0x5B: // { [
                    depth += 1
                    if sawLocations && entryDepth < 0 && c == 0x7B && depth == 3 { entryDepth = 3 }
                case 0x7D, 0x5D: // } ]
                    if c == 0x7D && depth == entryDepth {
                        if let la = lat, let lo = lon, let at = ts {
                            if let a = acc, a >= 2000 { r.dropped += 1 } else { add(&r, la / 1e7, lo / 1e7, at, nil, nil) }
                        } else { r.dropped += 1 }
                        reset()
                    }
                    depth -= 1
                case 0x2D, 0x30 ... 0x39: // a number value: kept when it is the location's own
                    guard depth == entryDepth else { break }
                    var j = i
                    while j < n, (b[j] >= 0x30 && b[j] <= 0x39) || b[j] == 0x2D || b[j] == 0x2E || b[j] == 0x65 || b[j] == 0x45 || b[j] == 0x2B { j += 1 }
                    let v = Double(String(decoding: UnsafeBufferPointer(rebasing: b[i ..< j]), as: UTF8.self))
                    switch lastKey {
                    case Array("latitudeE7".utf8): lat = v
                    case Array("longitudeE7".utf8): lon = v
                    case Array("accuracy".utf8): acc = v
                    case Array("timestampMs".utf8): ts = v.map { Date(timeIntervalSince1970: $0 / 1000) }
                    default: break
                    }
                    i = j
                    continue
                default: break
                }
                i += 1
            }
        }
        return r
    }

    /// C OR D WITHOUT PARSING THE FILE WHOLE: one pass over the bytes finds each element of D's top-level array, or of
    /// C's `semanticSegments` and `rawSignals` arrays, and parses only that element (a few KB); strings are stepped over
    /// whole. Nil when the file holds no segment (then it is read the ordinary way).
    static func scanSegments(_ d: Data) -> Result? {
        var r = Result(shape: .iphone, samples: [], dropped: 0)
        var found = false
        d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let b = raw.bindMemory(to: UInt8.self)
            guard let base = raw.baseAddress else { return }
            let n = b.count
            var i = 0
            var depth = 0
            var topArray = false             // D: the file is one array
            var lastKey1 = (0, 0)            // C: the last string read at depth 1 (the key before an array)
            var arrayKind = 0                // C: 1 inside semanticSegments, 2 inside rawSignals, 0 elsewhere
            var start = -1, kind = 0         // the element being read
            var segs: [[String: Any]] = [], sigs: [[String: Any]] = []
            func flush() {
                autoreleasepool {
                    segments(segs, &r); signals(sigs, &r)
                }
                segs.removeAll(keepingCapacity: true); sigs.removeAll(keepingCapacity: true)
            }
            func key(_ k: String) -> Bool {
                let u = Array(k.utf8)
                return lastKey1.1 - lastKey1.0 == u.count && u.withUnsafeBufferPointer { kp in
                    memcmp(base + lastKey1.0, kp.baseAddress!, u.count) == 0
                }
            }
            while i < n {
                let c = b[i]
                switch c {
                case 0x22: // a string: stepped over whole; at depth 1 it may be C's array key
                    let s0 = i + 1
                    i += 1
                    while i < n, b[i] != 0x22 { if b[i] == 0x5C { i += 1 }; i += 1 }
                    if depth == 1 { lastKey1 = (s0, i) }
                case 0x5B: // [
                    if depth == 0 { topArray = true }
                    if depth == 1, !topArray { arrayKind = key("semanticSegments") ? 1 : key("rawSignals") ? 2 : 0 }
                    depth += 1
                case 0x7B: // {
                    if start < 0 {
                        if topArray, depth == 1 { start = i; kind = 1 }
                        else if !topArray, depth == 2, arrayKind != 0 { start = i; kind = arrayKind }
                    }
                    depth += 1
                case 0x7D: // }
                    depth -= 1
                    let back = topArray ? 1 : 2
                    if start >= 0, depth == back {
                        // each element's own pool, so the parser's temporaries never pile up over a big file
                        autoreleasepool {
                            let slice = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base + start), count: i + 1 - start, deallocator: .none)
                            if let o = (try? JSONSerialization.jsonObject(with: slice)) as? [String: Any] {
                                if kind == 1 { if o["startTime"] != nil { found = true }; segs.append(o) } else { sigs.append(o) }
                            } else { r.dropped += 1 }
                        }
                        if segs.count + sigs.count >= 500 { flush() }
                        start = -1
                    }
                case 0x5D: // ]
                    depth -= 1
                    if depth == 1 { arrayKind = 0 }
                default: break
                }
                i += 1
            }
            flush()
            if !topArray { r.shape = .android }
        }
        return found ? r : nil
    }

    /// C's raw signals: a position with its time (and the offset its time carries)
    private static func signals(_ sigs: [[String: Any]], _ r: inout Result) {
        for s in sigs {
            guard let p = s["position"] as? [String: Any] else { continue }
            if let ll = latLng(p["LatLng"] ?? p["latLng"]), let at = date(p["timestamp"]) {
                add(&r, ll.0, ll.1, at, offsetOf(p["timestamp"]), nil)
            } else { r.dropped += 1 }
        }
    }

    /// C's and D's segments: a visit for its whole span, an activity's two ends, the path's points
    private static func segments(_ segs: [[String: Any]], _ r: inout Result) {
        for s in segs {
            guard let start = date(s["startTime"]) else { r.dropped += 1; continue }
            let end = date(s["endTime"])
            // the zone: C gives it in minutes; D's ISO strings carry it
            let off = num(s["startTimeTimezoneUtcOffsetMinutes"]).map { Int($0) } ?? offsetOf(s["startTime"])
            let endOff = num(s["endTimeTimezoneUtcOffsetMinutes"]).map { Int($0) } ?? offsetOf(s["endTime"]) ?? off
            if let v = s["visit"] as? [String: Any], let c = v["topCandidate"] as? [String: Any] {
                if let ll = latLng(c["placeLocation"]) { add(&r, ll.0, ll.1, start, off, end) } else { r.dropped += 1 }
            }
            if let a = s["activity"] as? [String: Any] {
                if let ll = latLng(a["start"]) { add(&r, ll.0, ll.1, start, off, nil) }
                if let ll = latLng(a["end"]) { add(&r, ll.0, ll.1, end ?? start, endOff, nil) }
            }
            for p in (s["timelinePath"] as? [[String: Any]]) ?? [] {
                guard let ll = latLng(p["point"]) else { r.dropped += 1; continue }
                if let t = date(p["time"]) {
                    add(&r, ll.0, ll.1, t, offsetOf(p["time"]) ?? off, nil)
                } else if let m = num(p["durationMinutesOffsetFromStartTime"]) {
                    add(&r, ll.0, ll.1, start.addingTimeInterval(m * 60), off, nil)
                } else {
                    add(&r, ll.0, ll.1, start, off, nil)
                }
            }
        }
    }

    private static func add(_ r: inout Result, _ lat: Double, _ lon: Double, _ at: Date, _ off: Int?, _ end: Date?) {
        guard abs(lat) <= 90, abs(lon) <= 180, !(lat == 0 && lon == 0) else { r.dropped += 1; return }
        r.samples.append(Sample(lat: lat, lon: lon, at: at, offset: off, end: end.flatMap { $0 > at ? $0 : nil }))
    }

    // MARK: presence (steps 2 and 4)

    /// one row per day, place and 1 km cell
    struct Presence: Equatable, Sendable {
        var day: LocalDay
        var place: String
        var count: Int
        var first: Date
        var last: Date
        var cell: Int64
    }

    /// the samples made into presence rows. `placeAt` answers which place (its id) a point is in, in the borders view
    /// you chose (the map's own shapes); it is asked once per 0.01 degree cell. A sample in no place (the sea) makes no
    /// row. A sample's day is the day where it happened: its own offset, else its place's zone, else the phone's.
    static func presence(_ samples: [Sample], placeAt: (Double, Double) -> String?) -> [Presence] {
        var cellPlace: [Int64: String?] = [:]
        var rows: [String: Presence] = [:]
        var order: [String] = []
        for s in samples {
            let cell = Self.cell(s.lat, s.lon)
            let place: String?
            if let p = cellPlace[cell] { place = p } else { place = placeAt(s.lat, s.lon); cellPlace[cell] = place }
            guard let place else { continue }
            let zone = Self.zone(s, place)
            let d0 = LocalDay(s.at, in: zone)
            let d1 = s.end.map { LocalDay($0, in: zone) } ?? d0
            var d = d0
            var guardDays = 0
            while d <= d1 && guardDays < 400 {   // a visit longer than a year is a bad file: cut
                let k = "\(d)|\(place)|\(cell)"
                if var row = rows[k] {
                    row.count += 1
                    row.first = min(row.first, s.at)
                    row.last = max(row.last, s.end ?? s.at)
                    rows[k] = row
                } else {
                    rows[k] = Presence(day: d, place: place, count: 1, first: s.at, last: s.end ?? s.at, cell: cell)
                    order.append(k)
                }
                d = d.plus(1)
                guardDays += 1
            }
        }
        return order.compactMap { rows[$0] }
    }

    /// the 0.01 degree cell (about 1 km) a point is in
    static func cell(_ lat: Double, _ lon: Double) -> Int64 {
        Int64((lat * 100).rounded(.down)) * 100_000 + Int64((lon * 100).rounded(.down))
    }
    /// the zone a sample happened in: its own offset, else its place's zone, else the phone's (Part 9.9)
    static func zone(_ s: Sample, _ place: String) -> TimeZone {
        s.offset.flatMap { TimeZone(secondsFromGMT: $0 * 60) }
            ?? TimeZones.zone(cc: place.count == 2 ? place : nil, lat: s.lat, lon: s.lon).flatMap(TimeZone.init(identifier:))
            ?? .current
    }

    // MARK: reading values

    static func num(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    /// "48.1372°, 11.5755°", "geo:48.137200,11.575500", {"latLng": ...}, {"latitudeE7":, "longitudeE7":}
    static func latLng(_ v: Any?) -> (Double, Double)? {
        if let o = v as? [String: Any] {
            if let s = o["latLng"] ?? o["LatLng"] { return latLng(s) }
            if let la = num(o["latitudeE7"]), let lo = num(o["longitudeE7"]) { return (la / 1e7, lo / 1e7) }
            return nil
        }
        guard var s = v as? String else { return nil }
        if s.hasPrefix("geo:") { s.removeFirst(4) }
        let parts = s.replacingOccurrences(of: "°", with: "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let la = Double(parts[0]), let lo = Double(parts[1]), abs(la) <= 90, abs(lo) <= 180 else { return nil }
        return (la, lo)
    }

    static func date(_ v: Any?) -> Date? {
        guard var s = v as? String else { return nil }
        // the usual "2024-10-01T19:00:00.000+05:45" read straight from its bytes (a formatter per time made a 60 MB
        // file take 90 s); anything else goes to Apple's ISO formatter
        if let d = s.withUTF8({ iso($0) }) { return d }
        return isoFrac.date(from: s) ?? isoPlain.date(from: s)
    }
    nonisolated(unsafe) private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    /// YYYY-MM-DDTHH:MM:SS, an optional fraction, then Z or ±HH:MM (nothing after); nil for any other form
    static func iso(_ b: UnsafeBufferPointer<UInt8>) -> Date? {
        let n = b.count
        guard n >= 20 else { return nil }
        func num(_ i: Int, _ k: Int) -> Int? {
            var v = 0
            for j in i ..< i + k { let c = b[j]; guard c >= 48, c <= 57 else { return nil }; v = v * 10 + Int(c - 48) }
            return v
        }
        guard b[4] == 45, b[7] == 45, b[10] == 84 || b[10] == 116, b[13] == 58, b[16] == 58,
              let y = num(0, 4), let mo = num(5, 2), let da = num(8, 2), let h = num(11, 2), let mi = num(14, 2), let se = num(17, 2),
              (1 ... 12).contains(mo), da >= 1, h < 24, mi < 60, se < 60 else { return nil }
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        guard da <= [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1] else { return nil }
        var i = 19
        var frac = 0.0
        if i < n, b[i] == 46 {
            i += 1
            var scale = 0.1
            while i < n, b[i] >= 48, b[i] <= 57 { frac += Double(b[i] - 48) * scale; scale /= 10; i += 1 }
        }
        guard i < n else { return nil }
        var off = 0
        if b[i] == 90 || b[i] == 122 { i += 1 }
        else if (b[i] == 43 || b[i] == 45), i + 6 <= n, b[i + 3] == 58, let oh = num(i + 1, 2), let om = num(i + 4, 2) {
            off = (oh * 60 + om) * (b[i] == 45 ? -1 : 1); i += 6
        } else { return nil }
        guard i == n else { return nil }
        // days since 1970 from the civil date (Howard Hinnant's days_from_civil)
        let yy = mo <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * ((mo + 9) % 12) + 2) / 5 + da - 1
        let days = era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468
        // milliseconds, as the formatter keeps them
        let ms = (frac * 1000).rounded()
        return Date(timeIntervalSince1970: Double(days * 86400 + h * 3600 + mi * 60 + se - off * 60) + ms / 1000)
    }

    /// the offset an ISO time carries, in minutes ("...+05:45" 345, "...Z" 0); nil when there is none
    static func offsetOf(_ v: Any?) -> Int? {
        guard let s = v as? String, s.count > 10 else { return nil }
        if s.hasSuffix("Z") { return 0 }
        let tail = s.suffix(6)
        guard let sign = tail.first, sign == "+" || sign == "-", tail.dropFirst(3).first == ":",
              let h = Int(tail.dropFirst().prefix(2)), let m = Int(tail.suffix(2)) else { return nil }
        return (sign == "-" ? -1 : 1) * (h * 60 + m)
    }

    /// B's duration: its start and end, in any of the forms Takeout has written
    private static func span(_ v: Any?) -> (Date?, Date?) {
        guard let d = v as? [String: Any] else { return (nil, nil) }
        func one(_ k: String) -> Date? {
            date(d[k]) ?? num(d[k + "Ms"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        }
        return (one("startTimestamp"), one("endTimestamp"))
    }
}
