import SwiftUI
import MapKit

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
                        // no zoom column under Regions' menu (6.3): it slides off the right edge and back
                        .offset(x: water.regions ? 90 : 0)
                        .animation(Motion.chrome, value: water.regions)
                }

                // under the water: the space's shaders set up once, unseen (Prewarm.swift)
                ShaderPrewarm()
                    .position(x: water.layout.W / 2, y: water.layout.capsule.midY)

                // the stamping card: over the map, under the sheet's glass and the head (Part 4.2)
                StampCard(map: map, water: water)
                // the region card (6.7): over the map, standing on the 25% water
                RegionCard(map: map, water: water)
                // the passport book from the plus's passport tool (Part 4.3)
                PassportBook(water: water, map: map)

                // a place's page (Part 16): over the map, under the water (closed to its tab capsule while the page is up:
                // the capsule stays at the bottom as on every pushed page in iOS, 16.3) and under the head (A16.1)
                PlacePageView(map: map, water: water)

                WaterView(water: water, map: map, tab: $tab)
                    .offset(y: side.chromeOut ? water.layout.H - water.layout.capsule.minY + 24 : 0)

                if !Perf.shared.off.contains("head") {
                    HeadView(map: map, water: water, head: head)
                        .offset(y: side.chromeOut ? -(water.layout.headBottom + 24) : 0)
                }
                if side.on { SidewaysMarks(map: map, L: water.layout) }
                #if DEBUG
                // the colour picker's test host (Part 15; its real hosts come with Pins)
                PickerTestHost(L: water.layout)
                // the pins review (8.3), over the map or Apple's
                PinReviewHost(L: water.layout)
                #endif
                // the sheet's top read in a view of its own, so its every frame re-runs only this, not the whole screen
                SheetWatch(water: water, map: map)
                // the open region map's country and level written into the session as they change
                Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
                    .onChange(of: regionKey) { _, _ in saveSession(after: 0) }
                    // HISTORY (Part 13): the tool on draws the journey (Countries for now); nothing dated, it refuses
                    .onChange(of: head.history) { _, on in
                        if on {
                            if !map.historyOn() { Feel.refuse(); head.history = false }
                        } else { map.historyOff(fast: head.searching) }
                    }
                    // a continent picked: the line runs through its stops only (13.4's states)
                    .onChange(of: map.continent) { _, _ in
                        if head.history, !map.historyOn() { head.history = false }
                    }
                    // the upload from Regions: once finding starts the wheel turns to Countries by itself, because the
                    // review always opens on the Countries map (6.3's connections, A6.4)
                    .onChange(of: UploadState.shared.phase) { _, ph in
                        if ph == .finding, head.mode == .regions { head.quickStamp = false; head.mode = .countries; Feel.notch() }
                    }

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
                // the map's size from the layout too, so a session restored before the map view's first layout frames
                // on this phone's size, not the placeholder's (the map view sets it again from its own bounds)
                if !Sideways.shared.on { map.view = CGSize(width: l.W, height: l.H) }
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
            water.head = head
            RegionsMenuModel.shared.onPick = { r in openRegion(r.place) }
            RegionsMenuModel.shared.openDirect = { i in closeCard(); openRegion(i) }
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
                // anything this touch closes: that press opens no hold menu
                if head.settingsOpen || BookState.shared.isOpen || DetailsState.shared.isOpen || VerifyState.shared.isOpen
                    || CardState.shared.isOpen || RegionCardState.shared.isOpen || (water.upload && [.choosing, .words].contains(UploadState.shared.phase)) {
                    map.touchClosedAt = CACurrentMediaTime()
                }
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
                else { CardState.shared.close(map: map); RegionCardState.shared.close(map: map) }
            }
            // a finger in the water is using Details or Verify when they are up; otherwise it closes the card
            water.onTouch = { [head, map] in
                Hints.shared.touched()
                head.putAwayAI()
                BookState.shared.close()
                if !DetailsState.shared.isOpen && !VerifyState.shared.isOpen { CardState.shared.close(map: map); RegionCardState.shared.close(map: map) }
            }
            // a confirmed tap on a place opens its stamping card (Part 4.2.1)
            map.onPlaceTap = { [head, map, water] i, p in
                // the upload sheet up: finding owns the map's presses, a tap while choosing has closed it (9.3, 9.4), and
                // at the review a found country's tap drops or keeps it (9.5)
                if water.upload { _ = UploadState.shared.tap(i); return }
                guard !map.locked else { return }
                // the tap that closed search opens nothing (one press, one job)
                guard CACurrentMediaTime() - head.mapClosedSearchAt > 0.6 else { return }
                // the region map: its regions answer (6.5); while the list is up or a country is still loading, nothing
                if map.regionTowns { if map.townPressed != nil { townTapped() }; return }
                if map.regionScene != nil { regionTapped(); return }
                if head.mode == .regions { return }
                // the Places map (7.4, the old app's system): a town of the open country answers; any other country opens
                if map.placesMode {
                    if map.ownPressed != nil { ownTapped() }
                    else if map.thingPressed != nil { thingTapped() }
                    else if map.townPressed != nil { townTapped() }
                    else if map.placeOpen != i { closeCard(); map.openPlace(i) }
                    // quick add on the open country's empty land: your own place there (7.8, A7.11)
                    else if head.quickStamp { map.makeOwnPlace(at: p) }
                    return
                }
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
            // APPLE'S HOLD MENU ON A COUNTRY (Part 11.5)
            map.menuFor = { [map, water, head] i, p in Self.countryMenu(i, at: p, map: map, water: water, head: head) }
            // leaving a tab ends quick stamping too (3.6)
            water.onTabChange = { [head] in head.quickStamp = false }
            water.currentMode = { [head] in head.mode.rawValue }
            water.onModePick = { [head] m in
                guard m != head.mode.rawValue, let mode = HeadState.Mode(rawValue: m) else { return }
                // a new mode starts fresh, quick stamping off (3.1a, 4.7), as the wheel does
                head.quickStamp = false
                head.mode = mode
                Feel.notch()
            }
            water.onMapAgain = { [head] in
                if head.mode == .regions { backToRegionsList() }
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
        // the session written as it changes; the camera 0.5 s after it last moved (19.2)
        .onChange(of: map.restVersion) { _, _ in saveSession(after: 0.5) }
        .onChange(of: water.stop) { _, _ in saveSession(after: 0) }
        .onChange(of: map.locked) { _, _ in saveSession(after: 0) }
        .onChange(of: head.mode) { _, _ in saveSession(after: 0) }
        // THE MODES (6.1): Regions always restarts at its selection menu (2 Oct: "it should restart"), the camera
        // flying to the world home under it; leaving it, the water goes to 25%
        .onChange(of: head.mode) { old, new in modeChanged(from: old, to: new) }
        .onChange(of: water.menuShown, initial: true) { _, v in head.filtersMenu = v }
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

    /// A6.5 entering Regions' menu (Regions always restarts there), and leaving Regions for another mode: the regions
    /// go, the camera stays where it is (6.1 rule 4)
    private func modeChanged(from old: HeadState.Mode, to new: HeadState.Mode) {
        // 7.4: the Places map's towns come and go with the mode (Regions' towns level is left first, while Places is
        // still off, so its open country goes with it)
        if old == .regions { map.leaveRegionTowns() }
        map.placesMode = new == .places
        if new == .places || old == .places { closeCard() }
        if new == .regions {
            closeCard()
            water.closeList(back: false)
            map.closeRegions()
            map.regionsMenu = true
            // A6.14: straight into a country (a country's "Open its region map"), never through the list or the world
            if let i = Self.directRegion {
                let row = Self.directRow, focus = Self.directFocus
                Self.directRegion = nil; Self.directRow = nil; Self.directFocus = nil
                openRegion(i, row: row, focus: focus)
                return
            }
            water.openMenu()
            map.goHome()
        } else if old == .regions {
            closeCard()
            map.regionsMenu = false
            map.closeRegions()
            water.closeMenu(to: .quarter)
        }
    }
    /// A6.7 A COUNTRY PICKED FROM THE LIST: the list goes down with the water to 25% while the camera flies into the
    /// country and its regions draw in
    private func openRegion(_ i: Int, row: Int? = nil, focus: String? = nil) {
        head.searching = false
        head.toolsOpen = false
        water.closeMenu(to: .quarter)
        map.openRegions(i, row: row, focus: focus)
    }
    /// THE MAP TAB IN REGIONS (20 Oct answer 15): back to the list, the regions folding away, the world under it
    private func backToRegionsList() {
        closeCard()
        map.closeRegions()
        water.openMenu()
        map.goHome()
    }
    /// YOUR OWN PLACE TAPPED (7.8): quick add toggles its stamp; otherwise its card ("Your place in Germany")
    private func ownTapped() {
        guard let id = map.ownPressed, let o = OwnPlaces.shared.place(id), let w = map.world, let place = w.placeIndex[o.cc] else { return }
        guard head.quickStamp else {
            RegionCardState.shared.open(o.key, name: o.name, parents: "Your place in \(w.places[place].n)", place: place, map: map)
            return
        }
        let stamped = MarkStore.shared.state(o.key).stamped
        if stamped { Feel.lift() } else { Feel.stamp() }
        Task {
            if stamped { await MarkStore.shared.unstamp(o.key, name: o.name) }
            else { await MarkStore.shared.stamp(o.key, name: o.name, cc: o.cc, source: .quick) }
        }
    }

    /// A THING TAPPED (7.4, 7.7): quick add stamps it with its region chain and country (or unstamps it); otherwise its
    /// card from the water
    private func thingTapped() {
        // a collection's place (its map up): the card with its stop's line, or quick add
        if let cid = map.placesCollection, let id = map.thingPressed,
           let it = CollectionStore.shared.collection(cid)?.items.first(where: { $0.id == id }), let w = map.world, let place = w.placeIndex[it.cc] {
            defer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if map.thingPressed == id { map.thingPressed = nil } } }
            let line = CollectionStore.line(it)
            guard head.quickStamp else {
                RegionCardState.shared.open(it.key, name: it.name, parents: line.isEmpty ? w.places[place].n : line, place: place, map: map,
                                            day: it.date)
                return
            }
            // quick add (D7): a stop that has been is stamped with its day as a visit; one still to come is wished with
            // its day (a second tap takes either back)
            let st = MarkStore.shared.state(it.key)
            let upcoming = CollectionStore.upcoming(it.date)
            if st.stamped || (upcoming && st.wished) { Feel.lift() } else if upcoming { Feel.tap() } else { Feel.stamp() }
            Task {
                if st.stamped { await TownStamps.unstamp(it.key, name: it.name, cc: it.cc) }
                else if upcoming {
                    if st.wished { await MarkStore.shared.unwish(it.key, name: it.name) }
                    else { await MarkStore.shared.wish(it.key, name: it.name, cc: it.cc, source: .quick, when: it.date) }
                } else {
                    await TownStamps.stamp(it.key, name: it.name, cc: it.cc, source: .quick, place: place, at: it.at,
                                           day: CollectionStore.pastDay(it.date))
                }
            }
            return
        }
        // (the open country's thing, or one of the countries in view close in)
        guard let id = map.thingPressed, let (cc, t) = ThingStore.shared.thing(id),
              let w = map.world, let place = w.placeIndex[cc] else { return }
        defer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if map.thingPressed == id { map.thingPressed = nil } } }
        guard head.quickStamp else {
            let line = t.line.isEmpty ? w.places[place].n : t.line.prefix(1).uppercased() + t.line.dropFirst()
            RegionCardState.shared.open(t.key, name: t.name, parents: line, place: place, map: map)
            return
        }
        let stamped = MarkStore.shared.state(t.key).stamped
        if stamped { Feel.lift() } else { Feel.stamp() }
        Task {
            if stamped { await TownStamps.unstamp(t.key, name: t.name, cc: cc) }
            else { await TownStamps.stamp(t.key, name: t.name, cc: cc, source: .quick, place: place, at: t.at) }
            UIAccessibility.post(notification: .announcement, argument: "\(t.name) \(stamped ? "unstamped" : "stamped")")
        }
    }

    /// A TOWN TAPPED (7.4): quick add stamps it with its country (or unstamps it); otherwise its card from the water
    private func townTapped() {
        guard let t = map.townPressed, let sc = map.townScenes[t.cc], t.i < sc.towns.count,
              let w = map.world, let place = w.placeIndex[t.cc] ?? w.placeIndex[t.cc.uppercased()] else { return }
        let town = sc.towns[t.i]
        guard head.quickStamp else {
            let country = w.places[place].n
            RegionCardState.shared.open(town.key, name: town.name, parents: town.region.isEmpty ? country : "\(town.region), \(country)",
                                        place: place, map: map)
            return
        }
        let stamped = MarkStore.shared.state(town.key).stamped
        if stamped { Feel.lift() } else { Feel.stamp() }
        Task {
            if stamped { await TownStamps.unstamp(town.key, name: town.name, cc: t.cc) }
            else { await TownStamps.stamp(town.key, name: town.name, cc: t.cc, source: .quick, place: place, at: sc.at[t.i]) }
            UIAccessibility.post(notification: .announcement, argument: "\(town.name) \(stamped ? "unstamped" : "stamped")")
        }
    }

    /// A REGION TAPPED (6.5): with quick stamping on it is stamped or unstamped at once; otherwise its card (6.7)
    private func regionTapped() {
        guard let sc = map.regionScene, let u = map.regionPressed, u < sc.unitIDs.count else { return }
        let key = PlaceKey(.region, sc.unitIDs[u])
        let name = sc.unitNames[u]
        guard head.quickStamp else {
            // the card from the water (6.7); its parents' line: the country at the first level
            let country = map.world.map { $0.places[sc.place].n } ?? ""
            RegionCardState.shared.open(key, name: name, parents: country, place: sc.place, map: map)
            return
        }
        let stamped = MarkStore.shared.state(key).stamped
        if stamped { Feel.lift() } else { Feel.stamp() }
        Task {
            // stamped with every parent above it (A6.12); unstamped with the parents stamped only through it
            if stamped { await RegionStamps.unstamp(u, in: sc) }
            else { await RegionStamps.stamp(u, in: sc, source: .quick) }
            UIAccessibility.post(notification: .announcement, argument: "\(name) \(stamped ? "unstamped" : "stamped")")
        }
    }

    private var regionKey: Int { (map.regionScene?.place ?? -1) * 64 + (map.regionScene?.row ?? 0) }

    /// a country to open in Regions without the list (A6.14), set just before the wheel turns there
    @MainActor static var directRegion: Int?
    @MainActor static var directRow: Int?
    /// and the region to show there (a region found by search outside Regions)
    @MainActor static var directFocus: String?
    /// A6.14 from anywhere: the wheel turns to Regions and the country opens; already in Regions, it opens from there
    @MainActor static func openRegionMap(_ i: Int, head: HeadState, row: Int? = nil, focus: String? = nil, map: MapController? = nil) {
        if head.mode == .regions {
            RegionsMenuModel.shared.openDirect?(i)
            if let focus, let map { map.openRegions(i, row: row, focus: focus) }
            return
        }
        directRegion = i; directRow = row; directFocus = focus
        head.quickStamp = false
        head.mode = .regions
        Feel.notch()
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
        /// Regions: the open country (its id) and its level's row (6.1.1 rule 5: a cold launch opens it again)
        var rp: String? = nil; var rr: Int? = nil
    }
    private func saveSession(after d: Double) {
        sessionWrite?.cancel()
        sessionWrite = Task { @MainActor in
            if d > 0 { try? await Task.sleep(for: .seconds(d)) }
            guard !Task.isCancelled, map.ready, !side.on else { return }
            // a stop the sheet only passes through for a moment (the upload, a list) is kept as where it rests
            var s = Session(tab: tab, mode: head.mode.rawValue, cont: map.continent, x: map.c.x, y: map.c.y, k: map.k,
                            stop: water.stop.rawValue, lock: map.locked)
            if let sc = map.regionScene, let w = map.world { s.rp = w.places[sc.place].id; s.rr = sc.row }
            if let d = try? JSONEncoder().encode(s), let t = String(data: d, encoding: .utf8) { session = t }
        }
    }
    private func restoreSession() {
        guard !session.isEmpty, let s = try? JSONDecoder().decode(Session.self, from: Data(session.utf8)) else { return }
        tab = s.tab
        // Regions with a country open: the mode opens that country at its level straight (6.1.1), not the list
        if s.mode == HeadState.Mode.regions.rawValue, let rp = s.rp, let i = map.world?.placeIndex[rp] {
            Self.directRegion = i; Self.directRow = s.rr
        }
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
        RegionCardState.shared.close(map: map)
    }

    /// A COUNTRY'S HOLD MENU (11.5): Stamp or Unstamp, Wish or Unwish | Details, Verify | Show in passport, Share. Rows
    /// that can't be used now are unavailable (Apple greys them in place). With a card, the book, Details or Verify up,
    /// or Map settings open, the hold only closes them (one press, one job; MapController.touchClosedAt). Not here yet: Lived here, Open
    /// its page, Open its region map, Its places, Add to a list, Add to a plan (their parts are not built).
    /// the disputes that are whole places (Taiwan, Kosovo, Abkhazia, Western Sahara ...): the place's id -> the dispute's
    @MainActor static let placeDisputes: [String: String] = {
        struct D: Decodable { let id: String; let entity: String? }
        struct F: Decodable { let list: [D] }
        guard let u = Bundle.main.url(forResource: "disputes", withExtension: "json"), let d = try? Data(contentsOf: u),
              let f = try? JSONDecoder().decode(F.self, from: d) else { return [:] }
        var out: [String: String] = [:]
        for x in f.list { if let e = x.entity, out[e] == nil { out[e] = x.id } }
        return out
    }()

    /// Asked as the press starts, so it changes nothing itself (the press's own touch does the closing, onTouch).
    /// Sideways (1.11), with search open, or on the press that closed search: no menu.
    @MainActor static func countryMenu(_ i: Int, at p: CGPoint, map: MapController, water: Water, head: HeadState) -> UIMenu? {
        guard let w = map.world, i >= 0, i < w.places.count else { return nil }
        let now = CACurrentMediaTime()
        if Sideways.shared.on || head.searching || now - head.mapClosedSearchAt < 0.6 || now - map.touchClosedAt < 0.6 { return nil }
        // PLACES with a country open (11.5's Places menu): a town held is that town's own menu, never its country's
        // (30 Oct 23:55: "You're long pressing Frankfurt, so you get the page for Frankfurt"); empty land of the open
        // country: no menu yet (its land rows, Add a place here · What's here? · Copy coordinates, wait for 7.8)
        // Places close in with no country open: a town or thing of the countries in view held is its own menu
        if map.placesMode, map.placeOpen == nil, !map.nearbyTowns.isEmpty {
            if let t = map.thingHit(at: p), let cc = ThingStore.shared.thing(t.id)?.cc, let pi = w.placeIndex[cc] {
                map.townPressed = nil; map.thingPressed = t.id
                return thingMenu(t, cc: cc, place: pi, map: map, water: water)
            }
            if let t = map.townHit(at: p), let sc = map.townScenes[t.cc], t.i < sc.towns.count, let pi = w.placeIndex[t.cc] {
                map.townPressed = t
                return townMenu(sc.towns[t.i], cc: t.cc, place: pi, at: p, map: map, water: water, head: head)
            }
        }
        if map.placesMode || map.regionTowns, let open = map.placeOpen {
            // a thing held: its own menu (its marks sit over the towns)
            if map.placesMode, let t = map.thingHit(at: p), let cc = map.placeOpenID {
                map.townPressed = nil
                map.thingPressed = t.id
                return thingMenu(t, cc: cc, place: open, map: map, water: water)
            }
            if let t = map.townHit(at: p), let sc = map.townScenes[t.cc], t.i < sc.towns.count {
                map.townPressed = t
                return townMenu(sc.towns[t.i], cc: t.cc, place: open, at: p, map: map, water: water, head: head)
            }
            map.townPressed = nil
            // the open country's own land: no menu yet; another country keeps its own menu
            if i == open { return nil }
        }
        // the region map: the region's own menu (11.5's Regions menu)
        if let sc = map.regionScene {
            guard let u = map.regionUnit(at: p), u < sc.unitIDs.count else { return nil }
            map.regionPressed = u
            return regionMenu(u, in: sc, at: p, map: map, water: water)
        }
        // still up (the press's touch may not have reached the map yet): this press only closes it
        if CardState.shared.isOpen || BookState.shared.isOpen || DetailsState.shared.isOpen || VerifyState.shared.isOpen
            || head.settingsOpen { return nil }
        // THE REVIEW (9.5): a found country's menu is Keep or Drop · Its dates · Show in the list; other places none
        if water.upload {
            let u = UploadState.shared
            guard u.reviewing(i), let row = u.rows.first(where: { $0.place == i }) else { return nil }
            let keep = UIAction(title: row.dropped ? "Keep" : "Drop", attributes: row.dropped ? [] : .destructive) { _ in
                _ = u.tap(i)
            }
            let dates = UIAction(title: "Its dates", attributes: row.trips.isEmpty ? .disabled : []) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { u.showInList(row.id) }
            }
            let list = UIAction(title: "Show in the list") { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if water.stop == .quarter || water.stop == .closed { water.go(.half) }
                }
            }
            return UIMenu(title: row.name, children: [UIMenu(options: .displayInline, children: [keep, dates, list])])
        }
        let pl = w.places[i]
        let key = PlaceKey.country(pl.id)
        let st = MarkStore.shared.state(key)
        // anything that moves a big thing starts once Apple's menu has closed
        let after = { (f: @escaping () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f) }
        let stamp = UIAction(title: st.stamped ? "Unstamp" : "Stamp", attributes: st.stamped ? .destructive : []) { _ in
            quickStamp(i, map: map)
        }
        let wish = UIAction(title: st.wished ? "Unwish" : "Wish", attributes: st.stamped ? .disabled : []) { _ in
            Feel.tap()
            Task {
                if st.wished { await MarkStore.shared.unwish(key, name: pl.n) } else { await MarkStore.shared.wish(key, name: pl.n) }
            }
        }
        let details = UIAction(title: "Details", attributes: st.stamped || st.wished ? [] : .disabled) { _ in
            after {
                CardState.shared.open(i, at: p, map: map, water: water)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    CardState.shared.heldTop = water.form().top
                    DetailsState.shared.open(key, name: pl.n, water: water)
                }
            }
        }
        let verify = UIAction(title: "Verify", attributes: st.stamped ? [] : .disabled) { _ in
            after {
                CardState.shared.open(i, at: p, map: map, water: water)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    CardState.shared.heldTop = water.form().top
                    VerifyState.shared.open(key, name: pl.n, place: i, water: water)
                }
            }
        }
        // OPEN ITS PAGE (11.5, Part 16): the page grows from the country's box on screen (A16.1)
        let page = UIAction(title: "Open its page") { _ in
            after { PlacePageState.shared.open(key, name: pl.n, country: pl.id, from: map.screenRect(of: i)) }
        }
        // OPEN ITS REGION MAP (11.5, A6.14): unavailable where the place has no regions
        let regionMap = UIAction(title: "Open its region map",
                                 attributes: RegionCatalog.shared.first(pl.id.lowercased()) == nil ? .disabled : []) { _ in
            after { Self.openRegionMap(i, head: head) }
        }
        let passport = UIAction(title: "Show in passport", attributes: st.stamped ? [] : .disabled) { _ in
            after { BookState.shared.open(showing: pl.id) }
        }
        let share = UIAction(title: "Share") { _ in
            after {
                // offline for now (no page links yet): the app's own link and the name (11.7)
                var items: [Any] = [pl.n]
                if let u = URL(string: "wya://country/\(pl.id)") { items.append(u) }
                let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
                let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
                var top = root
                while let next = top?.presentedViewController { top = next }
                top?.present(vc, animated: true)
            }
        }
        var sections: [UIMenuElement] = []
        // a waiting find (9.6, outside a review): its review first
        if UploadState.shared.waits(i) {
            sections.append(UIMenu(options: .displayInline, children: [UIAction(title: "Open the review") { _ in
                after { UploadState.shared.openReview(water: water, map: map) }
            }]))
        }
        sections += [
            UIMenu(options: .displayInline, children: [stamp, wish]),
            UIMenu(options: .displayInline, children: [details, verify]),
            UIMenu(options: .displayInline, children: [page, regionMap]),
            UIMenu(options: .displayInline, children: [passport, share]),
        ]
        // A DISPUTED PIECE (Crimea, the Kashmir pieces) or a disputed place (Taiwan, Kosovo): Whose borders here? opens Map settings at 50% on the Disputes
        // page at that piece's row; the map does not fly
        if let piece = map.piece(at: p) ?? Self.placeDisputes[pl.id] {
            sections.append(UIMenu(options: .displayInline, children: [UIAction(title: "Whose borders here?") { _ in
                after {
                    head.openSettings()
                    let nav = SettingsNav.shared
                    nav.path = ["disputes"]; nav.openDispute = piece; nav.show = "dispute:" + piece
                }
            }]))
        }
        return UIMenu(title: pl.n, children: sections)
    }

    /// A TOWN'S HOLD MENU (11.5, Places mode): Apple's menu with the town's own name (29 Oct 22:13, 11.2), every row
    /// about the town: Stamp or Unstamp, Wish or Unwish | Details, Verify (its card, then that sheet) | Directions (Apple
    /// Maps) | Share. Its page, Drop a pin here, Add to a list, Add to a plan and Report a wrong place wait for their parts
    /// (16, 8, 20); they are left out rather than shown dead.
    @MainActor static func townMenu(_ town: Town, cc: String, place: Int, at p: CGPoint, map: MapController, water: Water,
                                    head: HeadState) -> UIMenu {
        let key = town.key
        let st = MarkStore.shared.state(key)
        let after = { (f: @escaping () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f) }
        let country = map.world.map { $0.places[place].n } ?? ""
        let parents = town.region.isEmpty ? country : "\(town.region), \(country)"
        let stamp = UIAction(title: st.stamped ? "Unstamp" : "Stamp", attributes: st.stamped ? .destructive : []) { _ in
            if st.stamped { Feel.lift() } else { Feel.stamp() }
            Task {
                if st.stamped { await TownStamps.unstamp(key, name: town.name, cc: cc) }
                else {
                    await TownStamps.stamp(key, name: town.name, cc: cc, source: .hand, place: place,
                                           at: EqualEarth.project(lon: town.lon, lat: town.lat))
                }
            }
        }
        let wish = UIAction(title: st.wished ? "Unwish" : "Wish", attributes: st.stamped ? .disabled : []) { _ in
            Feel.tap()
            Task {
                if st.wished { await MarkStore.shared.unwish(key, name: town.name) }
                else { await MarkStore.shared.wish(key, name: town.name, cc: cc) }
            }
        }
        let details = UIAction(title: "Details", attributes: st.stamped || st.wished ? [] : .disabled) { _ in
            after {
                RegionCardState.shared.open(key, name: town.name, parents: parents, place: place, map: map)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { DetailsState.shared.open(key, name: town.name, water: water) }
            }
        }
        let verify = UIAction(title: "Verify", attributes: st.stamped ? [] : .disabled) { _ in
            after {
                RegionCardState.shared.open(key, name: town.name, parents: parents, place: place, map: map)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    VerifyState.shared.open(key, name: town.name, place: place, water: water)
                }
            }
        }
        // OPEN ITS PAGE (16): the town's own page, growing from its shape on screen (A16.1)
        let page = UIAction(title: "Open its page") { _ in
            let from = map.townScenes[cc].flatMap { s in s.index[key.id].map { map.screenRect(s.box($0)) } } ?? map.screenRect(of: place)
            after { PlacePageState.shared.open(key, name: town.name, what: "Town in \(parents)", country: cc, from: from) }
        }
        let directions = UIAction(title: "Directions") { _ in
            let item = MKMapItem(location: CLLocation(latitude: town.lat, longitude: town.lon), address: nil)
            item.name = town.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        }
        let share = UIAction(title: "Share") { _ in
            after {
                let vc = UIActivityViewController(activityItems: ["\(town.name), \(country)"], applicationActivities: nil)
                let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
                var top = root
                while let n = top?.presentedViewController { top = n }
                top?.present(vc, animated: true)
            }
        }
        return UIMenu(title: town.name, children: [
            UIMenu(options: .displayInline, children: [stamp, wish]),
            UIMenu(options: .displayInline, children: [details, verify]),
            UIMenu(options: .displayInline, children: [page, directions]),
            UIMenu(options: .displayInline, children: [share]),
        ])
    }

    /// A THING'S HOLD MENU (11.5's town or thing menu): Stamp or Unstamp, Wish or Unwish | Details, Verify | Open its
    /// page, Directions | Share
    @MainActor static func thingMenu(_ t: ThingStore.Thing, cc: String, place: Int, map: MapController, water: Water) -> UIMenu {
        let key = t.key
        let st = MarkStore.shared.state(key)
        let after = { (f: @escaping () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f) }
        let country = map.world.map { $0.places[place].n } ?? ""
        let line = t.line.isEmpty ? country : t.line.prefix(1).uppercased() + t.line.dropFirst()
        let ll = EqualEarth.unproject(SIMD2(Double(t.at.x), Double(t.at.y)))
        let stamp = UIAction(title: st.stamped ? "Unstamp" : "Stamp", attributes: st.stamped ? .destructive : []) { _ in
            if st.stamped { Feel.lift() } else { Feel.stamp() }
            Task {
                if st.stamped { await TownStamps.unstamp(key, name: t.name, cc: cc) }
                else { await TownStamps.stamp(key, name: t.name, cc: cc, source: .hand, place: place, at: t.at) }
            }
        }
        let wish = UIAction(title: st.wished ? "Unwish" : "Wish", attributes: st.stamped ? .disabled : []) { _ in
            Feel.tap()
            Task {
                if st.wished { await MarkStore.shared.unwish(key, name: t.name) }
                else { await MarkStore.shared.wish(key, name: t.name, cc: cc) }
            }
        }
        let details = UIAction(title: "Details", attributes: st.stamped || st.wished ? [] : .disabled) { _ in
            after {
                RegionCardState.shared.open(key, name: t.name, parents: line, place: place, map: map)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { DetailsState.shared.open(key, name: t.name, water: water) }
            }
        }
        let verify = UIAction(title: "Verify", attributes: st.stamped ? [] : .disabled) { _ in
            after {
                RegionCardState.shared.open(key, name: t.name, parents: line, place: place, map: map)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { VerifyState.shared.open(key, name: t.name, place: place, water: water) }
            }
        }
        // OPEN ITS PAGE (16): the thing's own page, growing from its mark (A16.1)
        let page = UIAction(title: "Open its page") { _ in
            let from = map.thingFrames[t.id].map { CGRect(x: $0.minX, y: $0.midY - 22, width: 44, height: 44) } ?? map.screenRect(of: place)
            after { PlacePageState.shared.open(key, name: t.name, what: line, country: cc, from: from) }
        }
        let directions = UIAction(title: "Directions") { _ in
            let item = MKMapItem(location: CLLocation(latitude: ll.lat, longitude: ll.lon), address: nil)
            item.name = t.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        }
        let share = UIAction(title: "Share") { _ in
            after {
                let vc = UIActivityViewController(activityItems: ["\(t.name), \(country)"], applicationActivities: nil)
                let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
                var top = root
                while let n = top?.presentedViewController { top = n }
                top?.present(vc, animated: true)
            }
        }
        return UIMenu(title: t.name, children: [
            UIMenu(options: .displayInline, children: [stamp, wish]),
            UIMenu(options: .displayInline, children: [details, verify]),
            UIMenu(options: .displayInline, children: [page, directions]),
            UIMenu(options: .displayInline, children: [share]),
        ])
    }

    /// A REGION'S HOLD MENU (11.5, Regions mode): Stamp or Unstamp, Wish or Unwish | Details, Verify | Go one level down |
    /// Share. Stamping stamps its parents too (A6.12). Details and Verify: the region card rises, then that sheet (6.7).
    /// Its places, its page, Add to a list and Add to a plan wait for their parts.
    @MainActor static func regionMenu(_ u: Int, in sc: RegionScene, at p: CGPoint, map: MapController, water: Water) -> UIMenu {
        let key = PlaceKey(.region, sc.unitIDs[u])
        let name = sc.unitNames[u]
        let st = MarkStore.shared.state(key)
        let after = { (f: @escaping () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f) }
        let country = map.world.map { $0.places[sc.place].n } ?? ""
        let stamp = UIAction(title: st.stamped ? "Unstamp" : "Stamp", attributes: st.stamped ? .destructive : []) { _ in
            if st.stamped { Feel.lift() } else { Feel.stamp() }
            Task {
                if st.stamped { await RegionStamps.unstamp(u, in: sc) }
                else { await RegionStamps.stamp(u, in: sc, source: .hand) }
            }
        }
        let wish = UIAction(title: st.wished ? "Unwish" : "Wish", attributes: st.stamped ? .disabled : []) { _ in
            Feel.tap()
            Task {
                if st.wished { await MarkStore.shared.unwish(key, name: name) }
                else { await MarkStore.shared.wish(key, name: name, cc: sc.id, level: sc.row) }
            }
        }
        let details = UIAction(title: "Details", attributes: st.stamped || st.wished ? [] : .disabled) { _ in
            after {
                RegionCardState.shared.open(key, name: name, parents: country, place: sc.place, map: map)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { DetailsState.shared.open(key, name: name, water: water) }
            }
        }
        let verify = UIAction(title: "Verify", attributes: st.stamped ? [] : .disabled) { _ in
            after {
                RegionCardState.shared.open(key, name: name, parents: country, place: sc.place, map: map)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    VerifyState.shared.open(key, name: name, place: sc.place, water: water)
                }
            }
        }
        // the next finer level in use, if there is one
        let used = RegionCatalog.shared.used(sc.id).map(\.row)
        let next = used.firstIndex(of: sc.row).flatMap { $0 + 1 < used.count ? used[$0 + 1] : nil }
        let down = UIAction(title: "Go one level down", attributes: next == nil ? .disabled : []) { _ in
            if let next { after { map.openRegions(sc.place, row: next) } }
        }
        // OPEN ITS PAGE (16): the region's own page, growing from its shape on screen
        let page = UIAction(title: "Open its page") { _ in
            let from = sc.box(of: u).map { map.screenRect($0) } ?? map.screenRect(of: sc.place)
            let word = RegionCatalog.shared.used(sc.id).first { $0.row == sc.row }.map { RegionsMenuModel.word($0.level.one) } ?? "region"
            let code = RegionCatalog.shared.file(sc.id, row: sc.row)?.units.first { $0.id == key.id }?.code
            after {
                PlacePageState.shared.open(key, name: name, what: "\(word.prefix(1).uppercased() + word.dropFirst()) of \(country)",
                                           country: sc.id, code: code, from: from)
            }
        }
        let share = UIAction(title: "Share") { _ in
            after {
                let vc = UIActivityViewController(activityItems: ["\(name), \(country)"], applicationActivities: nil)
                let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
                var top = root
                while let n = top?.presentedViewController { top = n }
                top?.present(vc, animated: true)
            }
        }
        return UIMenu(title: name, children: [
            UIMenu(options: .displayInline, children: [stamp, wish]),
            UIMenu(options: .displayInline, children: [details, verify]),
            UIMenu(options: .displayInline, children: [page, down]),
            UIMenu(options: .displayInline, children: [share]),
        ])
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

/// Hands the water's top to the map as the sheet moves (MapController.sheetMoved: a continent follows it). Its own view
/// so the per-frame read re-evaluates this body only.
private struct SheetWatch: View {
    let water: Water
    let map: MapController
    var body: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
            .onChange(of: water.form().top) { _, t in if !Sideways.shared.on { map.sheetMoved(top: t) } }
    }
}
