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
