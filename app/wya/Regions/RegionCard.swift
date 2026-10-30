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
    /// 0 in the water to 1 out
    var p: CGFloat = 0
    /// stamped on this card (a tap on Stamped lifts it again); stamped before, Stamped refuses (Part 4.2.3)
    var stampedHere = false
    @ObservationIgnored var closedAt: CFTimeInterval = 0
    var isOpen: Bool { key != nil }

    /// out of the water (A6.11): the map never moves; the region stays darkened while the card is up
    func open(_ key: PlaceKey, name: String, parents: String, place: Int, map: MapController) {
        guard self.key == nil, CACurrentMediaTime() - closedAt > 0.4 else { return }
        self.key = key; self.name = name; self.parents = parents; self.place = place
        stampedHere = false
        map.kept = place
        p = 0
        Feel.tap()
        DispatchQueue.main.async { [weak self] in
            withAnimation(Motion.reduce ? Motion.tight : .spring(response: 0.42, dampingFraction: 1)) { self?.p = 1 }
        }
    }
    /// back into the water, every change kept
    func close(map: MapController) {
        guard key != nil else { return }
        closedAt = CACurrentMediaTime()
        withAnimation(Motion.reduce ? Motion.tight : .spring(response: 0.30, dampingFraction: 1)) { p = 0 } completion: { [weak self] in
            guard let self, self.closedAt > 0, self.p < 0.01 else { return }
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

    var body: some View {
        if let key = card.key {
            let L = water.layout
            let w = StampCard.Geometry(L: L, sheetTop: L.top(.quarter)).bookW
            let half = (w - 12) / 2
            let s = marks.state(key)
            let base = L.top(.quarter) - 12
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
                VStack(spacing: 2) {
                    Text(card.name).font(.headline).foregroundStyle(Palette.ink)
                    if !card.parents.isEmpty {
                        Text(card.parents).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5))
                    }
                }
                .multilineTextAlignment(.center)
                .frame(width: w + 32)
                .fixedSize(horizontal: false, vertical: true)
                .scaleEffect(max(0.001, c), anchor: .bottom)
                .position(x: L.W / 2, y: base - 2 * (44 + 12) - 28)
            }
            .frame(width: L.W, height: L.H, alignment: .topLeading)
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
                .foregroundStyle(Palette.ink.opacity(live ? 1 : 0.5))
                .contentTransition(.numericText())
                .animation(Motion.quick, value: words)
                .frame(width: w, height: 44)
                .glassEffect(.clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func stampButton(_ s: MarkState, key: PlaceKey, w: CGFloat, words: Bool) -> some View {
        Button {
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
                    } else {
                        await MarkStore.shared.stamp(key, name: card.name)
                    }
                    card.stampedHere = true
                }
            } else if card.stampedHere {
                Feel.lift()
                Task {
                    if key.kind == .town { await TownStamps.unstamp(key, name: card.name, cc: String(key.id.prefix { $0 != "/" })) }
                    else if let sc = map.regionScene, let u = sc.unitIDs.firstIndex(of: key.id) { await RegionStamps.unstamp(u, in: sc) }
                    else { await MarkStore.shared.unstamp(key, name: card.name) }
                    card.stampedHere = false
                }
            } else {
                Feel.refuse()
            }
        } label: {
            Text(words ? (s.stamped ? "Stamped" : "Stamp") : " ")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
                .animation(Motion.quick, value: words)
                .frame(width: w, height: 44)
                .glassEffect(s.stamped ? .clear.tint(Palette.lime) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func wishButton(_ s: MarkState, key: PlaceKey, w: CGFloat, words: Bool) -> some View {
        let blocked = s.stamped && !card.stampedHere
        return Button {
            if blocked { Feel.refuse(); return }
            Task {
                if s.stamped {
                    // with the parents stamped only through it (the unstamp rule, 6.5)
                    if key.kind == .town { await TownStamps.unstamp(key, name: card.name, cc: String(key.id.prefix { $0 != "/" })) }
                    else if let sc = map.regionScene, let u = sc.unitIDs.firstIndex(of: key.id) { await RegionStamps.unstamp(u, in: sc) }
                    else { await MarkStore.shared.unstamp(key, name: card.name) }
                    card.stampedHere = false
                    Feel.lift()
                    await MarkStore.shared.wish(key, name: card.name)
                    Feel.tap()
                } else if s.wished {
                    await MarkStore.shared.unwish(key, name: card.name); Feel.lift()
                } else {
                    await MarkStore.shared.wish(key, name: card.name); Feel.tap()
                }
            }
        } label: {
            Text(words ? "Wishlist" : " ")
                .font(.body.weight(.semibold))
                .foregroundStyle(s.wished ? Color.white : blocked ? Palette.ink.opacity(0.5) : Palette.ink)
                .contentTransition(.numericText())
                .animation(Motion.quick, value: words)
                .frame(width: w, height: 44)
                .glassEffect(s.wished ? .clear.tint(Palette.blue) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
