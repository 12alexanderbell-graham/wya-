import SwiftUI

/// PINS' MAPS (after Google Earth's Projects): maps you make, each holding its own pins, routes and
/// drawings. The Pins map shows one at a time; `shown` nil is All pins (every pin, no routes or drawings). New pins,
/// routes and drawings go into the map shown. Kept on the phone (`pin-maps.json`); the map shown is kept between
/// launches. The water at 50% lists them (PinMapsList); the map shows only the one picked.
struct PinMap: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var made = Date()
}

@MainActor
@Observable
final class PinMaps {
    static let shared = PinMaps()
    private(set) var all: [PinMap] = []
    /// the map shown; nil: All pins
    var shown: UUID? {
        didSet { UserDefaults.standard.set(shown?.uuidString, forKey: "wya.pins.map") }
    }

    private var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("pin-maps.json")
    }
    private init() {
        if let u = url, let d = try? Data(contentsOf: u) {
            if let a = try? JSONDecoder().decode([PinMap].self, from: d) { all = a } else { PinRoutes.putAside(u) }
        }
        let s = UserDefaults.standard.string(forKey: "wya.pins.map").flatMap(UUID.init(uuidString:))
        shown = all.contains { $0.id == s } ? s : nil
    }
    private func save() {
        guard let u = url else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(all) { try? d.write(to: u, options: .atomic) }
    }

    func map(_ id: UUID?) -> PinMap? { id.flatMap { i in all.first { $0.id == i } } }

    /// the 50% water: your maps (false), or the shown map's own pins, routes and drawings (its row tapped again)
    var inside = false
    /// a pin is on the map shown: All pins shows every pin
    func shows(pin m: UUID?) -> Bool { shown == nil || m == shown }
    /// a route or drawing is on the map shown: All pins shows the ones made before maps (or whose map is gone)
    func shows(extra m: UUID?) -> Bool { shown == nil ? (m == nil || map(m) == nil) : m == shown }
    /// the map named again (an empty name keeps the old one)
    func rename(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let k = all.firstIndex(where: { $0.id == id }) else { return }
        all[k].name = n
        save()
    }
    /// A MAP TAKEN AWAY: what it held is kept and goes back to All pins; one undo step brings the map back
    func remove(_ id: UUID) {
        guard let k = all.firstIndex(where: { $0.id == id }) else { return }
        let m = all[k], was = shown
        all.remove(at: k)
        if shown == id { shown = nil; inside = false }
        save()
        MarkStore.shared.did("Map deleted", back: { [weak self] in
            guard let self, !self.all.contains(where: { $0.id == m.id }) else { return }
            self.all.insert(m, at: min(k, self.all.count)); self.save(); self.shown = was
        }, forth: { [weak self] in
            self?.all.removeAll { $0.id == m.id }; self?.save(); if self?.shown == m.id { self?.shown = nil }
        })
    }

    /// a new map, shown at once; one undo step takes it away
    /// (`rises`: false when its name is typed at once, the title the answer; the drop rose over it, 14 Nov)
    @discardableResult func make(_ name: String, rises: Bool = true) -> PinMap {
        let m = PinMap(name: name)
        let was = shown
        all.append(m)
        save()
        shown = m.id
        MarkStore.shared.did("Map made", rises: rises, back: { [weak self] in
            self?.all.removeAll { $0.id == m.id }; self?.save(); self?.shown = was
        }, forth: { [weak self] in
            guard let self, !self.all.contains(where: { $0.id == m.id }) else { return }
            self.all.append(m); self.save(); self.shown = m.id
        })
        return m
    }

    /// a map made without being asked for (tracking's): not shown, not an undo step
    func quietly(_ name: String) -> PinMap {
        let m = PinMap(name: name)
        all.append(m)
        save()
        return m
    }
}
