import SwiftUI

/// THE ZOOM COLUMN: plus, minus, reset, lock, full screen; five black glyphs with no glass, 16 from the edge on the
/// plus's own line. It stays centred in the open map between the head and the water, and rides the water's own spring
/// as the sheet moves.
struct ZoomColumn: View {
    let map: MapController
    let water: Water
    let head: HeadState
    /// the sideways mark's action (1.11)
    var sideways: () -> Void = {}

    var body: some View {
        let f = water.form()
        let L = water.layout
        let W = L.W
        let minTop = L.headBottom + 8
        // past half the column stays at its height and the rising sheet takes its buttons one by one from the bottom:
        // each slides off the right edge, at its own size, as the edge comes from 60 to 10 pt below its centre, and is
        // fully past the screen's edge before the glass reaches it. Nothing shrinks to nothing. It follows the finger,
        // so it reverses exactly. centred in the room for the sheet's top, or its 50% top above that (Layout.room)
        let room = L.room(sheetTop: max(f.top, L.top(.half)))
        let centre = (room.lowerBound + room.upperBound) / 2
        let top = max(minTop, centre - 110)
        let ink: Color = FullView.night(f.page) ? Palette.white : Palette.ink
        /// how far a button has slid right (0 at rest, 60 pt fully past the edge): straight with the edge's distance
        let slide = { (i: Int) -> CGFloat in
            let y = top + 22 + 44 * CGFloat(i)
            return 60 * (1 - Flow.clamp01((f.top - y - 10) / 50))
        }
        VStack(spacing: 0) {
            // at a limit a button dims to the one low-opacity black (50%) and can't be pressed
            holdCell("plus", dir: 1, label: "Zoom in", ink: ink, dim: map.atMax) { map.zoomIn() }
                .disabled(map.atMax)
                // a press on a mark at its limit: `refuse` (Part 0.3; 1.9's table)
                .overlay { if map.atMax { Color.clear.contentShape(Rectangle()).onTapGesture { Feel.refuse() }.accessibilityHidden(true) } }
                .offset(x: slide(0))
                .allowsHitTesting(slide(0) < 30)
            holdCell("minus", dir: -1, label: "Zoom out", ink: ink, dim: map.atHome) { map.zoomOut() }
                .disabled(map.atHome)
                // a press on a mark at its limit: `refuse` (Part 0.3; 1.9's table)
                .overlay { if map.atHome { Color.clear.contentShape(Rectangle()).onTapGesture { Feel.refuse() }.accessibilityHidden(true) } }
                .offset(x: slide(1))
                .allowsHitTesting(slide(1) < 30)
            cell("reset", label: "Back to the world", ink: ink, dim: map.atRest) { map.goHome() }
                .disabled(map.atRest)
                // a press on a mark at its limit: `refuse` (Part 0.3; 1.9's table)
                .overlay { if map.atRest { Color.clear.contentShape(Rectangle()).onTapGesture { Feel.refuse() }.accessibilityHidden(true) } }
                .offset(x: slide(2))
                .allowsHitTesting(slide(2) < 30)
            cell("lock", on: map.locked, label: map.locked ? "Unlock the map" : "Lock the map", ink: ink, feel: .notch) { map.locked.toggle() }
                .offset(x: slide(3))
                .allowsHitTesting(slide(3) < 30)
            cell("fullscreen", label: "Full screen", ink: ink, silent: true) { sideways() }
                .offset(x: slide(4))
                .allowsHitTesting(slide(4) < 30)
        }
        .frame(width: 44)
        .position(x: W - L.side - 22, y: top + 110)
    }

    /// plus and minus: a tap is one step; held past a third of a second the zoom keeps going until the finger lifts
    private func holdCell(_ key: String, dir: Int, label: String, ink: Color, dim: Bool, _ tap: @escaping () -> Void) -> some View {
        HoldButton(onTap: { Feel.tap(); tap() },
                   onHold: { held in
                       if held { Feel.tap() }
                       map.holdZoom = held ? dir : 0
                   }) {
            LimitIcon(key: key, ink: ink, dim: dim)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Feel.tap(); tap() }
    }

    /// a two-state switch landing is a `notch` (the lock); any other mark a `tap` (Part 0.3)
    enum CellFeel { case tap, notch }
    private func cell(_ key: String, on: Bool = false, label: String, ink: Color, dim: Bool = false, feel: CellFeel = .tap,
                      silent: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button {
            // a silent cell plays its own feel (the sideways mark refuses during an upload)
            if !silent { if feel == .notch { Feel.notch() } else { Feel.tap() } }
            action()
        } label: {
            LimitIcon(key: key, on: on, ink: ink, dim: dim)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(BareButton())
        .accessibilityLabel(label)
    }
}

/// a button that draws only its label: `.plain` fades a disabled label on its own, in one frame, over A1.8's circle
struct BareButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
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

/// A MARK REACHING A LIMIT (A1.8): its ink turns 50% black the moment the limit is reached and back the moment it is
/// left, in the same frame as the zoom's own landing, the way an iOS control's state changes. No circle.
struct LimitIcon: View {
    let key: String
    var on = false
    let ink: Color
    let dim: Bool
    var body: some View {
        Icon5(key: key, on: on, ink: dim ? Palette.ink.opacity(0.5) : ink, size: 22)
            .transaction { $0.animation = nil }
    }
}

