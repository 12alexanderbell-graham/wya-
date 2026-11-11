import SwiftUI
import MapKit

/// PINS' TOOLKIT (8.5): one bar where every map's caption sits, 44 pt tall across the water, its four tools as words
/// sharing it evenly (the system's own segmented bar: one shape that holds the tools, not four loose pills). Words,
/// not icons: a tool's name cannot be misread. No count of pins over them: a number there says nothing about the tools.
/// - Add pin: a pin in the middle of the map on screen, chosen, so its name is up and it can be dragged into place
///   (a hold on the map still drops one where the finger is).
/// - Route: the Route row in the tools' place.
/// - Layers: Apple's three looks in the tools' place.
/// - Saved: the water to 50% with your pins and routes under the row, its capsule lime while they are up; again, down.
/// Sharing is each pin's own (its menu, its sheet). Draw, Track and Moment come with their own features.
@MainActor @Observable
final class PinsDockState {
    static let shared = PinsDockState()
    /// a tool whose controls are in the row (Route has its own state, PinRoutes.open)
    enum Tool { case layers }
    var tool: Tool?

    /// ADD PIN: a pin where the middle of the map on screen is (between the head and the water), as a hold there would
    /// drop it: chosen, named once the phone knows the place, one undo step
    func addPin(water: Water) {
        guard let v = PinsMapState.shared.view, let map = PinsMapState.shared.map, !map.locked else { Feel.refuse(); return }
        let L = water.layout
        let p = CGPoint(x: L.W / 2, y: (L.headBottom + water.level) / 2)
        let c = v.convert(v.convert(p, from: nil), toCoordinateFrom: v)
        guard CLLocationCoordinate2DIsValid(c) else { Feel.refuse(); return }
        PinStore.shared.drop(at: c, country: PinsMapView.Coordinator.country(map, c))
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

    /// the row's middle from the dock's top: the caption's own middle on every other map
    static func rowY(_ top: CGFloat) -> CGFloat { top + 72 }
    /// where what is under the dock starts (Saved's rows)
    static func bottom(_ top: CGFloat) -> CGFloat { top + 104 }

    var body: some View {
        let L = water.layout
        ZStack(alignment: .topLeading) {
            if routes.open {
                // the Route row in the tools' place (its cross closes it)
                RouteRow(water: water, captionY: Self.rowY(top))
            } else if dock.tool == .layers {
                layersRow.position(x: L.W / 2, y: Self.rowY(top))
            } else {
                tools.position(x: L.W / 2, y: Self.rowY(top))
            }
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
    }

    // MARK: the tools

    private var savedOn: Bool { water.stop == .half || water.stop == .full }

    private var tools: some View {
        let L = water.layout
        // (16 pt inside the water each side, as its rows; the tools 4 pt inside the bar)
        let w = (L.W - 2 * L.sheetInset - 32 - 8) / 4
        return HStack(spacing: 0) {
            tool("Add pin", width: w) { dock.addPin(water: water) }
            tool("Route", width: w) {
                water.go(.quarter)
                routes.openEmpty()
            }
            tool("Layers", width: w) {
                water.go(.quarter)
                dock.tool = .layers
            }
            // (with nothing saved there is nothing to show: the capsule is grey and refuses)
            tool("Saved", width: w, on: savedOn, dim: n == 0) {
                if savedOn { water.go(.quarter) } else if n > 0 { water.go(.half) } else { Feel.refuse() }
            }
        }
        .padding(4)
        // (one even ground whatever the map under the water is: white at 45%)
        .background(Capsule().fill(Color.white.opacity(0.45)))
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
    private var n: Int { store.pins.count + routes.routes.count }

    /// one tool: its word in its quarter of the bar; on, its whole part lime
    private func tool(_ name: String, width: CGFloat, on: Bool = false, dim: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button {
            Feel.tap()
            act()
        } label: {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink.opacity(dim ? 0.5 : 1))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 6)
                .frame(width: width, height: 36)
                .background(Capsule().fill(on ? Palette.lime : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Layers' row, in the toolkit's own bar: the cross, then Apple's three looks as words, the one in use its
    // whole part lime

    private var layersRow: some View {
        let looks: [(String, String)] = [("apple-standard", "Standard"), ("apple-satellite", "Satellite"), ("apple-hybrid", "Hybrid")]
        let now = MapSettingsStore.shared.value.pinsMap
        let current = looks.contains { $0.0 == now } ? now : "apple-standard"
        let L = water.layout
        // (the bar's width less the cross's 36 pt and the 4 pt inside each end, in three)
        let w = (L.W - 2 * L.sheetInset - 32 - 8 - 36) / 3
        return HStack(spacing: 0) {
            Button {
                Feel.tap()
                dock.tool = nil
            } label: {
                Icon5(key: "cross", ink: Palette.ink, size: 18).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close layers")
            ForEach(looks, id: \.0) { l in
                Button {
                    guard l.0 != current else { return }
                    Feel.tap()
                    MapSettingsStore.shared.change { $0.pinsMap = l.0 }
                } label: {
                    Text(l.1).font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: w, height: 36)
                        .background(Capsule().fill(l.0 == current ? Palette.lime : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(l.0 == current ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.45)))
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

}
