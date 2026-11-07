import SwiftUI

/// WHAT'S HERE? (A11.4; 11.5's empty-land and pin menus): the nearest three names from our own data (towns and things,
/// nearest first, one a line, the subheadline style: 15 pt, larger with larger text) in a glass panel over the map, its
/// bottom 12 pt above the held point; each name is a tap to its card. The panel (frosted, as every surface) is a 44 pt
/// circle grown from that point (P1, `Motion.quick`) and widened into a rounded rectangle (0.4 rule 4, the chrome curve,
/// its corner 22 to 18 pt); the names roll in once it is past half way and out before it narrows back. A touch
/// anywhere else on the map takes it away the same way. At sea: "Open sea".
@MainActor
@Observable
final class WhatsHere {
    static let shared = WhatsHere()
    struct Item: Identifiable {
        let id: String
        let name: String
        /// its card, or nil (the open sea)
        let open: (() -> Void)?
    }
    /// the held point on screen
    private(set) var point: CGPoint = .zero
    private(set) var items: [Item] = []
    /// 0 gone into the point, 1 the 44 pt circle, 2 the panel
    private(set) var stage = 0
    /// drawn at all (still while it goes back into the point)
    private(set) var present = false
    private(set) var namesIn = false
    @ObservationIgnored private var job = 0

    var isOpen: Bool { stage > 0 }

    /// on our own map: the point held on screen
    func show(at p: CGPoint, map: MapController) {
        let mp = map.mapPoint(p)
        let ll = EqualEarth.unproject(mp)
        let land = map.world?.place(at: SIMD2(Float(mp.x), Float(mp.y)))
        show(at: p, lat: ll.lat, lon: ll.lon, land: land, map: map)
    }

    /// `land`: the country under the point on our map (nil: the sea)
    func show(at p: CGPoint, lat: Double, lon: Double, land: Int?, map: MapController) {
        items = Self.nearest(lat: lat, lon: lon, land: land, map: map)
        job += 1
        let me = job
        point = p
        namesIn = false
        present = true
        withAnimation(Motion.quick) { stage = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [self] in
            guard me == job else { return }
            withAnimation(Motion.chrome) { stage = 2 }
            // the names start once the shape is past half way; the tap haptic at half way
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) { [self] in
                guard me == job else { return }
                Feel.tap()
                withAnimation(Motion.quick) { namesIn = true }
            }
        }
        UIAccessibility.post(notification: .announcement, argument: items.map(\.name).joined(separator: ", "))
    }

    /// the names roll out, the panel narrows back into its circle, the circle goes back into the point
    func close() {
        guard stage > 0 else { return }
        job += 1
        let me = job
        withAnimation(Motion.quick) { namesIn = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            guard me == job else { return }
            withAnimation(Motion.quick) { stage = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [self] in
                guard me == job else { return }
                withAnimation(Motion.quick) { stage = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [self] in
                    if me == job { present = false }
                }
            }
        }
    }

    /// the three nearest of the towns (the index of every town) and the things of the country under the point
    private static func nearest(lat: Double, lon: Double, land: Int?, map: MapController) -> [Item] {
        guard let land, let w = map.world, land >= 0, land < w.places.count else {
            return [Item(id: "sea", name: "Open sea", open: nil)]
        }
        let country = w.places[land].n
        let k = cos(lat * .pi / 180)
        func d2(_ la: Double, _ lo: Double) -> Double {
            var dx = lo - lon
            if dx > 180 { dx -= 360 } else if dx < -180 { dx += 360 }
            dx *= k
            let dy = la - lat
            return dx * dx + dy * dy
        }
        var found: [(Double, Item)] = []
        for h in TownIndex.shared.nearest(lat: lat, lon: lon, count: 3) {
            let place = w.placeIndex[h.file] ?? w.placeIndex[h.file.uppercased()] ?? land
            let parents = [h.region, w.places[place].n].filter { !$0.isEmpty }.joined(separator: ", ")
            found.append((d2(h.lat, h.lon), Item(id: h.key, name: h.name) {
                RegionCardState.shared.open(PlaceKey(.town, h.id), name: h.name, parents: parents, place: place, map: map)
            }))
        }
        let cc = w.places[land].id.lowercased()
        for t in ThingStore.shared.things(cc) ?? [] {
            let ll = EqualEarth.unproject(SIMD2(Double(t.at.x), Double(t.at.y)))
            let d = d2(ll.lat, ll.lon)
            // only those that could be among the three
            guard found.count < 3 || d < found.map(\.0).max()! else { continue }
            let line = t.line.isEmpty ? country : t.line.prefix(1).uppercased() + t.line.dropFirst()
            found.append((d, Item(id: "wd:" + t.id, name: t.name) {
                RegionCardState.shared.open(t.key, name: t.name, parents: line, place: land, map: map)
            }))
            if found.count > 6 { found.sort { $0.0 < $1.0 }; found.removeLast(found.count - 3) }
        }
        found.sort { $0.0 < $1.0 }
        let three = found.prefix(3).map(\.1)
        // the towns not read yet (the index comes in the background): the country itself, its name only
        return three.isEmpty ? [Item(id: "land", name: country, open: nil)] : Array(three)
    }
}

/// the panel itself, over the map and under the water and the head
struct WhatsHereView: View {
    let layout: Layout
    @State private var here = WhatsHere.shared

    var body: some View {
        let open = here.stage == 2
        let widest = layout.W - 32
        let width = open ? min(widest, panelWidth + 32) : 44
        let height = open ? CGFloat(here.items.count) * lineHeight + CGFloat(max(0, here.items.count - 1)) * 8 + 28 : 44
        // its bottom 12 pt above the point, kept on the screen
        let x = min(max(here.point.x, width / 2 + 16), layout.W - width / 2 - 16)
        let y = max(here.point.y - 12 - height / 2, layout.headBottom + 8 + height / 2)
        if here.present {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(here.items) { item in
                    if let o = item.open {
                        Button {
                            Feel.tap()
                            here.close()
                            o()
                        } label: { name(item) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.name)
                    } else {
                        name(item).accessibilityLabel(item.name)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(width: width, height: height, alignment: .leading)
            .clipped()
            // a surface over the map: the system's frosted glass, as search's results box
            .glassEffect(PageGlass.surface, in: RoundedRectangle(cornerRadius: open ? 18 : 22, style: .continuous))
            // the circle grows from the point and goes back into it (it is control-sized)
            .scaleEffect(here.stage == 0 ? 0.001 : 1, anchor: .bottom)
            .position(x: x, y: y)
            .allowsHitTesting(here.stage == 2)
            .transition(.identity)
        }
    }

    /// one name, rolled in and out by the text roll (never scaled, never faded)
    private func name(_ item: WhatsHere.Item) -> some View {
        Text(here.namesIn ? item.name : Caption.blank(item.name, "\u{2002}"))
            .font(.subheadline)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .contentTransition(.numericText(value: here.namesIn ? 1 : 0))
            .frame(height: lineHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// one name's line: the subheadline style's own (15 pt at the default size, larger with larger text: 19.4)
    private var lineHeight: CGFloat { max(22, UIFont.preferredFont(forTextStyle: .subheadline).lineHeight.rounded(.up) + 2) }

    /// the longest name's width in that style
    private var panelWidth: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        return here.items.map { ($0.name as NSString).size(withAttributes: [.font: font]).width.rounded(.up) }.max() ?? 0
    }
}
