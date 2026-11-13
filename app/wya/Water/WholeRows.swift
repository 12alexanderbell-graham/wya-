import SwiftUI

extension View {
    /// WHOLE ROWS ONLY (a sheet below full, where its rows do not scroll): hidden when its bottom (plus `need`, the room
    /// for what must come with it) is past `cut`, in the screen's points (nil: always shown)
    func whole(_ cut: CGFloat?, need: CGFloat = 0) -> some View {
        visualEffect { content, proxy in
            content.opacity(cut.map { proxy.frame(in: .global).maxY + need > $0 ? 0 : 1 } ?? 1)
        }
    }
}
