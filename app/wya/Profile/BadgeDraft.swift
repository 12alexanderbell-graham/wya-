#if DEBUG
import SwiftUI

/// BADGE ART, TWO DRAFTS FOR A LOOK (P07 §6; debug builds only, nothing here is used by the app): a map badge and the
/// streak's, each in the five levels (lime, blue, silver, gold, diamond), shown over the Profile's own ground so the
/// diamond's glass is real. The map badge is Europe's land exactly as the map draws it (the map's own units of the
/// continent, its own projection); the streak's is the sun. Only the level's material changes; no shine streaks.
/// The test driver's `action review.badges` shows it and hides it.
@MainActor @Observable
final class BadgeDraft {
    static let shared = BadgeDraft()
    var on = false
}

/// a shape drawn from rings of points in a 0...1 box (its own width to height kept)
struct RingsShape: Shape {
    let rings: [[CGPoint]]
    let aspect: CGFloat
    func path(in r: CGRect) -> Path {
        // fitted in the middle of the frame, never stretched
        let w = min(r.width, r.height * aspect), h = w / aspect
        let o = CGPoint(x: r.midX - w / 2, y: r.midY - h / 2)
        var p = Path()
        for ring in rings where ring.count > 2 {
            p.move(to: CGPoint(x: o.x + ring[0].x * w, y: o.y + ring[0].y * h))
            for q in ring.dropFirst() { p.addLine(to: CGPoint(x: o.x + q.x * w, y: o.y + q.y * h)) }
            p.closeSubpath()
        }
        return p
    }
}

/// the sun: a disc and twelve rays with straight-cut ends (the icons' way: full shapes, sharp ends)
struct SunShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height), c = CGPoint(x: r.midX, y: r.midY)
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - s * 0.29, y: c.y - s * 0.29, width: s * 0.58, height: s * 0.58))
        for i in 0 ..< 12 {
            let a = Double(i) * .pi / 6
            let inner = s * 0.35, outer = s * 0.5, half = s * 0.035
            let d = CGPoint(x: cos(a), y: sin(a)), n = CGPoint(x: -sin(a), y: cos(a))
            let pt = { (rad: CGFloat, side: CGFloat) in CGPoint(x: c.x + d.x * rad + n.x * side, y: c.y + d.y * rad + n.y * side) }
            p.move(to: pt(inner, -half)); p.addLine(to: pt(outer, -half)); p.addLine(to: pt(outer, half)); p.addLine(to: pt(inner, half))
            p.closeSubpath()
        }
        return p
    }
}

/// one badge: the shape filled with its level's material, a hairline of its deep colour round it, a soft shadow under
/// it; the diamond is the system's own glass in the shape
struct BadgeMark<S: Shape>: View {
    let shape: S
    let level: BadgeLevel
    let size: CGFloat
    /// width to height of the frame (Europe is wider than tall)
    var wide: CGFloat = 1
    var body: some View {
        let m = level.stops
        Group {
            if level == .diamond {
                Color.clear.glassEffect(.regular.tint(Color.white.opacity(0.25)), in: shape)
            } else {
                shape.fill(LinearGradient(stops: [.init(color: m.light, location: 0), .init(color: m.body, location: 0.45),
                                                  .init(color: m.deep, location: 1)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Palette.ink.opacity(0.18), radius: size / 40, y: size / 60)
            }
        }
        .frame(width: size * wide, height: size)
    }
}

struct BadgeDraftView: View {
    let world: World?
    let L: Layout
    var body: some View {
        if BadgeDraft.shared.on {
            let europe = Self.europe(world)
            let eu = RingsShape(rings: europe.rings, aspect: europe.aspect)
            ZStack {
                // a ground of its own (the Profile's moving field), so nothing of the page is under the drafts and the
                // diamond's glass has something to bend
                LivingField().ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Text("Europe").frame(width: 150, alignment: .center)
                        Text("Streak").frame(width: 92, alignment: .center)
                        Text("Small").frame(maxWidth: .infinity, alignment: .center)
                    }
                    .font(.headline).foregroundStyle(Palette.ink)
                    .padding(.bottom, 8)
                    ForEach(BadgeLevel.allCases, id: \.self) { l in
                        HStack(spacing: 0) {
                            BadgeMark(shape: eu, level: l, size: 72, wide: 150.0 / 72).frame(width: 150)
                            BadgeMark(shape: SunShape(), level: l, size: 72).frame(width: 92)
                            HStack(spacing: 14) {
                                BadgeMark(shape: eu, level: l, size: 28, wide: 1.6)
                                BadgeMark(shape: SunShape(), level: l, size: 28)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 96)
                        .overlay(alignment: .bottomLeading) {
                            Text(l.name).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).offset(y: -2)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(width: L.W, height: L.H)
            .allowsHitTesting(false)
        }
    }

    static func europe(_ w: World?) -> (rings: [[CGPoint]], aspect: CGFloat) { BadgeRings.continent(w, "Europe") }
}
#endif
