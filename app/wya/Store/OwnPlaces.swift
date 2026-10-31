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
        let lat: Double
        let lon: Double
        /// the place it lies in (a world place id, "de")
        let cc: String
        let made: Date
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

    /// a new place at a point, named after what is there ("Near Kyoto"), kind "other"
    func make(name: String, lat: Double, lon: Double, cc: String) -> Place {
        let p = Place(id: UUID().uuidString.lowercased(), name: name, kind: "other", lat: lat, lon: lon, cc: cc, made: Date())
        all.append(p)
        save()
        return p
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
    func place(_ id: String) -> Place? { all.first { $0.id == id } }
}
