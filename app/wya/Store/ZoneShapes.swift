import Foundation
import simd

/// TIME ZONES BY POINT (Part 17.4 D13): timezone-boundary-builder's 419 zones (release 2025b, ODbL, from
/// OpenStreetMap), simplified to about 200 m (small pieces such as Baarle's enclaves to about 30 m) and packed by
/// tools/tz-pack.py into Resources/Map/timezones.wytz (1.4 MB). A point gets the zone whose shape holds it; at sea or
/// in a gap the old way (the country's nearest zone point, TimeZones.zone) answers. Read once, off the main thread, on
/// first use.
nonisolated final class ZoneShapes: @unchecked Sendable {
    static let shared = ZoneShapes()
    private struct Poly { var zone: Int; var rings: [[SIMD2<Float>]]; var lo: SIMD2<Float>; var hi: SIMD2<Float> }
    private var names: [String] = []
    private var polys: [Poly] = []
    /// 1 degree cells (360 x 180) to the polygons whose box touches them
    private var grid: [[Int32]] = []
    private let lock = NSLock()
    private var loaded = false

    /// the IANA zone at a point, or nil (sea, a gap, the file missing)
    func zone(lat: Double, lon: Double) -> String? {
        lock.lock(); defer { lock.unlock() }
        if !loaded { load(); loaded = true }
        guard !polys.isEmpty else { return nil }
        let cx = min(359, max(0, Int(floor(lon + 180)))), cy = min(179, max(0, Int(floor(lat + 90))))
        let p = SIMD2<Float>(Float(lon), Float(lat))
        for i in grid[cy * 360 + cx] {
            let g = polys[Int(i)]
            guard p.x >= g.lo.x, p.x <= g.hi.x, p.y >= g.lo.y, p.y <= g.hi.y else { continue }
            var inside = false
            for r in g.rings where Self.holds(r, p) { inside.toggle() }
            if inside { return names[g.zone] }
        }
        return nil
    }

    private static func holds(_ r: [SIMD2<Float>], _ p: SIMD2<Float>) -> Bool {
        var c = false
        var j = r.count - 1
        for i in 0 ..< r.count {
            let a = r[i], b = r[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
            j = i
        }
        return c
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "timezones", withExtension: "wytz"),
              let packed = try? Data(contentsOf: url),
              let raw = try? (packed as NSData).decompressed(using: .zlib) as Data, raw.count > 12 else { return }
        raw.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let b = buf.bindMemory(to: UInt8.self)
            var o = 0
            func u32() -> Int { defer { o += 4 }; return Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
            func u16() -> Int { defer { o += 2 }; return Int(b[o]) | Int(b[o + 1]) << 8 }
            func v() -> Int {
                var z = 0, s = 0
                while true { let c = Int(b[o]); o += 1; z |= (c & 0x7f) << s; if c & 0x80 == 0 { break }; s += 7 }
                return (z >> 1) ^ -(z & 1)
            }
            guard b[0] == 0x57, b[1] == 0x59, b[2] == 0x54, b[3] == 0x5A else { return }   // "WYTZ"
            o = 4
            _ = u32()
            let nz = u32()
            for _ in 0 ..< nz {
                let l = Int(b[o]); o += 1
                names.append(String(decoding: UnsafeRawBufferPointer(rebasing: buf[o ..< o + l]), as: UTF8.self)); o += l
            }
            let np = u32()
            var px = 0, py = 0
            grid = Array(repeating: [], count: 360 * 180)
            for k in 0 ..< np {
                let z = u16(), nr = u16()
                var rings: [[SIMD2<Float>]] = []
                var lo = SIMD2<Float>(.infinity, .infinity), hi = SIMD2<Float>(-.infinity, -.infinity)
                for _ in 0 ..< nr {
                    let n = u32()
                    var r: [SIMD2<Float>] = []
                    r.reserveCapacity(n)
                    for _ in 0 ..< n {
                        px += v(); py += v()
                        let q = SIMD2<Float>(Float(px) / 1e4, Float(py) / 1e4)
                        r.append(q); lo = simd_min(lo, q); hi = simd_max(hi, q)
                    }
                    rings.append(r)
                }
                polys.append(Poly(zone: z, rings: rings, lo: lo, hi: hi))
                let x0 = max(0, Int(floor(lo.x + 180))), x1 = min(359, Int(floor(hi.x + 180)))
                let y0 = max(0, Int(floor(lo.y + 90))), y1 = min(179, Int(floor(hi.y + 90)))
                if x0 <= x1, y0 <= y1 { for y in y0 ... y1 { for x in x0 ... x1 { grid[y * 360 + x].append(Int32(k)) } } }
            }
        }
    }
}
