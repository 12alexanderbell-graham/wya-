import SwiftUI

/// WHAT'S HERE? (A11.4; 11.5's empty-land and pin menus): the nearest three names from our own data (towns and things,
/// nearest first, one a line, the subheadline style: 15 pt, larger with larger text) in a glass panel over the map, its
/// bottom 12 pt above the held point; each name is a tap to its card. The panel (frosted, as every surface) is simply
/// there, and a touch anywhere else on the map simply takes it away (A11.4's grow and roll dropped on 7 Nov: no grow,
/// not everything needs an animation). At sea: "Open sea".
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
    /// up on the map
    private(set) var present = false
    private(set) var namesIn = false
    @ObservationIgnored private var job = 0

    var isOpen: Bool { present }

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
        point = p
        // simply there, and simply gone (7 Nov: no grow, no circle, not everything needs an animation)
        Feel.tap()
        namesIn = true; present = true
        UIAccessibility.post(notification: .announcement, argument: items.map(\.name).joined(separator: ", "))
    }

    func close() {
        guard present else { return }
        job += 1
        namesIn = false; present = false
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
        let open = here.present
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
            .position(x: x, y: y)
            .allowsHitTesting(here.present)
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
