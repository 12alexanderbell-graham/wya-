import SwiftUI
import MapKit

/// PINS' DRAWINGS: the lines and shapes drawn on Apple's map with the one draw tool (Map/DrawTool.swift), kept on the
/// phone beside the pins (`pin-drawings.json`). A drawing has no name until it is given one (its line in Saved is its
/// length or its area); black unless it is given a colour, as a route.
struct PinDrawing: Codable, Identifiable, Hashable {
    var id = UUID()
    /// "line" or "shape"
    var kind: String
    var name = ""
    var note = ""
    /// its colour as the picker holds it (as a route's and a pin's), nil for black
    var pick: ColourPick?
    /// [lat, lon] corners
    var points: [[Double]]
    var made = Date()
    /// the map of yours it is in (Map/PinMaps.swift); nil: none
    var map: UUID? = nil

    var isShape: Bool { kind == "shape" }
    var geo: [DrawTool.Geo] { points.map { DrawTool.Geo(lat: $0[0], lon: $0[1]) } }
    /// its length (a line) or its area (a shape), in words
    var measure: String {
        let g = geo
        if isShape { return DrawTool.words(km2: DrawTool.area(g)) }
        var t = 0.0
        for i in 1 ..< max(1, g.count) { t += DrawTool.km(g[i - 1], g[i]) }
        return DrawTool.words(km: t)
    }
    var ink: UIColor { pick?.uiColor ?? UIColor(Palette.ink) }
}

@MainActor
@Observable
final class PinDrawings {
    static let shared = PinDrawings()
    private(set) var all: [PinDrawing] = [] { didSet { changed?() } }
    /// Apple's map draws them again at once (its view is not redrawn by SwiftUI for a change here: a drawing kept
    /// showed only at the next change of something else)
    @ObservationIgnored var changed: (() -> Void)?

    private var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("pin-drawings.json")
    }
    private init() {
        if let u = url, let d = try? Data(contentsOf: u), let a = try? JSONDecoder().decode([PinDrawing].self, from: d) { all = a }
    }
    private func save() {
        guard let u = url else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(all) { try? d.write(to: u, options: .atomic) }
    }

    /// a drawing kept as it is finished; the undo drop takes it back
    func add(_ kind: DrawTool.Kind, _ points: [DrawTool.Geo]) {
        var d = PinDrawing(kind: kind == .shape ? "shape" : "line", points: points.map { [$0.lat, $0.lon] })
        d.map = PinMaps.shared.shown
        all.append(d)
        save()
        MarkStore.shared.did(d.isShape ? "Shape drawn" : "Line drawn",
                             back: { [weak self] in self?.remove(d.id, undoable: false) },
                             forth: { [weak self] in self?.put(d) })
    }
    func remove(_ id: UUID, undoable: Bool = true) {
        guard let k = all.firstIndex(where: { $0.id == id }) else { return }
        let d = all.remove(at: k)
        save()
        if undoable {
            MarkStore.shared.did(d.isShape ? "Shape deleted" : "Line deleted", back: { [weak self] in self?.put(d, at: k) },
                                 forth: { [weak self] in self?.remove(d.id, undoable: false) })
        }
    }
    private func put(_ d: PinDrawing, at k: Int? = nil) {
        guard !all.contains(where: { $0.id == d.id }) else { return }
        all.insert(d, at: min(k ?? all.count, all.count))
        save()
    }
    func drawing(_ id: UUID) -> PinDrawing? { all.first { $0.id == id } }

    /// the map framed on it (its box, a little room round it)
    func frame(_ id: UUID) {
        guard let d = drawing(id), let v = PinsMapState.shared.view else { return }
        var r = MKMapRect.null
        for c in d.points { let p = MKMapPoint(CLLocationCoordinate2D(latitude: c[0], longitude: c[1])); r = r.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0)) }
        guard !r.isNull else { return }
        let pad = max(r.width, r.height) * 0.15 + 1000
        v.setVisibleMapRect(r.insetBy(dx: -pad, dy: -pad), edgePadding: UIEdgeInsets(top: 60, left: 24, bottom: 24, right: 60), animated: true)
    }

    /// RENAME: Apple's small sheet with the name in a field; one undo step
    func rename(_ id: UUID) {
        guard let d = drawing(id) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard self != nil else { return }
            let a = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
            a.addTextField { f in f.text = d.name; f.placeholder = d.isShape ? "Shape" : "Line"; f.clearButtonMode = .whileEditing; f.autocapitalizationType = .words }
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            a.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self, weak a] _ in
                let new = String((a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                guard let self, new != d.name else { return }
                self.set(id) { $0.name = new }
                MarkStore.shared.did(new.isEmpty ? "Name taken off" : "Renamed \(new)", back: { [weak self] in self?.set(id) { $0.name = d.name } },
                                     forth: { [weak self] in self?.set(id) { $0.name = new } })
            })
            var top = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
            while let n = top?.presentedViewController { top = n }
            top?.present(a, animated: true)
        }
    }

    /// REDRAW: the tool from nothing, as the drawing's kind; Done keeps the new one in its place; one undo step
    func redraw(_ id: UUID, on v: MKMapView, water: Water) {
        guard let d = drawing(id) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak v] in
            guard let self, let v else { return }
            if water.stop != .quarter { water.go(.quarter) }
            DrawTool.shared.start(d.isShape ? .shape : .line,
                toGeo: { [weak v] p in
                    guard let v else { return nil }
                    let c = v.convert(p, toCoordinateFrom: v)
                    return CLLocationCoordinate2DIsValid(c) ? DrawTool.Geo(lat: c.latitude, lon: c.longitude) : nil
                },
                toScreen: { [weak v] g in v?.convert(CLLocationCoordinate2D(latitude: g.lat, longitude: g.lon), toPointTo: v) },
                finish: { [weak self] _, points in
                    let new = points.map { [$0.lat, $0.lon] }
                    self?.set(id) { $0.points = new }
                    MarkStore.shared.did(d.isShape ? "Shape redrawn" : "Line redrawn", back: { [weak self] in self?.set(id) { $0.points = d.points } },
                                         forth: { [weak self] in self?.set(id) { $0.points = new } })
                })
        }
    }

    /// A DRAWING'S HOLD MENU (on the map; Saved's row has the same): Rename · Redraw · Colour | Delete
    func menu(_ id: UUID, on v: MKMapView, water: Water) -> UIMenu? {
        guard let d = drawing(id) else { return nil }
        let after = { (g: @escaping @MainActor () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: g) }
        let rename = UIAction(title: "Rename") { [weak self] _ in self?.rename(id) }
        let redraw = UIAction(title: "Redraw") { [weak self, weak v] _ in if let v { self?.redraw(id, on: v, water: water) } }
        let colour = UIAction(title: "Colour") { [weak self] _ in
            after { PinStore.shared.selected = nil; PinRoutes.shared.close(); self?.colouring = id
                if water.stop == .quarter || water.stop == .closed { water.go(.half) } }
        }
        let delete = UIAction(title: "Delete", attributes: .destructive) { [weak self] _ in after { Feel.lift(); self?.remove(id) } }
        return UIMenu(title: d.name.isEmpty ? (d.isShape ? "Shape" : "Line") : d.name, children: [
            UIMenu(options: .displayInline, children: [rename, redraw, colour]),
            UIMenu(options: .displayInline, children: [delete]),
        ])
    }

    /// the drawing whose colour is being picked in the water (its hold menu's Colour), as a route's
    var colouring: UUID? {
        // the colour sheet going away (or to another drawing): its moves are one undo
        didSet { if oldValue != colouring { colourEnd(oldValue); colourWas = colouring.map { c in (c, drawing(c)?.pick) } } }
    }
    @ObservationIgnored private var colourWas: (id: UUID, pick: ColourPick?)?
    private func colourEnd(_ id: UUID?) {
        guard let was = colourWas, was.id == id else { return }
        colourWas = nil
        guard let d = drawing(was.id), d.pick != was.pick else { return }
        let now = d.pick, id = was.id
        MarkStore.shared.did(d.isShape ? "Shape colour changed" : "Line colour changed",
                             back: { [weak self] in self?.colour(id, was.pick) }, forth: { [weak self] in self?.colour(id, now) })
    }
    /// live while the finger moves in the picker; written to the file when it lifts, on Reset and when the sheet goes
    func colour(_ id: UUID, _ c: ColourPick?, keep: Bool = true) {
        guard let k = all.firstIndex(where: { $0.id == id }) else { return }
        all[k].pick = c
        if keep { save() }
    }
    func keepColours() { save() }

    private func set(_ id: UUID, _ change: (inout PinDrawing) -> Void) {
        guard let k = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[k])
        save()
    }

    /// DRAW IN PINS: the tool on Apple's map; a stroke that comes back to its start closes a shape, Done keeps a line
    func start(on v: MKMapView, water: Water) {
        DispatchQueue.main.async { if water.stop != .quarter { water.go(.quarter) } }
        DrawTool.shared.start(.any,
            toGeo: { [weak v] p in
                guard let v else { return nil }
                let c = v.convert(p, toCoordinateFrom: v)
                return CLLocationCoordinate2DIsValid(c) ? DrawTool.Geo(lat: c.latitude, lon: c.longitude) : nil
            },
            toScreen: { [weak v] g in
                guard let v else { return nil }
                return v.convert(CLLocationCoordinate2D(latitude: g.lat, longitude: g.lon), toPointTo: v)
            },
            finish: { [weak self] kind, points in self?.add(kind, points) })
    }
}

/// a drawing drawn small for its row: its points (in the map's own plane) fitted to the frame
struct DrawingShape: Shape {
    let points: [SIMD2<Float>]
    let closed: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard points.count > 1 else { return p }
        let xs = points.map(\.x), ys = points.map(\.y)
        let w = CGFloat((xs.max()! - xs.min()!)), h = CGFloat((ys.max()! - ys.min()!))
        let s = min(r.width / max(w, 0.0001), r.height / max(h, 0.0001))
        let ox = r.midX - w * s / 2, oy = r.midY - h * s / 2
        for (i, q) in points.enumerated() {
            let pt = CGPoint(x: ox + CGFloat(q.x - xs.min()!) * s, y: oy + CGFloat(q.y - ys.min()!) * s)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        if closed { p.closeSubpath() }
        return p
    }
}

/// a drawing on Apple's map: a line or a closed shape, knowing which drawing it is
final class PinDrawingLine: MKPolyline { var drawingID: UUID? }
final class PinDrawingShape: MKPolygon { var drawingID: UUID? }

