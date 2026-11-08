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
                // the icon is there only while the drop is out (it just appears; nothing of it inside the water); with
                // no undo icon drawn yet in the set, the words alone, centred (no empty slot beside them)
                // the undo mark, drawn (8 Nov: never an SF Symbol): an arrow turning back on itself
                UndoGlyph().stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 15, height: 15)
                    .opacity(up ? 1 : 0)
                    .transaction { $0.animation = nil }
                Text(up ? words : String(repeating: "\u{2002}", count: max(1, words.count)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    // (8 Nov: nothing held it to the capsule, so a long town's words ran off both edges) a little
                    // smaller first, then cut in the middle, the place's start and "stamped" kept
                    .minimumScaleFactor(0.75)
                    .truncationMode(.middle)
                    .contentTransition(.numericText())
                    .frame(width: min(Self.width(words), L.capsule.width - 28 - 23))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            // as wide as its words + 28 pt (the icon's 23 pt too, once it is drawn), never wider than the tab capsule
            .fixedSize()
            // its words at the standard sizes only: the pill is 36 pt high
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            // the water's own kind of glass (frosted over a page, clear on the map), so inside the water it merges away
            .glassEffect(PageGlass.surface, in: .capsule)
            // touched over 44 pt (the pill is drawn 36 pt high)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // rises out of the edge: from wholly inside it (its 36 pt merged into the water's glass, so nothing shows; at
        // edge + 4 its top stuck 14 pt out as a bump on every sheet) to 30 pt above it
        .position(x: L.W / 2, y: up ? edge - 30 : edge + 22)
        .opacity(atFull ? 0 : 1)
        .allowsHitTesting(up && !atFull)
        .accessibilityLabel("Undo \(words)")
        .accessibilityHidden(!up)
        // with a stamping card up the drop waits and rises as the card closes (4.2.3: the card closes keeping every
        // change, then the drop rises), so it never sits on the card's Details | Verify?
        // (a region's, town's or thing's card the same: its Details | Verify? row is where the drop rises)
        .onChange(of: marks.changes) { _, _ in if card.isOpen || regionCard.isOpen { pending = true } else { rise() } }
        .onChange(of: card.isOpen || regionCard.isOpen) { _, open in if !open, pending { pending = false; rise() } }
    }
    @State private var card = CardState.shared
    @State private var regionCard = RegionCardState.shared
    private static let icon = "undo-stroke"
    private static let hasIcon = IC5.all[icon] != nil || IC5.drawn[icon] != nil
    @State private var pending = false
    /// the words' own width at the drop's text style (the pill is as wide as its words, up to the capsule)
    private static func width(_ s: String) -> CGFloat {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
        return ceil((s as NSString).size(withAttributes: [.font: font]).width) + 2
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

/// the undo drop's mark: a bow over the top from right to left, its arrowhead at the left end pointing down and back
struct UndoGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        // the bow: from the lower right up over the top to the left
        p.move(to: CGPoint(x: r.minX + w * 0.86, y: r.minY + h * 0.86))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.16, y: r.minY + h * 0.42),
                   control1: CGPoint(x: r.minX + w * 1.02, y: r.minY + h * 0.30),
                   control2: CGPoint(x: r.minX + w * 0.42, y: r.minY + h * 0.08))
        // the arrowhead at its end
        p.move(to: CGPoint(x: r.minX + w * 0.10, y: r.minY + h * 0.12))
        p.addLine(to: CGPoint(x: r.minX + w * 0.16, y: r.minY + h * 0.44))
        p.addLine(to: CGPoint(x: r.minX + w * 0.46, y: r.minY + h * 0.36))
        return p
    }
}
