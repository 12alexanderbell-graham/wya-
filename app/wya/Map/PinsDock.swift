import SwiftUI

/// PINS' DOCK (8.5,, 23 Oct): at the water's top, how many pins you have in one grey line, and under it one row of
/// tools,
/// the app's own icons drawn in ink straight on the water (no glass, no words; a hold names a tool in Apple's menu). It rides the
/// water's edge at every stop; at 50% your saved pins and routes are under it.
/// Tools so far: Saved (the water to 50% with your pins, or back), Route (the Route row in the tools' place), Share
/// (every pin as an Apple Maps link) and Layers (Apple's three looks in the tools' place). Draw, Track and Moment come with
/// their own features.
@MainActor @Observable
final class PinsDockState {
    static let shared = PinsDockState()
    /// a tool whose controls are in the row (Route has its own state, PinRoutes.open)
    enum Tool { case layers }
    var tool: Tool?
}

struct PinsDock: View {
    let water: Water
    /// the dock's top (the water's top, never under the head)
    let top: CGFloat
    var store = PinStore.shared
    @State private var dock = PinsDockState.shared
    @State private var routes = PinRoutes.shared

    /// the count line's middle and the tools' row middle, from the dock's top
    static func countY(_ top: CGFloat) -> CGFloat { top + 25 }
    static func rowY(_ top: CGFloat) -> CGFloat { top + 68 }
    /// where what is under the dock starts (Saved's rows)
    static func bottom(_ top: CGFloat) -> CGFloat { top + 98 }

    var body: some View {
        let L = water.layout
        let n = store.pins.count
        ZStack(alignment: .topLeading) {
            Text(n == 0 ? "Hold the map to drop a pin" : n == 1 ? "1 pin" : "\(n) pins")
                .font(.subheadline)
                .foregroundStyle(Palette.ink.opacity(0.5))
                .contentTransition(.numericText(value: Double(n)))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .position(x: L.W / 2, y: Self.countY(top))
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
        HStack(spacing: 12) {
            tool("saved", "Saved", on: savedOn) {
                if savedOn { water.go(.quarter) } else if n > 0 { water.go(.half) } else { Feel.refuse(); return }
            }
            tool("route", "Route") {
                water.go(.quarter)
                routes.openEmpty()
            }
            tool("share", "Share") { share() }
            tool("layers", "Layers") {
                water.go(.quarter)
                dock.tool = .layers
            }
        }
    }
    private var n: Int { store.pins.count }

    /// one tool: its icon 22 pt in a 44 pt slot; on, a 36 pt ink circle behind it and the icon white (A18.3)
    private func tool(_ key: String, _ name: String, on: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button {
            Feel.tap()
            act()
        } label: {
            ZStack {
                if on { Circle().fill(Palette.ink).frame(width: 36, height: 36) }
                Icon5(key: key, ink: on ? .white : Palette.ink, size: 22)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // a hold names the tool in Apple's menu (29 Oct); choosing it does the tool
        .contextMenu { Button(name) { Feel.tap(); act() } }
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Layers' row: the cross, then Apple's three looks as words, the one in use bold (the region map's level line)

    private var layersRow: some View {
        let looks: [(String, String)] = [("apple-standard", "Standard"), ("apple-satellite", "Satellite"), ("apple-hybrid", "Hybrid")]
        let now = MapSettingsStore.shared.value.pinsMap
        let current = looks.contains { $0.0 == now } ? now : "apple-standard"
        return HStack(spacing: 20) {
            Button {
                Feel.tap()
                dock.tool = nil
            } label: {
                Icon5(key: "cross", ink: Palette.ink, size: 22).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close layers")
            ForEach(looks, id: \.0) { l in
                Button {
                    guard l.0 != current else { return }
                    Feel.tap()
                    MapSettingsStore.shared.change { $0.pinsMap = l.0 }
                } label: {
                    Text(l.1).font(l.0 == current ? .body.weight(.semibold) : .body)
                        .foregroundStyle(Palette.ink.opacity(l.0 == current ? 1 : 0.5))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(l.0 == current ? [.isButton, .isSelected] : .isButton)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: Share: every pin as its name and an Apple Maps link, in the system's share sheet

    private func share() {
        guard !store.pins.isEmpty else { Feel.refuse(); return }
        let lines = store.pins.reversed().compactMap { p -> String? in
            let q = p.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Pin"
            return "\(p.title)\nhttps://maps.apple.com/?ll=\(p.lat),\(p.lon)&q=\(q)"
        }
        var top = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        while let next = top?.presentedViewController { top = next }
        top?.present(UIActivityViewController(activityItems: [lines.joined(separator: "\n\n")], applicationActivities: nil), animated: true)
    }
}
