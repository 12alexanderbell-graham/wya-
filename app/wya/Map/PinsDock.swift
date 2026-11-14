import SwiftUI
import MapKit

/// PINS' TOOLS (8.5; 12 Nov): three glass circles where every map's caption sits, Add pin,
/// Route, Draw, with one line of words under them (Design/WaterTools.swift). No bar. Saved is the water itself (pulled up, your pins, routes and drawings are under the circles);
/// Apple's three looks are the map's settings (Settings/MapSettingsSheet.swift, Pins' rows).
/// - Add pin: a pin in the middle of the map on screen, chosen, so its name is up and it can be dragged into place
///   (a hold on the map still drops one where the finger is).
/// - Route: fills black; a tap on a pin or on land is where it starts, the next where it ends; the route is made and
///   kept; the next tap starts another. The circle again (or the water's mode) ends it.
/// - Draw: the one draw tool (Map/DrawTool.swift); its Undo, Cancel, Done take the circles' place.
@MainActor @Observable
final class PinsDockState {
    static let shared = PinsDockState()
    /// MEASURE: what the last line measured came to (shown under the tools until another tool is used)
    var measured = ""
    /// the file picker for Files' Import is up
    var importing = false

    /// MEASURE: the draw tool's line, its length under the circles as it grows; Done leaves the length there and keeps
    /// nothing on the map
    func measure(water: Water) {
        guard let v = PinsMapState.shared.view else { Feel.refuse(); return }
        measured = ""
        if water.stop != .quarter { water.go(.quarter) }
        DrawTool.shared.start(.line,
            toGeo: { [weak v] p in
                guard let v else { return nil }
                let c = v.convert(p, toCoordinateFrom: v)
                return CLLocationCoordinate2DIsValid(c) ? DrawTool.Geo(lat: c.latitude, lon: c.longitude) : nil
            },
            toScreen: { [weak v] g in
                guard let v else { return nil }
                return v.convert(CLLocationCoordinate2D(latitude: g.lat, longitude: g.lon), toPointTo: v)
            },
            finish: { [weak self] _, pts in
                var t = 0.0
                for i in 1 ..< max(1, pts.count) { t += DrawTool.km(pts[i - 1], pts[i]) }
                self?.measured = DrawTool.words(km: t)
            })
    }
    /// ADD PIN: a pin where the middle of the map on screen is (between the head and the water), as a hold there would
    /// drop it: chosen, named once the phone knows the place, one undo step
    func addPin(water: Water) {
        guard let v = PinsMapState.shared.view, let map = PinsMapState.shared.map, !map.locked else { Feel.refuse(); return }
        let L = water.layout
        let p = CGPoint(x: L.W / 2, y: (L.headBottom + water.level) / 2)
        var c = v.convert(v.convert(p, from: nil), toCoordinateFrom: v)
        guard CLLocationCoordinate2DIsValid(c) else { Feel.refuse(); return }
        // (the place found in search still under the point, within a finger's width: the pin is that place's, at its
        // own point and with its name; anywhere else the map was moved since, and the pin is named as any other)
        var known: String?
        if let f = PinsMapState.shared.found {
            let at = CLLocationCoordinate2D(latitude: f.lat, longitude: f.lon)
            let q = v.convert(at, toPointTo: v), o = v.convert(p, from: nil)
            if hypot(q.x - o.x, q.y - o.y) < 24 { c = at; known = f.name }
            PinsMapState.shared.found = nil
        }
        PinStore.shared.drop(at: c, country: PinsMapView.Coordinator.country(map, c), known: known)
        if water.stop != .quarter { water.go(.quarter) }
    }
}

struct PinsDock: View {
    let water: Water
    /// the dock's top (the water's top, never under the head)
    let top: CGFloat
    var store = PinStore.shared
    @State private var dock = PinsDockState.shared
    @State private var routes = PinRoutes.shared

    /// the row's middle from the dock's top: under the map's name, which sits on every map's name line
    static func rowY(_ top: CGFloat) -> CGFloat { top + 88 }
    /// the map's name: its own line at the sheet's top, left, with room under it (14 Nov: never crowding the circles)
    static func titleY(_ top: CGFloat) -> CGFloat { top + 34 }
    /// where what is under the dock starts (Saved's rows)
    static func bottom(_ top: CGFloat) -> CGFloat { top + 106 }

    var body: some View {
        let L = water.layout
        // drawing: the same three circles become Undo, Cancel, Done, their icons changing in place
        let drawing = DrawTool.shared.on
        WaterTools(tools: drawing ? DrawBar.tools(DrawTool.shared) : [
            .init(icon: "pin", label: "Add pin") {
                dock.measured = ""
                if routes.open { routes.close() }
                dock.addPin(water: water)
            },
            .init(icon: "route", label: "Route", on: routes.open) {
                dock.measured = ""
                if routes.open { routes.close() } else { water.go(.quarter); routes.openEmpty() }
            },
            .init(icon: "edit", label: "Draw") {
                guard let v = PinsMapState.shared.view, PinsMapState.shared.map?.locked != true else { Feel.refuse(); return }
                dock.measured = ""
                if routes.open { routes.close() }
                PinDrawings.shared.start(on: v, water: water)
            },
            .init(icon: "measure", label: "Measure") {
                if routes.open { routes.close() }
                dock.measure(water: water)
            },
            // FILES: Google Maps' and Google Earth's file tools, GeoJSON, KML and GPX in and out (Map/PinFiles.swift)
            .init(icon: "file", label: "Files", menu: [
                ("Import", { dock.importing = true }),
                ("Export", { PinFiles.export() }),
            ]) {},
        ], words: drawing ? DrawBar.caption(DrawTool.shared) : words, align: .leading)
        // the circles together, from the same left edge as the name and the rows (Apple's sheets: one left edge)
        .frame(width: L.W - 2 * L.sheetInset - 32, alignment: .leading)
        .fileImporter(isPresented: $dock.importing, allowedContentTypes: PinFiles.types, allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r, let map = PinsMapState.shared.map else { return }
            var n = 0
            for u in urls { n += PinFiles.bring(u, country: { PinsMapView.Coordinator.country(map, $0) }) ?? 0 }
            if n == 0 { Feel.refuse() } else { Feel.tap(); PinsMapState.shared.frameShownMap() }
        }
        .position(x: L.W / 2, y: Self.rowY(top))
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        // THE MAP'S NAME over the tools, on every map's name line: the map of yours shown, or All pins (no count:
        // what it holds is on the map); inside a map's list at 50%, the back circle at its left goes back to your maps
        .overlay(alignment: .topLeading) {
            let maps = PinMaps.shared
            HStack(spacing: 4) {
                if maps.inside, water.stop != .quarter {
                    Button { Feel.tap(); maps.inside = false } label: {
                        Icon5(key: "back", ink: Palette.ink, size: 22).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Your maps")
                    .padding(.leading, -12)
                }
                Text(maps.map(maps.shown)?.name ?? "All pins")
                    .font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
            }
            .frame(width: L.W - 2 * L.sheetInset - 32, height: 44)
            .position(x: L.W / 2, y: Self.titleY(top))
            .frame(width: L.W, height: L.H)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    /// under the circles: only what a route came to (its distance and time), or that it is being found, or that
    /// there is none by road; never a count and never how to use a tool
    private var words: String {
        guard routes.open else { return dock.measured }
        // (read first, so the words change when the route is kept: the route made is not itself observed)
        let kept = routes.routes
        if routes.noRoute { return "No route by road" }
        if routes.waiting == .from || routes.waiting == .to { return "" }
        if let id = routes.currentID, let r = kept.first(where: { $0.id == id }) { return r.words }
        return "Finding the way"
    }
}
