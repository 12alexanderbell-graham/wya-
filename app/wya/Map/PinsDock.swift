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
    /// the tool chosen in the first row (1 Route, 2 Draw, 3 Measure, 4 Files); its options are the second row
    var chosen: Int?
    /// how new routes go: straight | drive | walk
    var routeWay = "straight"
    /// the look of what is drawn next: thickness in points, dashed
    var drawWidth: Double = 4
    var drawDash = false
    /// Measure: a line's length or a shape's area
    var measureArea = false

    /// MEASURE: the draw tool's line, its length under the circles as it grows; Done leaves the length there and keeps
    /// nothing on the map
    func measure(water: Water) {
        guard let v = PinsMapState.shared.view else { Feel.refuse(); return }
        measured = ""
        if water.stop != .quarter { water.go(.quarter) }
        DrawTool.shared.start(measureArea ? .shape : .line,
            toGeo: { [weak v] p in
                guard let v else { return nil }
                let c = v.convert(p, toCoordinateFrom: v)
                return CLLocationCoordinate2DIsValid(c) ? DrawTool.Geo(lat: c.latitude, lon: c.longitude) : nil
            },
            toScreen: { [weak v] g in
                guard let v else { return nil }
                return v.convert(CLLocationCoordinate2D(latitude: g.lat, longitude: g.lon), toPointTo: v)
            },
            finish: { [weak self] kind, pts in
                if kind == .shape { self?.measured = DrawTool.words(km2: DrawTool.area(pts)); return }
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

    /// the first row's middle from the dock's top (the draw tool's own controls sit here too)
    static func rowY(_ top: CGFloat) -> CGFloat { top + 80 }
    /// the map's name: its own line at the sheet's top, centred, with room under it
    static func titleY(_ top: CGFloat) -> CGFloat { top + 34 }
    /// where what is under the dock starts (your maps' rows): under the second row when a tool is chosen
    @MainActor static func bottom(_ top: CGFloat) -> CGFloat {
        top + (PinsDockState.shared.chosen == nil && !DrawTool.shared.on ? 112 : 168)
    }

    var body: some View {
        let L = water.layout
        let w = L.W - 2 * L.sheetInset - 32
        let drawing = DrawTool.shared.on
        // THE TOOLS (14 Nov): two rows of plain words on the water, no capsule, no icons. The first row is the five
        // tools; the one chosen stays black and the others go to 50%. The second row is the chosen tool's options.
        VStack(spacing: 4) {
            // (14 Nov: drawing keeps this row, so another tool is one tap away; Cancel, Undo and Done sit on the
            // title's line, Cancel leading and Done trailing as on Apple's sheets)
            Group {
                WordRow(items: [
                    .init(word: "Pin") {
                        close()
                        dock.addPin(water: water)
                    },
                    .init(word: "Route", on: dock.chosen == 1) {
                        if dock.chosen == 1 { close() } else { close(); dock.chosen = 1; water.go(.quarter); routes.openEmpty() }
                    },
                    .init(word: "Draw", on: dock.chosen == 2) {
                        if dock.chosen == 2 { close(); return }
                        guard let v = PinsMapState.shared.view, PinsMapState.shared.map?.locked != true else { Feel.refuse(); return }
                        close(); dock.chosen = 2
                        PinDrawings.shared.start(on: v, water: water)
                    },
                    .init(word: "Measure", on: dock.chosen == 3) {
                        if dock.chosen == 3 { close(); return }
                        close(); dock.chosen = 3
                        dock.measure(water: water)
                    },
                    .init(word: "Files", on: dock.chosen == 4) {
                        if dock.chosen == 4 { close() } else { close(); dock.chosen = 4 }
                    },
                ], width: w, anyOn: dock.chosen != nil)
            }
            if let c = dock.chosen {
                WordRow(items: options(c), width: w, small: true, columns: true)
                    .transition(.blurReplace)
            }
            Text(words.isEmpty ? " " : words)
                .font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                .monospacedDigit().lineLimit(1)
                .contentTransition(.numericText())
        }
        .animation(Motion.quick, value: dock.chosen)
        .animation(Motion.quick, value: drawing)
        .frame(width: w)
        .frame(width: L.W, height: L.H, alignment: .top)
        .offset(y: Self.rowY(top) - 22)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // a tool's work done (a drawing or a measure kept, or given up): the tool lets go
        .onChange(of: drawing) { _, on in if !on, dock.chosen == 2 || dock.chosen == 3 { dock.chosen = nil } }
        .onChange(of: routes.open) { _, open in if !open, dock.chosen == 1 { dock.chosen = nil } }
        .fileImporter(isPresented: $dock.importing, allowedContentTypes: PinFiles.types, allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r, let map = PinsMapState.shared.map else { return }
            var n = 0
            for u in urls { n += PinFiles.bring(u, country: { PinsMapView.Coordinator.country(map, $0) }) ?? 0 }
            if n == 0 { Feel.refuse() } else { Feel.tap(); PinsMapState.shared.frameShownMap() }
        }
        // THE MAP'S NAME, centred on its own line over the tools; inside a map's list at 50%, back at its left
        .overlay(alignment: .topLeading) {
            let maps = PinMaps.shared
            ZStack {
                Text(maps.map(maps.shown)?.name ?? "All pins")
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: L.W - 2 * L.sheetInset - (DrawTool.shared.on ? 200 : 120))
                    .allowsHitTesting(false)
                if DrawTool.shared.on {
                    let t = DrawTool.shared
                    HStack(spacing: 0) {
                        Button { Feel.tap(); t.cancel() } label: { SheetWord(word: "Cancel") }
                            .buttonStyle(.plain)
                        Spacer(minLength: 0)
                        Button { if t.marks.isEmpty { Feel.refuse() } else { Feel.tap(); t.undo() } } label: {
                            SheetWord(word: "Undo", dim: t.marks.isEmpty)
                        }
                        .buttonStyle(.plain)
                        Button { if t.canFinish { Feel.tap(); t.done() } else { Feel.refuse() } } label: {
                            SheetWord(word: "Done", strong: true, dim: !t.canFinish)
                        }
                        .buttonStyle(.plain)
                    }
                } else if maps.inside, water.stop != .quarter {
                    HStack {
                        Button { Feel.tap(); maps.inside = false } label: {
                            Icon5(key: "back", ink: Palette.ink, size: 22).frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Your maps")
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: L.W - 2 * L.sheetInset - 16, height: 44)
            .position(x: L.W / 2, y: Self.titleY(top))
            .frame(width: L.W, height: L.H)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    /// whatever tool was out is put away
    private func close() {
        if routes.open { routes.close() }
        if DrawTool.shared.on { DrawTool.shared.cancel() }
        dock.measured = ""
        dock.chosen = nil
    }

    /// the second row: the chosen tool's options, the current value black
    private func options(_ c: Int) -> [WordRow.Item] {
        switch c {
        case 1:
            return [("Straight", "straight"), ("Drive", "drive"), ("Walk", "walk")].map { w, k in
                WordRow.Item(word: w, on: dock.routeWay == k) { dock.routeWay = k }
            }
        case 2:
            let last = PinDrawings.shared.all.last
            return [("Thin", 2.0), ("Medium", 4.0), ("Thick", 7.0)].map { w, v in
                WordRow.Item(word: w, on: dock.drawWidth == v) { dock.drawWidth = v }
            } + [
                .init(word: "Dashed", on: dock.drawDash) { dock.drawDash.toggle() },
                // the colour wheel for the newest drawing (as its hold menu's Colour)
                .init(word: "Colour", dim: last == nil) {
                    guard let d = last else { return }
                    if DrawTool.shared.on { DrawTool.shared.cancel() }
                    dock.chosen = nil
                    PinDrawings.shared.colouring = d.id
                    water.go(.half)
                },
            ]
        case 3:
            return [WordRow.Item(word: "Line", on: !dock.measureArea) { dock.measureArea = false; dock.measure(water: water) },
                    WordRow.Item(word: "Area", on: dock.measureArea) { dock.measureArea = true; dock.measure(water: water) }]
        default:
            return [WordRow.Item(word: "Import") { dock.importing = true },
                    WordRow.Item(word: "Export") { PinFiles.export() }]
        }
    }

    /// under the rows: only what a route or a measure came to; never a count, never how to use a tool
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


/// A ROW OF WORDS (Pins' tools and their options): plain words sharing the row evenly, no box, no icon. One chosen:
/// it black, the others black 50%; one that can't be used yet, black 30%.
struct WordRow: View {
    struct Item {
        let word: String
        var on = false
        var dim = false
        let act: () -> Void
    }
    let items: [Item]
    let width: CGFloat
    var small = false
    /// a tool is chosen in this row (the others fade)
    var anyOn = true
    /// the words sit in the five tools' columns (two words under the second and fourth, three under the middle
    /// three), so the options line up with the tools over them
    var columns = false

    /// which of the five columns each of n words takes
    static func slots(_ n: Int) -> [Int] {
        switch n {
        case 1: return [2]
        case 2: return [1, 3]
        case 3: return [1, 2, 3]
        case 4: return [0, 1, 3, 4]
        default: return Array(0 ..< n)
        }
    }

    var body: some View {
        if columns, items.count <= 5 {
            let col = width / 5
            let at = Self.slots(items.count)
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.offset) { k, it in
                    word(it).position(x: col * (CGFloat(at[k]) + 0.5), y: (small ? 36 : 44) / 2)
                }
            }
            .frame(width: width, height: small ? 36 : 44)
            .animation(Motion.quick, value: items.map(\.on))
        } else {
            plain
        }
    }

    private func word(_ it: Item) -> some View {
        Button {
            if it.dim { Feel.refuse(); return }
            Feel.tap()
            it.act()
        } label: {
            Text(it.word)
                .font(small ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(Palette.ink.opacity(it.dim ? 0.3 : (it.on || !anyOn ? 1 : 0.5)))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: width / 5, height: small ? 36 : 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(it.on ? [.isButton, .isSelected] : .isButton)
    }

    private var plain: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                Button {
                    if it.dim { Feel.refuse(); return }
                    Feel.tap()
                    it.act()
                } label: {
                    Text(it.word)
                        .font(small ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                        .foregroundStyle(Palette.ink.opacity(it.dim ? 0.3 : (it.on || !anyOn ? 1 : 0.5)))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: width / CGFloat(max(5, items.count)), height: small ? 36 : 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(it.on ? [.isButton, .isSelected] : .isButton)
            }
        }
        // every word sits in a fifth of the width, so a row of two or three words stays in the middle under the
        // five tools instead of spreading to the edges (14 Nov)
        .frame(width: width)
        .animation(Motion.quick, value: items.map(\.on))
    }
}


/// a word on the sheet's title line (Cancel, Undo, Done): 44 pt high, Done in the heavier weight as Apple's sheets have it
struct SheetWord: View {
    let word: String
    var strong = false
    var dim = false
    var body: some View {
        Text(word)
            .font(.body.weight(strong ? .semibold : .regular))
            .foregroundStyle(Palette.ink.opacity(dim ? 0.3 : 1))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 44)
            .contentShape(Rectangle())
    }
}
