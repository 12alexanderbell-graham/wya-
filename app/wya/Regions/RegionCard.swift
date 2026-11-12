import SwiftUI

/// THE REGION CARD'S STATE (6.7): which region, its name and its parents' line, how far it is out of the water
@MainActor
@Observable
final class RegionCardState {
    static let shared = RegionCardState()
    private(set) var key: PlaceKey?
    private(set) var name = ""
    private(set) var parents = ""
    /// the country it lies in (the map's place: Verify's shape test and the flag)
    private(set) var place: Int?
    /// an event stop's day ("2026-07-05"), when the card is a collection's stop (D7)
    private(set) var day: String?
    /// 0 in the water to 1 out
    var p: CGFloat = 0
    /// stamped on this card (a tap on Stamped lifts it again); stamped before, Stamped refuses (Part 4.2.3)
    var stampedHere = false
    @ObservationIgnored var closedAt: CFTimeInterval = 0
    @ObservationIgnored private var closing = false
    /// the water the card stands on (set once by the screen)
    @ObservationIgnored weak var water: Water?
    var isOpen: Bool { key != nil }

    /// out of the water (A6.11): the map never moves; the region stays darkened while the card is up
    func open(_ key: PlaceKey, name: String, parents: String, place: Int?, map: MapController, day: String? = nil) {
        guard self.key == nil, CACurrentMediaTime() - closedAt > 0.4 else { return }
        self.key = key; self.name = name; self.parents = parents; self.place = place; self.day = day
        stampedHere = false
        map.kept = place
        p = 0
        Feel.tap()
        // THE WATER HIGHER THAN 25% (Places' menu at 50%; 11 Nov: a pressed sea): the
        // card stands on the 25% water, so the water goes down first and the card comes out of it once it is there
        // (0.3 s later; coming at once, its buttons showed through the glass on the way down)
        var wait = 0.0
        if map.placesMode, let w = water, w.stop == .half || w.stop == .full { w.go(.quarter); wait = 0.3 }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.key == key else { return }
            withAnimation(Motion.reduce ? Motion.tight : .spring(response: 0.42, dampingFraction: 1)) { self.p = 1 }
        }
    }
    /// back into the water, every change kept
    /// `instant`: gone in this frame, no fold (a mode change moves nothing)
    func close(map: MapController, instant: Bool = false) {
        guard key != nil else { return }
        // (a set's place stays darkened while its card is up, as a region does; it is let go as the card goes)
        // (and a thing found by search on the towns' map)
        if map.markCollection != nil || key?.kind == .thing, map.thingPressed != nil { map.thingPressed = nil; map.needsFrame = true }
        if instant {
            closing = false
            closedAt = CACurrentMediaTime()
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { p = 0 }
            key = nil; map.kept = nil
            return
        }
        // one close per card: a second touch while it folds no longer starts the 0.4 s over (that ate the next tap)
        guard !closing else { return }
        closing = true
        closedAt = CACurrentMediaTime()
        withAnimation(Motion.reduce ? Motion.tight : .spring(response: 0.30, dampingFraction: 1)) { p = 0 } completion: { [weak self] in
            guard let self else { return }
            self.closing = false
            guard self.closedAt > 0, self.p < 0.01 else { return }
            self.key = nil
            map.kept = nil
        }
    }
}

/// THE REGION CARD (6.7): Part 4.2's card without the book, standing on the 25% water: from the water's top up 12 pt,
/// Details | Verify?, 12 pt, Stamp | Wishlist, 12 pt, the name with its parents' line under it. Each piece comes up out
/// of the glass under it and goes back down into it (the fallback of A6.11: each grows from its own bottom edge, the
/// lowest first), its words rolling in once it stands; the column is Part 4.2's book width.
struct RegionCard: View {
    let map: MapController
    let water: Water
    @State private var card = RegionCardState.shared
    @State private var marks = MarkStore.shared
    @State private var details = DetailsState.shared
    @State private var tapAt: CFTimeInterval = 0

    var body: some View {
        if let key = card.key {
            let L = water.layout
            let w = StampCard.Geometry(L: L, sheetTop: L.top(.quarter)).bookW
            let half = (w - 12) / 2
            let s = marks.state(key)
            // (over the water at history height when the journey is up, never on it)
            let base = (water.historyUp ? water.restTop(.quarter) : L.top(.quarter)) - 12
            let p = card.p
            // each piece's own share of the opening, lowest first (0.4 of the way apart)
            let a = Self.part(p, 0), b = Self.part(p, 1), c = Self.part(p, 2)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 12) {
                    button(details.isOpen ? " " : "Details", w: half, live: s.stamped || s.wished, words: a > 0.95) {
                        guard s.stamped || s.wished else { Feel.refuse(); return }
                        Feel.tap()
                        details.open(key, name: card.name, water: water)
                    }
                    // VERIFY (4.5): a region by its shape; live once it is stamped
                    button("Verify?", w: half, live: s.stamped, words: a > 0.95) {
                        guard s.stamped, let place = card.place else { Feel.refuse(); return }
                        Feel.tap()
                        VerifyState.shared.open(key, name: card.name, place: place, water: water)
                    }
                }
                .scaleEffect(max(0.001, a), anchor: .bottom)
                .position(x: L.W / 2, y: base - 22)
                HStack(spacing: 12) {
                    stampButton(s, key: key, w: half, words: b > 0.95)
                    wishButton(s, key: key, w: half, words: b > 0.95)
                }
                .scaleEffect(max(0.001, b), anchor: .bottom)
                .position(x: L.W / 2, y: base - 44 - 12 - 22)
                // (two lines each at most, held by their bottom over Stamp | Wishlist: a big type size grows them up,
                // never down over the buttons)
                VStack(spacing: 2) {
                    Text(card.name).font(.headline).foregroundStyle(Palette.ink).lineLimit(2).minimumScaleFactor(0.8)
                    if !card.parents.isEmpty {
                        Text(card.parents).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(2)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(width: w + 32)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: w + 32, height: 160, alignment: .bottom)
                .scaleEffect(max(0.001, c), anchor: .bottom)
                .position(x: L.W / 2, y: base - 2 * (44 + 12) - 8 - 80)
            }
            .frame(width: L.W, height: L.H, alignment: .topLeading)
            // the card's words up to the size its 44 pt buttons still hold on one line
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .allowsHitTesting(p > 0.98)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(card.name), \(card.parents)")
        }
    }

    /// piece n's progress inside the card's (each starts 0.3 of the way after the one under it)
    static func part(_ p: CGFloat, _ n: Int) -> CGFloat {
        let start = 0.3 * CGFloat(n)
        return max(0, min(1, (p - start) / (1 - 0.6)))
    }

    private func button(_ word: String, w: CGFloat, live: Bool, words: Bool, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(words ? word : " ")
                .font(.body.weight(.semibold))
                // (one line in the 44 pt capsule: a little smaller on a narrow card or a big type size, never broken mid-word)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(Palette.ink.opacity(live ? 1 : 0.5))
                .contentTransition(.identity)
                .animation(Motion.quick, value: words)
                .frame(width: w, height: 44)
                .glassEffect(.clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func stampButton(_ s: MarkState, key: PlaceKey, w: CGFloat, words: Bool) -> some View {
        Button {
            // a quick second tap is the same press (it used to stamp and take the stamp off again)
            guard CACurrentMediaTime() - tapAt > 0.35 else { return }
            tapAt = CACurrentMediaTime()
            if !s.stamped {
                Feel.stamp()
                Task {
                    // with every parent above it (A6.12)
                    if key.kind == .town {
                        let cc = String(key.id.prefix { $0 != "/" })
                        let at = map.townScenes[cc].flatMap { s in s.index[key.id].map { s.at[$0] } }
                        await TownStamps.stamp(key, name: card.name, cc: cc, source: .hand, place: card.place, at: at)
                    } else if let sc = map.regionScene, let u = sc.unitIDs.firstIndex(of: key.id) {
                        await RegionStamps.stamp(u, in: sc, source: .hand)
                    } else if key.kind == .thing, let place = card.place, let w = map.world {
                        // a thing stamps its country too; a collection's stop that has been gets its day as a visit (D7)
                        let cc = w.places[place].id.lowercased()
                        let at = ThingStore.shared.thing(key.id)?.1.at
                        await TownStamps.stamp(key, name: card.name, cc: cc, source: .hand, place: place, at: at,
                                               day: CollectionStore.pastDay(card.day))
                    } else {
                        await MarkStore.shared.stamp(key, name: card.name)
                    }
                    card.stampedHere = true
                }
            } else {
                // one meaning everywhere, as the country card's (7 Nov): a tap on Stamped always takes the stamp off, the
                // undo drop puts it back
                Feel.lift()
                Task {
                    if key.kind == .town { await TownStamps.unstamp(key, name: card.name, cc: String(key.id.prefix { $0 != "/" })) }
                    else if let sc = map.regionScene, let u = sc.unitIDs.firstIndex(of: key.id) { await RegionStamps.unstamp(u, in: sc) }
                    else { await MarkStore.shared.unstamp(key, name: card.name) }
                    card.stampedHere = false
                }
            }
        } label: {
            Text(words ? (s.stamped ? "Stamped" : "Stamp") : " ")
                .font(.body.weight(.semibold))
                // (one line in the 44 pt capsule: a little smaller on a narrow card or a big type size, never broken mid-word)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(Palette.ink)
                .contentTransition(.identity)
                .animation(Motion.quick, value: words)
                .frame(width: w, height: 44)
                .glassEffect(s.stamped ? .clear.tint(Palette.lime) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func wishButton(_ s: MarkState, key: PlaceKey, w: CGFloat, words: Bool) -> some View {
        // a place you have been is never on your wishlist (Q4.4), the same on every card (7 Nov)
        let blocked = s.stamped
        return Button {
            if blocked { Feel.refuse(); return }
            guard CACurrentMediaTime() - tapAt > 0.35 else { return }
            tapAt = CACurrentMediaTime()
            Task {
                if s.wished {
                    await MarkStore.shared.unwish(key, name: card.name); Feel.lift()
                } else {
                    // a stop still to come is wished with its day (D7)
                    let when = CollectionStore.upcoming(card.day) ? card.day : nil
                    await MarkStore.shared.wish(key, name: card.name, when: when); Feel.tap()
                }
            }
        } label: {
            Text(words ? "Wishlist" : " ")
                .font(.body.weight(.semibold))
                // (one line in the 44 pt capsule: a little smaller on a narrow card or a big type size, never broken mid-word)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(s.wished ? Color.white : blocked ? Palette.ink.opacity(0.5) : Palette.ink)
                .contentTransition(.identity)
                .animation(Motion.quick, value: words)
                .frame(width: w, height: 44)
                .glassEffect(s.wished ? .clear.tint(Palette.blue) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
