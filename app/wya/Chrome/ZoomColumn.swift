import SwiftUI

/// THE ZOOM COLUMN: plus, minus, reset, lock, full screen; five black glyphs with no glass, 16 from the edge on the
/// plus's own line. It stays centred in the open map between the head and the water, and rides the water's own spring
/// as the sheet moves.
struct ZoomColumn: View {
    let map: MapController
    let water: Water
    let head: HeadState

    var body: some View {
        let f = water.form()
        let L = water.layout
        let W = L.W
        let minTop = L.headBottom + 8
        // past half the column stays at its height and the rising sheet takes its buttons one by one from the bottom:
        // each shrinks into its own middle as the edge comes near it and is gone just before the edge reaches it, so
        // the glass never passes over a button. It follows the finger, so it reverses exactly.
        let centre = (L.headBottom + max(f.top, L.top(.half))) / 2
        let top = max(minTop, centre - 110)
        let ink: Color = FullView.night(f.page) ? Palette.white : Palette.ink
        let away = { (i: Int) -> CGFloat in
            let y = top + 22 + 44 * CGFloat(i)
            return max(0.001, Flow.smooth(10, 60, f.top - y))
        }
        VStack(spacing: 0) {
            // at a limit a button dims to the one low-opacity black (50%) and can't be pressed
            holdCell("plus", dir: 1, label: "Zoom in", ink: map.atMax ? ink.opacity(0.5) : ink) { map.zoomIn() }
                .disabled(map.atMax)
                .scaleEffect(away(0))
                .allowsHitTesting(away(0) > 0.5)
            holdCell("minus", dir: -1, label: "Zoom out", ink: map.atHome ? ink.opacity(0.5) : ink) { map.zoomOut() }
                .disabled(map.atHome)
                .scaleEffect(away(1))
                .allowsHitTesting(away(1) > 0.5)
            cell("reset", label: "Back to the world", ink: map.atRest ? ink.opacity(0.5) : ink) { map.goHome() }
                .disabled(map.atRest)
                .scaleEffect(away(2))
                .allowsHitTesting(away(2) > 0.5)
            cell("lock", on: map.locked, label: map.locked ? "Unlock the map" : "Lock the map", ink: ink) { map.locked.toggle() }
                .scaleEffect(away(3))
                .allowsHitTesting(away(3) > 0.5)
            cell("fullscreen", label: "Full screen", ink: ink) { }
                .scaleEffect(away(4))
                .allowsHitTesting(away(4) > 0.5)
        }
        .frame(width: 44)
        .position(x: W - L.side - 22, y: top + 110)
    }

    /// plus and minus: a tap is one step; held past a third of a second the zoom keeps going until the finger lifts
    private func holdCell(_ key: String, dir: Int, label: String, ink: Color, _ tap: @escaping () -> Void) -> some View {
        HoldButton(onTap: { Feel.tap(); tap() },
                   onHold: { held in
                       if held { Feel.tap() }
                       map.holdZoom = held ? dir : 0
                   }) {
            Icon5(key: key, ink: ink, size: 22)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Feel.tap(); tap() }
    }

    private func cell(_ key: String, on: Bool = false, label: String, ink: Color, _ action: @escaping () -> Void) -> some View {
        Button {
            Feel.tap()
            action()
        } label: {
            Icon5(key: key, on: on, ink: ink, size: 22)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A control that is tapped or held: a tap when the finger lifts within a third of a second, otherwise a hold from
/// that moment until it lifts (or slides off). Nothing fires twice.
struct HoldButton<Label: View>: View {
    var onTap: () -> Void
    var onHold: (Bool) -> Void
    @ViewBuilder var label: () -> Label
    @State private var down = false
    @State private var holding = false
    @State private var timer: Task<Void, Never>?
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        label()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard enabled else { return }
                        if !down {
                            down = true
                            timer = Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(330))
                                guard !Task.isCancelled, down else { return }
                                holding = true
                                onHold(true)
                            }
                        }
                        // a finger that slides well off lets go
                        if hypot(g.translation.width, g.translation.height) > 44, holding { holding = false; onHold(false) }
                    }
                    .onEnded { g in
                        timer?.cancel(); timer = nil
                        defer { down = false }
                        guard enabled else { return }
                        if holding { holding = false; onHold(false) }
                        else if hypot(g.translation.width, g.translation.height) < 22 { onTap() }
                    }
            )
    }
}
