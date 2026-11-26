import SwiftUI

/// YOUR STATS AND YOUR BADGES AS THEIR OWN PAGES: a number tapped on the Profile slides its page in from the right
/// over the Profile's own moving ground; the water closes to its tab capsule while it is up (as a place page's does).
/// The back circle at the top left, where the head's left circle sits on the Map; the page's name large under it; the
/// list under that, scrolling under the one soft edge. A swipe to the right, or the back circle, slides it away and
/// the water comes back to 25%.
struct ProfilePushedPage: View {
    let kind: ProfileEdit.Sheet
    let water: Water
    @State private var edit = ProfileEdit.shared
    @State private var store = ProfileStore.shared
    /// how far a swipe back has taken the page (0 at rest)
    @State private var pull: CGFloat = 0

    var body: some View {
        let L = water.layout
        let me = store.me
        let s = me.groundStrength ?? 0.5
        let w = L.W - 2 * L.side
        // (the page's name in the top row, in the middle, between the back circle and the far side, 19 Oct; it stood
        // large under the back circle)
        let listTop = L.headBottom + 12
        ZStack(alignment: .topLeading) {
            // the Profile's own ground, as it is behind the page
            LivingField(custom: me.ground.map { g in (0 ..< 4).map { g[$0 % max(1, g.count)].srgb } },
                        saturation: ProfileView.look.x * (0.7 + 0.6 * s), power: ProfileView.look.y * (0.62 + 0.76 * s))
                .frame(width: L.W, height: L.H)
            // (the list under the title and the back circle, which float over it)
            Group {
                // THE WHOLE SCREEN'S HEIGHT (26 Nov): resting where it did, it scrolls up under the title and the back
                // circle to the screen's top with Apple's soft edge, and down under the tab capsule's glass to the
                // screen's foot, its end kept clear of the capsule (it was cut hard under the title row and through a row
                // of badges over the capsule, as Lists was this morning)
                let foot = L.H - (L.capsule.minY - 8)
                // (the page's name is the list's own top bar, in the middle of the head's row)
                let name = kind == .stats ? "Stats" : "Badges"
                if kind == .stats { ProfileStatsList(width: w, room: L.H, top: listTop, foot: foot, side: L.side, title: name, titleY: L.headY) }
                else { ProfileBadgesList(width: w, room: L.H, top: listTop, foot: foot, side: L.side, title: name, titleY: L.headY) }
            }
            GlassCircle(icon: "back", label: "Back") { back() }
                .position(x: L.side + 22, y: L.headY)
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        .offset(x: pull)
        // the system's swipe back: from the left edge, the page follows the finger and goes past a third or a flick
        .simultaneousGesture(DragGesture(minimumDistance: 12)
            .onChanged { v in
                guard v.startLocation.x < 32, v.translation.width > 0 else { return }
                pull = v.translation.width
            }
            .onEnded { v in
                guard v.startLocation.x < 32 else { return }
                if v.translation.width > L.W / 3 || v.predictedEndTranslation.width > L.W / 2 { back() }
                else { withAnimation(Motion.settle) { pull = 0 } }
            })
        .accessibilityAction(.escape) { back() }
        // (opened while the tab was still switching, the water's move to closed was lost and it stood at 25% over the
        // list: once settled, it is closed again)
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            if water.stop != .closed { water.go(.closed) }
        }
    }

    private func back() {
        // (one badge open: back to all of them first)
        if kind == .badges, edit.badge != nil {
            Feel.tap()
            edit.badge = nil
            withAnimation(Motion.settle) { pull = 0 }
            return
        }
        withAnimation(Motion.chrome) { edit.close(water: water) }
        pull = 0
    }
}
