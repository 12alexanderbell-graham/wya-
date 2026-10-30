import Foundation
import simd

/// A TOWN (Part 7, D3): GeoNames' cities500 merged into the old app's towns, one file per place
/// (`towns-<cc>.wyat`: raw DEFLATE of JSON rows [name, region, population, lat, lon, kind, GeoNames id, part of]).
/// kind: 0 a town, 1 a regional capital, 2 the capital. A town's stamp key is `t:<file>/<GeoNames id>` (or its name
/// where it has no id), so Paris in Texas is never Paris in France (Part 0.2.2, the old app's keys).
nonisolated struct Town: Sendable, Equatable {
    let name: String
    let region: String
    let people: Int
    let lat: Double
    let lon: Double
    let kind: Int
    let gid: Int
    /// the bigger town it is part of ("Vienna" for Favoriten), or ""
    let part: String
    /// the file it comes from
    let file: String

    /// its stamp's key id ("fr/2988507")
    var id: String { gid != 0 ? "\(file)/\(gid)" : "\(file)/\(name)" }
    var key: PlaceKey { PlaceKey(.town, id) }
}

nonisolated enum TownFile {
    /// a file's towns (raw DEFLATE, or plain JSON)
    static func parse(_ packed: Data, file: String) -> [Town]? {
        let raw: Data
        if packed.first == UInt8(ascii: "[") { raw = packed }
        else if let d = try? (packed as NSData).decompressed(using: .zlib) as Data { raw = d }
        else { return nil }
        guard let rows = try? JSONSerialization.jsonObject(with: raw) as? [[Any]] else { return nil }
        return rows.compactMap { r in
            guard r.count >= 7, let n = r[0] as? String, let lat = (r[3] as? NSNumber)?.doubleValue,
                  let lon = (r[4] as? NSNumber)?.doubleValue else { return nil }
            return Town(name: n, region: r[1] as? String ?? "", people: (r[2] as? NSNumber)?.intValue ?? 0, lat: lat, lon: lon,
                        kind: (r[5] as? NSNumber)?.intValue ?? 0, gid: (r[6] as? NSNumber)?.intValue ?? 0,
                        part: r.count > 7 ? r[7] as? String ?? "" : "", file: file)
        }
    }
}

/// THE TOWNS AS THEIR BUILT-UP SHAPES (7.4: GHSL 90 m, the old app's `urban-<cc>.wyau`): raw DEFLATE of "WYAU", u32 1,
/// u32 head length, head JSON {"t": [[town key, [ring point counts]], ...]}, then every ring's points as zigzag varints
/// of 1e-5 degrees, longitude then latitude, each a step from the point before. Outlines run anticlockwise, holes
/// clockwise.
nonisolated enum UrbanFile {
    struct Shape: Sendable { let key: String; let rings: [[SIMD2<Double>]] }

    static func parse(_ packed: Data) -> [Shape]? {
        let raw: Data
        if packed.starts(with: [0x57, 0x59, 0x41, 0x55]) { raw = packed }
        else if let d = try? (packed as NSData).decompressed(using: .zlib) as Data { raw = d }
        else { return nil }
        let b = [UInt8](raw)
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        guard b.count >= 12, b[0] == 0x57, b[1] == 0x59, b[2] == 0x41, b[3] == 0x55, u32(4) == 1 else { return nil }
        let hl = u32(8)
        guard 12 + hl <= b.count,
              let head = try? JSONSerialization.jsonObject(with: Data(b[12 ..< 12 + hl])) as? [String: Any],
              let rows = head["t"] as? [[Any]] else { return nil }
        var at = 12 + hl
        func next() -> Int? {
            var z = 0, shift = 0
            while true {
                guard at < b.count, shift < 63 else { return nil }
                let x = b[at]; at += 1
                z |= Int(x & 0x7f) << shift
                if x & 0x80 == 0 { break }
                shift += 7
            }
            return (z >> 1) ^ -(z & 1)
        }
        var x = 0, y = 0
        var out: [Shape] = []
        out.reserveCapacity(rows.count)
        for r in rows {
            guard r.count == 2, let key = r[0] as? String, let counts = r[1] as? [Any] else { return nil }
            var rings: [[SIMD2<Double>]] = []
            for c in counts {
                guard let n = (c as? NSNumber)?.intValue, n >= 0 else { return nil }
                var ring: [SIMD2<Double>] = []
                ring.reserveCapacity(n)
                for _ in 0 ..< n {
                    guard let dx = next(), let dy = next() else { return nil }
                    x += dx; y += dy
                    ring.append(SIMD2(Double(x) / 1e5, Double(y) / 1e5))
                }
                rings.append(ring)
            }
            out.append(Shape(key: key, rings: rings))
        }
        return out
    }
}

/// A PLACE'S TOWNS AND THEIR SHAPES, from the data server (Part 17.7), kept once they have come
nonisolated final class TownStore: @unchecked Sendable {
    static let shared = TownStore()
    private let lock = NSLock()
    private var towns: [String: [Town]] = [:]
    private var shapes: [String: [UrbanFile.Shape]] = [:]

    func towns(_ cc: String) async -> [Town]? {
        lock.lock(); if let t = towns[cc] { lock.unlock(); return t }; lock.unlock()
        guard case .ok(let d) = await Servers.data.file("native/towns/towns-\(cc).wyat"), let t = TownFile.parse(d, file: cc) else { return nil }
        lock.lock(); towns[cc] = t; lock.unlock()
        return t
    }
    func shapes(_ cc: String) async -> [UrbanFile.Shape] {
        lock.lock(); if let s = shapes[cc] { lock.unlock(); return s }; lock.unlock()
        guard case .ok(let d) = await Servers.data.file("native/urban/urban-\(cc).wyau"), let s = UrbanFile.parse(d) else { return [] }
        lock.lock(); shapes[cc] = s; lock.unlock()
        return s
    }
}
