import SwiftUI

/// The Map tab: the world edge to edge under everything, the head on top, the zoom column on the right, and the
/// water (the tab capsule and its sheet) at the bottom. Everything is placed from this phone's own screen (Layout).
struct ContentView: View {
    @State private var map = MapController()
    @State private var water = Water()
    @State private var head = HeadState()
    @State private var tab = 0

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

                ZoomColumn(map: map, water: water, head: head)

                WaterView(water: water, map: map, tab: $tab)

                HeadView(map: map, water: water, head: head)

                TopPullView(head: head, water: water)
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
            // a finger on the map or the sheet puts settings and the AI away (and goes on doing what it does)
            map.onTouch = { [head] in head.putAway() }
            water.onTouch = { [head] in head.putAway() }
            // the text input system set up now, not on the first search (Prewarm)
            DispatchQueue.main.async { Prewarm.textInput() }
        }
        .task { await map.load() }
    }
}
