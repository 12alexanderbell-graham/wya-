import Foundation
import simd

/// ONE COUNTRY'S REGIONS AT ONE LEVEL (Part 6, D10): a `.wyar` file ("WYAR", u32 1, u32 head length, a JSON head
/// {t: [sx, sy, tx, ty], u: units, o: each unit's rings as arc indices (~i reversed), f}, u32 arcs, their starts, then
/// every point as absolute quantized int32 x, y; raw DEFLATE, or plain). A unit is {id, n (name), c (code), p (its
/// parent one level up), q (the disputed piece it lies in, D1b)}; a unit cut by a piece line is several entries with
/// the same id. Rings are even-odd: a ring inside another of the same unit is a hole.
nonisolated struct RegionFile: Sendable {
    struct Unit: Sendable {
        let id: String
        let name: String
        let code: String?
        let parent: String?
        let piece: String?
        /// its rings in longitude and latitude
        let rings: [[SIMD2<Double>]]
    }
    let units: [Unit]
    /// the lines between two different regions (each arc used by units of two ids), in longitude and latitude: the
    /// borders drawn inside the country (its outline is the world's own line)
    let inner: [[SIMD2<Double>]]

    /// the distinct regions (a unit cut by a piece line counts once)
    var ids: [String] {
        var seen = Set<String>(), out: [String] = []
        for u in units where seen.insert(u.id).inserted { out.append(u.id) }
        return out
    }

    init?(data packed: Data) {
        let raw: Data
        if packed.starts(with: [0x57, 0x59, 0x41, 0x52]) { raw = packed }   // "WYAR", plain
        else if let d = try? (packed as NSData).decompressed(using: .zlib) as Data { raw = d }
        else { return nil }
        guard raw.count > 12, raw.starts(with: [0x57, 0x59, 0x41, 0x52]) else { return nil }
        struct Head: Decodable {
            struct U: Decodable { let id: String; let n: String?; let c: String?; let p: String?; let q: String? }
            let t: [Double]
            let u: [U]
            let o: [[[Int]]]
        }
        func u32(_ at: Int) -> Int {
            raw.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian) }
        }
        let jn = u32(8)
        guard raw.count >= 12 + jn + 4,
              let head = try? JSONDecoder().decode(Head.self, from: raw.subdata(in: 12 ..< 12 + jn)),
              head.t.count == 4, head.u.count == head.o.count else { return nil }
        var o = 12 + jn
        let n = u32(o); o += 4
        guard raw.count >= o + 4 * (n + 1) else { return nil }
        var starts = [Int](repeating: 0, count: n + 1)
        for i in 0 ... n { starts[i] = u32(o + 4 * i) }
        o += 4 * (n + 1)
        let total = starts[n]
        guard raw.count >= o + 8 * total else { return nil }
        let sx = head.t[0], sy = head.t[1], tx = head.t[2], ty = head.t[3]
        let pts: [SIMD2<Double>] = raw.withUnsafeBytes { b in
            (0 ..< total).map { k in
                let x = Int32(littleEndian: b.loadUnaligned(fromByteOffset: o + 8 * k, as: Int32.self))
                let y = Int32(littleEndian: b.loadUnaligned(fromByteOffset: o + 8 * k + 4, as: Int32.self))
                return SIMD2(Double(x) * sx + tx, Double(y) * sy + ty)
            }
        }
        func arc(_ r: Int) -> ArraySlice<SIMD2<Double>> {
            let i = r >= 0 ? r : ~r
            guard i < n else { return [] }
            let s = pts[starts[i] ..< starts[i + 1]]
            return r >= 0 ? s : ArraySlice(s.reversed())
        }
        var users = [Set<String>](repeating: [], count: n)
        for (u, rings) in zip(head.u, head.o) {
            for ring in rings { for r in ring { let i = r >= 0 ? r : ~r; if i < n { users[i].insert(u.id) } } }
        }
        inner = (0 ..< n).compactMap { i in users[i].count >= 2 ? Array(arc(i)) : nil }
        units = zip(head.u, head.o).map { u, rings in
            let rs: [[SIMD2<Double>]] = rings.map { ring in
                var p: [SIMD2<Double>] = []
                for r in ring { let a = arc(r); p.append(contentsOf: p.isEmpty ? a : a.dropFirst()) }
                return p
            }
            return Unit(id: u.id, name: u.n ?? u.id, code: u.c, parent: u.p, piece: u.q, rings: rs)
        }
    }
}

/// THE REGION LEVELS OF EVERY PLACE (D10's `region-levels.json`): per place its levels in the file's order (a level's
/// file is `<place>-<row>.wyar`), each with its count and its English names; the bundled level is marked `first`
nonisolated final class RegionCatalog: @unchecked Sendable {
    static let shared = RegionCatalog()
    struct Level: Decodable, Sendable {
        let n: Int
        let k: String?
        let e: [String]?
        let first: Bool?
        var one: String { e?.first ?? k ?? "Region" }
        var many: String { e?.last ?? k ?? "Regions" }
    }
    private let lock = NSLock()
    private var table: [String: [Level]]?
    private var files: [String: RegionFile] = [:]

    var levels: [String: [Level]] {
        lock.lock(); defer { lock.unlock() }
        if let t = table { return t }
        var t: [String: [Level]] = [:]
        if let url = Bundle.main.url(forResource: "region-levels", withExtension: "json"),
           let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([String: [Level]].self, from: d) { t = m }
        table = t
        return t
    }
    /// a place's bundled level: its row (1-based, the file's number) and the level
    func first(_ place: String) -> (row: Int, level: Level)? {
        guard let rows = levels[place], let i = rows.firstIndex(where: { $0.first == true }) else { return nil }
        return (i + 1, rows[i])
    }
    /// the levels in use, coarsest first (the table's order is not top-down where a reform added a row at the end)
    func used(_ place: String) -> [(row: Int, level: Level)] {
        (levels[place] ?? []).enumerated().filter { $0.element.n > 0 }.map { ($0.offset + 1, $0.element) }
            .sorted { $0.1.n < $1.1.n }
    }
    /// a level's file, read once (off the main thread is the caller's business: the biggest bundled one is 1 MB)
    func file(_ place: String, row: Int) -> RegionFile? {
        let key = "\(place)-\(row)"
        lock.lock()
        if let f = files[key] { lock.unlock(); return f }
        lock.unlock()
        guard let url = Bundle.main.url(forResource: key, withExtension: "wyar"),
              let d = try? Data(contentsOf: url), let f = RegionFile(data: d) else { return nil }
        lock.lock(); files[key] = f; lock.unlock()
        return f
    }
}
