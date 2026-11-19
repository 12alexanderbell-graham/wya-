import SwiftUI

/// THE SCROLL BLUR, the same everywhere: Apple's soft edge at a list's top once the list has scrolled (fully up,
/// nothing is blurred and no line is drawn), and at its bottom once scrolled while more is below. Every vertical
/// scroll in the app takes it.
struct ScrollBlur: ViewModifier {
    @State private var above = false
    @State private var below = false
    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.soft, for: .all)
            .scrollEdgeEffectHidden(!above, for: .top)
            .scrollEdgeEffectHidden(!below, for: .bottom)
            .onScrollGeometryChange(for: [Bool].self) { g in
                [g.contentOffset.y + g.contentInsets.top > 1,
                 g.contentOffset.y + g.containerSize.height - g.contentInsets.bottom < g.contentSize.height - 1]
            } action: { _, now in
                above = now[0]; below = now[0] && now[1]
            }
    }
}

extension View {
    func scrollBlur() -> some View { modifier(ScrollBlur()) }
}

#if DEBUG
/// the driver's scroll (debug builds): a list that takes it scrolls to this many points down
@MainActor @Observable final class ScrollTest {
    static let shared = ScrollTest()
    var y: CGFloat = 0
}
#endif
