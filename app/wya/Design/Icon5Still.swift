import SwiftUI

/// One of his icons held at a point of its drawing: `progress` 0 is the first frame (unselected), 1 the last
/// (selected). Something that moves the icon by a finger (the mode wheel) sets the frame from where the finger has
/// put it, so the drawing changes exactly as fast as it moves and never plays a little film of its own.
struct Icon5Still: View {
    let key: String
    var progress: CGFloat
    var ink: Color = .black
    var size: CGFloat = 20

    var body: some View {
        let frames = IC5.all[key]?.frames ?? []
        let i = frames.isEmpty ? 0 : min(frames.count - 1, max(0, Int((progress * CGFloat(frames.count - 1)).rounded())))
        let layers = frames.isEmpty ? [] : frames[i]
        ZStack {
            ForEach(Array(layers.enumerated()), id: \.offset) { _, l in
                IC5Shape(path: l.path).fill(colour(l.colour), style: FillStyle(eoFill: true))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func colour(_ c: String) -> Color {
        switch c {
        case "#d94f3d": return Palette.red
        case "#ffe04a": return Palette.yellow
        case "#ffffff": return .white
        case "#78aef8": return Palette.blue
        case "#d4e249": return Palette.lime
        case "glass":   return Color.white.opacity(0.62)
        default:        return ink
        }
    }
}
