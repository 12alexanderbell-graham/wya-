import SwiftUI

/// THE PASSPORT BOOK'S STATE (Part 4.3): open from the plus's passport tool, the flight (A4.12), the cover (A4.2) and
/// the page you are on (A4.13), remembered on this phone
@MainActor
@Observable
final class BookState {
    static let shared = BookState()
    /// the book is out (or on its way out / back)
    private(set) var isOpen = false
    /// A4.12: 0 in the tool, 1 in its place
    var p: CGFloat = 0
    /// A4.2: the cover's turn, 0 flat over the page, 90 edge-on at the spine
    var cover: Double = 0
    /// the page showing (0 is page 01)
    var page = UserDefaults.standard.integer(forKey: "passportPage")
    /// A4.13: the leaf being turned, in degrees: > 0 the current page turning away (forward), < 0 the previous page
    /// coming back over (backward, -90 edge-on to 0 flat)
    var turn: Double = 0
    var order: [String] = []
    @ObservationIgnored private var job = 0

    var pages: Int { max(1, (order.count + 5) / 6) }

    /// THE TOOL TAPPED: the closed book comes out of the tool and opens on the page you last left
    func open() {
        guard !isOpen else { return }
        isOpen = true
        job += 1
        let j = job
        Task {
            order = await MarkStore.shared.passportOrder()
            page = min(page, pages - 1)
            Feel.tap()
            withAnimation(.spring(response: 0.42 * CardState.slow, dampingFraction: 1)) { p = 1 }
            // the cover starts to swing at p = 0.55 of the flight (about 0.15 s in)
            try? await Task.sleep(for: .milliseconds(Int(150 * CardState.slow)))
            guard job == j, isOpen else { return }
            withAnimation(.spring(response: 0.36 * CardState.slow, dampingFraction: 1)) { cover = 90 }
        }
    }

    /// back into the tool: the cover closes, and the book flies back once the cover is past 45 degrees
    /// when it last closed: the touch that closed it never opens a card (one press, one job)
    @ObservationIgnored private(set) var closedAt: CFTimeInterval = 0
    func close() {
        guard isOpen else { return }
        isOpen = false
        closedAt = CACurrentMediaTime()
        job += 1
        let j = job
        UserDefaults.standard.set(page, forKey: "passportPage")
        withAnimation(.spring(response: 0.30, dampingFraction: 1)) { cover = 0; turn = 0 }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard job == j else { return }
            withAnimation(.spring(response: 0.30, dampingFraction: 1)) { p = 0 } completion: {
                if self.job == j { Feel.land(speed: 0) }
            }
        }
    }
    func toggle() { isOpen ? close() : open() }
}

/// THE PASSPORT BOOK (Part 4.3): the book alone (no name, no buttons), the card's book's size at the same water stop
/// (never meeting the zoom column), as near the screen's middle as the room allows. It comes out of the passport tool
/// on one arc leaving straight down (A4.12), its cover swings open about the spine with real perspective (A4.2), and
/// its pages turn under the finger about the spine (A4.13). Haptics only.
/// The cover until Step 6 brings the real ones from the server: the old app's own drawn cover (its colour, the word,
/// the chip). Not here yet: a stamp's tap (its place page), its hold menu, the flick through several pages.
struct PassportBook: View {
    let water: Water
    @State private var b = BookState.shared
    @State private var drag: CGFloat?

    var body: some View {
        if b.isOpen || b.p > 0.001 {
            let L = water.layout
            let size = Self.size(L, sheetTop: water.form().top)
            let room = L.room(sheetTop: water.form().top)
            let mid = CGPoint(x: L.W / 2, y: min(max(L.H / 2, room.lowerBound + size.height / 2),
                                                  max(room.lowerBound + size.height / 2, room.upperBound - size.height / 2)))
            let spacing = (L.rightX - L.W / 2) / 4
            let tool = CGPoint(x: L.rightX - 3 * spacing, y: L.headY)
            let ctrl = CGPoint(x: tool.x, y: max(tool.y + 24, mid.y - 148))
            book(size)
                .modifier(BookFlight(t: b.p, from: tool, ctrl: ctrl, to: mid))
                .allowsHitTesting(b.isOpen && b.p > 0.98)
        }
    }

    static func size(_ L: Layout, sheetTop: CGFloat) -> CGSize {
        let room = L.room(sheetTop: sheetTop)
        var h = min(420, room.upperBound - room.lowerBound)
        let maxW = min(L.W - 64, 2 * (L.W - 16 - 44 - 12 - L.W / 2))
        if h * 0.704 > maxW { h = maxW / 0.704 }
        return CGSize(width: h * 0.704, height: h)
    }

    private func book(_ size: CGSize) -> some View {
        let w = size.width
        let current = b.page
        return ZStack(alignment: .leading) {
            // what lies under the leaf being turned: forward, the next page; backward, the current page
            PassportPage(id: "", order: b.order, hidden: nil, size: size,
                         pageIndex: b.turn > 0 ? min(current + 1, b.pages - 1) : current)
            if b.turn > 0 {
                // the current page turning away about the spine
                PassportPage(id: "", order: b.order, hidden: nil, size: size, pageIndex: current)
                    .rotation3DEffect(.degrees(-b.turn), axis: (0, 1, 0), anchor: .leading, perspective: 0.25)
            } else if b.turn < 0, current > 0 {
                // the previous page coming back over from edge-on
                PassportPage(id: "", order: b.order, hidden: nil, size: size, pageIndex: current - 1)
                    .rotation3DEffect(.degrees(-(90 + b.turn)), axis: (0, 1, 0), anchor: .leading, perspective: 0.25)
            }
            // turned leaves stay as a line along the spine, never gone into nothing
            if b.cover > 1 {
                Rectangle().fill(Palette.ink.opacity(0.25)).frame(width: min(3, 0.5 * CGFloat(current + 1)))
            }
            // the cover over it all until it has swung open; at 90 degrees a 1.5 pt band of its colour at the spine
            // (the swing reads its angle every frame, so the cover is solid until edge-on: an opacity tied to the
            // end value faded it over the whole swing)
            Cover(size: size).modifier(CoverSwing(angle: b.cover))
        }
        .frame(width: w, height: size.height)
        .contentShape(Rectangle())
        .gesture(pageDrag(w))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your passport, page \(current + 1) of \(b.pages)")
        .accessibilityAction(named: "Next page") { turn(forward: true, from: 0, speed: 0) }
        .accessibilityAction(named: "Previous page") { turn(forward: false, from: 0, speed: 0) }
    }

    /// A4.13: the leaf follows the finger: angle = travel / (half the book's width) x 90; released past 40 pt or faster
    /// than 300 pt/s it completes, else it falls back; past the last page a third of the finger's speed up to 30
    /// degrees and back; back past page 01 the cover closes and the book goes back into the tool
    private func pageDrag(_ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { g in
                guard b.cover >= 89 else { return }
                let dx = g.translation.width
                let a = Double(min(90, abs(dx) / (w / 2) * 90))
                if dx < 0 {
                    // forward; past the last page: a rubber band
                    b.turn = b.page >= b.pages - 1 ? min(30, a / 3) : a
                } else if b.page > 0 {
                    b.turn = -(90 - a)
                } else {
                    b.turn = 0
                }
            }
            .onEnded { g in
                guard b.cover >= 89 else { return }
                let dx = g.translation.width, v = g.velocity.width
                let commit = abs(dx) > 40 || abs(v) > 300
                if dx < 0 {
                    if b.page >= b.pages - 1 {
                        Feel.notch()
                        withAnimation(.spring(response: 0.32, dampingFraction: 1)) { b.turn = 0 }
                    } else if commit { turn(forward: true, from: b.turn, speed: v) }
                    else { withAnimation(.spring(response: 0.32, dampingFraction: 1)) { b.turn = 0 } }
                } else if b.page == 0 {
                    if commit { b.close() }
                } else if commit { turn(forward: false, from: b.turn, speed: v) }
                else { withAnimation(.spring(response: 0.32, dampingFraction: 1)) { b.turn = -90 } completion: { b.turn = 0 } }
            }
    }

    /// a turn completed: the tick at the frame it commits; forward the leaf goes edge-on and the next page is the page;
    /// backward the previous page comes down flat and is the page
    private func turn(forward: Bool, from: Double, speed: CGFloat) {
        Feel.tick()
        if forward {
            guard b.page < b.pages - 1 else { return }
            if from <= 0 { b.turn = 0.1 }
            withAnimation(.spring(response: 0.32, dampingFraction: 1)) { b.turn = 90 } completion: {
                b.page += 1
                b.turn = 0
            }
        } else {
            guard b.page > 0 else { return }
            if from >= 0 { b.turn = -89.9 }
            withAnimation(.spring(response: 0.32, dampingFraction: 1)) { b.turn = -0.01 } completion: {
                b.page -= 1
                b.turn = 0
            }
        }
    }
}

/// A4.2: the cover turning about the spine with real perspective, solid all the way; at 90 degrees what is left is
/// a 1.5 pt band of its colour along the spine (never gone into nothing)
struct CoverSwing: ViewModifier, Animatable {
    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            if angle < 89.5 {
                content.rotation3DEffect(.degrees(-angle), axis: (0, 1, 0), anchor: .leading, perspective: 0.25)
            }
            if angle > 0.5 { Rectangle().fill(Cover.colour).frame(width: 1.5) }
        }
    }
}

/// one object on one arc (A4.12): its centre on the quadratic curve, its size p squared (so it is still under 12 pt
/// wide while it is inside the tools capsule and never covers a neighbouring tool)
struct BookFlight: ViewModifier, Animatable {
    var t: CGFloat
    let from: CGPoint
    let ctrl: CGPoint
    let to: CGPoint
    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }
    func body(content: Content) -> some View {
        let k = max(0, min(1, t))
        content
            .scaleEffect(max(0.001, k * k))
            .position(StampCard.quad(from, ctrl, to, k))
    }
}

/// THE COVER until the real ones come (Step 6): the old app's own drawn cover (passports.css .passport.blank): its
/// colour, the word Passport, the chip; the spine side square, the outer corners rounded
struct Cover: View {
    let size: CGSize
    static let colour = Color(hex: 0x1F3A5F)
    var body: some View {
        let ink = Palette.cream.opacity(0.88)
        let corner = size.width * 0.036
        ZStack {
            Self.colour
            VStack(spacing: 4) {
                Spacer()
                Text("Passport")
                    .font(.subheadline)
                    .tracking(15 * 0.14)
                    .textCase(.uppercase)
                PassportChipShape().stroke(ink, lineWidth: 1.3).frame(width: 52, height: 34).padding(.top, 16)
            }
            .foregroundStyle(ink)
            .padding(.bottom, 40)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: corner, topTrailingRadius: corner, style: .continuous))
    }
}

/// the e-passport chip mark on a cover: a rounded rectangle with a smaller one inside and a bar through its middle
struct PassportChipShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: r.height * 0.18)
        let inner = r.insetBy(dx: r.width * 0.3, dy: r.height * 0.28)
        p.addRoundedRect(in: inner, cornerSize: CGSize(width: 3, height: 3))
        p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: inner.minX, y: r.midY))
        p.move(to: CGPoint(x: inner.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}
