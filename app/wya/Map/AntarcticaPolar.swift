import SwiftUI

/// ANTARCTICA'S OWN MAP: on a flat world Antarctica is a smear along the bottom edge, so picking it shows the world
/// from above the South Pole instead, as the web version did (v77b, v94), drawn as the rest of the map is: the sea by
/// its depth and the land by its height and light, baked once from the main map's own relief (ETOPO1) with the main
/// map's own colours (Resources/Map/antarctica-sea.jpg, antarctica-land.png). South-polar azimuthal equidistant: the
/// pole in the middle, r = 5.45 (90 + lat) units, longitude clockwise from 12 o'clock, so the Peninsula points
/// up-left towards South America. The coast (Natural Earth 10 m, antarctica-polar.txt, pole at 200,200) is the tap's
/// shape. The other places counted with Antarctica are the main map's diamonds at their own places. Opened framed so
/// Antarctica fills the room; pinch and drag move it, never past the picture's edge.
struct AntarcticaPolar: View {
    var map: MapController
    var water: Water
    /// the coast in units round the pole, read once
    static let land: Path = {
        guard let url = Bundle.main.url(forResource: "antarctica-polar", withExtension: "txt"),
              let d = try? String(contentsOf: url, encoding: .utf8) else { return Path() }
        var p = Path()
        let s = Scanner(string: d)
        s.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n")
        while !s.isAtEnd {
            if s.scanString("M") != nil, let x = s.scanDouble(), let y = s.scanDouble() { p.move(to: CGPoint(x: x - 200, y: y - 200)) }
            else if s.scanString("L") != nil, let x = s.scanDouble(), let y = s.scanDouble() { p.addLine(to: CGPoint(x: x - 200, y: y - 200)) }
            else if s.scanString("Z") != nil { p.closeSubpath() }
            else if let x = s.scanDouble(), let y = s.scanDouble() { p.addLine(to: CGPoint(x: x - 200, y: y - 200)) }
            else { break }
        }
        return p
    }()
    static let seaImage = Bundle.main.path(forResource: "antarctica-sea", ofType: "jpg").flatMap(UIImage.init(contentsOfFile:))
    static let landImage = Bundle.main.path(forResource: "antarctica-land", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
    /// the pictures' reach in units from the pole: the sea's (2° S) and the land's
    static let seaReach: CGFloat = 480, landReach: CGFloat = 140
    /// the coast's furthest reach (66° S, the Peninsula's tip a little more): what the opening frame fits
    static let coast: CGFloat = 136

    /// the view: the point at the screen's middle of the room (units from the pole) and points a unit
    @State private var centre = CGPoint.zero
    @State private var k: CGFloat = 0
    @State private var startCentre: CGPoint?
    @State private var startK: CGFloat?

    struct Spot: Identifiable { let id: String; let place: Int; let at: CGPoint }

    var body: some View {
        let L = water.layout
        let room = L.room(sheetTop: water.form().top)
        let mid = CGPoint(x: L.W / 2, y: (room.lowerBound + room.upperBound) / 2)
        let fit = min(L.W - 24, room.upperBound - room.lowerBound - 16) / (2 * Self.coast)
        // zoomed out no further than the whole of the coast at half its fitted size (past the sea picture's edge the
        // open ocean's blue carries on: its last part fades into it)
        let kMin = fit * 0.5
        let kk = max(kMin, k > 0 ? k : fit)
        let c = clamp(centre, kk, L, mid)
        let toScreen = { (u: CGPoint) in CGPoint(x: mid.x + (u.x - c.x) * kk, y: mid.y + (u.y - c.y) * kk) }
        let spots = Self.spots(map)
        let marks = MarkStore.shared
        let aq = map.world?.placeIndex["aq"]
        let st = marks.state(.country("aq"))
        ZStack(alignment: .topLeading) {
            // the open ocean's own blue round it all (the deep sea's colour)
            Palette.blue
            if let sea = Self.seaImage {
                Image(uiImage: sea).resizable().interpolation(.high)
                    .frame(width: 2 * Self.seaReach * kk, height: 2 * Self.seaReach * kk)
                    // its far edge goes into the open ocean's blue, never a line
                    .mask(RadialGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                         center: .center, startRadius: 0, endRadius: Self.seaReach * kk))
                    .position(toScreen(.zero))
            }
            if let land = Self.landImage {
                // stamped lime and wished blue soak into the land as on the world (the relief still shows)
                Image(uiImage: land).resizable().interpolation(.high)
                    .colorMultiply(st.stamped ? Palette.lime : st.wished ? Palette.blue : .white)
                    .frame(width: 2 * Self.landReach * kk, height: 2 * Self.landReach * kk)
                    .position(toScreen(.zero))
            }
            Canvas { g, _ in
                // the islands' diamonds as the main map's: 5.8 pt from the middle to a point, a 1.1 pt rim at 50% black
                for s in spots {
                    let p = toScreen(s.at), r: CGFloat = 5.8
                    var d = Path()
                    d.move(to: CGPoint(x: p.x, y: p.y - r)); d.addLine(to: CGPoint(x: p.x + r, y: p.y))
                    d.addLine(to: CGPoint(x: p.x, y: p.y + r)); d.addLine(to: CGPoint(x: p.x - r, y: p.y)); d.closeSubpath()
                    let ms = marks.state(.country(s.id))
                    g.fill(d, with: .color(Palette.ink.opacity(0.5)))
                    let e = r - 1.1 * 1.41
                    var inner = Path()
                    inner.move(to: CGPoint(x: p.x, y: p.y - e)); inner.addLine(to: CGPoint(x: p.x + e, y: p.y))
                    inner.addLine(to: CGPoint(x: p.x, y: p.y + e)); inner.addLine(to: CGPoint(x: p.x - e, y: p.y)); inner.closeSubpath()
                    g.fill(inner, with: .color(ms.stamped ? Palette.lime : ms.wished ? Palette.blue : Palette.white))
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: L.W, height: L.H)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                DragGesture(minimumDistance: 4).onChanged { v in
                    let s0 = startCentre ?? c
                    if startCentre == nil { startCentre = c }
                    centre = CGPoint(x: s0.x - v.translation.width / kk, y: s0.y - v.translation.height / kk)
                }.onEnded { _ in startCentre = nil; centre = clamp(centre, kk, L, mid) },
                MagnifyGesture().onChanged { v in
                    let k0 = startK ?? kk
                    if startK == nil { startK = kk }
                    k = min(fit * 6, max(kMin, k0 * v.magnification))
                }.onEnded { _ in startK = nil; centre = clamp(centre, k, L, mid) }
            )
        )
        .onTapGesture(coordinateSpace: .global) { pt in
            let u = CGPoint(x: c.x + (pt.x - mid.x) / kk, y: c.y + (pt.y - mid.y) / kk)
            if let s = spots.min(by: { hypot($0.at.x - u.x, $0.at.y - u.y) < hypot($1.at.x - u.x, $1.at.y - u.y) }),
               hypot(s.at.x - u.x, s.at.y - u.y) * kk < 22 {
                tap(s.place, at: pt)
            } else if let aq, Self.land.contains(u) {
                tap(aq, at: pt)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Antarctica, from above the South Pole")
        .transition(.opacity)
    }

    /// the middle kept within the islands' reach of the pole (it can't be dragged off into empty ocean)
    private func clamp(_ p: CGPoint, _ k: CGFloat, _ L: Layout, _ mid: CGPoint) -> CGPoint {
        let R: CGFloat = 240
        let d = hypot(p.x, p.y)
        return d <= R ? p : CGPoint(x: p.x / d * R, y: p.y / d * R)
    }


    /// the places counted with Antarctica other than the continent itself, at their own places
    static func spots(_ map: MapController) -> [Spot] {
        guard let w = map.world else { return [] }
        return w.places.indices.compactMap { i in
            let p = w.places[i]
            guard p.cont == "Antarctica", p.id != "aq", !p.junk, p.ll.count == 2 else { return nil }
            let r = 5.45 * (90 + p.ll[1]), a = p.ll[0] * .pi / 180
            return Spot(id: p.id, place: i, at: CGPoint(x: r * sin(a), y: -r * cos(a)))
        }
    }

    /// a place on this map tapped: its card, as a tap on the world map gives (Countries); elsewhere nothing yet
    private func tap(_ i: Int, at pt: CGPoint) {
        guard !map.placesMode, !map.pinsMode, map.regionScene == nil else { Feel.refuse(); return }
        Feel.tap()
        CardState.shared.open(i, at: pt, map: map, water: water)
    }
}
