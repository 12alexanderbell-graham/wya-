import SwiftUI

/// A LINE RISING INTO PLACE: the text sits in its own bounds as a window and comes up into it from below, once when
/// it first shows and again when `key` changes (another place's name). Still when Reduce Motion is on.
struct RiseIn: ViewModifier {
    let key: String
    var delay: Double = 0
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .visualEffect { c, g in c.offset(y: up || Motion.reduce ? 0 : g.size.height * 1.05) }
            .clipped()
            .onAppear { rise() }
            .onChange(of: key) { _, _ in
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { up = false }
                rise()
            }
    }

    private func rise() {
        guard !Motion.reduce else { up = true; return }
        withAnimation(.spring(duration: 0.75, bounce: 0).delay(delay)) { up = true }
    }
}

extension View {
    /// rises into place from behind its own bounds (RiseIn)
    func risesIn(_ key: String, delay: Double = 0) -> some View { modifier(RiseIn(key: key, delay: delay)) }
}

/// A TILE SETTLING AS IT SCROLLS IN: while a tile is coming up from under the bottom edge it leans back in depth, a
/// little low, and lies flat as it reaches its place; it keeps following the finger (no timer), never fades, and is
/// still under Reduce Motion.
struct SettleIn: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { c, phase in
            let p = Motion.reduce ? 0 : max(0, phase.value)
            return c
                .rotation3DEffect(.degrees(p * -24), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
                .offset(y: p * 18)
                .scaleEffect(1 - p * 0.05, anchor: .top)
        }
    }
}

extension View {
    /// leans back and settles flat as it scrolls up into view (SettleIn)
    func settlesIn() -> some View { modifier(SettleIn()) }
}

/// A HEADING RISING AS IT COMES INTO VIEW: the line comes up through its own bounds the first time it is nearly all
/// on screen, never fading; already in place under Reduce Motion
struct RiseWhenSeen: ViewModifier {
    @State private var up = false
    func body(content: Content) -> some View {
        content
            .visualEffect { [up] c, g in c.offset(y: up || Motion.reduce ? 0 : g.size.height * 1.05) }
            .clipped()
            .onScrollVisibilityChange(threshold: 0.8) { seen in
                guard seen, !up else { return }
                withAnimation(.spring(duration: 0.75, bounce: 0)) { up = true }
            }
    }
}

extension View {
    /// rises into place from behind its own bounds the first time it scrolls into view (RiseWhenSeen)
    func risesWhenSeen() -> some View { modifier(RiseWhenSeen()) }
}
