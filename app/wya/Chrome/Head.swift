import SwiftUI

/// The head's state: the mode, search, the plus's tools, and how far the top pull has come.
@MainActor
@Observable
final class HeadState {
    enum Mode: Int, CaseIterable {
        case countries, regions, places, pins
        var name: String { ["Countries", "Regions", "Places", "Pins"][rawValue] }
        var key: String { ["map-countries", "map-regions", "map-places", "map-pins"][rawValue] }
    }
    var mode: Mode = .countries
    var searching = false
    var query = ""
    /// search closed by a touch on the map (1.10): the typed text comes back if search opens again within 10 s, and that
    /// touch opens nothing else
    @ObservationIgnored var mapClosedSearchAt: CFTimeInterval = 0
    /// a touch on the map with search open closes search only, keeping what was typed for 10 s
    func closeSearchFromMap() {
        guard searching else { return }
        Feel.tap()
        mapClosedSearchAt = CACurrentMediaTime()
        searching = false
    }
    var toolsOpen = false
    var quickStamp = false
    var history = false
    /// the top pull, in points of finger travel (0 at rest): it brings the AI out of the dot (TopPull)
    var pull: CGFloat = 0
    /// where the top pull rests: 0 the head, 1 the AI out
    var pullStop: Int = 0
    /// the dot is held still (it is becoming the gear), and settings are open (the gear rolls in the head's middle)
    var dotHeld = false
    var settingsOpen = false
    /// how far the dot is the gear (0 the dot, 1 the gear); animated, or set by the finger when a pull starts from it
    var gear: CGFloat = 0
    /// the gear's own turn while it rests (degrees), and when settings last opened (it rolls on from there)
    var gearRoll: Double = 0
    var settingsSince = Date()
    /// this pull started from the gear: its first part turns the gear back into the dot, the rest brings the AI out
    var pullFromGear = false

    /// the gear's turn at a moment: rolling one turn in 6 s while settings are open (BUILD-BOOK 5), still otherwise
    func roll(at d: Date) -> Double {
        settingsOpen ? gearRoll + d.timeIntervalSince(settingsSince) * 60 : gearRoll
    }
    /// SETTINGS CLOSE, from wherever: the gear keeps the turn it had (an eighth of a turn looks the same, so it is kept
    /// under 45 degrees) and goes back into the dot, unless a pull is taking it
    func closeSettings(animated: Bool = true) {
        guard settingsOpen else { return }
        gearRoll = roll(at: Date()).truncatingRemainder(dividingBy: 45)
        settingsOpen = false
        dotHeld = false
        if animated { withAnimation(Motion.chrome) { gear = 0 } }
    }
    func openSettings() {
        guard !settingsOpen else { return }
        Hints.shared.usedHold()
        settingsSince = Date()
        settingsOpen = true
        // the hold that opened them is done: a later hold starts fresh, whatever happened to the finger
        dotHeld = false
    }
    /// THE MAP OR THE SHEET TOUCHED: settings and the AI go back into the dot, and the touch goes on doing what it
    /// does. Before, a screen-wide catcher took every touch while they were out, so a drag on the map or the sheet did
    /// nothing at all.
    func putAway() {
        closeSettings()
        if pullStop > 0 || pull > 0.5 { settlePull(to: 0) }
    }
    /// A TOUCH ON THE WATER (Part 3.9, with the Map settings sheet built): the AI goes back into the dot, settings stay
    /// (the water is the settings: it scrolls, its rows are tapped, it is pulled)
    func putAwayAI() {
        if pullStop > 0 || pull > 0.5 { settlePull(to: 0) }
    }
    // MARK: the top pull (TopPullView's finger, and the tests, run these)
    @ObservationIgnored private var pullStart: CGFloat = 0
    @ObservationIgnored private var pullGearStart: CGFloat = 0
    func pullBegan() {
        Hints.shared.touched()
        pullStart = pull
        // from the gear (settings open): its first part turns the gear back into the dot, following the finger, then
        // the AI comes out of the dot
        if settingsOpen {
            pullGearStart = gear
            pullFromGear = true
            closeSettings(animated: false)
        } else if pull < 0.5 && gear < 0.001 {
            pullFromGear = false
        }
    }
    func pullMoved(_ dy: CGFloat) {
        var p = pullStart + dy
        if p < 0 { p = -Flow.rubber(-p, 30) }
        let cap = HeadState.aiStop
        if p > cap { p = cap + Flow.rubber(p - cap, 60) }
        let was = ai >= 1
        pull = p
        if pullFromGear { gear = pullGearStart * (1 - Flow.clamp01(ai / 0.35)) }
        if (ai >= 1) != was { Feel.notch(); Sound.click() }
    }
    func pullEnded(velocity: CGFloat) {
        let projected = pull + Flow.project(velocity) * 0.5
        let out = projected > HeadState.aiStop / 2
        if out { Hints.shared.usedPull() } else if pullStop == 0 { Hints.shared.shortPull() }
        settlePull(to: out ? 1 : 0, speed: abs(velocity))
    }
    /// `speed`: the release's, for the landing (3.7: the `land` haptic by it, the thud above 15%); 900 for a settle
    /// that no finger let go of
    func settlePull(to s: Int, speed: CGFloat = 900) {
        pullStop = s
        withAnimation(Motion.settle) {
            pull = s == 1 ? HeadState.aiStop : 0
            // a pull from the gear never leaves half a gear behind: back to the dot, or on into the AI
            gear = 0
        } completion: {
            if self.pullStop == 0 && self.pull < 0.5 { self.pullFromGear = false }
        }
        Feel.land(speed: speed)
    }

    /// the AI's part of the pull as the dot morph draws it (after the gear has gone, when the pull started from it)
    var aiShown: CGFloat { pullFromGear ? Flow.clamp01((ai - 0.35) / 0.65) : ai }
    /// test only: holds the mode wheel mid-turn at this position, as if a finger were on it
    var testDial: CGFloat?
    /// a sideways drag on the tools capsule turns the wheel as if it were on the dot: the drag's translation while it
    /// lasts, and its predicted extra travel when it ends
    var capsuleDrag: CGFloat?
    var capsuleDragFling: CGFloat = 0

    /// how far down the AI is fully out
    static let aiStop: CGFloat = 72
    /// 0 the dot, 1 the AI out
    var ai: CGFloat { Flow.clamp01(pull / HeadState.aiStop) }
}

/// Two glyphs in one circle: the first rolls down out of it as the second comes down in from the top, cut only by the
/// circle's own round edge (never a fade).
struct IconRoll: View {
    let from: String
    let to: String
    let p: CGFloat
    let ink: Color
    var on = false
    var body: some View {
        ZStack {
            Icon5(key: from, on: on, ink: ink, size: 22)
                .scaleEffect(1 - 0.4 * p)
                .offset(y: p * 34)
            Icon5(key: to, ink: ink, size: 22)
                .scaleEffect(0.6 + 0.4 * p)
                .offset(y: (p - 1) * 34)
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }
}

/// THE HEAD (Apple's toolbar: 44 glass circles 16 from the edges, centred 22 under the safe top): search · the mode
/// wheel · plus. Pulled from the top, the wheel's dot becomes the AI; held, it becomes the gear (TopPull). It stays put
/// at every height of the sheet, the night included.
struct HeadView: View {
    let map: MapController
    let water: Water
    @Bindable var head: HeadState
    @FocusState private var typing: Bool
    /// how far the tools capsule is out (0 the plus alone, 1 reaching the dot): one value drives the capsule, the
    /// tools and the dot becoming the first tool, so they can never drift apart
    @State private var toolsP: CGFloat = 0
    /// how far search is open (0 the circle, 1 the field with its results)
    @State private var searchP: CGFloat = 0
    /// the wheel's dot is away in the Dynamic Island for search (from the moment search starts opening until it is
    /// back in its place after search has closed)
    @State private var dotInIsland = false
    /// the gear turning back into the dot as search opens with Map settings open (it stays drawn until it is the dot)
    @State private var gearLeaving = false

    var body: some View {
        let L = water.layout
        let form = water.form()
        let ink: Color = FullView.night(form.page) ? Palette.white : Palette.ink
        let aiOut = head.pull > 0.5 || head.pullStop > 0
        let tools = head.toolsOpen && !aiOut && !head.searching
        // the search grows out of its circle into the field, up to the plus
        let fieldW = L.W - 2 * L.side - L.circle - 8
        // the plus stretches to the left into one capsule that reaches the wheel's dot, which becomes the first tool
        let plusX = L.W - L.side - L.circle / 2
        let spacing = (plusX - L.W / 2) / 4
        ZStack(alignment: .topLeading) {
            // SEARCH: one capsule of glass for its whole life, grown from its circle into the field by the same value
            // that opens the results under it, so the two always move together, both ways SEARCH AND ITS RESULTS ARE
            // ONE GLASS: the results box starts as the search circle itself, in its place, and flows down out of it as
            // it grows; closing, it flows back up into the circle and is the circle again. One glass container, so the
            // two melt into each other and part the way water does.
            let gap = L.headBottom + 10 - (L.headY - L.circle / 2)
            GlassEffectContainer(spacing: 14) {
                ZStack(alignment: .topLeading) {
                    Animated(p: searchP) { p in
                        searchCapsule(ink: ink, p: p, fieldW: fieldW)
                            .frame(width: L.circle + (fieldW - L.circle) * p, height: L.circle, alignment: .leading)
                            .clipShape(Capsule())
                            .glassEffect(.clear, in: .capsule)
                    }
                    .frame(width: fieldW, height: L.circle, alignment: .leading)
                    .position(x: L.side + fieldW / 2, y: L.headY)

                    Animated(p: searchP) { p in
                        if p > 0.001 {
                            SearchResults(map: map, head: head, pick: pick, reveal: p,
                                          width: L.circle + (fieldW - L.circle) * p, fullWidth: fieldW, gap: gap)
                                .offset(y: -gap * (1 - p))
                        }
                    }
                    .frame(width: fieldW, alignment: .topLeading)
                    .padding(.leading, L.side)
                    .padding(.top, L.headBottom + 10)
                }
                .frame(width: L.W, height: L.H, alignment: .topLeading)
            }
            .frame(width: L.W, height: L.H, alignment: .topLeading)

            // PLUS: one capsule that stretches out of the plus to hold the tools
            ToolsCapsule(p: toolsP, full: 4 * spacing, spacing: spacing,
                         tool: { i, slot in toolButton(i, ink: ink, slot: slot).allowsHitTesting(tools) },
                         plus: plusButton(ink: ink))
                // a sideways drag anywhere on the open capsule turns the modes, as on the dot; a tap is still the
                // tool's (the drag needs 8 points)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { g in
                            // it starts only on the open capsule, then follows the finger even as the capsule draws back
                            if tools || head.capsuleDrag != nil { head.capsuleDrag = g.translation.width }
                        }
                        .onEnded { g in
                            guard head.capsuleDrag != nil else { return }
                            head.capsuleDragFling = g.predictedEndTranslation.width - g.translation.width
                            head.capsuleDrag = nil
                        }
                )
                // the capsule grows from the plus leftward inside a frame that never moves, so the plus stays put
                .frame(width: L.W - L.side, height: L.circle, alignment: .trailing)
                .position(x: (L.W - L.side) / 2, y: L.headY)

            // THE MODE WHEEL, no glass, in the middle, drawn over the capsule's end: with the tools out its dot is the
            // first tool; it goes into the hub only for search. While the dot is becoming the AI or the gear its top
            // glyph is hidden and the morph is drawn in its place, the same dot at the start (it keeps its touches, so
            // a hold that turns it into the gear is never lost halfway)
            let morphing = head.pull > 0.01 || head.pullStop > 0 || head.gear > 0.001
                || (head.settingsOpen && (!head.searching || gearLeaving))
            ModeWheel(head: head, ink: ink, tools: tools, toolsP: toolsP, hideDot: morphing || dotInIsland)
                .position(x: L.W / 2, y: L.headY)
                .allowsHitTesting(!head.searching && !aiOut)
            // FOR SEARCH THE DOT GOES UP INTO THE DYNAMIC ISLAND: it rises as search starts to grow and is in the
            // island before the field reaches it, so the two never overlap; closing, it drops back out of the island
            // once the field has drawn back.
            if dotInIsland {
                Animated(p: searchP) { p in
                    IslandDrop(p: p, dot: CGPoint(x: L.W / 2, y: L.headY), island: L.island, notch: L.notch, ink: ink)
                }
                .frame(width: L.W, height: L.H)
                .allowsHitTesting(false)
            }
            if morphing {
                // one view for every state, so nothing is ever swapped mid-move: it rolls while settings are open
                TimelineView(.animation(paused: !head.settingsOpen)) { tl in
                    DotMorph(ai: head.aiShown, gear: head.gear, roll: .degrees(head.roll(at: tl.date)), ink: ink)
                }
                .position(x: L.W / 2, y: L.headY)
                .accessibilityElement()
                .accessibilityLabel(aiOut ? "AI" : "Settings")
            }

        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        .onChange(of: tools) { _, v in withAnimation(Motion.chrome) { toolsP = v ? 1 : 0 } }
        .onChange(of: head.searching) { _, v in
            if v {
                // the AI goes back into the dot; MAP SETTINGS STAY OPEN (search searches them, Part 3.4): the gear first
                // turns back into the dot (the hold's morph reversed), and only then does the dot rise into the island
                // and the field grow, so the gear is never under the field and never vanishes
                if head.pullStop > 0 || head.pull > 0 { head.pullStop = 0; withAnimation(Motion.settle) { head.pull = 0 } }
                if head.settingsOpen {
                    gearLeaving = true
                    withAnimation(Motion.quick) { head.gear = 0 } completion: {
                        gearLeaving = false
                        guard head.searching else { return }
                        dotInIsland = true
                        withAnimation(Motion.chrome) { searchP = 1 }
                    }
                    return
                }
                dotInIsland = true
            }
            withAnimation(Motion.chrome) { searchP = v ? 1 : 0 } completion: {
                if !head.searching {
                    dotInIsland = false
                    // settings still open: the dot out of the island becomes the gear again
                    if head.settingsOpen { withAnimation(Motion.quick) { head.gear = 1 } }
                }
            }
        }
        .onChange(of: head.toolsOpen) { _, v in
            if v { putAIBack() }
            // quick stamping ends with the tools (3.6), unless Map settings' "Always on" (Part 4.7, not built yet)
            else if head.quickStamp { withAnimation(Motion.chrome) { head.quickStamp = false } }
        }
        // held still, the dot becomes the gear over the hold; let go early and it goes back; held to the end,
        // settings open and the gear stays, rolling
        .onChange(of: head.dotHeld) { _, held in
            if held {
                guard !head.settingsOpen else { return }
                Feel.tick()
                withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: TopPull.holdForm)) { head.gear = 1 } completion: {
                    guard head.dotHeld, !head.settingsOpen else { return }
                    head.openSettings()
                    Feel.notch(); Sound.click()
                }
            } else if !head.settingsOpen {
                withAnimation(Motion.quick) { head.gear = 0 }
            }
        }
        // settings opened from elsewhere (the profile, a test): the dot becomes the gear the same way
        // (checked against the state now, not the value that triggered it: settings opened and closed in one update,
        // as when the plus closes them, must never leave the gear standing on a closed head)
        .onChange(of: head.settingsOpen) { _, _ in
            if head.settingsOpen {
                // with search open the dot is in the island: the gear forms when search closes (its completion)
                if head.gear < 1 && !head.searching { withAnimation(Motion.chrome) { head.gear = 1 } }
            } else if !head.dotHeld && !head.pullFromGear && head.gear > 0 {
                withAnimation(Motion.chrome) { head.gear = 0 }
            }
        }
        .animation(Motion.chrome, value: head.searching)
        .animation(Motion.chrome, value: head.toolsOpen)
        .animation(Motion.quick, value: head.query.isEmpty)
        .animation(Motion.quick, value: head.searching)
    }

    // MARK: search / the search glyph never moves or changes; the field's / words are there from the start and are
    // uncovered by the capsule as it grows, and covered again as it shrinks
    private func searchCapsule(ink: Color, p: CGFloat, fieldW: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            if p > 0.001 || head.searching {
                TextField("Search", text: $head.query)
                    .font(.body)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(ink)
                    .focused($typing)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { if let first = SearchResults.matches(map: map, query: head.query).first { pick(first) } }
                    .padding(.leading, 44)
                    .padding(.trailing, 14)
                    .frame(width: fieldW, height: 44, alignment: .leading)
                    .allowsHitTesting(head.searching)
            }
            Button {
                putAIBack()
                if !head.searching { openSearch() }
            } label: {
                Icon5(key: "search", ink: ink, size: 22)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            // THE SEARCH CIRCLE'S HOLD MENU (11.5): your last searches (one flies there, as a result does) · Clear
            // recent; closed only (open, the circle is the field's glyph)
            .contextMenu {
                if !head.searching, let w = map.world {
                    let recent = SearchResults.recent.compactMap { w.placeIndex[$0] }.prefix(5)
                    Section {
                        ForEach(Array(recent), id: \.self) { i in
                            Button(w.places[i].n) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pick(i) } }
                        }
                    }
                    Button("Clear recent", role: .destructive) {
                        MapSettingsStore.shared.change { $0.recent = [] }
                        UserDefaults.standard.removeObject(forKey: "wya.search.recent")
                    }
                        .disabled(recent.isEmpty)
                }
            }
            .accessibilityLabel("Search")
        }
    }

    /// the sheet stays where it is: the results sit under the field, over the map or the glass
    private func openSearch() {
        Feel.tap(); Sound.tap()
        head.toolsOpen = false
        // closed by a touch on the map less than 10 s ago: what was typed comes back (1.10)
        if CACurrentMediaTime() - head.mapClosedSearchAt > 10 { head.query = "" }
        head.searching = true
        // the keyboard comes the moment search opens; the field exists from the first frame of the opening
        DispatchQueue.main.async { typing = true }
    }
    /// what was typed stays until search opens again, so the rows don't change while they draw back into the field
    private func closeSearch() {
        typing = false
        head.searching = false
    }
    /// a result: the search closes and the map flies to the place, framed in the room the sheet leaves
    private func pick(_ i: Int) {
        Feel.tap(); Sound.tap()
        if let id = map.world?.places[i].id { SearchResults.remember(id) }
        let f = water.form()
        map.show(place: i, sheetTop: f.page > 0.5 ? water.layout.top(.quarter) : f.top)
        closeSearch()
    }

    // MARK: plus and its tools
    /// the plus: it turns into the × (its own film, a spin) and back; the capsule grows out of it (ToolsCapsule)
    private func plusButton(ink: Color) -> some View {
        Button {
            Feel.tap(); Sound.tap()
            putAIBack()
            if head.searching { closeSearch() } else { head.toolsOpen.toggle() }
        } label: {
            Icon5(key: "plus", on: head.toolsOpen || head.searching, ink: ink, size: 22)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(head.searching ? "Close search" : head.toolsOpen ? "Close tools" : "Tools")
    }

    /// search or the plus while the AI is out or settings are open: those go back into the dot first, as they would
    /// by their own way out, while search or the tools open
    private func putAIBack() {
        head.closeSettings()
        guard head.pullStop > 0 || head.pull > 0 else { return }
        head.pullStop = 0
        withAnimation(Motion.settle) { head.pull = 0 }
    }

    private func toolButton(_ i: Int, ink: Color, slot: CGFloat) -> some View {
        let names = ["Quick stamping", "Your passport", "Your history", "Upload"]
        let on = (i == 0 && head.quickStamp) || (i == 1 && BookState.shared.isOpen) || (i == 2 && head.history)
        let act = {
            switch i {
            case 0: head.quickStamp.toggle()
            // the passport tool: the book out of it and back into it (4.3); the tool shows filled while it is out
            case 1: BookState.shared.toggle()
            case 2: head.history.toggle()
            // Upload (9.2): the tools go back into the plus as the upload sheet opens in the water (the two never cross:
            // one is in the head, the other at the bottom)
            default:
                head.toolsOpen = false
                UploadState.shared.open(water: water, map: map)
            }
        }
        // the one row of its hold menu (11.4: the tool's name over a row that does what a tap does, named by it)
        let row = [head.quickStamp ? "Quick stamping off" : "Quick stamping on",
                   BookState.shared.isOpen ? "Put the passport away" : "Passport",
                   head.history ? "History off" : "History on", "Upload"][i]
        return Button {
            Feel.tap(); Sound.tap()
            act()
        } label: {
            // bare circles until their icons are picked, filled when on: the ring thickens into the disc (and thins
            // back), as the first tool on the dot does, never a one-frame swap
            ToolRing(width: on ? 8.5 : 1.6)
                .fill(ink, style: FillStyle(eoFill: true))
                .animation(Motion.quick, value: on)
                .frame(width: 17, height: 17)
            .frame(width: slot, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Section(names[i]) {
                // once Apple's menu has closed, so the two never cross
                Button(row) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { act() } }
            }
        }
        .accessibilityLabel(names[i])
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// a ring of a given width inside its frame (as wide as the radius: the disc)
nonisolated struct ToolRing: Shape {
    var width: CGFloat
    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path(ellipseIn: rect)
        let w = min(width, rect.width / 2)
        if w < rect.width / 2 - 0.01 { p.addEllipse(in: rect.insetBy(dx: w, dy: w)) }
        return p
    }
}

/// A value that SwiftUI animates, handed to the content at every frame of the animation (a plain view only ever sees
/// where the value is going; this one sees where it is), so several things can be drawn from one moving value.
/// The wheel's dot on its way into the Dynamic Island and back (search): at 0 it is the dot exactly, in its place; it
/// rises, and as it reaches the island it widens into the island's own capsule,
/// black into black, so it is taken in rather than vanishing. Done by 60% of search's opening (the field passes the
/// dot's place at about 47%, by then the dot is above it); closing runs the same way back.
struct IslandDrop: View {
    let p: CGFloat
    let dot: CGPoint
    let island: CGRect
    var notch: CGRect = .zero
    let ink: Color

    var body: some View {
        let r = DotMorph.dotR
        // the island: it widens into the island's capsule. A notch (the 17e): it rises into the notch at its own size,
        // never widening, black into the notch's black (0.8.11; A3.2). No cutout at all: up past the screen's top edge
        let target = island != .zero ? island
            : notch != .zero ? CGRect(x: dot.x - r, y: notch.midY - r, width: 2 * r, height: 2 * r)
            : CGRect(x: dot.x - r, y: -3 * r, width: 2 * r, height: 2 * r)
        let travel = Flow.smooth(0, 0.5, p)
        let merge = Flow.smooth(0.28, 0.6, p)
        // a circle that becomes the island's capsule, never squashed or stretched on the way (no cartoon drop)
        let w = Flow.lerp(2 * r, target.width, merge)
        let h = Flow.lerp(2 * r, target.height, merge)
        let y = Flow.lerp(dot.y, target.midY, travel)
        if p < 0.995 {
            Capsule()
                .fill(ink.mix(with: .black, by: Double(merge)))
                .frame(width: w, height: h)
                .position(x: dot.x, y: y)
        }
    }
}

struct Animated<Content: View>: View, Animatable {
    var p: CGFloat
    @ViewBuilder let build: (CGFloat) -> Content
    var animatableData: CGFloat {
        get { p }
        set { p = newValue }
    }
    var body: some View { build(p) }
}

/// THE TOOLS CAPSULE: it grows leftward out of the plus while the plus stays exactly where it is and only turns. Each
/// tool sits in its own slot and grows from its middle as the capsule's end passes over it, the nearest first, so none
/// is ever drawn over the × or over another. Plain glass: Apple's interactive glass swells under the finger, which
/// pushed the plus forward and back.
private struct ToolsCapsule<Tool: View, Plus: View>: View, Animatable {
    var p: CGFloat
    let full: CGFloat
    let spacing: CGFloat
    let tool: (Int, CGFloat) -> Tool
    let plus: Plus
    var animatableData: CGFloat {
        get { p }
        set { p = newValue }
    }
    var body: some View {
        let e = max(0, p) * full
        ZStack(alignment: .trailing) {
            ForEach(1 ..< 4, id: \.self) { i in
                let slotAt = CGFloat(4 - i) * spacing
                // each in its own slot, never moving: it grows from its middle as the capsule's end passes over it
                // (opening) and shrinks back into it as the end comes back (closing); two never touch
                let grow = Flow.smooth(slotAt - 0.5 * spacing, slotAt, e)
                tool(i, min(44, spacing))
                    .frame(width: 44)
                    .scaleEffect(max(0.001, grow))
                    .offset(x: -slotAt)
            }
            plus
        }
        .frame(width: 44 + e, height: 44, alignment: .trailing)
        .clipShape(Capsule())
        .glassEffect(.clear, in: .capsule)
    }
}

/// THE MODE WHEEL: black, no glass, turned, never tapped. The modes sit on a wheel whose hub is under the glyph; the
/// one at the top is the one you are on, a full black circle. While you turn it, its neighbours ride the rim left and
/// right, smaller and lower, in their unselected shapes; the one coming to the top fills in exactly as far as it has
/// come (no little film of its own, no holes). A tick at each mode it passes, a click when it lands; the name shows
/// under it while you hold it. Let go and the neighbours go back into the hub.
struct ModeWheel: View {
    @Bindable var head: HeadState
    var ink: Color
    /// the plus's tools are out: the dot is the mode's first tool (quick stamping in Countries)
    var tools = false
    /// how far the tools capsule is out: the dot becomes the first tool as the capsule's end reaches it
    var toolsP: CGFloat = 0
    /// the dot is being drawn by the AI / gear morph (TopPull's DotMorph) in its place
    var hideDot = false

    @State private var at: CGFloat = 0
    /// the hold that turns the dot into the gear: started a moment after the finger goes down, if it stays still
    @State private var holdTask: Task<Void, Never>?
    @State private var dragging = false
    @State private var startAt: CGFloat = 0
    @State private var lastTick = 0
    @State private var reveal: CGFloat = 0
    /// the first tool on (1) or off (0)
    @State private var lit: CGFloat = 0

    private let step: CGFloat = 35

    var body: some View {
        ZStack {
            WheelFace(at: at, reveal: reveal, ink: ink, cover: toolsP, hideTop: hideDot)
                .allowsHitTesting(false)
            FirstTool(p: toolsP, lit: lit, ink: ink)
                .allowsHitTesting(false)
            // THE MODE'S NAME under the wheel while you turn it (A3.4): its top edge 28 points under the wheel's
            // middle, clear of the circle; it rolls in by the text roll as the turn starts, rolls to the next name as
            // the wheel passes a mode, and rolls out when the wheel lands. Never scaled (0.8.5): placeholder spaces
            // when not shown.
            let i = Int(at.rounded()).clamped(0, 3)
            let name = HeadState.Mode(rawValue: i)!.name
            VStack(spacing: 0) {
                Color.clear.frame(width: 1, height: 100 + 28)
                Text(dragging ? name : String(repeating: "\u{2002}", count: name.count))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ink)
                    .fixedSize()
                    // in rises, out goes down, a pass rolls the way the wheel turns
                    .contentTransition(.numericText(value: dragging ? Double(i + 1) : 0))
                    .animation(Motion.quick, value: dragging ? i + 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(width: 200, height: 200, alignment: .top)
            .allowsHitTesting(false)
        }
        .frame(width: 88, height: 44)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { g in turn(g.translation.width) }
                .onEnded { g in letGo(g.predictedEndTranslation.width - g.translation.width) }
        )
        // HOLD THE DOT FOR SETTINGS: still for a moment, it starts turning into the gear; moving (turning the wheel) or
        // letting go before it is the gear puts it back
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if hypot(g.translation.width, g.translation.height) > 6 { endHold(); return }
                    guard holdTask == nil, !tools, !head.settingsOpen, head.pullStop == 0, !head.searching, !head.dotHeld else { return }
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(TopPull.holdDelay))
                        if !Task.isCancelled && !dragging { head.dotHeld = true }
                        holdTask = nil
                    }
                }
                .onEnded { _ in endHold(); holdTask = nil }
        )
        .onChange(of: head.capsuleDrag) { _, t in
            if let t { turn(t) } else if dragging { letGo(head.capsuleDragFling) }
        }
        // with the tools out a tap on the dot is the first tool; with settings open, a tap on the gear closes them;
        // the wheel itself is never tapped
        .onTapGesture {
            if head.settingsOpen { Feel.tap(); Sound.tap(); head.closeSettings(); return }
            guard tools else { return }
            Feel.tap(); Sound.tap()
            withAnimation(Motion.chrome) { head.quickStamp.toggle() }
        }
        .onAppear { at = CGFloat(head.mode.rawValue); lastTick = head.mode.rawValue; lit = head.quickStamp ? 1 : 0 }
        .onChange(of: head.quickStamp) { _, v in withAnimation(Motion.quick) { lit = v ? 1 : 0 } }
        .onChange(of: head.testDial) { _, v in
            withAnimation(Motion.chrome) {
                if let v { dragging = true; reveal = 1; at = v } else { dragging = false; reveal = 0; at = CGFloat(head.mode.rawValue) }
            }
        }
        .onChange(of: head.mode) { _, m in
            if Int(at.rounded()) != m.rawValue && !dragging {
                withAnimation(Motion.chrome) { at = CGFloat(m.rawValue) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(tools ? "Quick stamping, \(head.quickStamp ? "on" : "off")" : "Map mode")
        .accessibilityValue(head.mode.name)
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: choose(min(3, head.mode.rawValue + 1))
            case .decrement: choose(max(0, head.mode.rawValue - 1))
            @unknown default: break
            }
        }
    }

    private func endHold() {
        holdTask?.cancel()
        holdTask = nil
        if head.dotHeld { head.dotHeld = false }
    }

    /// the finger has moved `dx` sideways since it went down (on the wheel, or on the tools capsule) With settings open
    /// the wheel still turns and changes the mode; the gear stays on top.
    private func turn(_ dx: CGFloat) {
        if !dragging {
            endHold()
            withAnimation(Motion.quick) { dragging = true; reveal = 1 }
            startAt = at
            // turning from the first tool: the tools go back into the plus, the dot is the wheel again
            if head.toolsOpen { withAnimation(Motion.chrome) { head.toolsOpen = false } }
        }
        var v = startAt - dx / step
        if v < 0 { v = -Flow.rubber(-v, 0.5) }
        if v > 3 { v = 3 + Flow.rubber(v - 3, 0.5) }
        at = v
        let i = Int(v.rounded()).clamped(0, 3)
        if i != lastTick { lastTick = i; Feel.tick(); Sound.tick() }
    }
    /// the finger is off; `fling` is how much further it would have gone
    private func letGo(_ fling: CGFloat) {
        guard dragging else { return }
        let projected = at - fling / step * 0.3
        choose(Int(projected.rounded()).clamped(0, 3))
        withAnimation(Motion.quick) { dragging = false }
        withAnimation(Motion.chrome.delay(0.12)) { reveal = 0 }
    }

    private func choose(_ i: Int) {
        // landing on another mode starts it fresh, quick stamping off (BUILD-BOOK 3.1a, 4.7)
        if i != head.mode.rawValue { head.quickStamp = false }
        head.mode = HeadState.Mode(rawValue: i)!
        lastTick = i
        withAnimation(Motion.chrome) { at = CGFloat(i) }
        Feel.notch(); Sound.click()
    }
}

/// THE FIRST TOOL IS THE DOT, BECOME A TOOL: as the capsule reaches it, the black dot draws in to the tools' own size
/// and hollows into the same ring the other three are, one shape changing (a solid circle is a ring as thick as its
/// radius); on, it is filled the way the others are when on. Closing is the same in reverse, ending as the dot exactly.
private struct FirstTool: View, Animatable {
    /// how far the tools capsule is out (ToolsCapsule's p)
    var p: CGFloat
    /// 0: off, 1: on
    var lit: CGFloat
    var ink: Color

    /// the capsule's end reaches the dot over the last quarter of its way out: the dot changes over exactly that
    static let start: CGFloat = 0.75

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(p, lit) }
        set { p = newValue.first; lit = newValue.second }
    }

    var body: some View {
        // the dot's own size: the wheel draws it 30 points on the 9-unit icon box, so the circle is 8/9 of that
        let dot: CGFloat = 30 * 8 / 9, tool: CGFloat = 17
        let t = Flow.smooth(Self.start, 1, p)
        let d = dot + (tool - dot) * t
        // a ring as thick as the radius is the solid dot; the tool's ring is 1.6, or solid again when on
        let ring = 1.6 + (d / 2 - 1.6) * max(1 - t, lit)
        if p > Self.start {
            Circle()
                .strokeBorder(ink, lineWidth: min(d / 2, ring))
                .frame(width: d, height: d)
        }
    }
}

/// The wheel's face at one position (animatable, so the fills follow the turn frame by frame).
private struct WheelFace: View, Animatable {
    var at: CGFloat
    var reveal: CGFloat
    var ink: Color
    /// the first tool is drawn in the top glyph's place (it starts and ends as exactly that dot)
    var cover: CGFloat = 0
    /// the AI or gear morph is drawn in the top glyph's place
    var hideTop = false

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(at, reveal), cover) }
        set { at = newValue.first.first; reveal = newValue.first.second; cover = newValue.second }
    }

    private let radius: CGFloat = 70
    private let spacing: Double = 30

    var body: some View {
        ZStack {
            ForEach(HeadState.Mode.allCases, id: \.rawValue) { m in
                let d = Double(CGFloat(m.rawValue) - at)
                let rad = d * spacing * .pi / 180
                let away = CGFloat(min(abs(d), 2))
                // full size at the top, two thirds one step away, gone two away (it shrinks, never fades)
                let size = away <= 1 ? 1 - 0.36 * away : 0.64 * (2 - away)
                // at the top a full circle; one step away its own unselected shape; in between, as far as it has come
                let fill = max(0, 1 - away)
                // only the one at the top shows when the wheel is at rest
                let shown = (cover > FirstTool.start || hideTop) && abs(d) < 0.5 ? 0 : max(fill > 0.5 ? 1 : 0, reveal)
                Icon5Still(key: m.key, progress: fill, ink: ink, size: 30)
                    .scaleEffect(max(0.001, size * shown))
                    .offset(x: radius * CGFloat(sin(rad)) * shown, y: radius * (1 - CGFloat(cos(rad))) * shown)
            }
        }
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

enum ResultKey: Hashable { case place(Int), miss, setting(String) }

/// a search result's slot: how open it is (0 shut, 1 the row's full 44 pt) on the quick curve, moved by our own clock
/// so the rows are always laid out from where every slot is at that moment: a row's top is the sum of the slots above
/// it, and the box's bottom edge is the sum of them all. (SwiftUI's own animations failed here three ways: a removal
/// transition froze the row's layout, a transition's modifier wrapped the row's y too, and rows placed at their final
/// y overlapped slots still closing when letters came faster than the curve.) The curve is `Motion.quick`'s: a
/// critically damped spring of response 0.26 s (0.2 s with Reduce Motion), retargeted from its value and speed.
struct ResultSlot {
    var x0: Double, v0: Double, t0: Double, to: Double
    static var w: Double { 2 * .pi / (Motion.reduce ? 0.2 : 0.26) }
    func at(_ t: Double) -> (x: Double, v: Double) {
        let w = Self.w, dt = max(0, t - t0), d = x0 - to, b = v0 + w * d, e = exp(-w * dt)
        return (to + (d + b * dt) * e, (b - w * (d + b * dt)) * e)
    }
}

/// The search results: the places whose name, formal name, other names or the names people type match. The box is the
/// field's own width, under it.
struct SearchResults: View {
    let map: MapController
    @Bindable var head: HeadState
    var pick: (Int) -> Void
    /// how far search is open: the box is that much of its height, growing down from under the field, and as wide as
    /// the field is at that moment (it grows out from under the search circle with it); its rows keep their full width
    /// and are uncovered, never squeezed
    var reveal: CGFloat = 1
    var width: CGFloat = 0
    var fullWidth: CGFloat = 0
    /// from the search circle's top to the results' top: the rows stay where they will rest while the box (which starts
    /// as the circle) flows down over them, so none is ever seen inside the circle
    var gap: CGFloat = 0

    var body: some View {
        let typed = !head.query.trimmingCharacters(in: .whitespaces).isEmpty
        let hits = typed ? Self.matches(map: map, query: head.query) : Self.suggestions(map: map)
        // a typo with no match: the nearest place, as a row of its own
        // the index first; with nothing there, Apple Intelligence's pick among the nearest names, once it has answered
        let near = hits.isEmpty && typed ? Self.nearest(map: map, query: head.query) : nil
        let guess = near ?? (hits.isEmpty && typed && smart?.q == head.query ? smart?.i : nil)
        // rows keyed by place, so a row that stays moves to its new y (A1.13); a guess is its place's own row, so "Fra"
        // to "Frnace" keeps the France row and only its note rolls to
        // with Map settings open, the field searches the settings (Part 3.4, 5.11)
        let settingHits = head.settingsOpen ? SettingsSearch.hits(head.query, map: map) : []
        let keys: [ResultKey] = head.settingsOpen
            ? (typed ? (settingHits.isEmpty ? [.miss] : settingHits.map { .setting($0.id) }) : [])
            : hits.isEmpty ? (typed ? [guess.map { .place($0) } ?? .miss] : []) : hits.map { .place($0) }
        let w = width > 0 ? width : fullWidth
        // a stack that is always there (an empty Group is no view, so its onChange never ran and the first list never
        // came)
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: 0, height: 0)
            if !shown.isEmpty && reveal > 0.001 {
                TimelineView(.animation(paused: Date().timeIntervalSinceReferenceDate > until)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let open = shown.map { CGFloat(min(1, max(0, slots[$0]?.at(t).x ?? 1))) }
                    let full = 44 * open.reduce(0, +) + 8
                    // from the circle (44 by 44, in the circle's place) to the full box
                    let h = 44 + (max(44, full + gap) - 44) * reveal - gap * reveal
                    // a row coming or going opens or closes its own slot from its bottom edge (uncovered or covered,
                    // the rows under it moving with it), never a fade (A1.13)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(shown.enumerated()), id: \.element) { n, k in
                            Group {
                                switch k {
                                case .place(let i): row(i, note: i == guess ? "Did you mean?" : nil)
                                case .miss: missRow()
                                case .setting(let id): settingRow(settingHits.first { $0.id == id })
                                }
                            }
                            .frame(height: 44 * open[n], alignment: .top)
                            .clipped()
                            .padding(.top, 44 * open[..<n].reduce(0, +))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, 4)
                    .frame(width: fullWidth > 0 ? fullWidth : nil, height: max(full, 8), alignment: .top)
                    .offset(y: gap * (1 - reveal))
                    // the box's own size grows with the opening, its rows uncovered from the top left (never scaled,
                    // never faded); its bottom edge is the slots' sum, so a change of rows grows or shrinks it with them
                    .frame(width: fullWidth > 0 ? w : nil, height: h, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: min(22, h / 2, w / 2), style: .continuous))
                    .glassEffect(.clear, in: .rect(cornerRadius: min(22, h / 2, w / 2)))
                }
            }
        }
        .onChange(of: keys, initial: true) { old, new in update(to: new, first: old == new) }
        .task(id: head.query) { await askModel() }
    }

    /// "DID YOU MEAN", STEP 2 (1.10): when the index finds nothing, Apple Intelligence on the phone picks one of the 20
    /// nearest names; the row shows only once it has answered (nothing turns while waiting); without Apple
    /// Intelligence, or past 1.5 s, the index alone
    @State private var smart: (q: String, i: Int)?
    private func askModel() async {
        let q = head.query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3, !head.settingsOpen, Self.matches(map: map, query: q).isEmpty,
              Self.nearest(map: map, query: q) == nil, let w = map.world else { return }
        // a short wait so a word still being typed asks nothing
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let names = Self.closest(map: map, query: q, count: 20)
        guard !names.isEmpty, let pick = await SmartGuess.pick(typed: q, among: names.map { w.places[$0].n }) else { return }
        guard !Task.isCancelled, head.query.trimmingCharacters(in: .whitespaces) == q,
              let i = names.first(where: { w.places[$0].n == pick }) else { return }
        smart = (head.query, i)
    }

    /// the rows on screen: the new rows in their order, each leaving row kept just after the row it followed, its slot
    /// closing; a row whose slot has shut is dropped at the next change or when all have settled (at no height, so
    /// nothing is seen to go). A row that comes back while closing opens again from where it is.
    @State private var shown: [ResultKey] = []
    @State private var slots: [ResultKey: ResultSlot] = [:]
    @State private var until: Double = 0
    @State private var run = 0
    private func update(to new: [ResultKey], first: Bool) {
        let t = Date().timeIntervalSinceReferenceDate
        // the first list (search opening) is there at once: the box itself opens over it
        if first || shown.isEmpty {
            shown = new
            slots = Dictionary(uniqueKeysWithValues: new.map { ($0, ResultSlot(x0: 1, v0: 0, t0: t, to: 1)) })
            return
        }
        // shut rows go first, so the list never grows while letters come fast
        let live = shown.filter { k in
            guard let s = slots[k], s.to == 0 else { return true }
            return s.at(t).x > 0.002
        }
        var merged: [ResultKey] = [], next = 0
        for k in live {
            if let j = new.firstIndex(of: k) {
                if j >= next { merged += new[next ... j]; next = j + 1 }
            } else {
                merged.append(k)
            }
        }
        if next < new.count { merged += new[next...] }
        var s2: [ResultKey: ResultSlot] = [:]
        for k in merged {
            let to: Double = new.contains(k) ? 1 : 0
            if let s = slots[k] {
                let (x, v) = s.at(t)
                s2[k] = ResultSlot(x0: x, v0: v, t0: t, to: to)
            } else {
                s2[k] = ResultSlot(x0: 0, v0: 0, t0: t, to: to)
            }
        }
        shown = merged
        slots = s2
        until = t + 0.6
        run += 1
        let me = run
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            guard me == run else { return }
            shown.removeAll { slots[$0]?.to == 0 }
            until = 0   // the clock stops (a new value makes the view look again and pause its timeline)
        }
    }

    /// a setting found (settings open): its name and where it is or what matched; a tap opens it in the sheet
    private func settingRow(_ h: SettingsSearch.Hit?) -> some View {
        Button {
            Feel.tap()
            if let h { SettingsSearch.go(h.id) }
            head.searching = false
        } label: {
            HStack(spacing: 12) {
                Text(h?.name ?? "").font(.body).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: 8)
                Text(h?.note ?? "").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .buttonStyle(.plain)
    }

    /// one row: the flag, the name, and what it is in the one low-opacity black (BUILD-BOOK 1.10), in the borders view:
    /// on the ground a breakaway held on its own is a country; a guess says so in that place instead
    private func row(_ i: Int, note: String?) -> some View {
        let pl = map.world?.places[i]
        return Button {
            pick(i)
        } label: {
            HStack(spacing: 12) {
                // square detailed flags, never rounded (0.8.8)
                Group {
                    if let f = pl.flatMap({ Flags.square($0.id) }) { f.resizable().interpolation(.high) } else { Color.clear }
                }
                .frame(width: 22, height: 22)
                Text(pl?.n ?? "")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(note ?? pl.map { p in map.world?.positions?.kindName(p.id) ?? Self.kind(p.k) } ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(Motion.quick, value: note)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
            // Apple's text styles up to the largest standard size: the rows are 44 pt; the AX sizes need growing rows
            // and a scrolling box (Part 1.10's AX note), not built yet
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .buttonStyle(.plain)
    }

    /// no match and no near name: "No results", in the name's place
    private func missRow() -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 22, height: 22)
            Text("No results")
                .font(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    /// the name closest to what was typed, by edit distance against each name's start of the same length (so "Shenzen"
    /// still finds a longer name); at most a third of the letters wrong, never for under 3 letters
    static func nearest(map: MapController, query: String) -> Int? {
        guard let w = map.world else { return nil }
        let q = Array(fold(query.trimmingCharacters(in: .whitespaces)))
        guard q.count >= 3 else { return nil }
        var best: (Int, Int)?
        let names = w.searchNames
        for (pi, p) in w.places.enumerated() where !p.junk {
            for name in names[pi] {
                let n = Array(name)
                let d = min(distance(q, n), distance(q, Array(n.prefix(q.count))))
                if d < (best?.1 ?? Int.max) { best = (pi, d) }
            }
        }
        guard let b = best, b.1 > 0, b.1 <= max(1, q.count / 3) else { return nil }
        return b.0
    }

    /// the `count` places whose names are nearest to what was typed (the same measure as `nearest`), nearest first
    static func closest(map: MapController, query: String, count: Int) -> [Int] {
        guard let w = map.world else { return [] }
        let q = Array(fold(query.trimmingCharacters(in: .whitespaces)))
        var best: [(Int, Int)] = []
        let names = w.searchNames
        for (pi, p) in w.places.enumerated() where !p.junk {
            var d = Int.max
            for name in names[pi] {
                let n = Array(name)
                d = min(d, distance(q, n), distance(q, Array(n.prefix(q.count))))
            }
            best.append((pi, d))
        }
        return best.sorted { $0.1 < $1.1 }.prefix(count).map(\.0)
    }

    /// a name as search compares it: no case, no accents ("Curacao" finds Curaçao)
    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0 ... b.count), cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1 ... a.count {
            cur[0] = i
            for j in 1 ... b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    // MARK: suggestions on the empty field (BUILD-BOOK 1.10): up to five, all real, never filler: the places you last
    // opened from search, newest first; then your wishes not yet stamped; then the unstamped neighbours (D19) of your
    // nationalities' countries (Profile), or of the phone's region before Profile has any. Never the phone's own
    // country, and never your nationalities' own countries, as a suggestion.
    /// the last 12 searches live in map-settings.json (19.2); the five kept in UserDefaults by older builds are read once
    private static let recentKey = "wya.search.recent"
    static var recent: [String] {
        let r = MapSettingsStore.shared.value.recent
        return r.isEmpty ? ((UserDefaults.standard.array(forKey: recentKey) as? [String]) ?? []) : r
    }
    static func remember(_ id: String) {
        var r = recent
        r.removeAll { $0 == id }
        r.insert(id, at: 0)
        MapSettingsStore.shared.change { $0.recent = Array(r.prefix(12)) }
        UserDefaults.standard.removeObject(forKey: recentKey)
    }
    static func suggestions(map: MapController, recentToo: Bool = true) -> [Int] {
        guard let w = map.world else { return [] }
        let stamped = map.stamped
        let phone = Locale.current.region.flatMap { w.placeIndex[$0.identifier.lowercased()] }
        let nats = (UserDefaults.standard.stringArray(forKey: MapController.nationalitiesKey) ?? []).compactMap { w.placeIndex[$0] }
        let homes = nats.isEmpty ? (phone.map { [$0] } ?? []) : nats
        var out = recentToo ? Array(recent.compactMap { w.placeIndex[$0] }.prefix(5)) : []
        func add(_ xs: [Int]) {
            for x in xs where out.count < 5 && !out.contains(x) && x != phone && !homes.contains(x) && !w.places[x].junk {
                out.append(x)
            }
        }
        // nearest a home first
        func near(_ h: Int?) -> (Int, Int) -> Bool {
            guard let h else { return { w.places[$0].n < w.places[$1].n } }
            let hc = w.places[h].c
            return { hypot(w.places[$0].c[0] - hc[0], w.places[$0].c[1] - hc[1]) < hypot(w.places[$1].c[0] - hc[0], w.places[$1].c[1] - hc[1]) }
        }
        add(map.wished.subtracting(stamped).sorted(by: near(homes.first)))
        // read only once worked out (in the background after the world loads): the main thread never waits for them
        let nb = w.neighboursIfReady ?? []
        for h in homes where h < nb.count { add(nb[h].subtracting(stamped).sorted(by: near(h))) }
        // still short (an island home has no neighbours, or they are not worked out yet): the unstamped places nearest
        // the first home
        if out.count < 5, let h = homes.first {
            add(w.places.indices.filter { !stamped.contains($0) && $0 != h }.sorted(by: near(h)))
        }
        return out
    }

    static func kind(_ k: String?) -> String {
        switch k {
        case "country": "Country"
        case "territory": "Territory"
        case "antarctica": "Continent"
        default: ""
        }
    }

    static func matches(map: MapController, query: String) -> [Int] {
        guard let w = map.world else { return [] }
        let typedLower = query.lowercased().trimmingCharacters(in: .whitespaces)
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return [] }
        // in order: a name people type for it (UK, Britain), its own name starting with what was typed, another of
        // its names starting with it ("Estados Unidos Mexicanos" is Mexico, after the United States for "united"),
        // then anything containing it
        var alias: [Int] = [], own: [Int] = [], other: [Int] = [], contains: [Int] = []
        if let a = w.aliases[typedLower] ?? w.aliases[q], let i = w.placeIndex[a] { alias.append(i) }
        let names = w.searchNames
        for (i, p) in w.places.enumerated() where !p.junk && !alias.contains(i) {
            let n = names[i]
            if n[0].hasPrefix(q) { own.append(i) }
            else if n.dropFirst().contains(where: { $0.hasPrefix(q) }) { other.append(i) }
            else if n.contains(where: { $0.contains(q) }) { contains.append(i) }
        }
        // its names in other languages ("Allemagne", "ドイツ") last, so they never push an English match down
        var language: [Int] = []
        let picked = Set(alias + own + other + contains)
        if q.count >= 2, let more = w.otherLanguageNamesIfReady {
            for (i, p) in w.places.enumerated() where !p.junk && !picked.contains(i) && more[i].contains(where: { $0.hasPrefix(q) }) {
                language.append(i)
            }
        }
        return Array((alias + own + other + contains + language).prefix(6))
    }
}
