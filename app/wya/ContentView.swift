import SwiftUI

/// The Map tab: the world edge to edge under everything, the head on top, the zoom column on the right, and the
/// water (the tab capsule and its sheet) at the bottom. Everything is placed from this phone's own screen (Layout).
struct ContentView: View {
    @State private var map = MapController()
    @State private var water = Water()
    @State private var head = HeadState()
    @State private var tab = 0
    @State private var launch = Launch.shared
    @State private var side = Sideways.shared
    /// THE SESSION (19.2), for when the system ends the app in the background (Apple's scene storage: discarded when
    /// the person quits the app, so a cold launch opens fresh): the tab, the mode, the continent, the camera, the sheet
    /// stop, the lock
    @SceneStorage("wya.map.session") private var session = ""
    @State private var sessionWrite: Task<Void, Never>?

    var body: some View {
        // THE SCREEN, pinned to its top left: everything inside is sized from the window (Layout), never from the room
        // SwiftUI offers. With the keyboard up that room is shorter; a full-height ZStack in it was centred and the
        // whole app slid up by half the keyboard. Laid over a Color.clear at its top left, it stays where it is and the
        // keyboard simply covers the bottom.
        Color.clear.overlay(alignment: .topLeading) { screen }
            .ignoresSafeArea()
            .ignoresSafeArea(.keyboard)
    }

    private var screen: some View {
        ZStack(alignment: .topLeading) {
            if water.layout.model.isEmpty {
                // the very first frame, before the layout is known: just the sea, nothing in a wrong place
                Palette.blue
            } else {
                if !Perf.shared.off.contains("map") { sidewaysMap }

                // sideways (1.11) the head goes up past the top edge, the column off the right edge, the water down past
                // the bottom edge
                if !Perf.shared.off.contains("zoom") {
                    ZoomColumn(map: map, water: water, head: head, sideways: { enterSideways() })
                        .offset(x: side.chromeOut ? 90 : 0)
                }

                // under the water: the space's shaders set up once, unseen (Prewarm.swift)
                ShaderPrewarm()
                    .position(x: water.layout.W / 2, y: water.layout.capsule.midY)

                // the stamping card: over the map, under the sheet's glass and the head (Part 4.2)
                StampCard(map: map, water: water)
                // the passport book from the plus's passport tool (Part 4.3)
                PassportBook(water: water, map: map)

                WaterView(water: water, map: map, tab: $tab)
                    .offset(y: side.chromeOut ? water.layout.H - water.layout.capsule.minY + 24 : 0)

                if !Perf.shared.off.contains("head") {
                    HeadView(map: map, water: water, head: head)
                        .offset(y: side.chromeOut ? -(water.layout.headBottom + 24) : 0)
                }
                if side.on { SidewaysMarks(map: map, L: water.layout) }

                if !Perf.shared.off.contains("pull") { TopPullView(head: head, water: water) }
            }
            // THE LOADING SCREEN (12.3) over everything until the map is ready; then it lifts away in one piece, the
            // map and all its chrome already in place under it; touches wait until it has gone
            if !launch.done {
                LoadingScreen(reveal: launch.reveal)
            }
            if !launch.settled {
                Color.clear.contentShape(Rectangle()).ignoresSafeArea()
            }
        }
        .frame(width: water.layout.model.isEmpty ? nil : water.layout.W, height: water.layout.model.isEmpty ? nil : water.layout.H,
               alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.blue)
        // the screen and its safe areas, read from the full-screen frame: this phone's own numbers
        .background(GeometryReader { g in
            Color.clear.onChange(of: g.frame(in: .global), initial: true) { _, f in
                #if DEBUG
                TestDriver.shared.contentFrame = f
                #endif
            }
            .onChange(of: Layout.current(size: g.size, insets: g.safeAreaInsets), initial: true) { _, l in
                water.layout = l
                map.layout = l
                #if DEBUG
                NSLog("wya layout %@ %.0fx%.0f safe top %.0f bottom %.0f", l.model, l.W, l.H, l.safeTop, l.safeBottom)
                #endif
            }
        })
        .ignoresSafeArea()
        // the keyboard comes up over the map; nothing moves out of its way (the results sit under the head)
        .ignoresSafeArea(.keyboard)
        .defersSystemGestures(on: .top)
        // sideways: no status bar, no home indicator
        .statusBarHidden(side.on)
        .persistentSystemOverlays(side.on ? .hidden : .automatic)
        // LINKS INTO THE MAP (19.6): whatever is out goes back first (keeping its changes), then the flight
        .onOpenURL { url in
            Task { await DeepLink.open(url, map: map) { putAwayForLink() } }
        }
        .onAppear {
            TestDriver.shared.start(map: map, water: water, head: head)
            #if DEBUG
            TestDriver.shared.restoreSession = { restoreSession() }
            #endif
            // the Map's actions, by stable id (Part 20.12): the AI, Siri, links and hold menus call these
            Actions.shared.registerMap(map: map, water: water, head: head)
            MapSettingsRows.registerActions(map: map)
            // a finger on the map or the sheet puts settings and the AI away (and goes on doing what it does)
            // with Details up, a touch on the map closes Details only (back to the card); the next one closes the card
            map.onTouch = { [head, water, map] in
                Hints.shared.touched()
                // search open: the touch closes it only (a drag still pans), keeping the typed text 10 s (1.10)
                if head.searching { head.closeSearchFromMap(); return }
                head.putAway(); water.hideCredit()
                // the upload sheet while choosing closes (and that touch does nothing else, 9.3); while finding or at the
                // review the touch is the map's (a pan, or a tap that drops or keeps a find)
                if water.upload {
                    let ph = UploadState.shared.phase
                    if ph == .choosing || ph == .words { UploadState.shared.close() }
                    return
                }
                // the passport book goes back into its tool (and that touch does nothing else)
                if BookState.shared.isOpen { BookState.shared.close(); return }
                if DetailsState.shared.isOpen { DetailsState.shared.close(water: water) }
                else if VerifyState.shared.isOpen { VerifyState.shared.close(water: water) }
                else { CardState.shared.close(map: map) }
            }
            // a finger in the water is using Details or Verify when they are up; otherwise it closes the card
            water.onTouch = { [head, map] in
                Hints.shared.touched()
                head.putAwayAI()
                BookState.shared.close()
                if !DetailsState.shared.isOpen && !VerifyState.shared.isOpen { CardState.shared.close(map: map) }
            }
            // a confirmed tap on a place opens its stamping card (Part 4.2.1)
            map.onPlaceTap = { [head, map, water] i, p in
                // the upload sheet up: finding owns the map's presses, a tap while choosing has closed it (9.3, 9.4), and
                // at the review a found country's tap drops or keeps it (9.5)
                if water.upload { _ = UploadState.shared.tap(i); return }
                guard !map.locked else { return }
                // the tap that closed search opens nothing (one press, one job)
                guard CACurrentMediaTime() - head.mapClosedSearchAt > 0.6 else { return }
                // sideways (1.11) a tap opens nothing; quick stamping still stamps
                if Sideways.shared.on {
                    if head.quickStamp { Self.quickStamp(i, map: map) } else { Feel.refuse() }
                    return
                }
                // a waiting find (9.6), quick stamping off: its review opens instead of the card
                if !head.quickStamp, UploadState.shared.waits(i) { UploadState.shared.openReview(water: water, map: map); return }
                // QUICK STAMPING (Part 4.7): the tap toggles the stamp at once, no card
                if head.quickStamp { Self.quickStamp(i, map: map); return }
                // the tap that put the book away opens no card (one press, one job)
                guard !BookState.shared.isOpen, CACurrentMediaTime() - BookState.shared.closedAt > 0.4 else { return }
                CardState.shared.open(i, at: p, map: map, water: water)
            }
            // leaving a tab ends quick stamping too (3.6)
            water.onTabChange = { [head] in head.quickStamp = false }
            water.onMapAgain = { [head] in
                UploadState.shared.close()
                head.searching = false
                head.toolsOpen = false
                head.putAway()
            }
            // the text input system set up now, not on the first search (Prewarm)
            DispatchQueue.main.async { Prewarm.textInput() }
        }
        .task {
            await map.load()
            // finds left waiting at the last review are darkened again (9.6)
            UploadState.shared.restoreWaiting(map: map)
            // the time zones' shapes read once in the background, so the first upload's days don't wait for them (D13)
            Task.detached(priority: .utility) { _ = ZoneShapes.shared.zone(lat: 0, lon: 0) }
            // the flags of the places you have stamped or wished, drawn ahead for the rows that show them (D14)
            if let w = map.world { Flags.prewarm(map.stamped.union(map.wished).map { w.places[$0].id.lowercased() }) }
            // the system ended the app in the background: everything back as it was, under the loading screen
            if DeepLink.waiting == nil { restoreSession() }
            // a link that opened the app: its flight runs under the loading screen, which lifts once it has landed
            if let url = DeepLink.waiting {
                DeepLink.waiting = nil
                if await DeepLink.open(url, map: map, close: {}) { try? await Task.sleep(for: .milliseconds(850)) }
            }
            // the map's first frame drawn under the loading screen, then the screen lifts away
            try? await Task.sleep(for: .milliseconds(80))
            #if DEBUG
            NSLog("wya launch: map ready, lifting at %.3f s", CACurrentMediaTime() - Launch.startTime)
            #endif
            withAnimation(Motion.chrome) { launch.reveal = 1 } completion: {
                launch.done = true
                launch.settled = true
                // the start credit once all is at rest (A1.20)
                water.showCredit()
                // the first-time hints, once nothing has been touched for 1.2 s (A3.15)
                Hints.shared.start(water: water, head: head)
            }
        }
        // MAP SETTINGS ARE THE WATER (Part 5.2): the gear out opens them in the water; the gear back closes them; a pull
        // that leaves the water below 50% closes them (A5.2)
        .onChange(of: head.settingsOpen) { _, open in
            if open { closeCard(); water.openSettings() } else { water.closeSettings() }
        }
        // any control of the head closes the card first (and Details over it), keeping their changes (Part 4.2.3)
        .onChange(of: head.searching) { _, v in if v { closeCard() } }
        // a shake undoes the store's last step (Part 3.10)
        .modifier(ShakeToUndo())
        // a continent follows the sheet (A1.16)
        .onChange(of: water.form().top) { _, t in if !side.on { map.sheetMoved(top: t) } }
        // the session written as it changes; the camera 0.5 s after it last moved (19.2)
        .onChange(of: map.restVersion) { _, _ in saveSession(after: 0.5) }
        .onChange(of: water.stop) { _, _ in saveSession(after: 0) }
        .onChange(of: map.locked) { _, _ in saveSession(after: 0) }
        .onChange(of: head.mode) { _, _ in saveSession(after: 0) }
        .onChange(of: map.continent) { _, _ in saveSession(after: 0.5) }
        .onChange(of: tab) { _, _ in saveSession(after: 0) }
        .onChange(of: head.toolsOpen) { _, v in if v { closeCard() } else { BookState.shared.close() } }
        .onChange(of: water.stop) { _, s in
            if head.settingsOpen, s == .quarter || s == .closed { head.closeSettings() }
            if DetailsState.shared.isOpen || VerifyState.shared.isOpen, water.stampedList {
                // Details or Verify opened from the list: a pull down closes them, back to the list at full (A4.21
                // reversed)
                if s != .full {
                    DetailsState.shared.close(water: water); VerifyState.shared.close(water: water); water.go(.full)
                }
            } else if water.stampedList, s != .full {
                // the list pulled down: it goes, the water stays where the pull left it (4.6.3)
                water.closeList(back: false)
            } else if DetailsState.shared.isOpen, s == .quarter || s == .closed {
                // Details pulled down below 50% close and keep (4.4.1)
                DetailsState.shared.close(water: water)
            } else if VerifyState.shared.isOpen, s == .quarter || s == .closed {
                // Verify pulled down: back to the card (4.5.1)
                VerifyState.shared.close(water: water)
            }
        }
    }

    /// a link closes everything transient as a tab change does (the AI in use stays)
    private func putAwayForLink() {
        Sideways.shared.leave(feel: false)
        closeCard()
        head.searching = false
        head.toolsOpen = false
        head.closeSettings()
        water.closeList(back: false)
    }

    /// THE MAP, turned sideways about the screen's centre (1.11): portrait size at rest, the diagonal's square while it
    /// turns (no corner ever empty), landscape size at rest sideways; the camera's centre stays the screen's centre,
    /// so a size change shows the same picture
    private var sidewaysMap: some View {
        let L = water.layout
        let D = (L.W * L.W + L.H * L.H).squareRoot().rounded(.up)
        let w = side.square ? D : (side.landscape ? L.H : L.W)
        let h = side.square ? D : (side.landscape ? L.W : L.H)
        return MapLayer(controller: map)
            .frame(width: w, height: h)
            .rotationEffect(.degrees(side.angle))
            .position(x: L.W / 2, y: L.H / 2)
    }

    private struct Session: Codable {
        var tab: Int; var mode: Int; var cont: String?; var x: Double; var y: Double; var k: Double; var stop: Int; var lock: Bool
    }
    private func saveSession(after d: Double) {
        sessionWrite?.cancel()
        sessionWrite = Task { @MainActor in
            if d > 0 { try? await Task.sleep(for: .seconds(d)) }
            guard !Task.isCancelled, map.ready, !side.on else { return }
            // a stop the sheet only passes through for a moment (the upload, a list) is kept as where it rests
            let s = Session(tab: tab, mode: head.mode.rawValue, cont: map.continent, x: map.c.x, y: map.c.y, k: map.k,
                            stop: water.stop.rawValue, lock: map.locked)
            if let d = try? JSONEncoder().encode(s), let t = String(data: d, encoding: .utf8) { session = t }
        }
    }
    private func restoreSession() {
        guard !session.isEmpty, let s = try? JSONDecoder().decode(Session.self, from: Data(session.utf8)) else { return }
        tab = s.tab
        head.mode = HeadState.Mode(rawValue: s.mode) ?? .countries
        map.locked = s.lock
        if let c = s.cont { map.show(continent: c) } else { map.restore(c: SIMD2(s.x, s.y), k: s.k) }
        if let st = SheetStop(rawValue: s.stop), st != water.stop { water.go(st) }
        #if DEBUG
        NSLog("wya session restored: tab %d mode %d continent %@ k %.2f stop %d lock %d", s.tab, s.mode, s.cont ?? "none", s.k, s.stop, s.lock ? 1 : 0)
        #endif
    }

    private func enterSideways() {
        Sideways.shared.enter(water: water, head: head, map: map) { closeCard() }
    }

    private func closeCard() {
        BookState.shared.close()
        DetailsState.shared.close(water: water)
        VerifyState.shared.close(water: water)
        CardState.shared.close(map: map)
    }

    /// QUICK STAMPING (Part 4.7): a tap toggles the place's stamp at once (a wished place becomes stamped in one
    /// write); the colour changes in one frame as every colour does (the book's fill front is not
    /// built); stamp or lift haptic (no sound); the undo drop rises each time (one tap, one undo step); VoiceOver
    /// says what happened. The record's source is `quick`.
    @MainActor static func quickStamp(_ i: Int, map: MapController) {
        guard let w = map.world, i >= 0, i < w.places.count else { return }
        let p = w.places[i]
        let key = PlaceKey.country(p.id)
        let stamped = MarkStore.shared.state(key).stamped
        if stamped { Feel.lift() } else { Feel.stamp() }
        Task {
            if stamped { await MarkStore.shared.unstamp(key, name: p.n) }
            else { await MarkStore.shared.stamp(key, name: p.n, source: .quick) }
            UIAccessibility.post(notification: .announcement, argument: "\(p.n) \(stamped ? "unstamped" : "stamped")")
        }
    }
}
