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

    init(key: Int64, points: MTLBuffer, fans: MTLBuffer, fanCount: Int, items: [(place: Int, start: Int, count: Int, cont: String?)],
         segs: MTLBuffer?, segCount: Int, cpu: [SIMD2<Float>], rings: [[Range<Int>]]) {
        self.key = key; self.points = points; self.fans = fans; self.fanCount = fanCount; self.items = items
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

    /// reads one tile's bytes and lays it out (off the main thread)
    static func make(key: Int64, x: Double, y: Double, blob: Data, owners: [String: Int], mainLon: [Double], device: MTLDevice) -> DetailTile? {
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
        /// `off` moves a country's piece over the date line to sit beside the rest of it (World: "the pieces over the
        /// date line"): ±360° when the tile is on the far side of 180° from the place's biggest piece
        func point(_ off: Double = 0) -> SIMD2<Float> {
            qx += next(); qy += next()
            return EqualEarth.project(lon: Double(qx) / 1e5 + off, lat: Double(qy) / 1e5)
        }
        func offset(_ key: String) -> Double {
            guard let p = owners[key], p >= 0, p < mainLon.count, !mainLon[p].isNaN else { return 0 }
            let tileLon = x + 0.5
            guard abs(tileLon - mainLon[p]) > 180 else { return 0 }
            return tileLon < mainLon[p] ? 360 : -360
        }
        var pts: [SIMD2<Float>] = []
        var idx: [UInt32] = []
        var items: [(place: Int, start: Int, count: Int, cont: String?)] = []
        var itemRings: [[Range<Int>]] = []
        var keys: [String] = []
        for p in ps {
            guard p.count == 2, let key = p[0] as? String, let counts = p[1] as? [NSNumber] else { return nil }
            keys.append(key)
            let off = offset(key)
            let s = idx.count
            var rings: [Range<Int>] = []
            for c in counts {
                let n = c.intValue
                let r0 = pts.count
                for _ in 0 ..< n { pts.append(point(off)) }
                rings.append(r0 ..< pts.count)
                if n >= 3 {
                    let b = UInt32(r0)
                    for i in 1 ..< n - 1 { idx += [b, b + UInt32(i), b + UInt32(i + 1)] }
                }
            }
            itemRings.append(rings)
            let parts = key.hasPrefix("o:") ? key.dropFirst(2).split(separator: "|") : []
            items.append((owners[key] ?? -1, s, idx.count - s, parts.count > 1 ? String(parts[1]) : nil))
        }
        // the lines: coasts (against the sea) and borders. A border is drawn only where the two sides belong to
        // different places in the chosen borders view. Dashed only where the view says a side is a dotted place (the
        // old WorldGeometry.dotted rule); on De facto nothing is dotted.
        var segs: [Float] = []
        func addLine(_ line: [SIMD2<Float>], a: Int, b: Int) {
            let kind: Float = b < 0 ? 0 : 1
            if b >= 0, b < keys.count, let oa = owners[keys[a]], let ob = owners[keys[b]], oa == ob { return }
            let dashed: Float = b >= 0 && (Borders.dotted(owners[keys[a]]) || Borders.dotted(owners[keys[b]])) ? 1 : 0
            var dist: Float = 0
            for i in 1 ..< max(1, line.count) {
                let p0 = line[i - 1], p1 = line[i]
                let l = simd_length(p1 - p0)
                if l == 0 { continue }
                segs += [p0.x, p0.y, p1.x, p1.y, dist, dashed + 2 * kind]
                dist += l
            }
        }
        for e in es where e.count == 5 {
            let a = e[0].intValue, b = e[1].intValue, ri = e[2].intValue, st = e[3].intValue, n = e[4].intValue
            guard a >= 0, a < itemRings.count, ri >= 0, ri < itemRings[a].count else { continue }
            let r = itemRings[a][ri]
            guard r.count > 0, n >= 2 else { continue }
            var line: [SIMD2<Float>] = []
            line.reserveCapacity(n)
            for i in 0 ..< n { line.append(pts[r.lowerBound + (st + i) % r.count]) }
            addLine(line, a: a, b: b)
        }
        for e in xs where e.count == 3 {
            let a = e[0].intValue, b = e[1].intValue, n = e[2].intValue
            var line: [SIMD2<Float>] = []
            let off = a >= 0 && a < keys.count ? offset(keys[a]) : 0
            for _ in 0 ..< n { line.append(point(off)) }
            if a >= 0, a < keys.count { addLine(line, a: a, b: b) }
        }
        guard !pts.isEmpty, !idx.isEmpty,
              let pb = device.makeBuffer(bytes: pts, length: pts.count * MemoryLayout<SIMD2<Float>>.stride),
              let ib = device.makeBuffer(bytes: idx, length: idx.count * 4) else { return nil }
        let sb = segs.isEmpty ? nil : device.makeBuffer(bytes: segs, length: segs.count * 4)
        return DetailTile(key: key, points: pb, fans: ib, fanCount: idx.count, items: items, segs: sb, segCount: segs.count / 6,
                          cpu: pts, rings: itemRings)
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
    private let keep = 160
    var onReady: () -> Void = {}

    init(device: MTLDevice, world: World) {
        self.device = device
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
    func visible(c: SIMD2<Double>, k: Double, view: CGSize) -> [DetailTile]? {
        let hw = Double(view.width) / 2 / k, hh = Double(view.height) / 2 / k
        let km = EqualEarth.kmAcross(x0: c.x - hw, x1: c.x + hw, y: c.y)
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
        // THE LEVELS CHANGE WITH THE ZOOM ITSELF: across a band of the zoom the finer lines come in and the coarser go,
        // each as strong as how far into the band the screen is, so a slow pinch changes them slowly, a pinch that
        // stops half way leaves them half way, and zooming back undoes it exactly. The world's outlines to the 500 m
        // tiles between 2,300 and 1,700 km across, the 500 m to the 100 m between 470 and 330 km.
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
        var sets: [(tiles: [DetailTile]?, strength: Float)] = []
        if let b = band {
            let cr = ready(b.coarse), fr = ready(b.fine)
            if let cr, let fr {
                fill = b.e >= 0.5 ? fr : cr
                sets = [(cr, Float(min(1, 2 * (1 - b.e)))), (fr, Float(min(1, 2 * b.e)))]
            } else if let cr { fill = cr; sets = [(cr, 1)] }
            else if let fr { fill = fr; sets = [(fr, 1)] }
        } else if let r = ready(only) { fill = r; sets = [(r, 1)] }
        // not ready: what was drawn last, while it still covers the screen; then the world
        if fill == nil {
            if let sl = shownLevel, let r = ready(sl) { fill = r } else { fill = .some(nil) }
            sets = [(fill!, 1)]
        }
        let chosen = fill!
        shownLevel = chosen == nil ? nil : (band.map { b in (b.e >= 0.5 ? b.fine : b.coarse) } ?? only)
        shownTiles = chosen
        lineSets = sets
        return chosen
    }

    /// the lines to draw now: one set, or while the zoom is in a band between two levels, both, each at its strength
    private(set) var lineSets: [(tiles: [DetailTile]?, strength: Float)] = []

    /// THE PLACE UNDER A FINGER on the detailed map: every place whose shape holds the point, and of them the one whose
    /// piece there is smallest (the enclave over the country round it, the Vatican over Rome); a tiny piece within
    /// `reach` of the finger wins over land round it, so a place smaller than a fingertip can still be touched.
    func place(at p: SIMD2<Float>, reach: Float, tiny: Float) -> Int? {
        guard let tiles = shownTiles else { return nil }
        var best: (place: Int, size: Float)?
        for t in tiles { for h in t.hits(p) where h.size < (best?.size ?? .greatestFiniteMagnitude) { best = h } }
        var close: (place: Int, d: Float)?
        for t in tiles { for n in t.near(p, reach: reach, under: tiny) where n.d < (close?.d ?? .greatestFiniteMagnitude) { close = (n.place, n.d) } }
        if let c = close, c.place != best?.place, (best?.size ?? .greatestFiniteMagnitude) > tiny * tiny { return c.place }
        return best?.place
    }

    private var shownLevel: String?
    private var shownTiles: [DetailTile]?
    var debugState: String {
        "level \(shownLevel ?? "world") tiles \(shownTiles?.count ?? -1) segs \(shownTiles?.reduce(0) { $0 + $1.segCount } ?? -1) cache \(cache.count)"
    }
    /// the detailed tiles are what is drawn now (then the world's coarse shapes don't answer touches)
    var drawsTiles: Bool { shownTiles != nil }

    nonisolated private static func cacheKey(_ level: String, _ k: Int64) -> Int64 { level == "100m" ? k : -k - 1 }

    private func load(level: String, pack: DetailPack, _ tiles: [(Double, Double, Int64)]) {
        let todo = tiles.filter { !loading.contains(Self.cacheKey(level, $0.2)) }
        guard !todo.isEmpty else { return }
        for t in todo { loading.insert(Self.cacheKey(level, t.2)) }
        let owners = self.owners, device = self.device, mainLon = self.mainLon
        Task.detached(priority: .userInitiated) {
            var made: [(Int64, DetailTile?)] = []
            for t in todo {
                let ck = DetailMaps.cacheKey(level, t.2)
                guard let blob = pack.blob(t.2) else { made.append((ck, nil)); continue }
                made.append((ck, DetailTile.make(key: t.2, x: t.0, y: t.1, blob: blob, owners: owners, mainLon: mainLon, device: device)))
            }
            await MainActor.run { [made] in self.arrived(made) }
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
