import SwiftUI

/// THE TUTORIAL (Part 5): a box under the head saying one thing to do, in a few words; once you have done it (or
/// tapped the box) the next. It comes once, right after the first open, and never again. Each line is shown with the
/// wordless hint that already plays that gesture (the dot turning, the gear coming), so the words and the move come
/// together. Four lines: a country's card, turning the dot, holding it, the two other tabs.
@MainActor @Observable
final class Tutorial {
    static let shared = Tutorial()
    private static let key = "wya.tutorial.done"

    enum Step: Int, CaseIterable { case card, turn, hold, tabs }
    /// the line on screen (nil: no tutorial)
    private(set) var step: Step?

    static let words: [Step: String] = [
        .card: "Tap a country to open it.",
        .turn: "Swipe the dot sideways for regions, places and pins.",
        .hold: "Hold the dot for map settings.",
        .tabs: "The square is your lists. The triangle is you.",
    ]

    var done: Bool { UserDefaults.standard.bool(forKey: Self.key) }

    /// after the first open: once, unless it has been seen
    func begin() {
        guard !done, step == nil else { return }
        withAnimation(Motion.chrome) { step = .card }
    }
    /// shown again whatever was seen (the test driver)
    func replay() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        step = nil
        begin()
    }

    /// that thing done (or the box tapped on it): the next line, or the end
    func did(_ s: Step) {
        guard step == s else { return }
        next()
    }
    func next() {
        guard let s = step else { return }
        if let n = Step(rawValue: s.rawValue + 1) {
            step = n
        } else {
            UserDefaults.standard.set(true, forKey: Self.key)
            withAnimation(Motion.chrome) { step = nil }
        }
    }
    /// put away without being finished (it comes back next time the app opens)
    func stop() { withAnimation(Motion.chrome) { step = nil } }
}

/// THE BOX: the width of the head's row, 8 pt under it, one or two lines in the app's black, the system's frosted glass
/// (words over the map need it, as search's results box and What's here? have it). It comes out from under the head
/// row and goes back under it (cut at the row's foot, so it never crosses the circles); its words change at once.
struct TutorialBox: View {
    let layout: Layout
    /// the map is on screen with nothing over it that the box would sit on
    let on: Bool
    @State private var tutorial = Tutorial.shared
    @State private var card = CardState.shared
    @State private var region = RegionCardState.shared

    var body: some View {
        let L = layout
        let w = L.W - 2 * L.side
        // (a card up: the box steps back under the head, its card's title and buttons are where it stood, and its next
        // line comes once the card has gone)
        let shown = on && !card.isOpen && !region.isOpen
        ZStack(alignment: .top) {
            if shown, let s = tutorial.step {
                Button {
                    Feel.tap()
                    tutorial.next()
                } label: {
                    Text(Tutorial.words[s] ?? "")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.identity)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: w)
                .glassEffect(PageGlass.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 8)
                .accessibilityHint("Goes on")
                // (out from under the head row: moved its own height and the gap, cut at the row's foot)
                .transition(.offset(y: -120))
            }
        }
        .frame(width: L.W, height: 140, alignment: .top)
        .clipped()
        .position(x: L.W / 2, y: L.headBottom + 70)
        .animation(Motion.chrome, value: shown)
        .allowsHitTesting(shown && tutorial.step != nil)
        // a card opened: its line is done
        .onChange(of: card.isOpen) { _, open in if open { tutorial.did(.card) } }
        .onChange(of: region.isOpen) { _, open in if open { tutorial.did(.card) } }
        // the gesture's own wordless hint plays under its words, once they are on screen
        .onChange(of: shown ? tutorial.step : nil) { _, s in
            if s == .turn { Hints.shared.show(turn: true) }
            if s == .hold { Hints.shared.show(turn: false) }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityHidden(!shown || tutorial.step == nil)
    }
}
