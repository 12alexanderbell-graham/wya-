import SwiftUI

/// The Map tab: the world edge to edge under everything, the head on top, the zoom column on the right, and the
/// water (the tab capsule and its sheet) at the bottom. Everything is placed from this phone's own screen (Layout).
struct ContentView: View {
    @State private var map = MapController()
    @State private var water = Water()
    @State private var head = HeadState()
    @State private var tab = 0
    @State private var launch = Launch.shared

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
                if !Perf.shared.off.contains("map") { MapLayer(controller: map) }

                if !Perf.shared.off.contains("zoom") { ZoomColumn(map: map, water: water, head: head) }

                // under the water: the space's shaders set up once, unseen (Prewarm.swift)
                ShaderPrewarm()
                    .position(x: water.layout.W / 2, y: water.layout.capsule.midY)

                // the stamping card: over the map, under the sheet's glass and the head (Part 4.2)
                StampCard(map: map, water: water)

                WaterView(water: water, map: map, tab: $tab)

                if !Perf.shared.off.contains("head") { HeadView(map: map, water: water, head: head) }

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
        .onAppear {
            TestDriver.shared.start(map: map, water: water, head: head)
            // the Map's actions, by stable id (Part 20.12): the AI, Siri, links and hold menus call these
            Actions.shared.registerMap(map: map, water: water, head: head)
            MapSettingsRows.registerActions(map: map)
            // a finger on the map or the sheet puts settings and the AI away (and goes on doing what it does)
            // with Details up, a touch on the map closes Details only (back to the card); the next one closes the card
            map.onTouch = { [head, water, map] in
                head.putAway(); water.hideCredit()
                if DetailsState.shared.isOpen { DetailsState.shared.close(water: water) } else { CardState.shared.close(map: map) }
            }
            // a finger in the water is using Details when they are up; otherwise it closes the card
            water.onTouch = { [head, map] in
                head.putAwayAI()
                if !DetailsState.shared.isOpen { CardState.shared.close(map: map) }
            }
            // a confirmed tap on a place opens its stamping card (Part 4.2.1)
            map.onPlaceTap = { [head, map, water] i, p in
                guard !head.quickStamp, !map.locked else { return }
                CardState.shared.open(i, at: p, map: map, water: water)
            }
            // leaving a tab ends quick stamping too (3.6)
            water.onTabChange = { [head] in head.quickStamp = false }
            water.onMapAgain = { [head] in
                head.searching = false
                head.toolsOpen = false
                head.putAway()
            }
            // the text input system set up now, not on the first search (Prewarm)
            DispatchQueue.main.async { Prewarm.textInput() }
        }
        .task {
            await map.load()
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
        .onChange(of: head.toolsOpen) { _, v in if v { closeCard() } }
        .onChange(of: water.stop) { _, s in
            if head.settingsOpen, s == .quarter || s == .closed { head.closeSettings() }
            if DetailsState.shared.isOpen, water.stampedList {
                // Details opened from the list: a pull down closes them, back to the list at full (A4.21 reversed)
                if s != .full { DetailsState.shared.close(water: water); water.go(.full) }
            } else if water.stampedList, s != .full {
                // the list pulled down: it goes, the water stays where the pull left it (4.6.3)
                water.closeList(back: false)
            } else if DetailsState.shared.isOpen, s == .quarter || s == .closed {
                // Details pulled down below 50% close and keep (4.4.1)
                DetailsState.shared.close(water: water)
            }
        }
    }

    private func closeCard() {
        DetailsState.shared.close(water: water)
        CardState.shared.close(map: map)
    }
}
