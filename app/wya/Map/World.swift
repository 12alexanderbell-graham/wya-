import Foundation
import simd

/// The world, already projected: Equal Earth into a box 1000 map units wide, y down from the North Pole. Built once
/// from the old app's topology by tools/prep.py, so the app never projects at launch. world.wyam: "WYAM", u32 version
/// 1, f32 width, f32 height, u32 units, then per unit u16 owner (the place's index in world-meta.json, 0xFFFF none),
/// u32 rings, then per ring u16 unit (0xFFFF = a lake), u32 n, n × (f32 x, f32 y), u32 segments, then per segment 6 ×
/// f32: x0 y0 x1 y1, distance along its line, flags (bit 1 dashed, bit 2 border).
nonisolated final class World: @unchecked Sendable {
    struct Place: Decodable, Sendable {
        let id: String
        let n: String
        let k: String
        let cont: String?
        /// the centre, projected
        let c: [Double]
        /// the centre, lon/lat
        let ll: [Double]
        let official: String?
        let alt: [String]
        let tiny: Bool
        let ext: Double?
        let junk: Bool
        /// its short name (the UN field of the disputes names places by it) and its own topology objects
        let s: String?
        let objs: [String]?
        /// a small place's biggest piece across in the detailed (100 m) map, in map units: its true size (the world
        /// file draws the Vatican a fifth of its size)
        let dsz: Double?
    }
    private struct Meta: Decodable {
        let places: [Place]
        let aliases: [String: String]
        let height: Double
        let unitConts: [[String]]?
        let placeConts: [[String]]?
        let contViews: [String: [Double]]?
        /// each unit's key ("ru|Europe", "piece:crimea"), and a disputed piece's continent for each place it can go to
        let unitKeys: [String]?
        let pieceConts: [String: [String: [String]]]?
    }
    struct Ring: Sendable {
        let unit: Int        // -1: a lake
        let start: Int
        let count: Int
        let box: SIMD4<Float> // x0 y0 x1 y1
    }

    let width: Float
    let height: Float
    let points: [SIMD2<Float>]
    /// whose each unit is in the borders view the world was loaded in (Positions)
    let unitOwner: [Int]
    let unitKeys: [String]
    /// the disputes and the view (whose each piece is, which places are dotted, what search calls them)
    let positions: Positions?
    /// each topology object's place (its own, whatever the view), for the detailed tiles' owners
    let objOwner: [String: String]
    let rings: [Ring]
    let segments: [Float]
    let places: [Place]
    let aliases: [String: String]
    let placeIndex: [String: Int]
    /// each unit's rings, and the lakes'
    let unitRings: [[Int]]
    let lakeRings: [Int]
    /// THE CONTINENTS (the old geo.js inCont, worked out by tools/conts.py from the old data): each unit's (a country
    /// across two is sliced, "ru|Europe" and "ru|Asia", each piece on its own), each place's, and each continent's
    /// view (the old WorldGeometry.contView, in map units x0 y0 x1 y1)
    let unitConts: [[String]]
    /// each place's biggest piece's longitude: which side of the date line the place is on (nan: none, or a place that
    /// stays where it is over the line)
    let mainLon: [Double]
    let placeConts: [[String]]
    let contViews: [String: SIMD4<Double>]
    func inCont(_ place: Int, _ k: String) -> Bool { place >= 0 && place < placeConts.count && placeConts[place].contains(k) }

    /// The places the count counts: everything but the three the data marks as not real places (Clipperton, the
    /// Coral Sea Islands, Ashmore and Cartier): 263.
    var countable: Int { places.reduce(0) { $0 + ($1.junk ? 0 : 1) } }

    /// D19 NEIGHBOURS: who borders whom in this world's borders view (each view is its own World, so Russia's include
    /// Abkhazia and South Ossetia under De facto and not under the UN view). Worked out from the outlines themselves:
    /// two places border where their pieces' rings share a point (the topology draws a shared border once, so both
    /// sides carry the same points). Made once on first use; the map asks for it off the main thread after loading.
    var neighbours: [Set<Int>] {
        neighbourLock.lock(); defer { neighbourLock.unlock() }
        if let n = madeNeighbours { return n }
        var first: [UInt64: Int] = [:]
        first.reserveCapacity(points.count)
        var n = [Set<Int>](repeating: [], count: places.count)
        for r in rings where r.unit >= 0 && r.unit < unitOwner.count {
            let o = unitOwner[r.unit]
            guard o >= 0, o < places.count else { continue }
            for j in r.start ..< r.start + r.count {
                let p = points[j]
                let key = UInt64(p.x.bitPattern) << 32 | UInt64(p.y.bitPattern)
                if let f = first[key] {
                    if f != o { n[f].insert(o); n[o].insert(f) }
                } else {
                    first[key] = o
                }
            }
        }
        madeNeighbours = n
        return n
    }
    /// the neighbours if they are worked out already, never waiting for them (for the main thread)
    var neighboursIfReady: [Set<Int>]? {
        guard neighbourLock.try() else { return nil }
        defer { neighbourLock.unlock() }
        return madeNeighbours
    }
    private let neighbourLock = NSLock()
    private var madeNeighbours: [Set<Int>]?

    /// D12, first part: each country's and territory's names in every language (GeoNames, `place-names.json`), folded,
    /// for search's "starts with" (typing "Allemagne" or "ドイツ" finds Germany). Worked out once, in the background
    /// after the world loads; never used for "did you mean" (its edit distance runs over the place's own names only)
    var otherLanguageNames: [[String]] {
        namesLock.lock(); defer { namesLock.unlock() }
        if let n = madeNames { return n }
        var out = [[String]](repeating: [], count: places.count)
        if let url = Bundle.main.url(forResource: "place-names", withExtension: "json"),
           let d = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode([String: [String]].self, from: d) {
            for (id, names) in m {
                guard let i = placeIndex[id] else { continue }
                out[i] = names.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            }
        }
        madeNames = out
        return out
    }
    private let namesLock = NSLock()
    private var madeNames: [[String]]?

    /// each place's names folded for search (case and accents gone), made once on first use, not per keystroke:
    /// its own name first, then its official name and other names
    private(set) lazy var searchNames: [[String]] = places.map { p in
        let f = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        return [f(p.n)] + ([p.official ?? ""] + p.alt).filter { !$0.isEmpty }.map(f)
    }

    init(wyam: Data, meta: Data, disputes: Data?, view: Borders.View) throws {
        let m = try JSONDecoder().decode(Meta.self, from: meta)
        places = m.places
        aliases = m.aliases
        var pi: [String: Int] = [:]
        for (i, p) in m.places.enumerated() { pi[p.id] = i }
        placeIndex = pi
        placeConts = m.placeConts ?? m.places.map { $0.cont.map { [$0] } ?? [] }
        var cv: [String: SIMD4<Double>] = [:]
        for (k, b) in m.contViews ?? [:] where b.count == 4 { cv[k] = SIMD4(b[0], b[1], b[2], b[3]) }
        contViews = cv

        var o = 0
        func u16() -> Int { defer { o += 2 }; return Int(wyam.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) }) }
        func u32() -> Int { defer { o += 4 }; return Int(wyam.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }) }
        func f32() -> Float { defer { o += 4 }; return wyam.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Float.self) } }
        guard wyam.count > 16, wyam.prefix(4) == Data("WYAM".utf8) else { throw CocoaError(.coderReadCorrupt) }
        o = 4
        let version = u32()
        guard version == 1 || version == 2 else { throw CocoaError(.coderReadCorrupt) }
        width = f32(); height = f32()
        let nu = u32()
        var owners: [Int] = []
        owners.reserveCapacity(nu)
        for _ in 0..<nu { let v = u16(); owners.append(v == 0xFFFF ? -1 : v) }
        // WHOSE EACH UNIT IS IN THE VIEW: the file's owners were the data's defaults; with the disputes, each unit goes
        // to whom the view gives it, the old app's way
        var oo: [String: String] = [:]
        for p in m.places { for o in p.objs ?? [] { oo[o] = p.id } }
        objOwner = oo
        let keys = m.unitKeys ?? []
        unitKeys = keys
        var pos: Positions?
        if let disputes, keys.count == nu {
            let f = try JSONDecoder().decode(DisputeFile.self, from: disputes)
            let p = Positions(file: f, places: m.places.map { ($0.id, $0.s ?? $0.n, $0.k) }, view: view,
                              picks: Borders.picks, fallback: Borders.fallback)
            pos = p
            owners = keys.map { k in p.unitOwner(k, objOwner: oo).flatMap { pi[$0] } ?? -1 }
            Borders.dottedPlaces = Set(m.places.indices.filter { p.dotted(m.places[$0].id) })
        }
        positions = pos
        unitOwner = owners
        let uc = m.unitConts ?? []
        var conts = uc.count == nu ? uc : owners.map { $0 >= 0 ? (m.places[$0].cont.map { [$0] } ?? []) : [] }
        // a disputed piece is on the continent of the place it is drawn with (Crimea with Russia's European part)
        if let pc = m.pieceConts {
            for (u, k) in keys.enumerated() where u < conts.count && owners[u] >= 0 {
                if let c = pc[k]?[m.places[owners[u]].id] { conts[u] = c }
            }
        }
        unitConts = conts
        let nr = u32()
        var pts: [SIMD2<Float>] = []
        pts.reserveCapacity(140_000)
        var rs: [Ring] = []
        rs.reserveCapacity(nr)
        var ur = Array(repeating: [Int](), count: nu)
        var lr: [Int] = []
        try wyam.withUnsafeBytes { raw in
            for _ in 0..<nr {
                let u = Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)); o += 2
                let n = Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)); o += 4
                guard o + n * 8 <= raw.count else { throw CocoaError(.coderReadCorrupt) }
                let start = pts.count
                var x0 = Float.greatestFiniteMagnitude, y0 = x0, x1 = -x0, y1 = -x0
                for _ in 0..<n {
                    let x = raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                    let y = raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self)
                    o += 8
                    pts.append(SIMD2(x, y))
                    x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
                }
                let unit = u == 0xFFFF ? -1 : u
                if unit >= 0 { ur[unit].append(rs.count) } else { lr.append(rs.count) }
                rs.append(Ring(unit: unit, start: start, count: n, box: SIMD4(x0, y0, x1, y1)))
            }
        }
        // THE PIECES OVER THE DATE LINE: a country's piece on the far side of 180° from the rest of it is moved over
        // the line to sit beside it, Chukotka's tip beside Russia, the Aleutians past 180° beside Alaska, Fiji's and
        // New Zealand's islands east of the line beside them. Each point moves by its own parallel's width (360°
        // there), the same as drawing it at its longitude ± 360°, so the shape is exactly its own. Antarctica (it is
        // the whole width) and Kiribati (it truly spans the line, with no side to belong to) stay where they are. The
        // relief and the sea run on past the edge, so the moved pieces have their own ground under them.
        func lonAt(_ x: Float, _ y: Float) -> Double { EqualEarth.lon(x: Double(x), lat: EqualEarth.lat(y: Double(y))) }
        var biggest: [Int: (area: Float, ring: Int)] = [:]
        for (ri, r) in rs.enumerated() where r.unit >= 0 && owners[r.unit] >= 0 {
            let a = (r.box.z - r.box.x) * (r.box.w - r.box.y), p = owners[r.unit]
            if a > (biggest[p]?.area ?? -1) { biggest[p] = (a, ri) }
        }
        var ml = [Double](repeating: .nan, count: m.places.count)
        for (p, b) in biggest where !Self.spansTheLine.contains(m.places[p].id) {
            let bx = rs[b.ring].box
            ml[p] = lonAt((bx.x + bx.z) / 2, (bx.y + bx.w) / 2)
        }
        mainLon = ml
        var movedTo: [SIMD2<Float>: SIMD2<Float>] = [:]
        for (ri, r) in rs.enumerated() where r.unit >= 0 {
            let p = owners[r.unit]
            guard p >= 0, !ml[p].isNaN else { continue }
            let c = lonAt((r.box.x + r.box.z) / 2, (r.box.y + r.box.w) / 2)
            guard abs(c - ml[p]) > 180 else { continue }
            let side: Float = c < ml[p] ? 1 : -1
            var x0 = Float.greatestFiniteMagnitude, x1 = -x0
            for i in r.start ..< r.start + r.count {
                let q = pts[i]
                let nq = SIMD2(q.x + side * Float(EqualEarth.wrapStep(y: Double(q.y))), q.y)
                movedTo[q] = nq
                pts[i] = nq
                x0 = min(x0, nq.x); x1 = max(x1, nq.x)
            }
            rs[ri] = Ring(unit: r.unit, start: r.start, count: r.count, box: SIMD4(x0, r.box.y, x1, r.box.w))
        }
        points = pts
        rings = rs
        unitRings = ur
        lakeRings = lr
        let ns = u32()
        let stride = version == 2 ? 8 : 6
        guard o + ns * stride * 4 <= wyam.count else { throw CocoaError(.coderReadCorrupt) }
        var raw = [Float](repeating: 0, count: ns * stride)
        raw.withUnsafeMutableBytes { dst in
            wyam.withUnsafeBytes { src in
                dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[o ..< o + ns * stride * 4]))
            }
        }
        var sg: [Float]
        if version == 2 {
            // each line keeps its two units: a border is drawn only between two places in this view (none between
            // Crimea and Russia on the ground, one on Ukraine's map), and dotted where it touches a dotted place
            sg = []
            sg.reserveCapacity(ns * 6)
            var i = 0
            while i + 7 < raw.count {
                let ua = Int(raw[i + 6]), ub = Int(raw[i + 7])
                let oa = ua >= 0 && ua < owners.count ? owners[ua] : -1
                let ob = ub >= 0 && ub < owners.count ? owners[ub] : -1
                if ub < 0 {
                    sg += [raw[i], raw[i + 1], raw[i + 2], raw[i + 3], raw[i + 4], 0]
                } else if oa != ob {
                    let dashed: Float = Borders.dotted(oa >= 0 ? oa : nil) || Borders.dotted(ob >= 0 ? ob : nil) ? 1 : 0
                    sg += [raw[i], raw[i + 1], raw[i + 2], raw[i + 3], raw[i + 4], 2 + dashed]
                }
                i += 8
            }
        } else {
            sg = raw
            if !Borders.anyDotted {
                var i = 5
                while i < sg.count { sg[i] = sg[i] >= 2 ? 2 : 0; i += 6 }
            }
        }
        // THE LAKES' SHORES at the world's own level too: the world file has the lakes as shapes but no shore lines,
        // while the slices draw every shore, so going in a level made the shores appear at once. Each lake ring's edges
        // are added here as coast (BUILD-BOOK 1.6: "lake shores exist at every level").
        for li in lr {
            let r = rs[li]
            guard r.count >= 3 else { continue }
            var dist: Float = 0
            for j in 0 ..< r.count {
                let a = pts[r.start + j], b = pts[r.start + (j + 1) % r.count]
                sg += [a.x, a.y, b.x, b.y, dist, 0]
                dist += simd_length(b - a)
            }
        }
        // the moved pieces' coasts go with them: a line whose two ends are points of a moved piece
        if !movedTo.isEmpty {
            var i = 0
            while i + 5 < sg.count {
                if let a = movedTo[SIMD2(sg[i], sg[i + 1])], let b = movedTo[SIMD2(sg[i + 2], sg[i + 3])] {
                    sg[i] = a.x; sg[i + 1] = a.y; sg[i + 2] = b.x; sg[i + 3] = b.y
                }
                i += 6
            }
        }
        segments = sg
    }

    /// the places that stay where they are over the date line (see above)
    static let spansTheLine: Set<String> = ["aq", "ki"]

    static func load() throws -> World {
        guard let a = Bundle.main.url(forResource: "world", withExtension: "wyam"),
              let b = Bundle.main.url(forResource: "world-meta", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        let d = Bundle.main.url(forResource: "disputes", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        return try World(wyam: Data(contentsOf: a), meta: Data(contentsOf: b), disputes: d, view: Borders.view)
    }

    /// The part of a place to frame when it is flown to: its biggest piece of land and the pieces close to it, gathered
    /// outward one after another (a gap under a twelfth of the biggest piece's size), so the United States is the 48
    /// states and not Alaska and Hawaii too, Russia is not stretched over the date line by its piece past 180°, and
    /// Indonesia is all its islands. A small archipelago (all of it under 30 map units, about 1,200 km) is framed
    /// whole: the Bahamas, Cape Verde, the Maldives. x0 y0 x1 y1 in map units.
    func frame(of place: Int) -> SIMD4<Float>? {
        var boxes: [SIMD4<Float>] = []
        for (u, owner) in unitOwner.enumerated() where owner == place {
            for ri in unitRings[u] { boxes.append(rings[ri].box) }
        }
        func area(_ b: SIMD4<Float>) -> Float { (b.z - b.x) * (b.w - b.y) }
        func union(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
            SIMD4(min(a.x, b.x), min(a.y, b.y), max(a.z, b.z), max(a.w, b.w))
        }
        guard let mi = boxes.indices.max(by: { area(boxes[$0]) < area(boxes[$1]) }) else { return nil }
        let all = boxes.dropFirst().reduce(boxes[0], union)
        if max(all.z - all.x, all.w - all.y) < 30 { return all }
        var f = boxes[mi]
        let reach = max(f.z - f.x, f.w - f.y) / 12
        var left = boxes
        left.remove(at: mi)
        var grew = true
        while grew {
            grew = false
            left.removeAll { b in
                let dx = max(f.x - b.z, 0, b.x - f.z), dy = max(f.y - b.w, 0, b.y - f.w)
                guard (dx * dx + dy * dy).squareRoot() <= reach else { return false }
                f = union(f, b)
                grew = true
                return true
            }
        }
        return f
    }

    /// The place under a point of the map (map units), by the even-odd rule on its rings; nil over the sea or a lake.
    /// Where several hold it (an enclave and the country round it, the Vatican and Italy), the smallest piece there
    /// wins; a tiny piece within `reach` of the point wins over land round it, so a place smaller than a fingertip can
    /// be touched.
    func place(at p: SIMD2<Float>, reach: Float = 0, tiny: Float = 0) -> Int? {
        var inside: [Int: (on: Bool, size: Float)] = [:]
        for (i, r) in rings.enumerated() where r.unit >= 0 {
            guard p.x >= r.box.x && p.x <= r.box.z && p.y >= r.box.y && p.y <= r.box.w else { continue }
            if crosses(rings[i], p) {
                let sz = (r.box.z - r.box.x) * (r.box.w - r.box.y)
                let cur = inside[r.unit] ?? (false, .greatestFiniteMagnitude)
                inside[r.unit] = (!cur.on, min(cur.size, sz))
            }
        }
        // over a lake: nothing
        for i in lakeRings {
            let r = rings[i]
            if p.x >= r.box.x && p.x <= r.box.z && p.y >= r.box.y && p.y <= r.box.w && crosses(r, p) { return nil }
        }
        var best: (place: Int, size: Float)?
        for (u, v) in inside where v.on && unitOwner[u] >= 0 && v.size < (best?.size ?? .greatestFiniteMagnitude) {
            best = (unitOwner[u], v.size)
        }
        if reach > 0 {
            var close: (place: Int, d: Float)?
            for r in rings where r.unit >= 0 && unitOwner[r.unit] >= 0 && places[unitOwner[r.unit]].tiny {
                // only a small place (smaller than a fingertip) is found by the reach, never a small piece of a big
                // country (Step 1f: a press in Kaliningrad picked Lithuania's bit of the Curonian Spit)
                let size = max(r.box.z - r.box.x, r.box.w - r.box.y)
                guard size < tiny else { continue }
                let dx = max(r.box.x - p.x, 0, p.x - r.box.z), dy = max(r.box.y - p.y, 0, p.y - r.box.w)
                let d = (dx * dx + dy * dy).squareRoot()
                if d <= reach, d < (close?.d ?? .greatestFiniteMagnitude) { close = (unitOwner[r.unit], d) }
            }
            if let c = close, c.place != best?.place, (best?.size ?? .greatestFiniteMagnitude) > tiny * tiny { return c.place }
        }
        return best?.place
    }

    /// the disputed piece under a map point ("crimea"), the smallest if pieces overlap; nil off every piece
    func piece(at p: SIMD2<Float>) -> String? {
        var inside: [Int: (on: Bool, size: Float)] = [:]
        for r in rings where r.unit >= 0 && r.unit < unitKeys.count && unitKeys[r.unit].hasPrefix("piece:") {
            guard p.x >= r.box.x && p.x <= r.box.z && p.y >= r.box.y && p.y <= r.box.w, crosses(r, p) else { continue }
            let cur = inside[r.unit] ?? (false, .greatestFiniteMagnitude)
            inside[r.unit] = (!cur.on, min(cur.size, (r.box.z - r.box.x) * (r.box.w - r.box.y)))
        }
        return inside.filter { $0.value.on }.min { $0.value.size < $1.value.size }.map { String(unitKeys[$0.key].dropFirst(6)) }
    }
    private func crosses(_ r: Ring, _ p: SIMD2<Float>) -> Bool {
        var c = false
        var j = r.start + r.count - 1
        for i in r.start ..< r.start + r.count {
            let a = points[i], b = points[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { c.toggle() }
            }
            j = i
        }
        return c
    }
}

/// The detailed map's picture (old app, Slice 127l): per point of the world the sea's depth and the land's height,
/// already on the scale the map colours by, from NOAA's ETOPO1 (public domain), every 4th arc-minute.
/// relief.wyar is raw DEFLATE of "WYAR", u32 1, u32 width, u32 height, then width × height pairs (depth, height).
nonisolated struct Relief: Sendable {
    let width: Int
    let height: Int
    let bytes: Data

    static func load() throws -> Relief {
        guard let url = Bundle.main.url(forResource: "relief", withExtension: "wyar") else { throw CocoaError(.fileNoSuchFile) }
        let packed = try Data(contentsOf: url)
        let raw = try (packed as NSData).decompressed(using: .zlib) as Data
        guard raw.count >= 16, raw.prefix(4) == Data("WYAR".utf8) else { throw CocoaError(.coderReadCorrupt) }
        func u32(_ o: Int) -> Int { Int(raw.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }) }
        let w = u32(8), h = u32(12)
        guard raw.count == 16 + w * h * 2 else { throw CocoaError(.coderReadCorrupt) }
        return Relief(width: w, height: h, bytes: raw.subdata(in: 16 ..< raw.count))
    }
}
