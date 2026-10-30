import SwiftUI

/// THE TOP PULL IS THE AI'S, AND ONLY THE AI'S. Pulled down from the head, following the finger: the wheel's black dot
/// is the AI's needle in disguise. Its round edge draws out into the needle's black point and swings round to where the
/// needle rests, the needle's white point grows out of its middle, and the lime glass circle grows out from behind it
/// to its full size. Let go past half way and it settles there; pull back up or tap the map and it goes back into the
/// dot the same way. Search and the plus stay exactly as they are. No bell, no gear, no notifications, no rank drop, no
/// page. The same dot, held still, turns into the gear: its edge notches in between the teeth until it is the gear icon
/// exactly, turning a little as it forms; it then rolls slowly for as long as settings are open (BUILD-BOOK 5: one turn
/// in 6 s), and a tap on it turns it back into the dot.
enum TopPull {
    /// how long the dot has to be held, still, before it starts to become the gear, and how long it takes to become it
    static let holdDelay: Double = 0.18
    static let holdForm: Double = 0.42
}

/// The dot at the head's middle, on its way to the AI (`ai` 0 to 1) or to the gear (`gear` 0 to 1). At 0 and 0 it is
/// exactly the wheel's dot: the wheel's own top glyph is hidden while this is drawn, so the swap never shows.
struct DotMorph: View, Animatable {
    var ai: CGFloat
    var gear: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ai, gear) }
        set { ai = newValue.first; gear = newValue.second }
    }
    /// the gear's own rolling, while settings are open
    var roll: Angle = .zero
    var ink: Color

    /// the dot: the wheel draws its glyphs 30 points on the 9-unit icon box, so the circle (8 units) is 26.67 points
    static let unit: CGFloat = 30 / 9
    static let dotR: CGFloat = 4 * unit
    /// the AI's circle and its mark (a third bigger than the head's circles, the mark the circle's own size)
    static let aiSize: CGFloat = 58

    var body: some View {
        let ea = Flow.smooth(0, 1, ai)
        ZStack {
            if ai > 0.0005 {
                // A glyph into a glyph by rolling within its circle (Part 0.4 rule 4): the dot rolls down out of the
                // lime circle as the needle, at its full size and resting angle, rolls in from above, both at the same
                // speed, clipped by the lime circle. No dot stays in the middle, and nothing is uncovered by a growing
                // circle. The lime glass still grows out from behind the dot. the lime is (nearly) whole before the
                // roll, so the roll happens inside the AI's own circle; the clip is the mark's own reach, fixed, never
                // growing
                let k = Flow.smooth(0, 0.35, ai)
                let limeD = Flow.lerp(2 * Self.dotR, Self.aiSize, k)
                Color.clear
                    .frame(width: Self.aiSize, height: Self.aiSize)
                    .glassEffect(.clear.tint(Palette.lime), in: .circle)
                    .scaleEffect(limeD / Self.aiSize)
                let r = Flow.smooth(0.2, 0.75, ai)
                let travel = Self.aiSize + 7.2   // the needle's whole length: it starts wholly outside the clip
                ZStack {
                    ZStack {
                        NeedleHalf(black: false)
                            .fill(Palette.white)
                        NeedleHalf(black: true)
                            .fill(ink == Palette.ink ? Palette.ink : ink.mix(with: Palette.ink, by: Double(ea)))
                    }
                    .frame(width: Self.aiSize, height: Self.aiSize)
                    .offset(y: -(1 - r) * travel)
                    Circle()
                        .fill(ink)
                        .frame(width: 2 * Self.dotR, height: 2 * Self.dotR)
                        .offset(y: r * travel)
                }
                .frame(width: Self.aiSize, height: Self.aiSize)
                .mask { Circle().frame(width: Self.aiSize + 7.2, height: Self.aiSize + 7.2) }
            } else {
                // THE GEAR, THE SAME WAY: the gear icon, never bent out of the dot, is behind it from the start (its
                // teeth reach exactly the dot's edge, so the dot covers it); the dot, a circle all the way, sinks into
                // its middle and the teeth are there as it goes, the gear turning a little; then it rolls while open.
                // Nothing gets smaller and then bigger again.
                let gt = Flow.smooth(0, 1, gear)
                GearMorph(t: 1)
                    .fill(ink)
                    .rotationEffect(.degrees(30 * Double(gt)) + roll)
                let dr = Self.dotR * (1 - Flow.smooth(0, 0.8, gear))
                if dr > 0.05 {
                    Circle()
                        .fill(ink)
                        .frame(width: 2 * dr, height: 2 * dr)
                }
            }
        }
        .frame(width: Self.aiSize, height: Self.aiSize)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The AI needle's two halves as the AIMark draws them (24-unit grid: the black point up to y -1.5, the white down to
/// 25.5, both on a base 5.14 wide through the middle, turned 45 degrees), in the 58-point box.
private struct NeedleHalf: Shape {
    let black: Bool
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let s = rect.width / 24
        let turn = CGFloat.pi / 4
        func rot(_ p: CGPoint) -> CGPoint {
            CGPoint(x: c.x + p.x * cos(turn) - p.y * sin(turn), y: c.y + p.x * sin(turn) + p.y * cos(turn))
        }
        let tip: CGFloat = black ? -13.5 * s : 13.5 * s
        var path = Path()
        path.addLines([CGPoint(x: 0, y: tip), CGPoint(x: 2.57 * s, y: 0), CGPoint(x: -2.57 * s, y: 0)].map(rot))
        path.closeSubpath()
        return path
    }
}

/// The gear (Icons5 "settings": one outline, eight teeth, no hole). Drawn at t 1, the icon exactly (DotMorph grows it
/// out of the dot by size; t below 1 bends the dot's edge into the teeth, which is no longer used).
private struct GearMorph: Shape {
    var t: CGFloat
    /// the gear's corners in grid units (0 to 8, the middle at 4,4), read once from the icon itself
    private static let corners: [CGPoint] = {
        guard let p = IC5.all["settings"]?.frames.first?.first?.path else { return [] }
        var pts: [CGPoint] = []
        p.forEach { e in
            switch e {
            case .move(let q), .line(let q): pts.append(q)
            default: break
            }
        }
        return pts
    }()

    func path(in rect: CGRect) -> Path {
        let u = DotMorph.unit
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        let pts: [CGPoint] = Self.corners.map { q in
            let dx = q.x - 4, dy = q.y - 4
            let r = max(0.0001, hypot(dx, dy))
            let rr = Flow.lerp(4, r, t)
            return CGPoint(x: c.x + dx / r * rr * u, y: c.y + dy / r * rr * u)
        }
        guard pts.count > 2 else {
            return Path(ellipseIn: CGRect(x: c.x - DotMorph.dotR, y: c.y - DotMorph.dotR, width: 2 * DotMorph.dotR, height: 2 * DotMorph.dotR))
        }
        path.addLines(pts)
        path.closeSubpath()
        return path
    }
}

/// Where the pull is grabbed, over everything: the strip across the top and the head's band beside the middle (never
/// the side circles or the wheel, which keep their own touches); with the AI out, the AI too, so it can be pushed back
/// up. One view with one gesture, so a drag never changes hands halfway.
struct TopPullView: View {
    @Bindable var head: HeadState
    let water: Water
    @State private var dragging = false

    var body: some View {
        let L = water.layout
        ZStack(alignment: .topLeading) {
            // no screen-wide catcher: a finger on the map or the sheet puts them away (HeadState.putAway) and goes on.
            // THE PULL ONLY OVER THE MAP: once the water's top is up at the head, the top of the screen is the water's
            // to pull down
            let sheetHigh = water.form().top < L.headBottom + 40
            Color.clear
                .frame(width: L.W, height: L.H)
                .contentShape(PullArea(layout: L, ai: head.pullStop > 0))
                .gesture(pullGesture)
                // sideways (1.11) the strip would be one of the map's side edges: the map's own
                .allowsHitTesting(!head.searching && !head.toolsOpen && !sheetHigh && !Sideways.shared.on)
                .onChange(of: sheetHigh) { _, high in if high { head.putAway() } }
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
    }

    /// the finger only: what it does is the head's (HeadState.pullBegan/Moved/Ended), so a test runs the same code
    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { g in
                if !dragging { dragging = true; head.pullBegan() }
                head.pullMoved(g.translation.height)
            }
            .onEnded { g in
                dragging = false
                head.pullEnded(velocity: g.velocity.height)
            }
    }
}

/// The pull's grab area: the strip across the top of the screen and the head's band beside the middle slot, and the
/// AI's circle while it is out.
nonisolated struct PullArea: Shape {
    var layout: Layout
    var ai: Bool
    func path(in rect: CGRect) -> Path {
        let L = layout
        var p = Path(CGRect(x: 0, y: 0, width: L.W, height: L.headTop))
        let band = L.headBottom + 14
        let leftEdge = L.side + L.circle + 6, mid = L.W / 2, half: CGFloat = 34
        p.addRect(CGRect(x: leftEdge, y: 0, width: mid - half - leftEdge, height: band))
        p.addRect(CGRect(x: mid + half, y: 0, width: L.W - leftEdge - mid - half, height: band))
        // under the head, all the way across between the side circles' columns
        p.addRect(CGRect(x: leftEdge, y: L.headBottom, width: L.W - 2 * leftEdge, height: 14))
        if ai {
            let r = DotMorph.aiSize / 2
            p.addEllipse(in: CGRect(x: mid - r, y: L.headY - r, width: 2 * r, height: 2 * r))
        }
        return p
    }
}
