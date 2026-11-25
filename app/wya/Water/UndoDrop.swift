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
    /// the drop carrying (a write the store refused): no undo in it, a tap only sinks it
    @State private var notice = false

    var body: some View {
        let L = water.layout
        let atFull = form.page > 0.5
        let edge = water.stop == .closed && !water.held ? L.capsule.minY : form.top
        Button {
            if notice { sink(); return }
            Feel.tap()
            Task { await MarkStore.shared.undo() }
            sink()
        } label: {
            HStack(spacing: 8) {
                // the icon is there only while the drop is out (it just appears; nothing of it inside the water); with
                // no undo icon drawn yet in the set, the words alone, centred (no empty slot beside them)
                // the undo mark (never an SF Symbol): the set's share arrow turned to point back, on the 8 by 8 grid
                // (IconsDrawn "undo"; the hand-drawn bow before it had a bent head)
                Icon5Still(key: "undo", progress: 0, ink: Palette.ink, size: 15)
                    .opacity(up && !notice ? 1 : 0)
                    .transaction { $0.animation = nil }
                Text(up ? words : String(repeating: "\u{2002}", count: max(1, words.count)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    // cut in the middle, the place's start and kept
                    .truncationMode(.middle)
                    .contentTransition(.identity)
                    .frame(width: min(Self.width(words), L.capsule.width - 28 - 23))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            // as wide as its words + 28 pt (the icon's 23 pt too, once it is drawn), never wider than the tab capsule
            .fixedSize()
            // its words at the standard sizes only: the pill is 36 pt high
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            // the water's own kind of glass, so inside the water it merges away
            .glassEffect(.clear, in: .capsule)
            // touched over 44 pt (the pill is drawn 36 pt high)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // rises out of the edge: from wholly inside it to 30 pt above it
        .position(x: L.W / 2, y: up ? edge - 30 : edge + 22)
        .opacity(atFull || water.pageUp ? 0 : 1)
        .allowsHitTesting(up && !atFull && !water.pageUp)
        .accessibilityLabel(notice ? words : "Undo \(words)")
        .accessibilityHidden(!up)
        // with a stamping card up the drop waits and rises as the card closes (4.2.3:), so it never sits on the
        // card's Details | Verify? (a region's, town's or thing's card the same: its Details | Verify? row is where
        // the drop rises)
        .onChange(of: marks.changes) { _, _ in if card.isOpen || regionCard.isOpen { pending = true } else { rise() } }
        .onChange(of: marks.notKept) { _, _ in rise(notice: "Not kept") }
        .onChange(of: card.isOpen || regionCard.isOpen) { _, open in if !open, pending { pending = false; rise() } }
        // a change of map or tab sinks it; the step stays, for a shake
        .onChange(of: water.head?.mode) { _, _ in pending = false; if up { sink() } }
        .onChange(of: water.profile) { _, _ in pending = false; if up { sink() } }
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

    private func rise(notice say: String? = nil) {
        notice = say != nil
        words = say ?? marks.lastWords ?? ""
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
