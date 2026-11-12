import SwiftUI

/// PINS' MAPS (after Google Earth's Projects): maps you make, each holding its own pins, routes and
/// drawings. The Pins map shows one at a time; `shown` nil is All pins (every pin, no routes or drawings). New pins,
/// routes and drawings go into the map shown. Kept on the phone (`pin-maps.json`); the map shown is kept between
/// launches. Step 1: the store and each thing's map; nothing on screen uses it yet.
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

    /// a new map, shown at once; one undo step takes it away
    @discardableResult func make(_ name: String) -> PinMap {
        let m = PinMap(name: name)
        let was = shown
        all.append(m)
        save()
        shown = m.id
        MarkStore.shared.did("Map made", back: { [weak self] in
            self?.all.removeAll { $0.id == m.id }; self?.save(); self?.shown = was
        }, forth: { [weak self] in
            guard let self, !self.all.contains(where: { $0.id == m.id }) else { return }
            self.all.append(m); self.save(); self.shown = m.id
        })
        return m
    }
}
