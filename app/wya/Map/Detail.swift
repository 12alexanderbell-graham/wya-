import Foundation
import QuartzCore
import Metal
import simd

/// THE DETAILED MAP: the slices. The world file (Natural Earth) is drawn while the screen is wider than about 2,000 km;
/// from there to about 400 km the 500 m tiles; closer, the 100 m tiles (OpenStreetMap coasts and borders, ODbL). Same
/// data and the same rule as the old app (DetailTiles.swift); the reader is a port of it. A pack,
/// `detail-<level>.wyad`: "WYDP", u32 version 1, u32 head length, a JSON head {"level", "size", "tiles": [[x, y,
/// offset, length]]}, then the tiles, each raw DEFLATE of "WYAD", u32 1, u32 head length, a JSON head {"p": [[item key,
/// [ring point counts]]], "e": [[a, b, ring, start, count]], "x": [[a, b, count]]}, then the points as zigzag varint
/// steps of 1e-5 degrees from the tile's corner. An item's key is "o:<object>" (a country's piece) or "p:<disputed
/// piece>"; `detail-owners.json` says whose each one is.
nonisolated final class DetailPack: @unchecked Sendable {
    let level: String
    let size: Double
    private let data: Data
    private let base: Int
    private let index: [Int64: (offset: Int, length: Int)]

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
        let b = [UInt8](data.prefix(12))
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        guard b.count == 12, b[0] == 0x57, b[1] == 0x59, b[2] == 0x44, b[3] == 0x50, u32(4) == 1 else { throw CocoaError(.coderReadCorrupt) }
        let hl = u32(8)
        guard let head = try JSONSerialization.jsonObject(with: data.subdata(in: 12 ..< 12 + hl)) as? [String: Any],
              let level = head["level"] as? String, let size = (head["size"] as? NSNumber)?.doubleValue,
              let tiles = head["tiles"] as? [[NSNumber]] else { throw CocoaError(.coderReadCorrupt) }
        var idx: [Int64: (Int, Int)] = [:]
        for t in tiles where t.count == 4 {
            idx[Self.key(t[0].doubleValue + size / 2, t[1].doubleValue + size / 2, size)] = (t[2].intValue, t[3].intValue)
        }
        self.level = level; self.size = size; base = 12 + hl; index = idx
    }

    static func key(_ x: Double, _ y: Double, _ size: Double) -> Int64 {
        let i = Int64((x / size).rounded(.down)), j = Int64((y / size).rounded(.down))
        return (i + 1_000_000) * 2_000_000 + (j + 1_000_000)
    }

    /// the tiles (their south-west corners) over a box of longitude and latitude that this level has
    func tiles(lon0: Double, lat0: Double, lon1: Double, lat1: Double) -> [(x: Double, y: Double, key: Int64)] {
        guard lon1 > lon0, lat1 > lat0 else { return [] }
        var out: [(Double, Double, Int64)] = []
        let j0 = Int((max(-90, lat0) / size).rounded(.down)), j1 = Int((min(90, lat1) / size).rounded(.up))
        let i0 = Int((max(-180, lon0) / size).rounded(.down)), i1 = Int((min(180, lon1) / size).rounded(.up))
        guard j1 > j0, i1 > i0 else { return [] }
        for i in i0 ..< i1 {
            for j in j0 ..< j1 {
                let x = Double(i) * size, y = Double(j) * size
                let k = Self.key(x + size / 2, y + size / 2, size)
                if index[k] != nil { out.append((x, y, k)) }
            }
        }
        return out
    }

    func blob(_ key: Int64) -> Data? {
        guard let e = index[key] else { return nil }
        let s = base + e.offset
        return data.subdata(in: s ..< s + e.length)
    }
}

/// A tile laid out for the GPU in map units: every item's rings as even-odd fans (so lakes, its holes, stay sea),
/// each item's run of the fans with whose place it is, and its coasts and borders as line segments.
nonisolated final class DetailTile: @unchecked Sendable {
    let key: Int64
    let points: MTLBuffer
    /// each point's place at the start of the morph (on the coarser level's outline; Morph.swift)
    let from: MTLBuffer
    let fans: MTLBuffer
    let fanCount: Int
    /// per item: the place (index into World.places, -1 for none), its run of the fans, and its own continent when it is
    /// a sliced country's piece ("o:ru|Europe"; nil: its place's)
    let items: [(place: Int, start: Int, count: Int, cont: String?)]
    let segs: MTLBuffer?
    let segCount: Int
    /// for touches: the points again on the CPU, each item's rings in them, and each ring's box (x0 y0 x1 y1)
    let cpu: [SIMD2<Float>]
    let rings: [[Range<Int>]]
    let boxes: [[SIMD4<Float>]]

    init(key: Int64, points: MTLBuffer, from: MTLBuffer, fans: MTLBuffer, fanCount: Int, items: [(place: Int, start: Int, count: Int, cont: String?)],
         segs: MTLBuffer?, segCount: Int, cpu: [SIMD2<Float>], rings: [[Range<Int>]]) {
        self.key = key; self.points = points; self.from = from; self.fans = fans; self.fanCount = fanCount; self.items = items
        self.segs = segs; self.segCount = segCount
        self.cpu = cpu; self.rings = rings
        boxes = rings.map { rs in rs.map { r in
            var b = SIMD4<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            for i in r { let q = cpu[i]; b = SIMD4(min(b.x, q.x), min(b.y, q.y), max(b.z, q.x), max(b.w, q.y)) }
            return b
        } }
    }

    /// the item under a point, as (place, the size of the smallest of its rings that holds the point); nil: none here
    func hits(_ p: SIMD2<Float>) -> [(place: Int, size: Float)] {
        var out: [(place: Int, size: Float)] = []
        for (ii, rs) in rings.enumerated() where items[ii].place >= 0 {
            var inside = false
            var smallest = Float.greatestFiniteMagnitude
            for (ri, r) in rs.enumerated() {
                let b = boxes[ii][ri]
                guard p.x >= b.x, p.x <= b.z, p.y >= b.y, p.y <= b.w, r.count >= 3 else { continue }
                var c = false
                var j = r.upperBound - 1
                for i in r {
                    let a = cpu[i], q = cpu[j]
                    if (a.y > p.y) != (q.y > p.y), p.x < (q.x - a.x) * (p.y - a.y) / (q.y - a.y) + a.x { c.toggle() }
                    j = i
                }
                if c { inside.toggle(); smallest = min(smallest, (b.z - b.x) * (b.w - b.y)) }
            }
            if inside { out.append((items[ii].place, smallest)) }
        }
        return out
    }

    /// tiny pieces near a point (within `reach` map units of their box), as (place, size, distance)
    func near(_ p: SIMD2<Float>, reach: Float, under: Float) -> [(place: Int, size: Float, d: Float)] {
        var out: [(place: Int, size: Float, d: Float)] = []
        for (ii, bs) in boxes.enumerated() where items[ii].place >= 0 {
            for b in bs {
                let size = max(b.z - b.x, b.w - b.y)
                guard size < under else { continue }
                let dx = max(b.x - p.x, 0, p.x - b.z), dy = max(b.y - p.y, 0, p.y - b.w)
                let d = (dx * dx + dy * dy).squareRoot()
                if d <= reach { out.append((items[ii].place, size, d)) }
            }
        }
        return out
    }

    #if DEBUG
    nonisolated(unsafe) static var morphMs: Double = 0
    #endif
    /// one tile's bytes read into points and rings (off the main thread): each point in map units, and whether it lies
    /// on the tile's cut edge (its square's side, where the data was cut, not a real coast)
    struct Parsed {
        var pts: [SIMD2<Float>] = []
        var cut: [Bool] = []
        /// on a line of the coarser level's own grid (a 100 m tile's edge that is also a 500 m tile's): such a point
        /// never moves, since the tiles on its two sides are laid on two different coarse tiles
        var pin: [Bool] = []
        var itemRings: [[Range<Int>]] = []
        var places: [Int] = []
        var keys: [String] = []
        var conts: [String?] = []
        var edges: [[NSNumber]] = []
        /// the lines that are not along a ring (their own points)
        var extra: [(a: Int, b: Int, pts: [SIMD2<Float>], cut: [Bool])] = []
    }

    static func parse(x: Double, y: Double, size: Double, blob: Data, owners: [String: Int], mainLon: [Double],
                      coarseSize: Double = 0) -> Parsed? {
        guard let raw = try? (blob as NSData).decompressed(using: .zlib) as Data else { return nil }
        let bytes = [UInt8](raw)
        func u32(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24 }
        guard bytes.count >= 12, bytes[0] == 0x57, bytes[1] == 0x59, bytes[2] == 0x41, bytes[3] == 0x44 else { return nil }
        let hl = u32(8)
        guard 12 + hl <= bytes.count,
              let head = try? JSONSerialization.jsonObject(with: Data(bytes[12 ..< 12 + hl])) as? [String: Any],
              let ps = head["p"] as? [[Any]] else { return nil }
        let es = head["e"] as? [[NSNumber]] ?? [], xs = head["x"] as? [[NSNumber]] ?? []
        var at = 12 + hl
        func next() -> Int {
            var z = 0, shift = 0
            while at < bytes.count, shift < 63 {
                let b = bytes[at]; at += 1
                z |= Int(b & 0x7f) << shift
                if b & 0x80 == 0 { break }
                shift += 7
            }
            return (z >> 1) ^ -(z & 1)
        }
        var qx = Int((x * 1e5).rounded()), qy = Int((y * 1e5).rounded())
        let ex0 = qx, ey0 = qy, ex1 = Int(((x + size) * 1e5).rounded()), ey1 = Int(((y + size) * 1e5).rounded())
        /// `off` moves a country's piece over the date line to sit beside the rest of it (World: "the pieces over the
        /// date line"): ±360° when the tile is on the far side of 180° from the place's biggest piece
        let grid = Int((coarseSize * 1e5).rounded())
        func point(_ off: Double = 0) -> (SIMD2<Float>, Bool, Bool) {
            qx += next(); qy += next()
            let onCut = qx == ex0 || qx == ex1 || qy == ey0 || qy == ey1
            let onGrid = grid > 0 && onCut && (qx % grid == 0 || qy % grid == 0)
            return (EqualEarth.project(lon: Double(qx) / 1e5 + off, lat: Double(qy) / 1e5), onCut, onGrid)
        }
        func offset(_ key: String) -> Double {
            guard let p = owners[key], p >= 0, p < mainLon.count, !mainLon[p].isNaN else { return 0 }
            let tileLon = x + 0.5
            guard abs(tileLon - mainLon[p]) > 180 else { return 0 }
            return tileLon < mainLon[p] ? 360 : -360
        }
        var out = Parsed()
        for p in ps {
            guard p.count == 2, let key = p[0] as? String, let counts = p[1] as? [NSNumber] else { return nil }
            out.keys.append(key)
            let off = offset(key)
            var rings: [Range<Int>] = []
            for c in counts {
                let n = c.intValue
                let r0 = out.pts.count
                for _ in 0 ..< n { let (q, k, g) = point(off); out.pts.append(q); out.cut.append(k); out.pin.append(g) }
                rings.append(r0 ..< out.pts.count)
            }
            out.itemRings.append(rings)
            out.places.append(owners[key] ?? -1)
            let parts = key.hasPrefix("o:") ? key.dropFirst(2).split(separator: "|") : []
            out.conts.append(parts.count > 1 ? String(parts[1]) : nil)
        }
        out.edges = es
        for e in xs where e.count == 3 {
            let a = e[0].intValue, b = e[1].intValue, n = e[2].intValue
            let off = a >= 0 && a < out.keys.count ? offset(out.keys[a]) : 0
            var line: [SIMD2<Float>] = [], cut: [Bool] = []
            for _ in 0 ..< n { let (q, k, _) = point(off); line.append(q); cut.append(k) }
            out.extra.append((a, b, line, cut))
        }
        return out
    }

    /// the coarse outlines of a parsed tile, for the finer tiles inside it to be laid on
    static func morphIndex(_ p: Parsed) -> MorphIndex {
        var rings: [(points: [SIMD2<Float>], place: Int, cut: [Bool]?)] = []
        for (ii, rs) in p.itemRings.enumerated() {
            for r in rs { rings.append((Array(p.pts[r]), p.places[ii], Array(p.cut[r]))) }
        }
        return MorphIndex(rings: rings, cell: 0.05)
    }

    /// reads one tile's bytes and lays it out (off the main thread); `coarse`: the outlines its morph starts from (nil:
    /// none, it is drawn at its true place always)
    static func make(key: Int64, x: Double, y: Double, size: Double, blob: Data, owners: [String: Int], mainLon: [Double],
                     device: MTLDevice, coarse: MorphIndex?, coarseSize: Double = 0, close: Float, maxR: Float) -> DetailTile? {
        guard let p = parse(x: x, y: y, size: size, blob: blob, owners: owners, mainLon: mainLon, coarseSize: coarseSize) else { return nil }
        let pts = p.pts
        #if DEBUG
        let tm = CACurrentMediaTime()
        #endif
        let from = coarse?.from(points: pts, rings: p.itemRings, places: p.places, cut: p.cut, pin: p.pin, close: close, maxR: maxR) ?? pts
        #if DEBUG
        DetailTile.morphMs += (CACurrentMediaTime() - tm) * 1000
        #endif
        var idx: [UInt32] = []
        var items: [(place: Int, start: Int, count: Int, cont: String?)] = []
        for (ii, rs) in p.itemRings.enumerated() {
            let s = idx.count
            for r in rs where r.count >= 3 {
                let b = UInt32(r.lowerBound)
                for i in 1 ..< r.count - 1 { idx += [b, b + UInt32(i), b + UInt32(i + 1)] }
            }
            items.append((p.places[ii], s, idx.count - s, p.conts[ii]))
        }
        // the lines: coasts (against the sea) and borders. A border is drawn only where the two sides belong to
        // different places in the chosen borders view. Dashed only where the view says a side is a dotted place (the
        // old WorldGeometry.dotted rule); on De facto nothing is dotted. Each segment: its two ends, the same two at
        // their morph start, its distance along the line, its kind.
        var segs: [Float] = []
        let keys = p.keys
        func addLine(_ line: [SIMD2<Float>], _ start: [SIMD2<Float>], a: Int, b: Int) {
            let kind: Float = b < 0 ? 0 : 1
            if b >= 0, b < keys.count, let oa = owners[keys[a]], let ob = owners[keys[b]], oa == ob { return }
            let dashed: Float = b >= 0 && (Borders.dotted(owners[keys[a]]) || Borders.dotted(owners[keys[b]])) ? 1 : 0
            var dist: Float = 0
            for i in 1 ..< max(1, line.count) {
                let p0 = line[i - 1], p1 = line[i]
                let l = simd_length(p1 - p0)
                if l == 0 { continue }
                segs += [p0.x, p0.y, p1.x, p1.y, start[i - 1].x, start[i - 1].y, start[i].x, start[i].y, dist, dashed + 2 * kind]
                dist += l
            }
        }
        for e in p.edges where e.count == 5 {
            let a = e[0].intValue, b = e[1].intValue, ri = e[2].intValue, st = e[3].intValue, n = e[4].intValue
            guard a >= 0, a < p.itemRings.count, ri >= 0, ri < p.itemRings[a].count else { continue }
            let r = p.itemRings[a][ri]
            guard r.count > 0, n >= 2 else { continue }
            var line: [SIMD2<Float>] = [], start: [SIMD2<Float>] = []
            line.reserveCapacity(n); start.reserveCapacity(n)
            for i in 0 ..< n { let j = r.lowerBound + (st + i) % r.count; line.append(pts[j]); start.append(from[j]) }
            addLine(line, start, a: a, b: b)
        }
        for x in p.extra where x.a >= 0 && x.a < keys.count {
            // a line of its own: each point laid on the coarse outline of its place on its own
            var start = x.pts
            if let coarse { start = coarse.lineFrom(points: x.pts, place: p.places[x.a], cut: x.cut, close: close, maxR: maxR) }
            addLine(x.pts, start, a: x.a, b: x.b)
        }
        guard !pts.isEmpty, !idx.isEmpty,
              let pb = device.makeBuffer(bytes: pts, length: pts.count * MemoryLayout<SIMD2<Float>>.stride),
              let fb = device.makeBuffer(bytes: from, length: from.count * MemoryLayout<SIMD2<Float>>.stride),
              let ib = device.makeBuffer(bytes: idx, length: idx.count * 4) else { return nil }
        let sb = segs.isEmpty ? nil : device.makeBuffer(bytes: segs, length: segs.count * 4)
        return DetailTile(key: key, points: pb, from: fb, fans: ib, fanCount: idx.count, items: items, segs: sb,
                          segCount: segs.count / 10, cpu: pts, rings: p.itemRings)
    }
}

/// Which tiles the map shows and keeping them ready: the level for the zoom, the tiles over what is on screen (and a
/// little round it), read off the main thread, 96 kept. A level is drawn only once every tile on screen is ready;
/// until then the coarser map stays, so nothing ever pops in tile by tile.
@MainActor
final class DetailMaps {
    private var packs: [String: DetailPack] = [:]
    private var owners: [String: Int] = [:]
    private let mainLon: [Double]
    private var cache: [Int64: DetailTile] = [:]
    private var used: [Int64: Int] = [:]
    private var clock = 0
    private var loading = Set<Int64>()
    private let device: MTLDevice
    private let world: World
    /// the coarse outlines each tile's morph starts from (Morph.swift)
    private let sources = MorphSources()
    private let keep = 160
    var onReady: () -> Void = {}

    init(device: MTLDevice, world: World) {
        self.device = device
        self.world = world
        mainLon = world.mainLon
        for l in ["500m", "100m"] {
            if let url = Bundle.main.url(forResource: "detail-\(l)", withExtension: "wyad"), let p = try? DetailPack(url: url) { packs[l] = p }
        }
        // whose each detailed item is in the borders view (the old app's detailOwners): a piece to whom the view gives
        // it, the whole of a place given away to the one it goes to (Western Sahara to Morocco on the ground)
        if let pos = world.positions {
            let pieces = world.unitKeys.filter { $0.hasPrefix("piece:") }.map { String($0.dropFirst(6)) }
            for (k, id) in pos.detailOwners(objOwner: world.objOwner, pieces: pieces) {
                if let i = world.placeIndex[id] { owners[k] = i }
            }
        } else if let url = Bundle.main.url(forResource: "detail-owners", withExtension: "json"),
           let d = try? Data(contentsOf: url),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let o = j["owners"] as? [String: Any] {
            for (k, v) in o { if let id = v as? String, let i = world.placeIndex[id] { owners[k] = i } }
        }
    }

    /// THE TILES TO DRAW, or nil for the world's own outlines. What it draws never falls back to a coarser map for a
    /// moment while you move: before, a single tile not yet read anywhere in a margin round the screen sent the whole
    /// map back to the world's coarse outlines until it came, then forward again. Now only the tiles actually on screen
    /// decide; the margin (now 60%) is only read ahead. If the level wanted isn't ready on screen, the level drawn last
    /// stays while it still covers the screen, then the other level, and the world only when nothing else can.
    #if DEBUG
    /// test only (Step 1f's hit test): the tile of a level under a map point, read now on this thread (no morph)
    func testTile(at p: SIMD2<Float>, level: String) -> DetailTile? {
        guard let pack = packs[level] else { return nil }
        let lat = EqualEarth.lat(y: Double(p.y)), lon = EqualEarth.lon(x: Double(p.x), lat: lat)
        let ll = (lon: lon, lat: lat)
        let k = DetailPack.key(ll.lon, ll.lat, pack.size)
        let ck = Self.cacheKey(level, k)
        if let t = cache[ck] { return t }
        let x = (ll.lon / pack.size).rounded(.down) * pack.size, y = (ll.lat / pack.size).rounded(.down) * pack.size
        guard let blob = pack.blob(k) else { return nil }
        return DetailTile.make(key: k, x: x, y: y, size: pack.size, blob: blob, owners: owners, mainLon: mainLon, device: device,
                               coarse: nil, close: 0, maxR: 0)
    }
    #endif

    /// READ AHEAD AT WHERE THE CAMERA IS GOING (a flight's end, set as it starts), so the levels it ends on are ready
    /// when it arrives and nothing drops to the world's outlines on the way (Step 1e: a flight from 400 km out to
    /// 2,500 km and back showed the world's outlines for a moment each time, then the detail settling back in)
    func prefetch(c: SIMD2<Double>, k: Double, view: CGSize) {
        let hw = Double(view.width) / 2 / k, hh = Double(view.height) / 2 / k
        let km = EqualEarth.kmAcross(x0: c.x - hw, x1: c.x + hw, y: c.y)
        func read(_ level: String) {
            guard let pack = packs[level] else { return }
            let box = EqualEarth.geoBox(x0: c.x - hw * 1.3, x1: c.x + hw * 1.3, y0: c.y - hh * 1.3, y1: c.y + hh * 1.3)
            let want = pack.tiles(lon0: box.lon0, lat0: box.lat0, lon1: box.lon1, lat1: box.lat1)
                .map { ($0.x, $0.y, $0.key) }.filter { cache[Self.cacheKey(level, $0.2)] == nil }
            if !want.isEmpty, want.count <= 400 { load(level: level, pack: pack, want) }
        }
        if km < 3000 { read("500m") }
        if km < 620 { read("100m") }
    }

    func visible(c: SIMD2<Double>, k: Double, view: CGSize) -> [DetailTile]? {
        let hw = Double(view.width) / 2 / k, hh = Double(view.height) / 2 / k
        let km = EqualEarth.kmAcross(x0: c.x - hw, x1: c.x + hw, y: c.y)
        lastKm = km
        clock += 1
        func keys(_ pack: DetailPack, margin m: Double) -> [(Double, Double, Int64)] {
            let box = EqualEarth.geoBox(x0: c.x - hw * (1 + m), x1: c.x + hw * (1 + m), y0: c.y - hh * (1 + m), y1: c.y + hh * (1 + m))
            // past the world's edge, the tiles just over the date line too: their pieces that belong on this side are
            // drawn here (Chukotka's tip beside Russia)
            var want = pack.tiles(lon0: box.lon0, lat0: box.lat0, lon1: box.lon1, lat1: box.lat1)
            if box.over > 0 { want += pack.tiles(lon0: -180, lat0: box.lat0, lon1: -180 + box.over, lat1: box.lat1) }
            if box.over < 0 { want += pack.tiles(lon0: 180 + box.over, lat0: box.lat0, lon1: 180, lat1: box.lat1) }
            return want.map { ($0.x, $0.y, $0.key) }
        }
        /// a level's tiles over the screen, if every one of them is ready (the world, nil, always is)
        func ready(_ level: String?) -> [DetailTile]?? {
            guard let level else { return .some(nil) }
            guard let pack = packs[level] else { return nil }
            let onScreen = keys(pack, margin: 0)
            guard onScreen.count <= 400 else { return nil }
            var out: [DetailTile] = []
            for t in onScreen {
                guard let d = cache[Self.cacheKey(level, t.2)] else { return nil }
                out.append(d); used[Self.cacheKey(level, t.2)] = clock
            }
            // and the ready ones just round it, so nothing is missing at the screen's edge while it moves
            for t in keys(pack, margin: 0.15) {
                if let d = cache[Self.cacheKey(level, t.2)], !out.contains(where: { $0 === d }) { out.append(d) }
            }
            return .some(out)
        }
        func readAhead(_ level: String) {
            guard let pack = packs[level] else { return }
            let ahead = keys(pack, margin: 0.6).filter { cache[Self.cacheKey(level, $0.2)] == nil }
            if !ahead.isEmpty, ahead.count <= 400 { load(level: level, pack: pack, ahead) }
        }
        // THE LEVELS CHANGE WITH THE ZOOM ITSELF: across a band of the zoom the finer level is drawn alone, every point
        // moving from its place on the coarser outline to its own (the morph, Morph.swift) as far as the screen is into
        // the band, so a slow pinch changes it slowly, a pinch that stops half way leaves it half way, and zooming back
        // undoes it exactly. Nothing fades: at the band's start the finer level lies on the coarser one, so the swap
        // between them can't be seen. The world's outlines to the 500 m tiles between 2,300 and 1,700 km across, the
        // 500 m to the 100 m between 470 and 330 km.
        let band: (coarse: String?, fine: String, e: Double)?
        let only: String?
        if km >= 2300 { band = nil; only = nil }
        else if km > 1700 { band = (nil, "500m", Double(Flow.smooth(2300, 1700, CGFloat(km)))); only = nil }
        else if km >= 470 { band = nil; only = "500m" }
        else if km > 330 { band = ("500m", "100m", Double(Flow.smooth(470, 330, CGFloat(km)))); only = nil }
        else { band = nil; only = "100m" }
        // read ahead well before a level is needed, so it is there when the band begins
        if km < 3000 { readAhead("500m") }
        if km < 620 { readAhead("100m") }
        var fill: [DetailTile]?? = nil
        var level: String?
        var m: Float = 1
        if let b = band, testCoarse, let cr = ready(b.coarse) {
            // test only: the coarser level as it is, to lay the morph's start over it
            fill = cr; level = b.coarse
        } else if let b = band {
            // the finer level, morphing, once every tile of it on screen is ready; until then the coarser one as it is
            if let fr = ready(b.fine) { fill = fr; level = b.fine; m = Float(b.e) }
            else if let cr = ready(b.coarse) { fill = cr; level = b.coarse }
        } else if let r = ready(only) { fill = r; level = only }
        // A LEVEL ARRIVING LATE (the zoom already into or past the band when its tiles come: a fast pinch, a flight):
        // the same morph runs from its start to where the zoom is over 0.35 s on a smoothstep (Part 1.6), never a jump.
        // Its goal moves with the zoom while it runs.
        let goal: Float = level != nil && level == band?.fine ? m : 1
        let now = CACurrentMediaTime()
        // (only from the level just coarser than it, which its morph starts on: the world for the 500 m tiles, the
        // 500 m tiles for the 100 m ones)
        if let lv = level, (fill ?? nil) != nil, lv != shownLevel, shownLevel == (lv == "100m" ? "500m" : nil), goal > 0.05 {
            arrival = (lv, now)
            #if DEBUG
            FrameStats.log(String(format: "wya detail %@ arrived late, settling to %.2f", lv, goal))
            #endif
        }
        #if DEBUG
        if level != shownLevel { FrameStats.log(String(format: "wya detail level %@ (morph %.2f) -> %@ (morph %.2f)", shownLevel ?? "world", morph, level ?? "world", m)) }
        #endif
        settling = false
        if let a = arrival {
            let k = Float(min(1, (now - a.at) / 0.35))
            if a.level == level && k < 1 { m = goal * k * k * (3 - 2 * k); settling = true } else { arrival = nil }
        }
        // not ready: what was drawn last, while it still covers the screen; then the world
        if fill == nil {
            if let sl = shownLevel, let r = ready(sl) { fill = r; level = sl } else { fill = .some(nil); level = nil }
        }
        let chosen = fill!
        shownLevel = chosen == nil ? nil : level
        shownTiles = chosen
        morph = chosen == nil ? 1 : (testMorph ?? (level == band?.fine || settling ? m : 1))
        lineSets = [(chosen, morph)]
        return chosen
    }

    /// the lines to draw now, and how far into its morph the level is (1: at its true place)
    private(set) var lineSets: [(tiles: [DetailTile]?, morph: Float)] = []
    private(set) var morph: Float = 1
    private var lastKm: Double = 0
    /// a level that came in late, settling into its place (when, and how far it had to go)
    private var arrival: (level: String, at: CFTimeInterval)?
    /// the late level is still settling: the map keeps drawing at full rate
    private(set) var settling = false
    /// test only (driver "morph <0..1|auto>", "coarse on|off"): the morph held at a value; the coarser level shown
    var testMorph: Float?
    var testCoarse = false
    /// test only: every tile read again (after the morph's rules change, or to probe one)
    func dropTiles() { cache = [:]; used = [:]; shownTiles = nil; shownLevel = nil }

    /// THE PLACE UNDER A FINGER on the detailed map: every place whose shape holds the point, and of them the one whose
    /// piece there is smallest (the enclave over the country round it, the Vatican over Rome); a tiny piece within
    /// `reach` of the finger wins over land round it, so a place smaller than a fingertip can still be touched.
    func place(at p: SIMD2<Float>, reach: Float, tiny: Float, small: (Int) -> Bool = { _ in true }) -> Int? {
        guard let tiles = shownTiles else { return nil }
        return Self.place(in: tiles, at: p, reach: reach, tiny: tiny, small: small)
    }
    /// the same, on given tiles, from any thread (the tiles never change once made); `small`: the places the reach may
    /// find (only places smaller than a fingertip, never a small piece of a big country)
    nonisolated static func place(in tiles: [DetailTile], at p: SIMD2<Float>, reach: Float, tiny: Float,
                                  small: (Int) -> Bool = { _ in true }) -> Int? {
        var best: (place: Int, size: Float)?
        for t in tiles { for h in t.hits(p) where h.size < (best?.size ?? .greatestFiniteMagnitude) { best = h } }
        var close: (place: Int, d: Float)?
        for t in tiles { for n in t.near(p, reach: reach, under: tiny) where small(n.place) && n.d < (close?.d ?? .greatestFiniteMagnitude) { close = (n.place, n.d) } }
        if let c = close, c.place != best?.place, (best?.size ?? .greatestFiniteMagnitude) > tiny * tiny { return c.place }
        return best?.place
    }

    private var shownLevel: String?
    private var shownTiles: [DetailTile]?
    var debugState: String {
        "level \(shownLevel ?? "world") morph \(String(format: "%.2f", morph)) km \(Int(lastKm)) tiles \(shownTiles?.count ?? -1) segs \(shownTiles?.reduce(0) { $0 + $1.segCount } ?? -1) cache \(cache.count)"
    }
    /// the detailed tiles are what is drawn now (then the world's coarse shapes don't answer touches)
    var drawsTiles: Bool { shownTiles != nil }
    /// the tiles drawn now (nil: the world's own shapes), for lookups made off the main thread
    var tilesShown: [DetailTile]? { shownTiles }

    nonisolated private static func cacheKey(_ level: String, _ k: Int64) -> Int64 { level == "100m" ? k : -k - 1 }

    private func load(level: String, pack: DetailPack, _ tiles: [(Double, Double, Int64)]) {
        let todo = tiles.filter { !loading.contains(Self.cacheKey(level, $0.2)) }
        guard !todo.isEmpty else { return }
        for t in todo { loading.insert(Self.cacheKey(level, t.2)) }
        let owners = self.owners, device = self.device, mainLon = self.mainLon, world = self.world, sources = self.sources
        let coarsePack = packs["500m"]
        Task.detached(priority: .userInitiated) {
            var made: [(Int64, DetailTile?)] = []
            #if DEBUG
            let t0 = CACurrentMediaTime()
            #endif
            for t in todo {
                let ck = DetailMaps.cacheKey(level, t.2)
                guard let blob = pack.blob(t.2) else { made.append((ck, nil)); continue }
                // the coarser outline its morph starts from: the world's for a 500 m tile; for a 100 m tile, the 500 m
                // tile it lies in (2° tiles inside 10° ones). In map units (about 40 km each): `close` 2.4 km and
                // 0.5 km (a cut edge's point that near is laid on it), looked for up to 80 km and 20 km.
                var coarse: MorphIndex?
                var close: Float = 0, maxR: Float = 0
                if level == "500m" {
                    coarse = sources.world(world); close = 0.06; maxR = 2
                } else if level == "100m", let cp = coarsePack {
                    let cx = t.0 + pack.size / 2, cy = t.1 + pack.size / 2
                    let k5 = DetailPack.key(cx, cy, cp.size)
                    let x5 = (cx / cp.size).rounded(.down) * cp.size, y5 = (cy / cp.size).rounded(.down) * cp.size
                    coarse = sources.tile(k5) {
                        cp.blob(k5).flatMap { DetailTile.parse(x: x5, y: y5, size: cp.size, blob: $0, owners: owners, mainLon: mainLon) }
                            .map(DetailTile.morphIndex)
                    }
                    close = 0.0125; maxR = 0.5
                }
                made.append((ck, DetailTile.make(key: t.2, x: t.0, y: t.1, size: pack.size, blob: blob, owners: owners, mainLon: mainLon,
                                                 device: device, coarse: coarse, coarseSize: level == "100m" ? (coarsePack?.size ?? 0) : 0,
                                                 close: close, maxR: maxR)))
            }
            #if DEBUG
            let line = String(format: "wya tiles %@ %d read in %.0f ms (of which the morph: %.0f ms)", level, made.count,
                              (CACurrentMediaTime() - t0) * 1000, DetailTile.morphMs)
            DetailTile.morphMs = 0
            #endif
            await MainActor.run { [made] in
                #if DEBUG
                FrameStats.log(line)
                #endif
                self.arrived(made)
            }
        }
    }

    private func arrived(_ made: [(Int64, DetailTile?)]) {
        for (k, d) in made {
            loading.remove(k)
            if let d { cache[k] = d; used[k] = clock }
        }
        // keep the most recently used
        if cache.count > keep {
            for (k, _) in used.sorted(by: { $0.value < $1.value }).prefix(cache.count - keep) { cache[k] = nil; used[k] = nil }
        }
        onReady()
    }
}

nonisolated extension EqualEarth {
    /// the latitude at a map y (y depends on latitude only)
    static func lat(y: Double) -> Double {
        let target = RY - y / S
        var th = target / A1
        for _ in 0 ..< 8 {
            let t2 = th * th, t6 = t2 * t2 * t2
            let f = th * (A1 + A2 * t2 + t6 * (A3 + A4 * t2)) - target
            let df = A1 + 3 * A2 * t2 + t6 * (7 * A3 + 9 * A4 * t2)
            th -= f / df
        }
        th = min(max(th, -Double.pi / 3), Double.pi / 3)
        return asin(min(1, max(-1, sin(th) / M))) * 180 / .pi
    }
    /// the longitude at a map x on the parallel `lat`
    static func lon(x: Double, lat: Double) -> Double {
        let th = asin(M * sin(lat * .pi / 180)), t2 = th * th, t6 = t2 * t2 * t2
        let xr = x / S - RX
        return xr * M * (A1 + 3 * A2 * t2 + t6 * (7 * A3 + 9 * A4 * t2)) / cos(th) * 180 / .pi
    }
    /// the box of longitude and latitude a box of the map covers; `over` is how many degrees it reaches past 180° (on
    /// the east, positive) or past -180° (on the west, negative)
    static func geoBox(x0: Double, x1: Double, y0: Double, y1: Double) -> (lon0: Double, lat0: Double, lon1: Double, lat1: Double, over: Double) {
        let latTop = lat(y: max(0, y0)), latBottom = lat(y: y1)
        var lats = [latTop, latBottom]
        if latTop > 0, latBottom < 0 { lats.append(0) }
        let lons = lats.flatMap { [lon(x: x0, lat: $0), lon(x: x1, lat: $0)] }
        let lo = lons.min() ?? -180, hi = lons.max() ?? 180
        let over = hi > 180 ? min(180, hi - 180) : lo < -180 ? max(-180, lo + 180) : 0
        return (max(-180, lo), max(-90, latBottom), min(180, hi), min(90, latTop), over)
    }
    /// how many km a span of the map is across, along the parallel at map y
    static func kmAcross(x0: Double, x1: Double, y: Double) -> Double {
        let la = lat(y: y)
        let dl = abs(lon(x: x1, lat: la) - lon(x: x0, lat: la))
        return dl * .pi / 180 * 6371 * cos(la * .pi / 180)
    }
}
