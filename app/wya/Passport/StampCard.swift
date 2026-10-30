import SwiftUI

/// THE STAMPING CARD'S STATE (Part 4.2): which place, where the finger was, how far it is open, and what this card did
@MainActor
@Observable
final class CardState {
    static let shared = CardState()
    private(set) var place: Int?
    private(set) var at: CGPoint = .zero
    /// 0 closed (a point under the finger) to 1 open
    var p: CGFloat = 0
    /// the passport's order when the card opened (the stamped countries, oldest first)
    var order: [String] = []
    /// the place was stamped on this card (a tap on Stamped then lifts it again); stamped before it refuses
    var stampedHere = false
    /// THE STAMP IN FLIGHT (A4.4): `travel` 0 at the button to 1 above its slot, then `press` 1.25 to 1
    var flying = false
    var travel: CGFloat = 1
    var press: CGFloat = 1.25
    var landing = false

    /// stamp it: the stamp travels from the button and presses onto the page; the stamp haptic on the real contact
    func land() {
        flying = true
        travel = 0
        press = 1.25
        withAnimation(.spring(response: 0.30, dampingFraction: 1)) { travel = 1 } completion: { [weak self] in
            guard let self, self.flying else { return }
            withAnimation(.spring(response: 0.12, dampingFraction: 1)) { self.press = 1 } completion: { [weak self] in
                guard let self, self.flying else { return }
                Feel.stamp()
                self.flying = false
            }
        }
    }
    /// lift it back (Stamped tapped on the card that made it): up to 1.25, then back along the arc into the button
    func lift(then done: @escaping () -> Void) {
        flying = true
        travel = 1
        press = 1
        Feel.lift()
        withAnimation(.spring(response: 0.12, dampingFraction: 1)) { press = 1.25 } completion: { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 1)) { self.travel = 0 } completion: { [weak self] in
                self?.flying = false
                done()
            }
        }
    }
    @ObservationIgnored var closedAt: CFTimeInterval = 0
    /// A4.8: while Details (or Verify) is up the card keeps the size and place it had (nothing gets smaller): the
    /// water's top when it rose, which the geometry keeps using
    var heldTop: CGFloat?

    var isOpen: Bool { place != nil }

    func open(_ i: Int, at point: CGPoint, map: MapController) {
        // one press, one job: the touch that closed a card never opens another (Appendix A.4)
        guard place == nil, CACurrentMediaTime() - closedAt > 0.4 else { return }
        place = i
        at = point
        stampedHere = false
        landing = false
        map.kept = i
        Task {
            order = await MarkStore.shared.passportOrder()
            Feel.tap()
            withAnimation(.spring(response: 0.42, dampingFraction: 1)) { p = 1 }
        }
    }

    /// back into the point it came from, every change kept (no Save: closing keeps, the undo drop takes it back)
    func close(map: MapController) {
        guard place != nil else { return }
        closedAt = CACurrentMediaTime()
        withAnimation(.spring(response: 0.30, dampingFraction: 1)) { p = 0 } completion: { [weak self] in
            guard let self, self.closedAt > 0, self.p < 0.01 else { return }
            self.place = nil
            self.heldTop = nil
            map.kept = nil
        }
    }
}

/// THE STAMPING CARD (Part 4.2): the place's name, Stamp | Wishlist, your passport open on the page where its stamp is
/// (or would go), Details | Verify?, one straight mirror-symmetrical column in the open map; the map never moves.
/// As built: the glass tints change in one frame (no fronts); haptics only (no sounds).
struct StampCard: View {
    let map: MapController
    let water: Water
    @State private var card = CardState.shared
    @State private var marks = MarkStore.shared
    @State private var details = DetailsState.shared

    var body: some View {
        if let i = card.place, let w = map.world {
            let L = water.layout
            let waterTop = water.form().top
            let g = Geometry(L: L, sheetTop: card.heldTop ?? waterTop)
            // A4.8: the water rising from where it was to the book's bottom edge takes Details | Verify? into their
            // edge points on that edge (r 0 to 1): centre up 34 pt, scale 1 - r; their bottom never under the water
            let bookBottom = g.mid.y + g.bookH / 2 + 28
            let r: CGFloat = card.heldTop.map { h in max(0, min(1, (h - waterTop) / max(1, h - bookBottom))) } ?? 0
            let detailsUp = details.isOpen
            // THE CARD GOES BACK (replacing A4.8's first version): once the bottom pair has
            // gone, the name, Stamp | Wishlist and the book shrink as one about their top centre, Apple's way with the
            // screen behind a sheet, so the book's bottom stays 12 pt above the water every frame; at full it has gone
            let colTop = g.mid.y - (168 + g.bookH) / 2
            let back: CGFloat = card.heldTop == nil ? 1
                : max(0, min(1, (waterTop - 12 - colTop) / max(1, bookBottom - colTop)))
            let id = w.places[i].id
            let key = PlaceKey.country(id)
            let state = marks.state(key)
            let p = card.p
            // the column grows out of the finger on one arc (A4.1): position and scale from one progress, animated
            // along the arc itself (ArcPlace), not on a straight line between the two ends
            let c = CGPoint(x: g.mid.x, y: g.mid.y)
            let ctrl = Self.control(card.at, c)
            let half = (g.bookW - 12) / 2
            VStack(spacing: 12) {
                nameCapsule(w.places[i].n, width: g.bookW)
                HStack(spacing: 12) {
                    stampButton(state, key: key, name: w.places[i].n, w: (g.bookW - 12) / 2)
                    wishButton(state, key: key, name: w.places[i].n, w: (g.bookW - 12) / 2)
                }
                PassportPage(id: id, order: card.order, hidden: card.flying ? id : nil,
                             size: CGSize(width: g.bookW, height: g.bookH))
                HStack(spacing: 12) {
                    detailsButton(state, key: key, name: w.places[i].n, w: half, words: !detailsUp && r < 0.4)
                    notYet("Verify?", w: half, live: false, dim: !state.stamped, words: !detailsUp && r < 0.4)
                }
                .scaleEffect(max(0.001, 1 - r))
                .offset(y: -34 * r)
                .allowsHitTesting(r < 0.01 && !detailsUp)
            }
            .frame(width: g.bookW)
            // Details closed and the water back where it was: the card follows the water again
            .onChange(of: !water.details && abs(waterTop - (card.heldTop ?? waterTop)) < 0.5) { _, back in
                if back { card.heldTop = nil }
            }
            // with Details up, a tap on the card closes Details only, back to the card (4.4.1)
            .overlay {
                if detailsUp {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { details.close(water: water) }
                }
            }
            // A4.4: the stamp comes out of the Stamp button's centre, travels on one arc to above its slot growing to
            // 1.25, then presses down to 1 (no dip below 1); drawn in front of the button and the page
            .overlay(alignment: .topLeading) {
                if card.flying, let ui = StampArt.image(id),
                   let at = PassportPage.placement(of: id, order: card.order, size: CGSize(width: g.bookW, height: g.bookH)) {
                    let top: CGFloat = 44 + 12 + 44 + 12
                    let from = CGPoint(x: half / 2, y: 44 + 12 + 22)
                    let to = CGPoint(x: at.center.x, y: top + at.center.y)
                    Image(uiImage: ui)
                        .resizable()
                        .frame(width: at.size.width, height: at.size.height)
                        .rotationEffect(.degrees(at.turn))
                        .scaleEffect(card.press / 1.25)
                        .modifier(ArcPlace(t: card.travel, from: from, ctrl: Self.control(from, to), to: to, scaleTo: 1.25))
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(max(0.001, back), anchor: .top)
            .modifier(ArcPlace(t: p, from: card.at, ctrl: ctrl, to: c))
            .allowsHitTesting(p > 0.98 && back > 0.1)
        }
    }

    // MARK: the controls

    private func nameCapsule(_ name: String, width: CGFloat) -> some View {
        Text(name)
            .font(.title2.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.center)
            // just the name: no glass box round it
            .frame(minHeight: 44)
            .frame(maxWidth: width + 32)
    }

    private func stampButton(_ s: MarkState, key: PlaceKey, name: String, w: CGFloat) -> some View {
        Button {
            if !s.stamped {
                Feel.tap()
                Task {
                    await MarkStore.shared.stamp(key, name: name)
                    card.stampedHere = true
                    card.order = await MarkStore.shared.passportOrder()
                    card.land()
                }
            } else if card.stampedHere {
                guard !card.flying else { return }
                card.lift {
                    Task {
                        await MarkStore.shared.unstamp(key, name: name)
                        card.stampedHere = false
                        card.order = await MarkStore.shared.passportOrder()
                    }
                }
            } else {
                // stamped before this card: removing a stamp (with its visits) is Verify's last row, never one tap
                Feel.refuse()
            }
        } label: {
            Text(s.stamped ? "Stamped" : "Stamp")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
                .frame(width: w, height: 44)
                .glassEffect(s.stamped ? .clear.tint(Palette.lime) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func wishButton(_ s: MarkState, key: PlaceKey, name: String, w: CGFloat) -> some View {
        let blocked = s.stamped && !card.stampedHere
        return Button {
            if blocked { Feel.refuse(); return }
            Task {
                if s.stamped {
                    await MarkStore.shared.unstamp(key, name: name)
                    card.stampedHere = false
                    card.order = await MarkStore.shared.passportOrder()
                    Feel.lift()
                    await MarkStore.shared.wish(key, name: name)
                    Feel.tap()
                } else if s.wished {
                    await MarkStore.shared.unwish(key, name: name); Feel.lift()
                } else {
                    await MarkStore.shared.wish(key, name: name); Feel.tap()
                }
            }
        } label: {
            Text("Wishlist")
                .font(.body.weight(.semibold))
                .foregroundStyle(s.wished ? Color.white : blocked ? Palette.ink.opacity(0.5) : Palette.ink)
                .frame(width: w, height: 44)
                .glassEffect(s.wished ? .clear.tint(Palette.blue) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    /// a button whose sheet is not built yet keeps its place in the "not yet" look and refuses
    private func notYet(_ word: String, w: CGFloat, live: Bool, dim: Bool = true, words: Bool = true) -> some View {
        Button { Feel.refuse() } label: {
            Text(words ? word : " ")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink.opacity(dim || !live ? 0.5 : 1))
                .contentTransition(.numericText())
                .animation(Motion.quick, value: words)
                .frame(width: w, height: 44)
                .glassEffect(.clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    /// DETAILS (4.4): live once the place is stamped (a wished place's details come with 4.4.5); the card stays as it
    /// is and the water rises over the book's lower part (A4.8)
    private func detailsButton(_ s: MarkState, key: PlaceKey, name: String, w: CGFloat, words: Bool) -> some View {
        Button {
            guard s.stamped, !card.flying else { Feel.refuse(); return }
            card.heldTop = water.form().top
            details.open(key, name: name, water: water)
        } label: {
            Text(words ? "Details" : " ")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink.opacity(s.stamped ? 1 : 0.5))
                .contentTransition(.numericText())
                .animation(Motion.quick, value: words)
                .frame(width: w, height: 44)
                .glassEffect(.clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: the geometry (Part 4.2.2)

    struct Geometry {
        let bookW: CGFloat, bookH: CGFloat, mid: CGPoint
        init(L: Layout, sheetTop: CGFloat) {
            let room = L.room(sheetTop: sheetTop)
            let fixed: CGFloat = 44 + 12 + 44 + 12 + 12 + 44
            var h = min(420, room.upperBound - room.lowerBound - fixed)
            // never wider than the screen less 64, nor reaching the zoom column (12 pt clear of it)
            let maxW = min(L.W - 64, 2 * (L.W - 16 - 44 - 12 - L.W / 2))
            if h * 0.704 > maxW { h = maxW / 0.704 }
            bookH = max(200, h); bookW = bookH * 0.704
            let above: CGFloat = 44 + 12 + 44 + 12, below: CGFloat = 12 + 44
            let lo = room.lowerBound + above + bookH / 2, hi = room.upperBound - below - bookH / 2
            let bookMid = min(max(L.H / 2, lo), max(lo, hi))
            // the column's centre: the book's centre moved by the difference between what is above and below it
            mid = CGPoint(x: L.W / 2, y: bookMid + (below - above) / 2)
        }
    }

    /// the arc's control point: the middle of the way moved 30% of its length to the upper side (A4.1)
    static func control(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x, dy = b.y - a.y, len = max(1, hypot(dx, dy))
        var n = CGPoint(x: -dy / len, y: dx / len)
        if n.y > 0 { n = CGPoint(x: -n.x, y: -n.y) }
        return CGPoint(x: m.x + n.x * 0.3 * len, y: m.y + n.y * 0.3 * len)
    }
    static func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }
}

/// ONE OBJECT ON ONE ARC: its centre on the quadratic curve from `from` through `ctrl` to `to`, and its scale from
/// `scaleFrom` to `scaleTo`, both from one progress t that SwiftUI animates (so the path is the arc itself, never the
/// straight line between its ends)
struct ArcPlace: ViewModifier, Animatable {
    var t: CGFloat
    let from: CGPoint
    let ctrl: CGPoint
    let to: CGPoint
    var scaleFrom: CGFloat = 0
    var scaleTo: CGFloat = 1
    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }
    func body(content: Content) -> some View {
        let k = max(0, min(1, t))
        content
            .scaleEffect(max(0.001, scaleFrom + (scaleTo - scaleFrom) * t))
            .position(StampCard.quad(from, ctrl, to, k))
    }
}

/// ONE PAGE OF YOUR PASSPORT (4.2.2): clear glass, the spine side square, 2 x 3 slots filled top left, middle right,
/// bottom left, top right, middle left, bottom right; each stamp 80% of its slot, thrown off its centre and turned up to
/// 9 degrees by a hash of the place, never touching an edge; the page number at the bottom centre. A place with no art
/// yet shows nothing in its slot (no ghost) until the generator draws it (Step 6).
struct PassportPage: View {
    let id: String
    let order: [String]
    /// a stamp not drawn on the page (the one in flight, drawn by the card above the page)
    let hidden: String?
    let size: CGSize

    static let fill: [(col: Int, row: Int)] = [(0, 0), (1, 1), (0, 2), (1, 0), (0, 1), (1, 2)]

    /// the page this place's stamp is on (or would go on)
    static func page(of id: String, order: [String]) -> Int { (order.firstIndex(of: id) ?? order.count) / 6 }

    /// WHERE A STAMP SITS on its page (page-local): its centre, its size and its turn; nil when it has no art
    @MainActor
    static func placement(of pid: String, order: [String], size: CGSize) -> (center: CGPoint, size: CGSize, turn: Double)? {
        guard let ui = StampArt.image(pid), let index = order.firstIndex(of: pid) else { return nil }
        let n = index % 6
        let slot = CGSize(width: (size.width - 32) / 2, height: (size.height - 48) / 3)
        let f = fill[n]
        let h = hash(pid)
        let fit = min(slot.width * 0.8 / ui.size.width, slot.height * 0.8 / ui.size.height)
        let sw = ui.size.width * fit, sh = ui.size.height * fit
        let room = CGSize(width: (slot.width - sw) / 2 - 2, height: (slot.height - sh) / 2 - 2)
        let dx = (CGFloat(h & 0xff) / 255 - 0.5) * 2 * max(0, room.width) * 0.6
        let dy = (CGFloat((h >> 8) & 0xff) / 255 - 0.5) * 2 * max(0, room.height) * 0.6
        let turn = (Double((h >> 16) & 0xff) / 255 - 0.5) * 18
        return (CGPoint(x: 16 + slot.width * (CGFloat(f.col) + 0.5) + dx, y: 16 + slot.height * (CGFloat(f.row) + 0.5) + dy),
                CGSize(width: sw, height: sh), turn)
    }

    var body: some View {
        // this place's page: where its stamp is, or the first free slot's
        let page = Self.page(of: id, order: order)
        let onPage = Array(order.dropFirst(page * 6).prefix(6))
        let corner = size.width * 0.036
        ZStack(alignment: .topLeading) {
            ForEach(onPage, id: \.self) { pid in
                if pid != hidden, let ui = StampArt.image(pid), let at = Self.placement(of: pid, order: order, size: size) {
                    Image(uiImage: ui)
                        .resizable()
                        .frame(width: at.size.width, height: at.size.height)
                        .rotationEffect(.degrees(at.turn))
                        .position(at.center)
                }
            }
            Text("\(page + 1)")
                .font(.caption2)
                .foregroundStyle(Palette.ink.opacity(0.5))
                .position(x: size.width / 2, y: size.height - 16)
        }
        .frame(width: size.width, height: size.height)
        .glassEffect(.clear, in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                                         bottomTrailingRadius: corner, topTrailingRadius: corner,
                                                         style: .continuous))
    }

    /// a stable hash of the place (the scatter never changes between openings; FNV-1a)
    static func hash(_ s: String) -> Int {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return Int(h)
    }
}
