import SwiftUI

/// The water on screen: clear glass on the droplet outline, what rides inside it, and the tab capsule with its three
/// tabs, which is its own glass the whole time (the 02:09). The sheet's glass and the capsule's glass are in one
/// container, so out of the capsule
/// they are one body of water and at rest they are the capsule.
struct WaterView: View {
    let water: Water
    let map: MapController
    @Binding var tab: Int

    var body: some View {
        let f = water.form()
        let L = water.layout
        let shape = WaterShape(form: f)
        ZStack(alignment: .topLeading) {
            // THE FROST (12 Nov: fading to none as it gets smaller): one shape, its frost
            // under the clear glass, at the water's own width between capsule and sheet; none in the capsule, all of it
            // once it is the sheet, frame by frame with the water (never a switch, never a second shape)
            // (14 Nov: off. A material under the clear glass made every sheet more frosted than Apple's own sheets;
            // the sheet is the system's regular glass now, the same frost as Apple's at every size)
            if false, !Perf.shared.off.contains("sheetglass"), f.sheet > 0.001 {
                shape.fill(.thinMaterial)
                    .opacity(Double(f.sheet))
                    .frame(width: L.W, height: L.H)
                    .allowsHitTesting(false)
            }
            // the sheet's glass
            // the sheet's glass and the undo drop in one container: the drop is the water's own glass rising out of
            // its edge (Part 3.10), never glass on glass
            GlassEffectContainer(spacing: 20) {
                ZStack(alignment: .topLeading) {
                    if !Perf.shared.off.contains("sheetglass") {
                        Color.clear
                            .frame(width: L.W, height: L.H)
                            // over a place's page, the page's frosted glass like the head's (16.3)
                            // (clear Liquid Glass always: in the capsule it is the system's minimized tab bar; the
                            // frost under it says how much of a sheet it is)
                            .glassEffect(.regular, in: shape)
                            .allowsHitTesting(false)
                    }
                    UndoDrop(water: water, form: f)
                }
                .frame(width: L.W, height: L.H, alignment: .topLeading)
            }

            // what rides inside it, cut only by the water's own curved outline (never a straight mask)
            if water.profile {
                // (the Profile's own water: its three numbers, in place of everything the map's water holds)
                ProfileWater(water: water, form: f, map: map, openMap: {
                    water.onTabChange?()
                    tab = 0
                    Feel.tap()
                    Sound.tap()
                })
                    .frame(width: L.W, height: L.H, alignment: .topLeading)
                    .mask(shape)
            } else if water.lists {
                // (the Lists tab's own water: its top row and your lists, in place of everything the map's water holds)
                ListsWater(water: water, map: map, form: f)
                    .frame(width: L.W, height: L.H, alignment: .topLeading)
                    .mask(shape)
            } else if !Perf.shared.off.contains("sheet") {
                SheetContent(water: water, map: map, form: f)
                    .frame(width: L.W, height: L.H, alignment: .topLeading)
                    .mask(shape)
                    .allowsHitTesting(f.sheet > 0.5)
            }

            // the OpenStreetMap credit, on the map just above the water (outside the water's own outline)
            // (not over Apple's map in Pins: Apple's own credit is on it)
            if !map.pinsMode, !water.profile, !water.lists { StartCredit(water: water, form: f) }

            // the tabs sit on the water itself (one glass, the 02:45); at full the night leaves the capsule's place clear
            // so they are still on that same glass
            // ON LISTS the water is the whole screen, so the tabs get the capsule's own glass under them (on the Map
            // and the Profile the water itself draws in to that capsule, or holds them at its foot): one tab bar shape
            if water.lists {
                let c = L.capsule(mini: water.mini)
                Color.clear
                    .frame(width: c.width, height: c.height)
                    .glassEffect(.regular, in: .capsule)
                    .position(x: c.midX, y: c.midY)
                    .allowsHitTesting(false)
            }
            if !Perf.shared.off.contains("tabs") { tabs(L) }
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        // the lists in the water hand a pull down from their top to the water (Water/WaterHandoff)
        .environment(\.handoffWater, water)
        .contentShape(shape)
        // at Regions' menu stop a drag scrolls the list and never moves the water (6.3): the water's own drag is off
        // there, the list's scroll and the tabs keep theirs
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .updating($dragLive) { _, live, _ in live = true }
                .onChanged { g in
                    if !dragging { dragging = true; water.onTouch?(); water.begin(at: g.startLocation) }
                    water.move(to: g.location)
                }
                .onEnded { g in
                    dragging = false
                    water.end(velocity: g.velocity.height)
                },
            including: water.menuShown || water.lists ? .subviews : .all
        )
        // a drag cancelled with no end (a hold menu on the caption or a tab took the touch): the water lets go there
        .onChange(of: dragLive) { _, live in
            if !live, dragging { dragging = false; water.end(velocity: 0) }
        }
    }

    @State private var dragging = false
    @GestureState private var dragLive = false

    /// the Map tab tapped again (the tab and the test driver run this one function)
    static func mapAgain(water: Water, map: MapController) {
        water.go(.quarter)
        map.goHome()
        water.onMapAgain?()
    }
    /// the logical Lists and Profile icons were a test; back to the square and the triangle; a new key, so a phone
    /// that stored the test's choice forgets it
    @AppStorage("tabIconsLogical2") private var logicalTabs = false

    private func tabs(_ L: Layout) -> some View {
        // the logical icons while the owner tests them (TabIconsTest.swift); off = the circle, square and triangle
        let keys = logicalTabs ? ["tab-map", "tab-lists-b", "tab-profile-b"] : ["tab-map", "tab-lists", "tab-profile"]
        let names = ["Map", "Lists", "Profile"]
        let spacing: CGFloat = (L.capsule.width - 8) / 3
        // the tabs are always on clear glass over the map (at full too), so always the dark ink
        let ink: Color = Palette.ink
        return ZStack(alignment: .topLeading) {
            ForEach(0 ..< 3, id: \.self) { i in
                Button {
                    // (drawn in: a tap opens the capsule again, nothing else)
                    if water.mini > 0.5 { Feel.tap(); withAnimation(Motion.chrome) { water.mini = 0 }; return }
                    if i == tab && i == 0 {
                        // the Map tab again resets, in one tap (2.3): the water to 25% and the map home, and what a
                        // reset closes (search, the tools, settings)
                        Self.mapAgain(water: water, map: map)
                    }
                    if i != tab { water.onTabChange?() }
                    tab = i
                    Feel.tap()
                    Sound.tap()
                } label: {
                    Icon5(key: keys[i], on: i == tab, ink: i == tab ? ink : ink.opacity(0.5), size: 24)
                        .frame(width: spacing, height: 54)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // THE MAP TAB'S HOLD MENU (11.5): the four modes, from any tab. From another tab the mode is set unseen,
                // then the tab changes; on the Map tab, once Apple's menu has closed, the wheel turns to it
                .contextMenu {
                    if i == 0 {
                        let cur = water.currentMode?() ?? 0
                        ForEach(Array(["Countries", "Regions", "Places", "Pins"].enumerated()), id: \.offset) { m, name in
                            Button(name) {
                                if tab != 0 {
                                    water.onModePick?(m)
                                    water.onTabChange?()
                                    tab = 0
                                } else {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { water.onModePick?(m) }
                                }
                            }
                            .disabled(m == cur && tab == 0)
                        }
                    }
                }
                .accessibilityLabel(names[i])
                .accessibilityAddTraits(i == tab ? .isSelected : [])
                // (drawn in, the tab you are on goes to the circle's middle and the others go)
                .opacity(i == tab ? 1 : Double(1 - water.mini))
                .allowsHitTesting(i == tab || water.mini < 0.5)
                .position(x: L.W / 2 + CGFloat(i - 1) * spacing * (i == tab ? 1 - water.mini : 1), y: L.capsule.midY)
            }
        }
    }
}

/// THE FULL VIEW: at full the water is clear glass to
/// the top with the map behind it, the solar system in the middle, the head and the tabs staying black, a light mist and
/// stars. `light` is the switch the build book asks for (2.6): false brings back the dark night.
enum FullView {
    static let light = true
    /// whether the chrome turns white for the night at this point of the move to full
    static func night(_ page: CGFloat) -> Bool { !light && page > 0.55 }
}

/// What the water holds: at 25% the name and number; at 50% the system; at full the light space (BUILD-BOOK 2.6).
/// Everything in it moves with the water's top edge; nothing fades in or out. Closing, it all goes down with the
/// edge into the capsule and on under it; at full the words have gone up and off with the edge.
struct SheetContent: View {
    let water: Water
    let map: MapController
    let form: Water.Form

    var body: some View {
        let L = water.layout
        let (count, total) = map.count
        ZStack(alignment: .topLeading) {
            // the full view's space: the mist and the stars over the map (light), or the old night; either leaves the
            // capsule's place as the water's own clear glass
            Group {
                // no stars under Regions' list (the whole screen is the list there)
                // nor in Places or Pins (the stars are the countries you have left: they mean nothing there, 7 Nov)
                // nor over a place's page and its sheet (the page is the screen there), nor behind Details, Map settings
                // or Upload risen to full (they are the screen there too: the stars stood behind their words as specks)
                if Perf.shared.off.contains("stars") || water.regions || water.menuLeaving || map.placesMode || map.pinsMode || water.pageSheet
                    || water.details || water.settings || water.upload
                    // nor on a country's region map (the solar system is the Countries world's; it stood in France's sheet)
                    || map.regionScene != nil {
                    Color.clear
                } else {
                    PlasmaStars(page: form.page, top: form.top, stars: map.placesLeft, sun: CGPoint(x: L.W / 2, y: L.H / 2), map: map,
                                size: CGSize(width: L.W, height: L.H))
                }
            }
            .frame(width: L.W, height: L.H)
            .mask(CapsuleHole(capsule: L.capsule).fill(style: FillStyle(eoFill: true)))

            // THE SOLAR SYSTEM in the water (50%), the water's own content when nothing else is
            if !Perf.shared.off.contains("cosmos") {
                CosmosView(water: water, map: map, form: form)
                    // something else the water's content (settings, a list, Details, upload): the system is simply not
                    // there, and simply there again when it goes; no sliding down out of the water and no rising back
                    // up through its frosted bottom (8 Nov 20:42)
                    .opacity(cosmosOut ? 0 : 1)
                    .animation(nil, value: cosmosOut)
                    // (12 Nov: it comes up from the water's own bottom edge as the water rises, behind the tabs' glass,
                    // never out of a soft band above the tabs; the water's outline is its only edge)

            }
            if water.settings { MapSettingsSheet(water: water, map: map, form: form) }
            // THE SHELF (7.5): Places' maps for where you look, one sideways row under the caption, riding the edge
            // HISTORY'S RANGE BAR (13.4) on the water, its centre at the water's top + 156
            // (not under the journey's rows at full: it rode up over the head, 31 Oct 11:32)
            // (84 pt under the caption's middle, so at full it stays under the caption, never in the head's row; and not
            // under settings, Details or the upload, which take the water)
            // (and only once the water is at history height: switched on from 25%, the bar was drawn in the still
            // short sheet on top of the tab icons for the frames the water took to rise its 56 pt)
            if water.historyUp, map.historyInfo != nil, !water.stampedList, !water.listLeaving, !water.settings, !water.details, !water.upload, !water.regions,
               form.top <= water.restTop(.quarter) + 6 {
                HistoryBar(map: map, width: L.W - 2 * L.sheetInset - 32)
                    .position(x: L.W / 2, y: max(L.headBottom + 12 + 52, form.top + 72) + 84)
            }
            // THE PAGE'S OWN SHEET (16.6) over a place's page, in the water at 50%
            if water.pageSheet { PageSheet(water: water, map: map, form: form).transition(.identity) }
            // (never under a place's page: the water there is only the tab capsule or the page's sheet)
            // (nor at history height: the shelf's cards peeked behind the range bar there, 31 Oct 06:25)
            // THE DRAW BAR (Map/DrawTool.swift) in the caption's place while a shape or line is drawn
            // (in Pins its controls are the tools' own circles, changing in place: PinsDock)
            if DrawTool.shared.on, !water.settings, !map.pinsMode { DrawBar(water: water).transition(.opacity.animation(Motion.quick)) }
            if map.placesMode, !water.settings, !water.details, !water.stampedList, !water.upload, !water.pageSheet,
               !water.historyUp, !PlacePageState.shared.isOpen, map.regionScene == nil, !DrawTool.shared.on {
                PlacesSheet(water: water, map: map, captionY: max(L.headBottom + 12 + 52, form.top + 72), top: form.top, captionUp: captionShown)
            }
            // REGIONS' SELECTION MENU (6.3), riding the water's top; kept while its rows leave
            if water.menuShown || water.menuLeaving, let head = water.head {
                RegionsMenu(water: water, map: map, head: head, form: form).transition(.identity)
            }
            // THE UPLOAD SHEET (Part 9.3) at 25%, the caption's words out while it is up
            // (settings take the water over it, as everywhere; the upload is there again when they close)
            if water.upload, !water.settings { UploadSheet(water: water, form: form).transition(.identity) }
            // DETAILS (Part 4.4): the same place in the water as settings, the Cosmos out of the way the same way
            // (its contents are there in one frame once the water has risen; no fade, no words rolling yet)
            if water.details && water.detailsWords {
                // the same place in the water holds Verify (4.5) when that is what opened it
                if VerifyState.shared.isOpen { VerifySheet(water: water, map: map, form: form).transition(.identity) }
                else { DetailsSheet(water: water, form: form, map: map).transition(.identity) }
            }
            // THE STAMPED LIST (Part 4.6) under the caption, which stays; hidden while Details from a row is up
            let captionY = max(L.headBottom + 12 + 52, form.top + 72)
            // (settings take the water over it; the list is there again when they close)
            if (water.stampedList || water.listLeaving) && !water.details && !water.pageSheet && !water.settings {
                StampedList(water: water, map: map, form: form, top: captionY + 56).transition(.identity)
            }

            // the name and number: at full they stay under the head (29 Oct 22:13, Q2.1)
            // THE REGION MAP'S LINE fills the 25% water from the top where the Countries caption's name sits (its first
            // line 28 pt under the water's edge), not a small block in its middle
            // (history up on a region map: the journey's caption takes the level line's place, its dates and count as
            // everywhere else, 8 Nov answer 15)
            if !Perf.shared.off.contains("caption"), !(water.historyUp && map.historyInfo != nil),
               let rl = regionLevels(width: L.W - 2 * L.sheetInset - 32) {
                rl
                    // (at full under the head, as every caption: never in the head's row)
                    .padding(.top, max(L.headBottom + 10, form.top + 18))
                    .frame(width: L.W, height: L.H, alignment: .top)
                    .mask(alignment: .top) { Rectangle().frame(height: L.capsule.minY - 2) }
            }
            // PINS (Part 8): its own words where the caption sits: the count, or the chosen pin's name and place
            // (settings, details and the upload take the water as they do in every mode: Pins' words step out)
            // (and only where every map's caption fits: never inside the closed capsule over the tabs)
            if map.pinsMode, waterFits, !water.pageSheet {
                let cy = max(L.headBottom + 12 + 52, form.top + 72)
                // (the water's three contents, the tools, a pin, a colour, give way to each other blurred and faded, Apple's
                // blur replace; at once, a pin chosen swapped the tools for its name in one frame, 17:46)
                let kind = PinRoutes.shared.colouring != nil || PinDrawings.shared.colouring != nil ? 0
                    : PinStore.shared.selected == nil || PinRoutes.shared.open || DrawTool.shared.on ? 1 : 2
                ZStack {
                // a route's colour being picked takes the water (its name where the pins' caption sits)
                if kind == 0 {
                    RouteColourSheet(water: water, captionY: cy).transition(.blurReplace)
                } else if kind == 1 {
                    Group {
                    // THE DOCK (8.5): the tools in glass circles at the water's top, what you have under them (a route
                    // being made: what it wants next); your saved pins, routes and drawings under it from 50%
                    let dockTop = max(form.top, L.headBottom + 8)
                    PinsDock(water: water, top: dockTop)
                    if !PinRoutes.shared.open, !DrawTool.shared.on,
                       !PinStore.shared.pins.isEmpty || !PinRoutes.shared.routes.isEmpty || !PinDrawings.shared.all.isEmpty {
                        // (how far the water is from 25% towards 50%: at 25% no row shows at all, no words poking
                        // out of the bottom; by a third of the way they are whole)
                        let up = (L.top(.quarter) - form.top) / max(1, L.top(.quarter) - L.top(.half))
                        PinsList(water: water, captionY: cy, top: PinsDock.bottom(dockTop), rest: abs(form.top - L.top(.half)) < 1.5)
                            .opacity(min(1, max(0, Double(up) * 3)))
                    }
                    }
                    .transition(.blurReplace)
                } else {
                    Group {
                    PinsWater(water: water, form: form, captionY: cy)
                    // the pin's sheet under its name, once the water is above 25% (8.8)
                    if water.stop != .quarter, water.stop != .closed {
                        // (the name sits on the caption's name line, about 42 pt over the caption's middle, its place line
                        // under it; the sheet's rows 10 pt under the place line; Share is a row of the sheet at full, and in the pin's menu)
                        PinSheet(water: water, top: cy + 6)
                    }
                    }
                    .transition(.blurReplace)
                }
                }
                .animation(Motion.quick, value: kind)
            }
            if !Perf.shared.off.contains("caption"), map.regionScene == nil || (water.historyUp && map.historyInfo != nil), !water.pageSheet, !map.pinsMode {
                    // 7.4: the Places caption: Everywhere's (every town you marked anywhere, no "of N"), or the open
                    // country's (its towns you marked, of its towns)
                    // (history up: the journey's range, its places and its length, 13.4)
                    let hc = water.historyUp ? map.historyInfo?.caption : nil
                    Caption(name: hc?.name ?? (map.placesMode ? (placesCaption?.name ?? "") : map.moonHeld ? CosmosView.stops[map.filter] : map.sunPicked ? "Streak" : (map.continent ?? "World")),
                            count: hc?.count ?? (map.placesMode ? (placesCaption?.count ?? map.stampedTowns(on: .everywhere)) : map.sunPicked ? map.streakWeeks : count),
                            tail: hc?.tail ?? (map.placesMode ? (placesCaption?.tail ?? (map.stampedTowns(on: .everywhere) == 1 ? "place" : "places")) : map.sunPicked ? (map.streakWeeks == 1 ? "week" : "weeks") : "of \(total)"),
                            // (Places before a set is picked: the menu alone, no count of "places" as a whole, 11 Nov 12:33)
                            night: FullView.night(form.page), visible: captionShown && !(map.placesMode && hc == nil && placesCaption == nil),
                            quiet: water.modeSwitching,
                            // (Places: the name keeps clear of the back arrow on its line)
                            maxNameWidth: water.layout.W - 2 * (water.layout.sheetInset + (map.placesMode ? 60 : 24)))
                // (Places: a set picked or left is the water's content changing at once, the caption with it: its words
                // rolled out over the menu's first rows, 11 Nov)
                .transaction(value: map.placesPicked) { $0.animation = nil; $0.disablesAnimations = true }
                // always 72 pt under the top edge; its words are there only when the whole caption fits in the water
                // above the capsule, and roll in and out by the text roll as the edge crosses that line (A2.5), so
                // the edge never cuts a word and no word passes over the tabs. Past half it rides the edge up at its
                // full size and stops under the head, where it stays at full (28 Oct 01:21: the edge must
                // never cut it).
                .position(x: L.W / 2, y: max(L.headBottom + 12 + 52, form.top + 72))
                // never drawn over the tabs: the water going down to the capsule moves faster than a roll, so the
                // last of a roll out is under the capsule's top (author's call, A2.5)
                .frame(width: L.W, height: L.H, alignment: .topLeading)
                .mask(alignment: .top) { Rectangle().frame(height: L.capsule.minY - 2) } }
            // THE NUMBER OPENS THE STAMPED LIST (4.6.2): at 25%, 50% or full while it shows your count; above 0 only
            // (at 0 it refuses); with the list up the same tap closes it
            // (not in Pins: its caption is its own, and its number is not your stamps)
            // (the journey's caption over a picked sun: its count opens the journey's list)
            // (only where the caption is your stamped count: not over Places' menu, where it was a blank square on the
            // buttons, nor the journey's caption, whose number is not that count)
            if captionShown, !map.pinsMode, !map.placesMode, !water.historyUp, !map.sunPicked, !map.moonHeld, !water.settings, !water.details, !water.upload, !water.pageSheet, region == nil {
                Color.clear
                    .frame(width: 180, height: 76)
                    .contentShape(Rectangle())
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22))
                    // THE NUMBER'S HOLD MENU (11.5): count by Stamps or Countries (Map settings' Count row), Copy. Share
                    // waits for its picture
                    .contextMenu {
                        let by = MapSettingsStore.shared.value.count
                        Section("Count by") {
                            Button("Stamps") { Task { await MapSettingsRows.set("count", "stamps", map: map) } }
                                .disabled(by == "stamps")
                            Button("Countries") { Task { await MapSettingsRows.set("count", "countries", map: map) } }
                                .disabled(by == "countries")
                        }
                        Button("Copy") { UIPasteboard.general.string = "\(count) of \(total)" }
                    }
                    .position(x: L.W / 2, y: captionY + 4)
                    // (a tap no longer opens the Stamped list: the list at full is not wanted, 12 Nov 14:16; the code
                    // stays in Passport/StampedList.swift, reached only by the test driver's "list on")
            }
            // THE CAPTION'S NAME (11.5): the menu of the planet it names: on the world, Earth's (a continent by name); on
            // a continent, that planet's (Open it, here unavailable, · Its stamped list). The ring follows
            // (only on the world now: on a continent and in Places its one row was the Stamped list, which is gone,
            // and the continent's own row was always unavailable)
            if captionShown, !map.pinsMode, !map.placesMode, map.continent == nil, !map.sunPicked, !map.moonHeld, !water.settings, !water.details,
               !water.upload, !water.stampedList, !water.pageSheet, region == nil {
                Color.clear
                    .frame(width: 180, height: 26)
                    .contentShape(Rectangle())
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 13))
                    .contextMenu {
                        ForEach(["Africa", "Antarctica", "Asia", "Europe", "North America", "Oceania", "South America"], id: \.self) { k in
                            Button(k) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { map.show(continent: k) } }
                        }
                    }
                    .position(x: L.W / 2, y: captionY - 44)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: water.pageUp) { _, v in DispatchQueue.main.async { pageWasUp = v } }
        .onChange(of: water.settings || water.details || water.upload) { _, v in DispatchQueue.main.async { takenWas = v } }
        // PINS AT FULL is a name or note being typed, or a route's colour: when the pin or the colour goes (deleted,
        // done, put away) the water comes back to 50%, where the toolkit and the list are
        .onChange(of: PinStore.shared.selected == nil && PinRoutes.shared.colouring == nil && PinDrawings.shared.colouring == nil) { _, none in
            if none, map.pinsMode, water.stop == .full, !water.settings, !water.details, !water.upload, !water.pageSheet { water.go(.half) }
        }
        .onChange(of: captionFits, initial: true) { _, fits in
            // in on the quick curve; out faster (0.15 s), so it has gone before the edge comes down to the tabs
            // (a mode change swaps the caption with no roll)
            if captionShown != fits {
                // (a page coming or going is the screen changing at once: the caption with it, 8 Nov: it faded over
                // the page's first frames)
                // (and a tab coming back: the map's caption is there with the map)
                // (and settings, Details or the upload taking the water or giving it back: rolled, the leaving letters
                // stayed where the caption had stood while the water rose past them, 12 Nov)
                let taken = water.settings || water.details || water.upload
                if water.modeSwitching || water.tabSwitching || water.pageUp != pageWasUp || taken != takenWas { captionShown = fits }
                else { withAnimation(fits ? Motion.quick : .smooth(duration: Motion.reduce ? 0.1 : 0.15)) { captionShown = fits } }
            }
        }
    }

    /// THE REGION MAP'S LINE (6.6, the old app's band row): the country's name and its levels, in the caption's place
    private func regionLevels(width: CGFloat) -> AnyView? {
        guard let sc = map.regionScene, let w = map.world, sc.place < w.places.count else { return nil }
        // (as labels, capitalised like every other label: Regions, Departments, Towns)
        var levels = RegionCatalog.shared.used(sc.id).map { RegionLevels.Level(row: $0.row, word: RegionsMenuModel.label($0.level.many)) }
        // the last word: towns (6.6), for a country with towns in the data
        levels.append(RegionLevels.Level(row: Self.townsRow, word: "Towns"))
        // while another level loads, the one asked for is already the bold one
        let current = map.regionTowns ? Self.townsRow : map.regionRow > 0 && map.regionNotReady == nil ? map.regionRow : sc.row
        return AnyView(RegionLevels(name: w.places[sc.place].n, levels: levels, current: current, notReady: map.regionNotReady,
                                    failed: map.regionFailed, loading: map.regionLoading,
                                    width: width, visible: captionShown) { row in
            // the card of a region of the old level goes (its region is no longer drawn)
            RegionCardState.shared.close(map: map); DetailsState.shared.close(water: water); VerifyState.shared.close(water: water)
            if row == Self.townsRow { map.showRegionTowns() } else { map.leaveRegionTowns(); map.openRegions(sc.place, row: row) }
        })
    }

    /// the towns level's row in the level line (no region level uses it)
    static let townsRow = 99

    /// PLACES' CAPTION (9 Nov): the set looked at, your places of it, of how many it lists; narrowed to a country,
    /// of how many it has there ("of 61 in Italy"). The towns' set says its total only
    /// in a country (the world's towns are not a list anyone holds: "Towns 12").
    private var placesCaption: (name: String, count: Int, tail: String)? {
        _ = map.townsVersion; _ = MarkStore.shared.changes; _ = CollectionStore.shared.ready; _ = map.continent
        let place: String? = map.placeOpen.flatMap { i in map.world.map { $0.places[i].n } }
        // (no set picked yet: the menu's rows, and how many places are yours in all)
        guard map.placesPicked else { return nil }
        if let c = map.setCollection {
            let n = c.items.filter { MarkStore.shared.state($0.key).stamped }.count
            // (the set's own name whatever kind it is cut down to: the lime bar under it says the kind)
            // (a continent picked: of how many it has there, "of 612 in Europe")
            let area = place ?? (MapController.continents.contains(c.scope) ? c.scope : nil)
            return (CollectionStore.shared.title(map.placesSet), n, "of " + Self.number(c.total) + (area.map { " in " + $0 } ?? ""))
        }
        let n = map.stampedTowns(on: map.placesPick)
        let cities = "Cities"
        if let cc = map.placeOpenID, let place {
            let total = map.townScenes[cc]?.towns.count ?? 0
            return (cities, n, total > 0 ? "of " + Self.number(total) + " in " + place : "in " + place)
        }
        if let a = map.placesArea { return (cities, n, "in " + a) }
        return (cities, n, "")
    }

    /// a count as people read it ("28,246")
    static func number(_ n: Int) -> String {
        let nf = NumberFormatter(); nf.numberStyle = .decimal; nf.locale = Locale(identifier: "en_GB")
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// is a region map up (the caption's own taps stand down for it)
    private var region: Bool? { map.regionScene != nil ? true : nil }

    /// A2.5: the top at or above the capsule's top less 134 pt (PM 739, 17e 627: 10 pt under the 25% stop); and not
    /// on its way into the capsule (sent there, not held), so the words go as the water starts down, not after
    private var captionFits: Bool { waterFits && !DrawTool.shared.on }
    /// the water has room for what sits where the caption does (Pins' tools stay while drawing: they become its controls)
    private var waterFits: Bool {
        form.top <= water.layout.capsule.minY - 134 && !(water.stop == .closed && !water.held) && !water.settings && !water.details
            && !water.upload && !water.regions && !water.menuLeaving && !water.pageUp
    }
    /// the solar system is down out of the water while something else is the water's content
    private var cosmosOut: Bool {
        water.settings || water.details || water.stampedList || water.listLeaving || water.upload || water.regions || water.menuLeaving
            || water.pageSheet
            // and history's (9 Nov: the years sat on its orbit)
            || water.historyUp
            // Places' water holds your maps (7 Nov 16:37: the solar system means nothing in Places), and Pins' its pins
            || map.placesMode || map.pinsMode
            // and a region map's (the system is the Countries world's; it sat in France's sheet at 50%)
            || map.regionScene != nil
            // and the water on its way down to 25% by itself (settings, a list or Details closed, the Map tab): the
            // system is not shown for a moment only to sink away under the caption (8 Nov burst: it came back at 50%
            // and rode down for a second); under a finger it rises and sinks with the water as before
            || (!water.held && (water.stop == .quarter || water.stop == .closed))
    }
    @State private var captionShown = false
    /// the page state the caption last saw (a page coming or going swaps the caption at once)
    @State private var pageWasUp = false
    /// whether settings, Details or the upload had the water when the caption last looked
    @State private var takenWas = false
}

/// THE FULL VIEW IS CLEAR GLASS WITH STARS: no field, no mist,
/// nothing spreading from the sun; the water stays the clear glass it is everywhere else, the map under it, the tabs on
/// the same glass. Only the stars, one for each place you have left (8 Oct).
///
/// Each star is the sun's plasma and only that (the 10:47): white tongues of light round a soft bright middle, no
/// disc, no rim,
/// at full strength; small. White light can't be seen on the white land, so each
/// star's light is darkened as much as the ground under it needs (the 13:58): white over the sea, darker over land.
///
/// They come with the water's top edge, never all at once and never from a point in the middle: past half, as the
/// edge goes up over a star, that star grows out of its own middle to its size, and goes back into it as the edge
/// comes down. Drawn from eight star pictures made once (each a moment of the plasma), so a moving sheet only places
/// pictures; at rest nothing is drawn again.
struct PlasmaStars: View {
    let page: CGFloat
    let top: CGFloat
    let stars: Int
    let sun: CGPoint
    let map: MapController
    let size: CGSize
    @State private var sprites: [Image] = []
    /// how dark each star is drawn (0 white light; more over light ground: MapController.groundDark), worked out once
    /// as the view heads for full, before any star shows, so a star never changes while it is seen
    @State private var dark: [Double] = []

    static let sprite: CGFloat = 30
    /// the plasma's own radius as a share of the picture (its light reaches about three times as far)
    static let disc: CGFloat = 0.22

    var body: some View {
        // past half the stars can come; each as the edge has gone 28 points above it
        let open = Flow.smooth(0.5, 0.8, page)
        ZStack {
            // below half nothing is drawn at all (not even an empty canvas each frame the sheet moves)
            if open > 0 && !sprites.isEmpty { canvas(open: open) }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .task { if sprites.isEmpty { sprites = Self.makeSprites(); Self.shared = sprites } }
        // WORKED OUT AHEAD, OFF THE MAIN THREAD (Step 1c found it: done all at once as the sheet headed for full it held
        // the screen 350 ms, 229 stars x 3 lookups; then done a few stars a frame on the main thread it still took a few
        // ms of every frame of the next pan or pinch): once each time the camera comes to rest or the marks change, a
        // quarter second later, every lookup on a background thread; the stars only show past half way to full, by
        // when it is long done
        .task(id: Key(stars: drawn, rest: map.restVersion, marks: map.stamped.count &* 4096 &+ map.wished.count,
                      w: Int(size.width), h: Int(size.height))) {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            #if DEBUG
            let t0 = CACurrentMediaTime()
            #endif
            let stars = drawn
            var g = SeededRandom(seed: 987654)
            var pts: [CGPoint] = []
            pts.reserveCapacity(stars * 3)
            for _ in 0 ..< stars {
                let u = g.next(), v = g.next(); _ = g.next(); _ = g.next()
                let x = u * Double(size.width), y = v * Double(size.height)
                pts += [CGPoint(x: x, y: y), CGPoint(x: x - 4, y: y), CGPoint(x: x + 4, y: y)]
            }
            let d = await map.groundDark(at: pts)
            if Task.isCancelled { return }
            dark = (0 ..< stars).map { (d[3 * $0] + d[3 * $0 + 1] + d[3 * $0 + 2]) / 3 }
            Self.sharedDark = dark
            #if DEBUG
            NSLog("wya stars grounds %d stars over %.0f ms", stars, (CACurrentMediaTime() - t0) * 1000)
            #endif
        }
    }

    /// THE STARS IN ONE CANVAS DRAWN BY THE GPU (Step 1c: drawn by the CPU into a screen-sized picture, every frame of the
    /// move to full cost 8 ms and 14 late frames in 120; as 229 separate layers the render server fell to 20 frames a
    /// second). In a drawing group each star is one textured square on the GPU; each picture is resolved once a frame.
    private func canvas(open: CGFloat) -> some View {
        // the stars falling now are drawn by the Cosmos, which knows where their planets are (A2.20)
        let air = stars ..< stars + map.flying
        return Canvas { ctx, size in
            var g = SeededRandom(seed: 987654)
            var resolved: [Int: GraphicsContext.ResolvedImage] = [:]
            for i in 0 ..< drawn {
                let u = g.next(), v = g.next(), s = g.next(), k = g.next()
                if air.contains(i) { continue }
                let x = u * Double(size.width), y = v * Double(size.height)
                if hypot(x - Double(sun.x), y - Double(sun.y)) < 64 { continue }
                let grow = Double(open) * min(1, max(0, (y - Double(top)) / 28))
                guard grow > 0.01 else { continue }
                // most small, a few bigger, as real brightness goes (the 11:39): seen by being full white light
                // not by size
                let scale = Self.scale(s) * grow
                let w = Double(Self.sprite) * scale
                // the same plasma, its light darkened as much as the ground under it needs (white over the sea): one of
                // the pictures already darkened to the nearest level (a filter per star cost a layer per star, every
                // frame the sheet moved; Step 1c)
                let n = Self.picture(i, k: k, dark: dark, count: sprites.count)
                let r = resolved[n] ?? ctx.resolve(sprites[n])
                resolved[n] = r
                ctx.draw(r, in: CGRect(x: x - w / 2, y: y - w / 2, width: w, height: w))
            }
        }
        .drawingGroup()
    }

    private struct Key: Hashable { let stars: Int; let rest: Int; let marks: Int; let w: Int; let h: Int }

    /// the places left, and the stamped ones whose star has not fallen yet (they stay where they were until then)
    private var drawn: Int { stars + map.falls.count }
    /// a star's size for its third number (most small, a few bigger)
    static func scale(_ s: Double) -> Double { 0.3 + 0.4 * pow(s, 2.4) }
    /// which picture star i is drawn with: its darkness level, then one of that level's eight moments
    static func picture(_ i: Int, k: Double, dark: [Double], count: Int) -> Int {
        let d = i < dark.count ? dark[i] : 0
        let level = levels.indices.min { abs(levels[$0] - d) < abs(levels[$1] - d) } ?? 0
        let set = count / levels.count
        return level * set + Int(k * Double(set)) % set
    }
    /// star i where it sits in a view of this size (nil when it is never drawn: too close to the sun), its size and
    /// its picture, for the Cosmos to draw it as it falls
    @MainActor static func star(_ i: Int, size: CGSize, sun: CGPoint) -> (at: CGPoint, scale: Double, picture: Int)? {
        guard !shared.isEmpty else { return nil }
        var g = SeededRandom(seed: 987654)
        for _ in 0 ..< i { _ = g.next(); _ = g.next(); _ = g.next(); _ = g.next() }
        let u = g.next(), v = g.next(), s = g.next(), k = g.next()
        let x = u * Double(size.width), y = v * Double(size.height)
        if hypot(x - Double(sun.x), y - Double(sun.y)) < 64 { return nil }
        return (CGPoint(x: x, y: y), scale(s), picture(i, k: k, dark: sharedDark, count: shared.count))
    }
    /// the pictures and darknesses the stars were last drawn with, for the falling ones
    @MainActor static var shared: [Image] = []
    @MainActor static var sharedDark: [Double] = []

    /// the darkness levels a star is drawn at (the grounds' values and their means: sea, wished, stamped, land)
    static let levels: [Double] = [0, 0.15, 0.3, 0.45, 0.6, 0.8]

    /// eight moments of the white plasma at each darkness level, drawn once (no disc, no rim, no shadow)
    @MainActor static func makeSprites() -> [Image] {
        levels.flatMap { d in (0 ..< 8).compactMap { i -> Image? in
            let content = Rectangle()
                .frame(width: sprite, height: sprite)
                .colorEffect(ShaderLibrary.starPlasma(.float2(Float(sprite), Float(sprite)), .float(Float(i) * 7.3 + 1),
                                                      .float(Float(disc)), .float(1.0)))
                .colorMultiply(Color(white: 1 - d))
            .frame(width: sprite, height: sprite)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            renderer.isOpaque = false
            return renderer.uiImage.map { Image(uiImage: $0) }
        } }
    }
}

/// Everything except the tab capsule's place.
nonisolated struct CapsuleHole: Shape {
    var capsule: CGRect
    func path(in rect: CGRect) -> Path {
        var p = Path(rect.insetBy(dx: -200, dy: -200))
        p.addRoundedRect(in: capsule, cornerSize: CGSize(width: capsule.height / 2, height: capsule.height / 2), style: .continuous)
        return p
    }
}

/// The name and the count (Apple's way, as in Weather and Fitness): the name in SF semibold, the number big in SF
/// Rounded, the total at body size in the secondary ink, set tight on one centre line.
struct Caption: View {
    var name: String
    var count: Int
    var tail: String
    var night: Bool
    /// A2.5: the words there (rolled in) or not (each line a placeholder of spaces of about its width, never an empty
    /// string, which SwiftUI would insert with a blur and a fade); in rises, out goes down
    var visible = true
    /// a mode change: the new name, number and tail are simply there (no roll)
    var quiet = false
    /// the widest the name may be (inside the sheet's margins): a long one gets a little smaller to fit, never
    /// runs off the sheet (8 Nov)
    var maxNameWidth: CGFloat = 360
    @ScaledMetric(relativeTo: .largeTitle) private var big: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let ink: Color = night ? Palette.white : Palette.ink
        let way = visible ? 1.0 : 0.0
        VStack(spacing: 0) {
            // a new name rolls in letter by letter, the way the number does (Apple's text roll), never swapped in
            // place
            Text(visible ? name : Self.blank(name, "\u{2002}"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: way))
                .animation(quiet ? nil : Motion.quick, value: name)
                .frame(width: min(Self.nameWidth(name, typeSize), maxNameWidth))
            // with its thousands mark, as its tail is written ("15,229" over "of 15,229", never "15229")
            Text(visible ? count.formatted() : Self.blank(count.formatted(), "\u{2007}"))
                .font(.system(size: big, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .contentTransition(.numericText(value: visible ? Double(count) : -1))
                .animation(quiet ? nil : Motion.quick, value: count)
                .padding(.top, -6)
            // an empty tail (Everywhere) keeps its line as a space, so the caption keeps its place and sizes
            Text(visible && !tail.isEmpty ? tail : Self.blank(tail, "\u{2002}"))
                .font(.body.weight(.semibold))
                .foregroundStyle(ink.opacity(0.5))
                .contentTransition(.numericText(value: way))
                // (rolled with the name and the number: changed at once, "World 39 of 58" stood for a frame, 12 Nov)
                .animation(quiet ? nil : Motion.quick, value: tail)
                .padding(.top, -8)
        }
        .multilineTextAlignment(.center)
        .fixedSize()
        // Apple's text styles (Part 0.8: title2 22, headline 17, the number 64 scaled with largeTitle), up to the
        // largest standard size: past it the caption would not fit above the capsule at 25% (the AX sizes are Part 19)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tail.isEmpty ? "\(name), \(count)" : "\(name), \(count) \(tail)")
        .accessibilityHidden(!visible)
    }

    /// a line's placeholder: one space per character (en spaces for words, figure spaces for digits)
    /// the name's own width at title2 semibold for the type size in use (the caption is as wide as its words)
    static func nameWidth(_ s: String, _ size: DynamicTypeSize) -> CGFloat {
        let base = UIFont.preferredFont(forTextStyle: .title2, compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size)))
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
        return ceil((s as NSString).size(withAttributes: [.font: font]).width) + 2
    }
    static func blank(_ s: String, _ space: String) -> String { String(repeating: space, count: max(1, s.count)) }
}

/// THE START CREDIT (A1.20, on top of the sheet, on the left): plain words on the map
/// just above the water's top edge, at the sheet's inner left, no box of its own; in and out by the text roll like every
/// word; at each cold launch until 5 s or the first touch on the map, while the water is low enough for its caption.
struct StartCredit: View {
    let water: Water
    let form: Water.Form
    @State private var shown = false
    var body: some View {
        let L = water.layout
        // (and not above 50%: higher, the water's top is under the head and the words would sit over the status bar)
        let fits = form.top <= L.capsule.minY - 134 && form.top >= L.top(.half) - 2 && !(water.stop == .closed && !water.held)
        Text(shown ? "© OpenStreetMap" : "\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}")
            .font(.caption)
            .foregroundStyle(Palette.ink.opacity(0.5))
            .contentTransition(.identity)
            .fixedSize()
            .padding(.leading, L.sheetInset + 16)
            .padding(.top, form.top - 22)
            .frame(width: L.W, height: L.H, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(!shown)
            .accessibilityLabel("Map data from OpenStreetMap")
            .onChange(of: water.credit && fits) { _, on in withAnimation(on ? Motion.quick : .smooth(duration: 0.15)) { shown = on } }
    }
}
