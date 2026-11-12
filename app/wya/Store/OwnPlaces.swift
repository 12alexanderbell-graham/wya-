import Foundation
import simd

/// YOUR OWN PLACES (7.8): markable places you made: name, kind (one of the twelve; "other" until you pick), point,
/// country (from the point), private, key `y:<id>` (Part 0.2). Kept on the phone in Application Support
/// (`own-places.json`); a place made by quick add is stamped as it is made (29 Oct 20:30).
@MainActor
@Observable
final class OwnPlaces {
    static let shared = OwnPlaces()
    struct Place: Codable, Hashable, Identifiable {
        let id: String
        var name: String
        var kind: String
        var lat: Double
        var lon: Double
        /// the place it lies in (a world place id, "de")
        let cc: String
        let made: Date
        /// its outline, drawn (Map/DrawTool.swift): [lat, lon] corners of one ring; nil for a place made as a point
        var ring: [[Double]]? = nil
        var key: PlaceKey { PlaceKey(.yours, id) }
        var point: SIMD2<Float> { EqualEarth.project(lon: lon, lat: lat) }
    }
    private(set) var all: [Place] = []

    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("own-places.json")
    }
    private init() {
        if let u = Self.url, let d = try? Data(contentsOf: u), let p = try? JSONDecoder().decode([Place].self, from: d) { all = p }
    }
    private func save() {
        guard let u = Self.url else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: u, options: .atomic)
    }

    /// a new place at a point (or with its drawn outline, the point its middle), named after what is there, kind
    /// "other"
    func make(name: String, lat: Double, lon: Double, cc: String, ring: [[Double]]? = nil) -> Place {
        let p = Place(id: UUID().uuidString.lowercased(), name: name, kind: "other", lat: lat, lon: lon, cc: cc, made: Date(), ring: ring)
        all.append(p)
        save()
        return p
    }
    /// its outline drawn (or drawn again; nil: back to a point), its point the outline's middle
    func setRing(_ id: String, _ ring: [[Double]]?) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].ring = ring
        if let r = ring, !r.isEmpty {
            // (the outline's middle in the map's own plane, its edges' midpoints weighted by their lengths: as a drawn place's
            // point is made, MapController.makeOwnPlace, so an undo puts it back where it was)
            let q = r.map { EqualEarth.project(lon: $0[1], lat: $0[0]) }
            var sx = 0.0, sy = 0.0, sw = 0.0
            for k in 0 ..< q.count {
                let a = q[k], b = q[(k + 1) % q.count], w = Double(simd_distance(a, b))
                sx += Double(a.x + b.x) / 2 * w; sy += Double(a.y + b.y) / 2 * w; sw += w
            }
            guard sw > 0 else { save(); return }
            let ll = EqualEarth.unproject(SIMD2(sx / sw, sy / sw))
            all[i].lat = ll.lat; all[i].lon = ll.lon
        }
        save()
    }
    func remove(_ id: String) {
        all.removeAll { $0.id == id }
        save()
    }
    func rename(_ id: String, to name: String) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].name = String(name.prefix(80))
        save()
    }
    /// its kind, one of the twelve (7.3)
    func setKind(_ id: String, _ kind: String) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].kind = kind
        save()
    }
    /// a removed place back where it was (the undo drop)
    func restore(_ p: Place, at i: Int) {
        guard place(p.id) == nil else { return }
        all.insert(p, at: min(i, all.count))
        save()
    }
    func place(_ id: String) -> Place? { all.first { $0.id == id } }
    /// the twelve kinds (7.3), in the book's order
    static let kinds = ["city", "area", "landmark", "mountain", "water", "nature", "spot", "stay", "station", "route", "event", "other"]
}
