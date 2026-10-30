import SwiftUI

/// THE UNDO DROP (Part 3.10, A3.16): after an undoable change, a small drop of the water's own glass rises out of its
/// top edge at the middle (out of the capsule when the water is closed) carrying the undo icon and the change's words;
/// a tap undoes it; it sinks back into the edge after 4 s. At full there is no edge, so no drop (the gestures still
/// undo). Drawn inside the water's GlassEffectContainer, so it is the water's glass, never glass on glass.
/// Haptics only (pour as it rises, tap on an undo); no sound.
struct UndoDrop: View {
    let water: Water
    let form: Water.Form
    @State private var marks = MarkStore.shared
    @State private var up = false
    @State private var words = ""
    @State private var hide: DispatchWorkItem?

    var body: some View {
        let L = water.layout
        let atFull = form.page > 0.5
        let edge = water.stop == .closed && !water.held ? L.capsule.minY : form.top
        Button {
            Feel.tap()
            Task { await MarkStore.shared.undo() }
            sink()
        } label: {
            HStack(spacing: 8) {
                // the icon is there only while the drop is out (it just appears; nothing of it inside the water)
                Icon5(key: "undo-stroke", ink: Palette.ink, size: 15).opacity(up ? 1 : 0)
                Text(up ? words : String(repeating: "\u{2002}", count: max(1, words.count)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            // as wide as its words + 28 pt (the icon included), never wider than the tab capsule
            .fixedSize()
            .glassEffect(.clear, in: .capsule)
        }
        .buttonStyle(.plain)
        // rises out of the edge: from inside it (where the glass merges with the water's) to 30 pt above it
        .position(x: L.W / 2, y: up ? edge - 30 : edge + 4)
        .opacity(atFull ? 0 : 1)
        .allowsHitTesting(up && !atFull)
        .accessibilityLabel("Undo \(words)")
        .accessibilityHidden(!up)
        .onChange(of: marks.changes) { _, _ in rise() }
    }

    private func rise() {
        words = marks.lastWords ?? ""
        if !up {
            Feel.pour()
            withAnimation(Motion.chrome) { up = true }
        }
        hide?.cancel()
        let w = DispatchWorkItem { sink() }
        hide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    private func sink() {
        hide?.cancel()
        withAnimation(Motion.chrome) { up = false }
    }
}
