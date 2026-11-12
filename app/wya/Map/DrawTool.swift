import SwiftUI

/// THE DRAW TOOL: one tool for every map that draws (Places' own places now; Pins' lines and shapes on Apple's map
/// after), the same strokes, corners, undo and look wherever it is used.
/// - Drag one finger and the line follows it; lift and that stroke is kept. Tap and a corner is put there.
/// - Two fingers still move and zoom the map under it (the map passes only one finger's touches here).
/// - A shape closes when a stroke ends or a corner is tapped within 24 pt of its first corner; Done closes it too.
/// - Undo takes back the last stroke or corner; Cancel leaves with nothing made.
/// - Each stroke is cleaned (points closer than 1.5 pt to the line through their neighbours dropped) before it is kept,
///   and kept as latitude and longitude, so the map can move and zoom between strokes.
@MainActor @Observable
final class DrawTool {
    static let shared = DrawTool()

    enum Kind { case line, shape }
    struct Geo: Hashable, Codable { var lat: Double; var lon: Double }

    private(set) var on = false
    private(set) var kind: Kind = .shape
    /// the corners and traced points kept so far
    private(set) var points: [Geo] = []
    /// where each stroke or corner began in `points`: undo takes back from the last
    private(set) var marks: [Int] = []
    /// the finger's stroke now, on screen
    private(set) var live: [CGPoint] = []

    /// the map's conversions, given by whichever map is drawn on
    @ObservationIgnored private var toGeo: ((CGPoint) -> Geo?)?
    @ObservationIgnored private(set) var toScreen: ((Geo) -> CGPoint?)?
    @ObservationIgnored private var finish: ((Kind, [Geo]) -> Void)?
    @ObservationIgnored private var cancelled: (() -> Void)?

    static let closeDistance: CGFloat = 24
    static let clean: CGFloat = 1.5

    /// drawing starts on a map: what it is to be, the map's two conversions, and what happens when it is done or given up
    func start(_ kind: Kind, toGeo: @escaping (CGPoint) -> Geo?, toScreen: @escaping (Geo) -> CGPoint?,
               finish: @escaping (Kind, [Geo]) -> Void, cancel: @escaping () -> Void = {}) {
        self.kind = kind
        self.toGeo = toGeo; self.toScreen = toScreen
        self.finish = finish; self.cancelled = cancel
        points = []; marks = []; live = []
        on = true
    }

    func cancel() {
        guard on else { return }
        let c = cancelled
        end()
        c?()
    }

    /// Done: a shape with three corners or more, or a line with two, is made; with fewer, nothing to make
    func done() {
        guard on else { return }
        guard canFinish else { Feel.refuse(); return }
        let k = kind, p = points, f = finish
        end()
        Feel.tap()
        f?(k, p)
    }

    var canFinish: Bool { points.count >= (kind == .shape ? 3 : 2) }

    func undo() {
        guard on, let m = marks.popLast() else { Feel.refuse(); return }
        points.removeSubrange(m...)
        Feel.tick()
    }

    private func end() {
        on = false
        points = []; marks = []; live = []
        toGeo = nil; toScreen = nil; finish = nil; cancelled = nil
    }

    // MARK: one finger, from the map

    @ObservationIgnored private var downAt: CGPoint?
    @ObservationIgnored private var moved = false

    func touchBegan(_ p: CGPoint) {
        guard on else { return }
        downAt = p; moved = false
        live = [p]
    }

    func touchMoved(_ p: CGPoint) {
        guard on, let d = downAt else { return }
        if !moved, hypot(p.x - d.x, p.y - d.y) < 6 { return }
        moved = true
        live.append(p)
    }

    func touchEnded(_ p: CGPoint) {
        guard on, downAt != nil else { return }
        defer { downAt = nil; live = [] }
        // a tap: one corner; a drag: the stroke, cleaned
        var stroke = moved ? Self.simplify(live + [p], Self.clean) : [p]
        // (a stroke begun on the last corner does not repeat it)
        if stroke.count > 1, let l = points.last, let ls = toScreen?(l), hypot(stroke[0].x - ls.x, stroke[0].y - ls.y) < 6 { stroke.removeFirst() }
        // (a stroke or corner that ends on the first corner closes the shape, once there are three corners without that
        // last point: a loop drawn in one stroke closes too)
        var closes = false
        var kept = stroke
        let first = points.first.flatMap { toScreen?($0) } ?? stroke.first
        if kind == .shape, let f = first, let last = kept.last, points.count + kept.count - 1 >= 3,
           hypot(last.x - f.x, last.y - f.y) <= Self.closeDistance {
            kept.removeLast(); closes = true
        }
        let geo = kept.compactMap { toGeo?($0) }
        if !geo.isEmpty {
            marks.append(points.count)
            points += geo
            if !closes { Feel.tick() }
        }
        if closes { done() }
    }

    /// a second finger came down, or the system took the touch: the stroke so far is dropped, nothing is kept
    func touchCancelled() {
        downAt = nil; live = []
    }

    // MARK: measures

    /// a line's length, or a shape's outline's, in km
    var lengthKm: Double {
        guard points.count > 1 else { return 0 }
        var t = 0.0
        for i in 1 ..< points.count { t += Self.km(points[i - 1], points[i]) }
        if kind == .shape, points.count > 2 { t += Self.km(points[points.count - 1], points[0]) }
        return t
    }

    /// a shape's area in km², on the sphere
    var areaKm2: Double { Self.area(points) }

    static func km(_ a: Geo, _ b: Geo) -> Double {
        let p = Double.pi / 180
        let dlat = (b.lat - a.lat) * p, dlon = (b.lon - a.lon) * p
        let h = sin(dlat / 2) * sin(dlat / 2) + cos(a.lat * p) * cos(b.lat * p) * sin(dlon / 2) * sin(dlon / 2)
        return 2 * 6371.0088 * asin(min(1, h.squareRoot()))
    }

    /// the area a ring closes on the sphere (the sum over its edges of the longitude step times the sines' sum)
    static func area(_ ring: [Geo]) -> Double {
        guard ring.count > 2 else { return 0 }
        let p = Double.pi / 180, r = 6371.0088
        var s = 0.0
        for i in 0 ..< ring.count {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            var dl = (b.lon - a.lon) * p
            if dl > .pi { dl -= 2 * .pi } else if dl < -.pi { dl += 2 * .pi }
            s += dl * (2 + sin(a.lat * p) + sin(b.lat * p))
        }
        return abs(s * r * r / 2)
    }

    /// the words for a measure ("850 m", "2.4 km", "12 km²", "0.3 ha")
    static func words(km d: Double) -> String {
        d < 1 ? "\(Int((d * 1000 / 10).rounded()) * 10) m" : d < 10 ? String(format: "%.1f km", d) : "\(Int(d.rounded())) km"
    }
    static func words(km2 a: Double) -> String {
        a < 1 ? String(format: "%.1f ha", a * 100) : a < 10 ? String(format: "%.1f km²", a) : "\(Int(a.rounded()).formatted()) km²"
    }

    /// Douglas-Peucker: the points of a stroke the line needs, at `tol` points
    static func simplify(_ s: [CGPoint], _ tol: CGFloat) -> [CGPoint] {
        guard s.count > 2 else { return s }
        var keep = [Bool](repeating: false, count: s.count)
        keep[0] = true; keep[s.count - 1] = true
        var stack = [(0, s.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            let p = s[a], q = s[b]
            let dx = q.x - p.x, dy = q.y - p.y, len = max(0.0001, hypot(dx, dy))
            var far = a, fd: CGFloat = 0
            for i in a + 1 ..< b {
                let d = abs(dy * s[i].x - dx * s[i].y + q.x * p.y - q.y * p.x) / len
                if d > fd { fd = d; far = i }
            }
            if fd > tol { keep[far] = true; stack.append((a, far)); stack.append((far, b)) }
        }
        return s.indices.filter { keep[$0] }.map { s[$0] }
    }
}

/// THE DRAWING ON THE MAP: what is kept, as a line in ink 2.5 pt, its corners where they were tapped; the finger's stroke
/// now; a shape's first corner a ring the size of the closing distance once it can close. Worked out from latitude and
/// longitude every frame while drawing, so it stays on its places as the map moves. Takes no touches.
struct DrawLayer: View {
    var tool = DrawTool.shared

    var body: some View {
        if tool.on {
            TimelineView(.animation) { _ in
                Canvas { ctx, _ in
                    guard let to = tool.toScreen else { return }
                    let pts = tool.points.compactMap(to)
                    var line = Path()
                    if let f = pts.first {
                        line.move(to: f)
                        for p in pts.dropFirst() { line.addLine(to: p) }
                    }
                    if let l = tool.live.first {
                        if pts.isEmpty { line.move(to: l) } else { line.addLine(to: l) }
                        for p in tool.live.dropFirst() { line.addLine(to: p) }
                    }
                    let style = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    // (white under the ink, so the line reads over dark land and the sea alike)
                    ctx.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
                    ctx.stroke(line, with: .color(Palette.ink), style: style)
                    // the corners kept (each stroke's ends and every tapped corner)
                    for m in tool.marks where m < pts.count {
                        let p = pts[m]
                        let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                        ctx.fill(Path(r), with: .color(.white))
                        ctx.fill(Path(r.insetBy(dx: 1.5, dy: 1.5)), with: .color(Palette.ink))
                    }
                    // where a shape closes, once it has the corners to
                    if tool.kind == .shape, tool.points.count >= 2, let f = pts.first {
                        let d = DrawTool.closeDistance
                        let c = Path(ellipseIn: CGRect(x: f.x - d, y: f.y - d, width: 2 * d, height: 2 * d))
                        ctx.stroke(c, with: .color(Palette.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

/// THE DRAW BAR, in the water where a map's caption sits: its measure as the caption (the line's length, or the shape's
/// area once it has three corners), and under it one bar of words: Undo, Cancel, Done (Done grey until there is
/// enough to make)
struct DrawBar: View {
    let water: Water
    var tool = DrawTool.shared

    var body: some View {
        let L = water.layout
        let top = max(L.headBottom + 12, water.level)
        let w = (L.W - 2 * L.sheetInset - 32 - 8) / 3
        VStack(spacing: 10) {
            Text(caption)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink.opacity(tool.points.count < 2 ? 0.5 : 1))
                .monospacedDigit()
                .contentTransition(.identity)
            HStack(spacing: 0) {
                word("Undo", width: w, dim: tool.marks.isEmpty) { tool.undo() }
                word("Cancel", width: w) { tool.cancel() }
                word("Done", width: w, dim: !tool.canFinish) { tool.done() }
            }
            .padding(4)
            .background(Capsule().fill(Color.white.opacity(0.45)))
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .position(x: L.W / 2, y: top + 56)
    }

    private var caption: String {
        if tool.points.count < 2 { return tool.kind == .shape ? "Draw round the place" : "Draw the line" }
        if tool.kind == .shape, tool.points.count >= 3 { return DrawTool.words(km2: tool.areaKm2) }
        return DrawTool.words(km: tool.lengthKm)
    }

    private func word(_ name: String, width: CGFloat, dim: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink.opacity(dim ? 0.5 : 1))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: width, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}
