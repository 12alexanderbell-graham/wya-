import SwiftUI

/// OUR AI MARK: "two triangles ... the short sides touch each other. There's no circle in between ... these triangles
/// extend slightly past the outside of the circle". Black north, white south, resting at 45°.
struct AIMark: View {
    var angle: Double = 45

    private func tri(_ size: CGSize, _ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        let s = min(size.width, size.height) / 24
        let ox = size.width / 2 - 12 * s, oy = size.height / 2 - 12 * s
        for (i, q) in pts.enumerated() {
            let pt = CGPoint(x: ox + q.0 * s, y: oy + q.1 * s)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                tri(geo.size, [(12, -1.5), (9.43, 12), (14.57, 12)]).fill(Palette.ink)
                tri(geo.size, [(12, 25.5), (9.43, 12), (14.57, 12)]).fill(Palette.white)
            }
            .rotationEffect(.degrees(angle))
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}
