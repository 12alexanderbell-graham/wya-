import SwiftUI

/// PINS' MAPS: maps you make, each holding its own pins, routes and drawings. The Pins map shows one at a time;
/// `shown` nil is All pins (every pin, no routes or drawings). New pins, routes and drawings go into the map shown.
/// Kept on the phone (`pin-maps.json`); the map shown is kept between launches. The water at 50% lists them
/// (PinMapsList); the map shows only the one picked.
struct PinMap: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var made = Date()
    /// its layers in order (Google Earth's and My Maps' layers); nil: one, unnamed, never shown as a layer
    var layers: [PinLayer]? = nil
}

/// A LAYER of one of your maps: its name and whether it is shown on the map
struct PinLayer: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var hidden = false
}

@MainActor
@Observable
final class PinMaps {
    static let shared = PinMaps()
    private(set) var all: [PinMap] = []
    /// the map shown; nil: All pins
    var shown: UUID? {
        didSet {
            UserDefaults.standard.set(shown?.uuidString, forKey: "wya.pins.map")
            // (a tool waiting belongs to the map it was chosen on: another map shown puts it away)
            if oldValue != shown { PinsDockState.shared.reset() }
        }
    }

    private var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("pin-maps.json")
    }
    private init() {
        if let u = url, let d = try? Data(contentsOf: u) {
            if let a = try? JSONDecoder().decode([PinMap].self, from: d) { all = a } else { PinRoutes.putAside(u) }
        }
        if let d = UserDefaults.standard.dictionary(forKey: "wya.pins.layer") as? [String: String] {
            picked = Dictionary(uniqueKeysWithValues: d.compactMap { k, v in UUID(uuidString: k).flatMap { a in UUID(uuidString: v).map { (a, $0) } } })
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
    // MARK: layers

    /// the layer something new in the map goes into: the one last picked there, else its first (nil while the map has
    /// no layers). `show`: a hidden one is shown again, so what is made is seen (tracking, done by itself, leaves it).
    func newLayer(in m: UUID?, show: Bool = true) -> UUID? {
        guard let m, let ls = map(m)?.layers, let f = ls.first else { return nil }
        let l = ls.first { $0.id == picked[m] } ?? f
        if show, ls.count > 1, l.hidden { setHidden(l.id, in: m, false) }
        return l.id
    }
    /// the layer new pins, routes and drawings go into in the map shown (a hidden one is shown again)
    func takeLayer() -> UUID? { newLayer(in: shown) }
    /// the same, only read (nothing shown again)
    var layerForNew: UUID? { newLayer(in: shown, show: false) }
    /// the layer last picked, per map (kept between launches)
    var picked: [UUID: UUID] = [:] {
        didSet { UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: picked.map { ($0.key.uuidString, $0.value.uuidString) }),
                                           forKey: "wya.pins.layer") }
    }
    /// the layer an item is in: its own, or the map's first when it has none or one that is gone
    func layerOf(_ m: UUID?, _ x: UUID?) -> PinLayer? {
        guard let m, let ls = map(m)?.layers, let f = ls.first else { return nil }
        return ls.first { $0.id == x } ?? f
    }
    /// a layer that is hidden: what is in it is not drawn on the map (the map's list still has it); a map with one
    /// layer has nothing hidden
    func hidden(_ m: UUID?, _ l: UUID?) -> Bool {
        guard let m, (map(m)?.layers?.count ?? 0) > 1 else { return false }
        return layerOf(m, l)?.hidden ?? false
    }
    /// drawn on the map: in the map shown and not in a hidden layer
    func draws(pin m: UUID?, layer l: UUID?) -> Bool { shows(pin: m) && !hidden(m, l) }
    func draws(extra m: UUID?, layer l: UUID?) -> Bool { shows(extra: m) && !hidden(m, l) }

    /// what in the map is in a layer by itself only through having none, or one that is gone (it reads as the first)
    private func loose(in id: UUID) -> (Set<UUID>, Set<UUID>, Set<UUID>) {
        let known = Set((map(id)?.layers ?? []).map { $0.id })
        func lost(_ x: UUID?) -> Bool { x.map { !known.contains($0) } ?? true }
        return (Set(PinStore.shared.pins.filter { $0.map == id && lost($0.layer) }.map { (p: Pin) in p.id }),
                Set(PinRoutes.shared.routes.filter { $0.map == id && lost($0.layer) }.map { (r: PinRoute) in r.id }),
                Set(PinDrawings.shared.all.filter { $0.map == id && lost($0.layer) }.map { (d: PinDrawing) in d.id }))
    }
    private func setLayer(_ s: (Set<UUID>, Set<UUID>, Set<UUID>), _ l: UUID?) {
        PinStore.shared.setLayer(s.0, l); PinRoutes.shared.setLayer(s.1, l); PinDrawings.shared.setLayer(s.2, l)
    }
    private func setLayers(_ id: UUID, _ ls: [PinLayer]) {
        guard let k = all.firstIndex(where: { $0.id == id }) else { return }
        all[k].layers = ls.isEmpty ? nil : ls
    }

    /// a new layer at the end of the map's layers, picked for what comes next; a map with none first gets its own
    /// first layer (named) so the two read as layers, and everything already in the map goes into it (so its items
    /// keep their layer whatever order the layers are put in later). One undo step; undo and redo change only this
    /// layer (a name or a hide given to another meanwhile stays).
    @discardableResult func addLayer(to id: UUID, named name: String) -> PinLayer? {
        guard map(id) != nil else { return nil }
        var first: PinLayer? = (map(id)?.layers ?? []).isEmpty ? PinLayer(name: "Layer 1") : nil
        var l = PinLayer(name: name)
        var stamped: (Set<UUID>, Set<UUID>, Set<UUID>) = ([], [], [])
        var pickedBefore: UUID?
        let put = { [weak self] in
            guard let self else { return }
            var cur = self.map(id)?.layers ?? []
            if let f = first, !cur.contains(where: { $0.id == f.id }) {
                // (the items with no layer of their own, or one that is gone, go into it)
                stamped = self.loose(in: id)
                cur.insert(f, at: 0)
                self.setLayers(id, cur)
                self.setLayer(stamped, f.id)
            }
            if !cur.contains(where: { $0.id == l.id }) { cur.append(l) }
            self.setLayers(id, cur)
            pickedBefore = self.picked[id]
            self.picked[id] = l.id
            self.save()
            PinsMapState.shared.redrawRoutes()
        }
        let takeBack = { [weak self] in
            guard let self else { return }
            var cur = self.map(id)?.layers ?? []
            if let now = cur.first(where: { $0.id == l.id }) { l = now }
            cur.removeAll { $0.id == l.id }
            if let f = first, cur.count == 1, cur[0].id == f.id {
                first = cur[0]
                cur = []
                self.setLayer(stamped, nil)
            }
            self.setLayers(id, cur)
            if self.picked[id] == l.id { self.picked[id] = pickedBefore }
            self.save()
            PinsMapState.shared.redrawRoutes()
        }
        put()
        MarkStore.shared.did("Layer added", back: takeBack, forth: put)
        return l
    }
    /// PINS, ROUTES AND DRAWINGS MOVED INTO ANOTHER LAYER of their map (an item's hold menu, Move to layer); one undo
    /// step puts each back in the layer it was in
    func move(pins: Set<UUID> = [], routes: Set<UUID> = [], drawings: Set<UUID> = [], to l: UUID, in id: UUID) {
        guard let name = map(id)?.layers?.first(where: { $0.id == l })?.name else { return }
        let was = (PinStore.shared.pins.filter { pins.contains($0.id) }.map { ($0.id, $0.layer) },
                   PinRoutes.shared.routes.filter { routes.contains($0.id) }.map { ($0.id, $0.layer) },
                   PinDrawings.shared.all.filter { drawings.contains($0.id) }.map { ($0.id, $0.layer) })
        let wasHidden = hidden(id, l)
        let put = { [weak self] in
            guard let self else { return }
            self.setLayer((pins, routes, drawings), l)
            // (a hidden layer shown again, so what was just put in it is seen)
            if self.hidden(id, l) { self.setHidden(l, in: id, false) }
            PinsMapState.shared.redrawRoutes()
        }
        let back = {
            for (i, o) in was.0 { PinStore.shared.setLayer([i], o) }
            for (i, o) in was.1 { PinRoutes.shared.setLayer([i], o) }
            for (i, o) in was.2 { PinDrawings.shared.setLayer([i], o) }
            // the layer hidden again if it was, and nothing left open in a layer that isn't drawn
            if wasHidden { PinMaps.shared.setHidden(l, in: id, true) }
            PinMaps.shared.closeHidden(in: id)
            PinsMapState.shared.redrawRoutes()
        }
        put()
        MarkStore.shared.did("Moved to \(name)", back: back, forth: put)
    }
    /// the pin or route open on the map closed when its layer is hidden (it isn't drawn)
    func closeHidden(in id: UUID) {
        if let s = PinStore.shared.selected, let p = PinStore.shared.pin(s), p.map == id, hidden(id, p.layer) {
            PinStore.shared.selected = nil
        }
        if let c = PinRoutes.shared.currentID, let r = PinRoutes.shared.routes.first(where: { $0.id == c }), r.map == id, hidden(id, r.layer) {
            PinRoutes.shared.close()
        }
    }
    /// an item opened from the list while its layer is hidden: the layer is shown, so what opens is on the map
    func reveal(map m: UUID?, layer x: UUID?) {
        guard let m, hidden(m, x), let l = layerOf(m, x)?.id else { return }
        setHidden(l, in: m, false)
    }
    /// a new layer's name: the first the map doesn't have yet (from 2 on a map with no layers yet, whose first
    /// becomes Layer 1)
    func freshName(in id: UUID) -> String {
        let names = Set(map(id)?.layers?.map(\.name) ?? [])
        var n = names.isEmpty ? 2 : 1
        while names.contains("Layer \(n)") { n += 1 }
        return "Layer \(n)"
    }
    /// the layer things go into next, picked by a tap on its name in the map's list
    func pick(_ l: UUID, in id: UUID) {
        guard map(id)?.layers?.contains(where: { $0.id == l }) == true else { return }
        picked[id] = l
    }

    /// a layer named again (an empty name keeps the old one)
    func renameLayer(_ l: UUID, in id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let k = all.firstIndex(where: { $0.id == id }), let j = all[k].layers?.firstIndex(where: { $0.id == l }) else { return }
        all[k].layers?[j].name = n
        save()
    }
    /// a layer shown or hidden on the map; the pin or route open on the map goes when its layer is hidden
    func setHidden(_ l: UUID, in id: UUID, _ hide: Bool) {
        guard let k = all.firstIndex(where: { $0.id == id }), let j = all[k].layers?.firstIndex(where: { $0.id == l }) else { return }
        all[k].layers?[j].hidden = hide
        save()
        if hide {
            if let s = PinStore.shared.selected, let p = PinStore.shared.pin(s), p.map == id, layerOf(id, p.layer)?.id == l {
                PinStore.shared.selected = nil
            }
            if let c = PinRoutes.shared.currentID, let r = PinRoutes.shared.routes.first(where: { $0.id == c }), r.map == id,
               layerOf(id, r.layer)?.id == l {
                PinRoutes.shared.close()
            }
        }
        PinsMapState.shared.redrawRoutes()
    }
    /// a layer moved to another place in the map's order
    func moveLayer(_ l: UUID, in id: UUID, to index: Int) {
        guard let k = all.firstIndex(where: { $0.id == id }), var ls = all[k].layers, let j = ls.firstIndex(where: { $0.id == l }) else { return }
        let x = ls.remove(at: j)
        ls.insert(x, at: min(max(0, index), ls.count))
        all[k].layers = ls
        save()
        PinsMapState.shared.redrawRoutes()
    }
    /// A LAYER TAKEN AWAY: what was in it goes to the layer before it (the first layer's to the next); with one layer
    /// left no layer names show again (that layer is kept, and shown). One undo step brings it back with what was in
    /// it, at its place; undo and redo change only this layer (a name or a hide given to another meanwhile stays).
    func removeLayer(_ l: UUID, in id: UUID) {
        guard let ls = map(id)?.layers, ls.count > 1, let j = ls.firstIndex(where: { $0.id == l }) else { return }
        var removed = ls[j]
        var moved: (Set<UUID>, Set<UUID>, Set<UUID>) = ([], [], [])
        var to: UUID?
        var unhid: UUID?
        var pickMoved = false
        let take = { [weak self] in
            guard let self, var cur = self.map(id)?.layers, cur.count > 1, let i = cur.firstIndex(where: { $0.id == l }) else { return }
            removed = cur[i]
            // (what is in it: its own, and the first layer's items with none or a gone one when it is the first)
            let inIt = (Set(PinStore.shared.pins.filter { $0.map == id && self.layerOf(id, $0.layer)?.id == l }.map { (p: Pin) in p.id }),
                        Set(PinRoutes.shared.routes.filter { $0.map == id && self.layerOf(id, $0.layer)?.id == l }.map { (r: PinRoute) in r.id }),
                        Set(PinDrawings.shared.all.filter { $0.map == id && self.layerOf(id, $0.layer)?.id == l }.map { (d: PinDrawing) in d.id }))
            moved = inIt
            let into = cur[i == 0 ? 1 : i - 1].id
            to = into
            cur.remove(at: i)
            unhid = nil
            if cur.count == 1, cur[0].hidden { cur[0].hidden = false; unhid = cur[0].id }
            self.setLayers(id, cur)
            self.setLayer(moved, into)
            pickMoved = self.picked[id] == l
            if pickMoved { self.picked[id] = into }
            self.save()
            PinsMapState.shared.redrawRoutes()
        }
        let putBack = { [weak self] in
            guard let self else { return }
            var cur = self.map(id)?.layers ?? []
            guard !cur.contains(where: { $0.id == l }) else { return }
            if let u = unhid, let i = cur.firstIndex(where: { $0.id == u }) { cur[i].hidden = true }
            cur.insert(removed, at: min(j, cur.count))
            self.setLayers(id, cur)
            self.setLayer(moved, l)
            if pickMoved, self.picked[id] == to { self.picked[id] = l }
            self.save()
            PinsMapState.shared.redrawRoutes()
        }
        take()
        MarkStore.shared.did("Layer deleted", back: putBack, forth: take)
    }

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
