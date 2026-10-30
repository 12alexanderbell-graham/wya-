import SwiftUI

/// THE LEVEL LINE (6.6): the Regions caption's third line. The level shown reads as the tail always does, "of 96
/// departments", semibold, centred where Countries' "of 263" sits; the country's other levels sit beside it on the same
/// line, coarsest to the left, finest to the right, each its word alone, 18 pt apart. It is one sideways strip: a word
/// tapped slides to the centre and becomes the level; a drag moves the strip with the finger and the word nearest the
/// centre when it comes to rest becomes the level (a tick as each word passes the centre, a notch on landing). Words
/// past the strip's ends run under a soft edge. A level that can't be had now (offline, not on the phone) says "Not
/// ready" in its place.
struct LevelLine: View {
    struct Level: Identifiable, Equatable { let row: Int; let word: String; var id: Int { row } }
    let levels: [Level]
    /// the level drawn now, and how many regions it has
    let current: Int
    let total: Int
    let notReady: Int?
    let width: CGFloat
    let visible: Bool
    let pick: (Int) -> Void

    @State private var centred: Int?
    @State private var mids: [Int: CGFloat] = [:]
    @State private var lastTick: Int?
    @State private var dragging = false
    /// the level last asked for (a tap and the scroll settling on it ask once)
    @State private var asked: Int?

    var body: some View {
        let ink = Palette.ink.opacity(0.5)
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(levels) { l in
                    let here = l.row == current
                    let words = here ? "of \(total.formatted()) \(l.word)" : l.row == notReady ? "Not ready" : l.word
                    Text(visible ? words : Caption.blank(words, "\u{2002}"))
                        .font(here ? .headline : .body)
                        .foregroundStyle(ink)
                        .contentTransition(.numericText(value: visible ? 1 : 0))
                        .animation(Motion.quick, value: words)
                        .fixedSize()
                        .id(l.row)
                        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named("levels")).midX }) { mids[l.row] = $0 }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !here else { return }
                            Feel.tap()
                            withAnimation(Motion.chrome) { centred = l.row }
                            asked = l.row
                            pick(l.row)
                        }
                        .accessibilityLabel(here ? "\(total) \(l.word), shown" : l.word)
                        .accessibilityAddTraits(.isButton)
                }
            }
            .scrollTargetLayout()
        }
        .coordinateSpace(name: "levels")
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centred, anchor: .center)
        // half the strip's width of room at each end, so any word, the first and the last too, can sit in the middle
        .contentMargins(.horizontal, width / 2, for: .scrollContent)
        .onScrollPhaseChange { _, phase in
            dragging = phase == .interacting || phase == .decelerating
            guard phase == .idle, let near = nearest(), near != current, near != asked else { return }
            Feel.notch()
            asked = near
            pick(near)
        }
        .onChange(of: nearest()) { _, n in
            guard dragging, let n, n != lastTick else { return }
            lastTick = n
            Feel.tick()
        }
        .onChange(of: current, initial: true) { _, c in
            if centred != c { withAnimation(Motion.chrome) { centred = c } }
        }
        .frame(width: width, height: 26)
        // soft at the strip's two ends, never a straight cut (P3)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                   .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityElement(children: .contain)
    }

    /// the word whose middle is nearest the strip's middle
    private func nearest() -> Int? {
        mids.min { abs($0.value - width / 2) < abs($1.value - width / 2) }?.key
    }
}
