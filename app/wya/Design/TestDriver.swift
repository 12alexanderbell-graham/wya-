import SwiftUI
import MapKit

/// TEST ONLY, simulator builds only: reads snaps/cmd.txt in the night folder four times a second and runs it when it
/// changes, so every state of the screen can be reached and checked from outside (with Snap's frames). The first
/// line is an id; each next line one command. Never in a phone build.
@MainActor
final class TestDriver {
    static let shared = TestDriver()
    weak var map: MapController?
    weak var water: Water?
    weak var head: HeadState?
    private var lastID = ""
    /// the pin `pins add` made (the only pin `pins unadd` ever takes away)
    private var testPin: UUID?
    private var lostOwner = false
    /// the command file is being read (off the main thread), since when, and whether a stuck read was said
    private var reading = false, readSince = 0.0, saidStuck = false
    /// where the whole content is on screen (to see whether the keyboard moves it)
    var contentFrame: CGRect = .zero
    /// the session put back as after the system ended the app (19.2): `session restore`
    var restoreSession: (() -> Void)?

    /// a hold menu's row, found by its words in the menu and its groups, chosen
    private static func choose(_ title: String, in menu: UIMenu) {
        for e in menu.children {
            if let m = e as? UIMenu { choose(title, in: m) }
            else if let a = e as? UIAction, a.title == title { a.performWithSender(nil, target: nil) }
        }
    }

    func start(map: MapController, water: Water, head: HeadState) {
        #if targetEnvironment(simulator) && DEBUG
        self.map = map; self.water = water; self.head = head
        NSLog("wya test driver started")
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in NSLog("wya t keyboard will show") }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in NSLog("wya t keyboard did show") }
        // a launch to record: snaps/launch-burst.txt holds the burst's length in ms (read once, then emptied)
        let lb = Snap.dir + "/launch-burst.txt"
        if let ms = (try? String(contentsOfFile: lb, encoding: .utf8)).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }), ms > 0 {
            try? "".write(toFile: lb, atomically: true, encoding: .utf8)
            Snap.burst(ms: ms)
        }
        let path = Snap.dir + "/cmd.txt"
        // a command left over from the last run is not run again
        lastID = (try? String(contentsOfFile: path, encoding: .utf8))?.split(separator: "\n").first.map(String.init) ?? ""
        // (8 Nov 01:20: the read itself sometimes never came back, the file in the synced folder held by something
        // outside the app, and the whole app stood still with it; now it is read off the main thread, one read at a
        // time, and a read that hangs only stops the commands, said once in the log)
        let queue = DispatchQueue(label: "testdriver.read", qos: .userInitiated)
        let ownerPath = Snap.dir + "/owner.txt"
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated {
                if self.reading {
                    if !self.saidStuck, CACurrentMediaTime() - self.readSince > 3 {
                        self.saidStuck = true
                        NSLog("wya test driver: reading cmd.txt has not come back for 3 s")
                    }
                    return
                }
                self.reading = true; self.readSince = CACurrentMediaTime()
                queue.async {
                    let s = try? String(contentsOfFile: path, encoding: .utf8)
                    let owner = try? String(contentsOfFile: ownerPath, encoding: .utf8)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self.reading = false
                            if self.saidStuck { self.saidStuck = false; NSLog("wya test driver: cmd.txt read again") }
                            self.took(s, owner: owner)
                        }
                    }
                }
            }
        }
        #endif
    }

    /// the command file as read: run it when its id is new and it is whole (its last line "end", so a file read
    /// while it was being written is left for the next read)
    private func took(_ s: String?, owner: String?) {
        if let owner { Snap.ownerSeen = owner }
        if let owner, owner != Snap.me {
            // another copy of the app (another simulator) took the test files over: say so once
            if !lostOwner {
                lostOwner = true
                NSLog("wya test driver: owner is now %@, I am %@", owner, Snap.me)
            }
            return
        }
        guard let s else { return }
        var lines = s.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let id = lines.first, id != lastID, lines.last == "end" else { return }
        lastID = id
        lines.removeFirst()
        lines.removeLast()
        NSLog("wya test driver runs %@", lines.joined(separator: " | "))
        // "quiet" anywhere in the commands: no screen grabs (measuring lag, the grabs would be the lag)
        Snap.activeUntil = lines.contains("quiet") ? 0 : CACurrentMediaTime() + 20
        run(lines)
    }

    private func run(_ lines: [String]) {
        Task { @MainActor in
            for l in lines {
                let p = l.split(separator: " ").map(String.init)
                guard let c = p.first else { continue }
                let a = p.count > 1 ? p[1] : ""
                switch c {
                case "wait": try? await Task.sleep(for: .milliseconds(Int(a) ?? 300))
                case "water":
                    let s: Water.Stop = ["closed": .closed, "quarter": .quarter, "half": .half, "full": .full][a] ?? .quarter
                    water?.go(s)
                case "dragwater":
                    // dragwater y0 y1 ms [hold]
                    let y0 = CGFloat(Double(a) ?? 700), y1 = CGFloat(Double(p.count > 2 ? p[2] : "400") ?? 400)
                    let ms = Int(p.count > 3 ? p[3] : "400") ?? 400
                    water?.begin(at: CGPoint(x: 201, y: y0))
                    let steps = max(1, ms / 16)
                    for i in 1 ... steps {
                        water?.move(to: CGPoint(x: 201, y: y0 + (y1 - y0) * CGFloat(i) / CGFloat(steps)))
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    if p.count > 4 && p[4] == "hold" { continue }
                    water?.end(velocity: (y1 - y0) / CGFloat(ms) * 1000 * 0.3)
                case "release": water?.end(velocity: 0)
                case "pull":
                    guard let h = head else { break }
                    // pull ai | <points> (held there, as a finger would) | off
                    // through the same code as a finger (from settings too), so a test sees what a person would
                    let v: CGFloat = a == "ai" ? HeadState.aiStop : a == "off" ? 0 : CGFloat(Double(a) ?? 0)
                    h.pullBegan()
                    h.pullMoved(v - h.pull)
                    if a == "ai" || a == "off" { h.settlePull(to: v >= HeadState.aiStop ? 1 : 0) }
                case "tools": head?.toolsOpen = a == "on"
                // history on|off; history tap <x> <y> (a tap on the journey at that point, as the map's confirmed tap
                // would hand it over); history pull <dy> (the water grabbed at its top, moved dy pt, let go still)
                case "history": await HistoryLineView.drive(p, map: map, water: water, head: head)
                case "nametap", "names": TownNamesView.drive(p, map: map)
                // visit <id> <yyyy-mm-dd>: the country stamped with that day as a visit (test data for history lines)
                // (a key like r:fr/FR-ARA for a region)
                case "visit": if p.count > 2 { await MarkStore.shared.stamp(a.contains(":") ? (PlaceKey(a) ?? .country(a)) : .country(a), day: p[2]) }
                case "quick": head?.quickStamp = a == "on"
                case "dial": head?.testDial = a == "off" ? nil : CGFloat(Double(a) ?? 0)
                case "mode": head?.mode = HeadState.Mode(rawValue: Int(a) ?? 0) ?? .countries
                // zoomhold 1|-1|0: + or − held (as the zoom column's hold), or let go; logs the limits
                case "zoomhold":
                    map?.holdZoom = Int(a) ?? 0
                    if let m = map { NSLog("wya zoomhold %d home %d max %d dist %.0f", m.holdZoom, m.atHome ? 1 : 0, m.atMax ? 1 : 0, PinsMapState.shared.view?.camera.centerCoordinateDistance ?? -1) }
                // neighbours <id>: who borders it in this borders view (D19)
                case "neighbours":
                    if let w = map?.world, let i = w.placeIndex[a] {
                        NSLog("wya neighbours %@: %@", a, w.neighbours[i].map { w.places[$0].id }.sorted().joined(separator: " "))
                    }
                case "search":
                    if a == "off" { head?.searching = false }
                    // search suggest [new]: the empty field's suggestions, logged by id (new: as with no searches yet)
                    else if a == "suggest", let m = map, let w = m.world {
                        let s = SearchResults.suggestions(map: m, recentToo: p.count < 3)
                        NSLog("wya suggestions %@", s.map { w.places[$0].id }.joined(separator: " "))
                    }
                    else { NSLog("wya t search open"); head?.searching = true; head?.query = p.dropFirst().joined(separator: " ") }
                // submit: the keyboard's Search key
                case "submit": head?.submitAsked += 1
                // where: what is up, logged (mode, search, card, Places' open country, the water's stop, a page)
                case "where":
                    NSLog("wya where: mode %d search %d card %@ placeOpen %@ stop %@ page %d continent %@", head?.mode.rawValue ?? -1, head?.searching == true ? 1 : 0,
                          CardState.shared.isOpen ? "up" : "none", map?.placeOpen.map { "\($0)" } ?? "nil", water.map { "\($0.stop)" } ?? "?",
                          PlacePageState.shared.isOpen ? 1 : 0, map?.continent ?? "nil")
                    // (and the camera: its middle in map units, its zoom, the view's size)
                    if let m = map { NSLog("wya camera c %.4f %.4f k %.1f view %.0f x %.0f", m.c.x, m.c.y, m.k, m.view.width, m.view.height) }
                    // (and the region map's own box on screen, in points)
                    if let m = map, let sc = m.regionScene {
                        let a = m.screenPoint(SIMD2(Double(sc.box.x), Double(sc.box.y))), b = m.screenPoint(SIMD2(Double(sc.box.z), Double(sc.box.w)))
                        NSLog("wya scene box on screen x %.0f to %.0f y %.0f to %.0f", a.x, b.x, a.y, b.y)
                        // (and its diamonds: how many regions stand alone, and each one's size on screen and diamond)
                        let alone = sc.unitSpot.indices.filter { sc.unitSpot[$0].z.isFinite }
                        NSLog("wya region diamonds: %d regions, %d alone, towns %d: %@", sc.unitSpot.count, alone.count, m.regionTowns ? 1 : 0,
                              alone.prefix(12).map { String(format: "%@ %.1fpt d%.2f", sc.unitNames[$0], Double(sc.unitSpot[$0].z) * m.k, m.regionDiamondSize($0)) }.joined(separator: ", "))
                    }
                case "zoom":
                    if a == "in" { map?.zoomIn() } else if a == "out" { map?.zoomOut() } else { map?.goHome() }
                case "show":
                    if let m = map, let i = m.world?.placeIndex[a] { m.show(place: i) }
                // reset: what the zoom column's Reset does where the map is (Apple's map included)
                case "reset":
                    if let m = map {
                        if m.onApple {
                            if let sc = m.regionScene { PinsMapState.shared.show(place: sc.place, world: m.world) } else { m.appleHome() }
                        } else if let sc = m.regionScene { m.frameRegion(sc.place) } else { m.closePlace(); m.goHome() }
                    }
                case "continent": map?.show(continent: p.dropFirst().joined(separator: " "))
                case "look":
                    // look lon lat zoom
                    if p.count > 3, let lo = Double(p[1]), let la = Double(p[2]), let z = Double(p[3]) {
                        map?.look(lon: lo, lat: la, zoom: z)
                    }
                case "press":
                    if let m = map { m.pressed = a == "off" ? nil : m.world?.placeIndex[a] }
                case "hold": head?.dotHeld = a == "on"
                // gear <0..1>: holds the dot part way to the gear, to look at one frame of it
                case "gear": head?.gear = CGFloat(Double(a) ?? 0)
                case "drag":
                    // drag <dy> <ms>: the top pull as a finger would do it, through the same code as the gesture
                    guard let h = head else { break }
                    let dy = CGFloat(Double(a) ?? 0), ms = Int(p.count > 2 ? p[2] : "400") ?? 400
                    h.pullBegan()
                    let steps = max(1, ms / 16)
                    for i in 1 ... steps {
                        h.pullMoved(dy * CGFloat(i) / CGFloat(steps))
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    if !(p.count > 3 && p[3] == "hold") { h.pullEnded(velocity: 0) }
                // a finger on the map: the same hook the map's touch calls (ContentView: map.onTouch)
                case "maptap": map?.onTouch?()
                // seatap: a confirmed tap on the sea; placetap <id>: a confirmed tap on that place (its middle)
                case "seatap": map?.onSeaTap?()
                // axdump: the map's VoiceOver elements, logged (count, then the first twelve labels and their actions)
                case "axdump":
                    func find(_ v: UIView) -> MapMTKView? { (v as? MapMTKView) ?? v.subviews.lazy.compactMap(find).first }
                    let win = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
                    if let mv = win.flatMap(find) {
                        let els = (mv.accessibilityElements ?? []).compactMap { $0 as? NSObject }
                        NSLog("wya ax %d elements; rotors %@", els.count, (mv.accessibilityCustomRotors ?? []).map(\.name).joined(separator: ", "))
                        for e in els.prefix(12) + els.suffix(3) {
                            NSLog("wya ax %@ | %@", e.accessibilityLabel ?? "?", (e.accessibilityCustomActions ?? []).map(\.name).joined(separator: ", "))
                        }
                    }
                // axpress <words>: the first accessibility element whose label holds the words, its frame logged and
                // activated (what VoiceOver's double tap does)
                case "axpress":
                    let want = p.dropFirst().joined(separator: " ")
                    func walk(_ o: NSObject, _ depth: Int) -> NSObject? {
                        if depth > 40 { return nil }
                        if let l = o.accessibilityLabel, l.contains(want), o.isAccessibilityElement { return o }
                        let kids: [Any] = (o as? UIView).map { v in (v.accessibilityElements ?? []) + v.subviews } ?? (o.accessibilityElements ?? [])
                        for k in kids { if let k = k as? NSObject, let f = walk(k, depth + 1) { return f } }
                        let n = o.accessibilityElementCount()
                        if n > 0, n != NSNotFound { for i in 0 ..< n { if let k = o.accessibilityElement(at: i) as? NSObject, let f = walk(k, depth + 1) { return f } } }
                        return nil
                    }
                    let win = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
                    if let w = win, let e = walk(w, 0) {
                        NSLog("wya axpress %@ at %@ -> %d", e.accessibilityLabel ?? "?", NSCoder.string(for: e.accessibilityFrame), e.accessibilityActivate() ? 1 : 0)
                    } else { NSLog("wya axpress %@: none", want) }
                case "placetap":
                    if let m = map, let i = m.world?.placeIndex[a] { let r = m.screenRect(of: i); m.onPlaceTap?(i, CGPoint(x: r.midX, y: r.midY)) }
                // whatshere x y | whatshere off: What's here? at that screen point (A11.4), or taken away
                case "whatshere":
                    if a == "off" { WhatsHere.shared.close() }
                    else if p.count > 2, let x = Double(p[1]), let y = Double(p[2]), let m = map { WhatsHere.shared.show(at: CGPoint(x: x, y: y), map: m) }
                // wheel <dx> <ms>: a finger turning the dot sideways, through the same path as the capsule's drag
                case "wheel":
                    guard let h = head else { break }
                    let dx = CGFloat(Double(a) ?? 0), ms = Int(p.count > 2 ? p[2] : "600") ?? 600
                    let steps = max(1, ms / 16)
                    for k in 1 ... steps {
                        h.capsuleDrag = dx * CGFloat(k) / CGFloat(steps)
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    h.capsuleDragFling = 0
                    h.capsuleDrag = nil
                // sheet flags: a review sheet (1p) into snaps/review-<name>.png
                case "sheet":
                    if a == "flags" { ReviewSheet.flags(world: map?.world) }
                    if a == "tabicons" { ReviewSheet.tabIcons() }
                    if a == "launch" { ReviewSheet.launchPicture() }
                    if a == "logoturn" { ReviewSheet.logoTurnMovie() }
                    if a == "icons" { ReviewSheet.icons() }
                    if a == "placesideas" { PlacesIdeas.make() }
                    if a == "emblems" { ReviewSheet.emblems() }
                    if a == "flagshapes" { ReviewSheet.flagShapes(world: map?.world) }
                // profile name|handle|code|bio <words> | clear: the Profile's words, as its editor will set them (a test's
                // own words are taken away again with clear)
                case "profile":
                    let words = p.dropFirst(2).joined(separator: " ")
                    ProfileStore.shared.set { me in
                        switch a {
                        case "name": me.name = words
                        case "handle": me.handle = words
                        case "code": me.code = words
                        case "bio": me.bio = words
                        case "clear": me = ProfileStore.Me(); DispatchQueue.main.async { ProfileStore.shared.removePhoto() }
                        default: break
                        }
                    }
                    // profile edit name|handle|bio|off: that line's text box, as its tap; profile sheet picture|nations|off;
                    // profile colour <hue> <light> <strength>; profile picture none|photo|flag <id>; profile phototest (a
                    // made-up photo through the upload's own crop); profile nats <id> <id>... | none (logs them)
                    let edit = ProfileEdit.shared
                    if a == "edit" { edit.field = p.count > 2 ? ["name": .name, "handle": .handle, "bio": .bio][p[2]] : nil }
                    if a == "sheet", let w = water {
                        if p.count > 2, p[2] == "picture" { edit.open(.picture, water: w) }
                        else if p.count > 2, p[2] == "nations" { edit.open(.nationalities, water: w) }
                        else if p.count > 2, p[2] == "ground" { edit.open(.ground, water: w) }
                        else { edit.end(water: w) }
                    }
                    if a == "colour", p.count > 4 {
                        let c = ColourPick(hue: Double(p[2]) ?? 0, light: Double(p[3]) ?? 0.5, strength: Double(p[4]) ?? 1)
                        ProfileStore.shared.set { $0.colour = c; $0.picture = nil }
                    }
                    if a == "picture" {
                        ProfileStore.shared.set { $0.picture = p.count > 3 && p[2] == "flag" ? "flag:" + p[3] : p.count > 2 && p[2] == "photo" ? "photo" : nil }
                        if p.count > 2, p[2] == "none" { ProfileStore.shared.set { $0.colour = nil } }
                    }
                    if a == "phototest" {
                        let img = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600)).image { c in
                            UIColor.systemTeal.setFill(); c.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
                            UIColor.systemOrange.setFill(); c.cgContext.fillEllipse(in: CGRect(x: 300, y: 150, width: 300, height: 300))
                        }
                        if let d = img.pngData() { await ProfileStore.shared.setPhoto(d) }
                    }
                    // profile ground <hue> <light> <strength> (the first colour) | none
                    if a == "ground" {
                        if p.count > 4 {
                            var g = ProfileStore.shared.me.ground ?? ColourPick.field
                            g[0] = ColourPick(hue: Double(p[2]) ?? 0, light: Double(p[3]) ?? 0.5, strength: Double(p[4]) ?? 1)
                            ProfileStore.shared.set { $0.ground = g }
                        } else { ProfileStore.shared.set { $0.ground = nil } }
                    }
                    if a == "natsearch" { edit.query = p.dropFirst(2).joined(separator: " ") }
                    if a == "nats", let m = map {
                        if p.count > 2 { edit.setNationalities(p[2] == "none" ? [] : Array(p.dropFirst(2)), map: m) }
                        NSLog("wya profile nats: %@ picture %@", edit.nationalities.joined(separator: " "), ProfileStore.shared.me.picture ?? "-")
                    }
                    // profile look <saturation> <power>: the gradient's strength, to compare (0 0 = its own)
                    if a == "look", p.count > 3 { ProfileView.look = SIMD2(Double(p[2]) ?? 0, Double(p[3]) ?? 0) }
                    NSLog("wya profile: stats %d stamps %d badges %d ready %d pack %d", ProfileNumbers.shared.stats, ProfileNumbers.shared.stamps, ProfileNumbers.shared.badges, ProfileNumbers.shared.ready ? 1 : 0, BadgeStore.shared.ready ? 1 : 0)
                    // profile dump: every stat's row and every badge you have, in the log (to check the counts by hand)
                    if a == "dump" || a == "book" {
                        if let w = map?.world, let b = BadgeStore.shared.book(w) {
                            let more = b.catalog.filter { $0.live == "more" }.count
                            NSLog("wya profile book: catalog %d badges (%d counted by the tally), places in the world %d of %d", b.catalog.count, more, b.world.countries.count, w.places.count)
                        } else { NSLog("wya profile book: none") }
                    }
                    if a == "dump" {
                        for g in ProfileNumbers.shared.groups { for r in g.rows { NSLog("wya stat | %@ | %@ | %@", g.title, r.label, r.value) } }
                        for s in ProfileNumbers.shared.sections { for r in s.rows { NSLog("wya stat | %@ | %@ | %@", s.name, r.label, r.value) } }
                        for b in ProfileNumbers.shared.earned { NSLog("wya badge | %@ | %@ | level %d | have %d | %@", b.id, b.name, b.level, b.have, b.family) }
                    }
                case "maptab": if let w = water, let m = map { WaterView.mapAgain(water: w, map: m) }
                // tabgo 0|1|2: that tab, as its button does when it is another tab (the tab change's own hook first)
                case "tabgo":
                    water?.onTabChange?()
                    NotificationCenter.default.post(name: Notification.Name("wyaTestTab"), object: Int(a) ?? 0)
                case "streak": map?.streakHeld = true; map?.streakWeeks = Int(a) ?? 0
                case "sunpick": map?.sunPicked = a == "on"
                case "settings": if a == "on" { head?.openSettings() } else { head?.closeSettings() }
                case "frames":
                    NSLog("wya frames content %@", NSCoder.string(for: contentFrame))
                    // the windows and their root views, to see whether anything has been moved (the keyboard)
                    for w in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows) {
                        let v = w.rootViewController?.view
                        NSLog("wya frames %@ level %.0f frame %@ root %@ bounds %@ safe %@", String(describing: type(of: w)), w.windowLevel.rawValue,
                              NSCoder.string(for: w.frame), NSCoder.string(for: v?.frame ?? .zero), NSCoder.string(for: v?.bounds ?? .zero),
                              NSCoder.string(for: CGRect(x: 0, y: v?.safeAreaInsets.top ?? 0, width: 0, height: v?.safeAreaInsets.bottom ?? 0)))
                    }
                case "burst": Snap.burst(ms: Int(a) ?? 1000)
                case "quiet": break
                // block ms: the main thread held that long (to see the hang watch say where it is)
                case "block": Thread.sleep(forTimeInterval: (Double(a) ?? 4000) / 1000)
                // searchpick <id>: that place's search result picked (Head's pick)
                // pins drop x y (a hold there) | pins select <n> | pins none: Pins' map without a finger
                case "pins":
                    if a == "drop", p.count > 3, let x = Double(p[2]), let y = Double(p[3]), let v = PinsMapState.shared.view {
                        let c = v.convert(CGPoint(x: x, y: y), toCoordinateFrom: v)
                        PinStore.shared.drop(at: c, country: map.flatMap { PinsMapView.Coordinator.country($0, c) })
                    } else if a == "select", p.count > 2, let n = Int(p[2]), n < PinStore.shared.pins.count {
                        PinStore.shared.selected = PinStore.shared.pins[n].id
                    } else if a == "move", p.count > 4, let n0 = Int(p[2]), case let n = n0 < 0 ? PinStore.shared.pins.count + n0 : n0,
                              n >= 0, n < PinStore.shared.pins.count,
                              let x = Double(p[3]), let y = Double(p[4]), let v = PinsMapState.shared.view {
                        // pins move <n> <x> <y>: pin n set down at that screen point, as a drag lets it go there
                        let c = v.convert(CGPoint(x: x, y: y), toCoordinateFrom: v)
                        PinStore.shared.move(PinStore.shared.pins[n].id, to: c, country: map.flatMap { PinsMapView.Coordinator.country($0, c) })
                    } else if a == "colour", p.count > 2, let n = Int(p[2]), n < PinStore.shared.pins.count {
                        // pins colour <n>: a pick made in its picker and the picker closed (one undo step)
                        let s = PinStore.shared, id = s.pins[n].id
                        s.colourStart(id); s.colour(id, ColourPick(hue: 0.6, light: 0.5, strength: 0.9)); s.colourEnd()
                    } else if a == "kind" || a == "photo", p.count > 2, let n0 = Int(p[2]),
                              case let n = n0 < 0 ? PinStore.shared.pins.count + n0 : n0, n >= 0, n < PinStore.shared.pins.count {
                        // pins kind <n> <kind>|none: pin n's category (n -1: the last pin)
                        // pins photo <n> on|off: a drawn test picture as its photo, or none
                        let s = PinStore.shared, id = s.pins[n].id
                        if a == "kind" { s.kind(id, p.count > 3 && p[3] != "none" ? p[3] : nil) }
                        else if p.count > 3, p[3] == "on" {
                            let img = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { c in
                                let g = CGGradient(colorsSpace: nil, colors: [UIColor.systemTeal.cgColor, UIColor.systemOrange.cgColor] as CFArray, locations: nil)!
                                c.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 1200, y: 800), options: [])
                            }
                            s.photo(id, img.jpegData(compressionQuality: 0.9))
                        } else { s.photo(id, nil) }
                    } else if a == "routedrop", p.count > 3 {
                        // pins routedrop <from> <to>: a test's own route taken away again, found by its two spots' names
                        // (only a route between spots of exactly those names; never one between pins)
                        let r = PinRoutes.shared
                        let mine = r.routes.filter { ($0.spots ?? []).count == 2 && Set(($0.spots ?? []).map(\.name)) == Set([p[2], p[3]]) }
                        for x in mine { r.remove(x.id, undoable: false) }
                        NSLog("wya pins routedrop: %d gone, %d left", mine.count, r.routes.count)
                    } else if a == "end" { PinStore.shared.endAsked += 1
                    } else if a == "state" {
                        // pins state: how many pins and routes, each pin's colour and where it is
                        let s = PinStore.shared
                        NSLog("wya pins state: %d pins, %d routes, redo %d; %@", s.pins.count, PinRoutes.shared.routes.count, MarkStore.shared.canRedo ? 1 : 0,
                              s.pins.map { String(format: "%@ %.3f,%.3f %@", $0.title, $0.lat, $0.lon, $0.pick == nil ? "black" : "coloured") }.joined(separator: " | "))
                    } else if a == "dropat", p.count > 3, let la = Double(p[2]), let lo = Double(p[3]) {
                        // pins dropat <lat> <lon>: a pin there, named as a hold names it (its country logged)
                        let c = CLLocationCoordinate2D(latitude: la, longitude: lo)
                        let k = map.flatMap { PinsMapView.Coordinator.country($0, c) }
                        NSLog("wya pins dropat %.3f %.3f: our country %@", la, lo, k?.name ?? "none")
                        PinStore.shared.drop(at: c, country: k)
                    } else if a == "route", p.count > 3, let n = Int(p[2]), let k = Int(p[3]), n < PinStore.shared.pins.count, k < PinStore.shared.pins.count {
                        // pins route <n> <m>: Route from here on pin n, then pin m tapped (8.6)
                        PinRoutes.shared.start(.from, at: PinStore.shared.pins[n].id)
                        _ = PinRoutes.shared.pinTapped(PinStore.shared.pins[k].id)
                    } else if a == "look", p.count > 4, let la = Double(p[2]), let lo = Double(p[3]), let d = Double(p[4]), let v = PinsMapState.shared.view {
                        // pins look <lat> <lon> <degrees>: Apple's map there, that many degrees tall (kept to a span Apple's
                        // map takes: a span past the world stopped the app)
                        let dd = min(170, max(0.001, d))
                        v.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: max(-85, min(85, la)), longitude: max(-180, min(180, lo))),
                                                       span: MKCoordinateSpan(latitudeDelta: dd, longitudeDelta: min(359, dd))), animated: false)
                    } else if a == "routeland", p.count > 3, let la = Double(p[2]), let lo = Double(p[3]) {
                        // pins routeland <lat> <lon>: a tap on land there while a chip waits
                        let c = CLLocationCoordinate2D(latitude: la, longitude: lo)
                        _ = PinRoutes.shared.landTapped(c, country: map.flatMap { PinsMapView.Coordinator.country($0, c)?.name } ?? "Land")
                    } else if a == "routecolour", p.count > 3, let n = Int(p[2]), n < PinRoutes.shared.routes.count, let h = Double(p[3]) {
                        // pins routecolour <n> <hue>: route n in that colour, as the picker sets it
                        PinRoutes.shared.colour(PinRoutes.shared.routes[n].id, ColourPick(hue: h, light: 0.55, strength: 0.9))
                    } else if a == "routepick", p.count > 2, let n = Int(p[2]), n < PinRoutes.shared.routes.count, let w = water {
                        // pins routepick <n>: its Colour picked from the route's menu (nothing changed until a colour is moved)
                        PinStore.shared.selected = nil; PinRoutes.shared.close()
                        PinRoutes.shared.colouring = PinRoutes.shared.routes[n].id
                        if w.stop == .quarter || w.stop == .closed { w.go(.half) }
                    } else if a == "routeclose" { PinRoutes.shared.close()
                    // pins routeempty: the dock's Route tool
                    } else if a == "routeempty" { PinRoutes.shared.openEmpty()
                    // pins days: how many pins were made on each day, logged with every pin (name, place, day, where)
                    // pins prune <yyyy-mm-dd> ...: the pins made on those days deleted, after pins.json is copied beside
                    // itself (pins-backup-<time>.json); the routes that end on them go with them
                    } else if a == "days" || a == "prune" {
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                        let s = PinStore.shared
                        var per: [String: Int] = [:]
                        for (i, pin) in s.pins.enumerated() {
                            let d = f.string(from: pin.made)
                            per[d, default: 0] += 1
                            NSLog("wya pin %d | %@ | %@ | %@ | %.4f,%.4f", i, pin.title, pin.place, d, pin.lat, pin.lon)
                        }
                        NSLog("wya pins by day: %@; routes %d", per.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "), PinRoutes.shared.routes.count)
                        if a == "prune" {
                            let days = Set(p.dropFirst(2))
                            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                            guard let from = dir?.appendingPathComponent("pins.json"),
                                  let to = dir?.appendingPathComponent("pins-backup-\(Int(Date().timeIntervalSince1970)).json"),
                                  (try? FileManager.default.copyItem(at: from, to: to)) != nil else {
                                NSLog("wya pins backup FAILED: nothing deleted"); break
                            }
                            NSLog("wya pins backup: %@", to.path)
                            let gone = s.pins.filter { days.contains(f.string(from: $0.made)) }
                            for pin in gone { s.remove(pin.id, undoable: false) }
                            NSLog("wya pins pruned: %d gone, %d left, routes %d", gone.count, s.pins.count, PinRoutes.shared.routes.count)
                        }
                    // pins add: the toolkit's Add pin; pins unadd: the pin it made taken away again (a test's own pin)
                    // (only ever the pin this test added: its id is kept from the add)
                    } else if a == "add", let w = water {
                        let before = Set(PinStore.shared.pins.map(\.id))
                        PinsDockState.shared.addPin(water: w)
                        testPin = PinStore.shared.pins.first { !before.contains($0.id) }?.id
                    } else if a == "unadd", let id = testPin { PinStore.shared.remove(id, undoable: false); testPin = nil
                    } else if a == "list" {
                        for (i, pin) in PinStore.shared.pins.enumerated() { NSLog("wya pin %d %@ (%@)", i, pin.title, pin.place) }
                        for (i, r) in PinRoutes.shared.routes.enumerated() {
                            NSLog("wya route %d %@ -> %@ %@ walk %d", i, PinRoutes.shared.end(r.from, r)?.title ?? "?", PinRoutes.shared.end(r.to, r)?.title ?? "?", r.words, r.walk == true ? 1 : 0)
                        }
                    } else if a == "none" { PinStore.shared.selected = nil
                    } else if a == "colour", p.count > 2, let h = Double(p[2]), let id = PinStore.shared.selected {
                        PinStore.shared.colour(id, ColourPick(hue: h, light: 0.55, strength: 0.9))
                    }
                // menu country <id> <row> | menu pin <n> <row> | menu at <x> <y> <row>: that hold menu built as a hold
                // builds it, and the row with those words chosen (as a finger would, after the menu)
                case "menu":
                    var row = p.dropFirst(3).joined(separator: " ")
                    var menu: UIMenu?
                    if a == "at", p.count > 4, let x = Double(p[2]), let y = Double(p[3]), let m = map, let w = water, let h = head {
                        row = p.dropFirst(4).joined(separator: " ")
                        let mp = m.mapPoint(CGPoint(x: x, y: y))
                        let i = m.world?.place(at: SIMD2(Float(mp.x), Float(mp.y))) ?? -1
                        menu = ContentView.countryMenu(i, at: CGPoint(x: x, y: y), map: m, water: w, head: h)
                    }
                    if a == "country", p.count > 3, let m = map, let w = water, let h = head, let i = m.world?.placeIndex[p[2]] {
                        let r = m.screenRect(of: i)
                        menu = ContentView.countryMenu(i, at: CGPoint(x: r.midX, y: r.midY), map: m, water: w, head: h)
                    } else if a == "pin", p.count > 3, let n = Int(p[2]), n < PinStore.shared.pins.count {
                        menu = PinAnnotationView.menu(PinStore.shared.pins[n].id)
                    } else if a == "route", p.count > 3, let n = Int(p[2]), n < PinRoutes.shared.routes.count {
                        // menu route <n> <row>: the kept route n's hold menu (11.5)
                        menu = PinRoutes.shared.menu(PinRoutes.shared.routes[n].id)
                    }
                    if let menu { Self.choose(row, in: menu) }
                // regionat <cc> <lat> <lon>: the first-level region the upload's second round finds there, logged
                case "regionat":
                    if p.count > 3, let m = map, let w = m.world, let la = Double(p[2]), let lo = Double(p[3]) {
                        let s = HistoryReader.Sample(lat: la, lon: lo, at: Date(), offset: 0, end: nil, asset: nil)
                        let r = await UploadState.regionsFound(in: [a], samples: [s], world: w, source: .history)
                        NSLog("wya regionat %@ %.4f %.4f -> %@", a, la, lo, r.map(\.name).joined(separator: ", "))
                    }
                // report <country id>: its page opened at Report a mistake (a hold menu's Report a wrong place)
                case "report":
                    if let m = map, let i = m.world?.placeIndex[a] {
                        PlacePageState.shared.openReporting(.country(a), name: m.world!.places[i].n, country: a, from: m.screenRect(of: i))
                    }
                // cardtap stamp: the open country card's Stamp / Stamped pressed
                case "cardtap": if a == "stamp" { CardTest.stamp?() }
                case "searchpick": if let i = map?.world?.placeIndex[a] { HeadTest.pick?(i) }
                // recent: the recent searches in the log; recent drop <id>: one taken out again (a test's own pick)
                case "recent":
                    if a == "drop", p.count > 2 { MapSettingsStore.shared.change { $0.recent.removeAll { $0 == p[2] } } }
                    NSLog("wya recent searches: %@", MapSettingsStore.shared.value.recent.joined(separator: ","))
                case "tap":
                    // tap x y (screen points): what a finger there would press, logged and pressed
                    if p.count > 2, let x = Double(p[1]), let y = Double(p[2]), let m = map {
                        let h = m.hit(at: CGPoint(x: x, y: y))
                        NSLog("wya tap %.0f %.0f -> %@", x, y, h.flatMap { m.world?.places[$0].id } ?? "nothing")
                        m.pressed = h
                        // tap x y go: and handed over as a confirmed tap (what a real tap does once the double-tap window passes)
                        if p.count > 3, p[3] == "go", let h { m.onPlaceTap?(h, CGPoint(x: x, y: y)) }
                    }
                // unlive <country id>: its Lived taken off, its details and times kept (test data clean-up)
                case "unlive":
                    let k = PlaceKey.country(a)
                    if let d = await MarkStore.shared.details(k), let w = map?.world, let i = w.placeIndex[a] {
                        await MarkStore.shared.setDetails(k, name: w.places[i].n, details: d.details, times: d.times, lived: false)
                    }
                case "mark":
                    // mark <place id> stamp|wish|none: the place's marks change (a fill front from its middle)
                    // through the store, as every marking surface does (MarkStore)
                    if p.count > 2, map?.world?.placeIndex[p[1]] != nil {
                        let k = PlaceKey.country(p[1]), st = MarkStore.shared
                        if p[2] == "stamp" { await st.stamp(k, source: .hand) }
                        else if p[2] == "wish" { await st.wish(k, source: .hand) }
                        else if st.state(k).stamped { await st.unstamp(k) } else { await st.unwish(k) }
                    }
                // unmarkregions <cc> [list|<region id>]: that country's stamped regions logged, or one (or all) unstamped
                // (test data clean-up)
                case "unmarkregions":
                    let mine = MarkStore.shared.marks.filter { $0.key.kind == .region && $0.value.stamped && $0.key.id.lowercased().hasPrefix(a + "/") }
                    NSLog("wya regions stamped in %@: %@", a, mine.keys.map(\.id).sorted().joined(separator: " "))
                    if p.count > 2, p[2] == "list" { break }
                    for k in mine.keys where p.count < 3 || k.id == p[2] { await MarkStore.shared.unstamp(k) }
                case "undo": await MarkStore.shared.undo()
                // nationality <id> | none: Profile's first nationality, for the home's centre (1.4)
                case "nationality":
                    if a == "none" { UserDefaults.standard.removeObject(forKey: MapController.nationalitiesKey) }
                    else { UserDefaults.standard.set([a], forKey: MapController.nationalitiesKey) }
                    map?.refreshHome(); map?.goHome()
                case "hittest": if let m = map { HitTest.run(map: m) }
                case "action":
                    // action <id> [arg] [source]: one registered action, logged with the screen state after it
                    let ok = await Actions.shared.perform(a, p.count > 2 ? p[2] : nil,
                                                          source: ActionSource(rawValue: p.count > 3 ? p[3] : "you") ?? .you)
                    try? await Task.sleep(for: .milliseconds(100))
                    var line = "action \(a) \(p.count > 2 ? p[2] : "") -> \(ok)"
                    if let m = map, let w = water, let h = head {
                        line += "\n\(ScreenStateSource(map: m, water: w, head: h, tab: { 0 }).now())"
                    }
                    line += "\nregistered: \(Actions.shared.all.keys.sorted().joined(separator: ", "))"
                    line += "\nfeatures: " + Feature.allCases.map { "\($0.rawValue) \($0.isOn)" }.joined(separator: ", ")
                    try? line.write(toFile: Snap.dir + "/action.log", atomically: true, encoding: .utf8)
                case "borders":
                    // borders defacto|un|<KEY> [piece=owner,...] [fallback un]: the map in another borders view; the time
                    // it took and the caption after, into snaps/borders.log
                    let v: Borders.View = a == "defacto" ? .deFacto : a == "un" ? .unitedNations : .country(a)
                    var picks: [String: String] = [:]
                    if p.count > 2, p[2] != "-" {
                        for kv in p[2].split(separator: ",") { let x = kv.split(separator: "="); if x.count == 2 { picks[String(x[0])] = String(x[1]) } }
                    }
                    let fb: Borders.View = p.count > 3 && p[3] == "un" ? .unitedNations : .deFacto
                    let t0 = CACurrentMediaTime()
                    let ok = await map?.setBorders(v, picks: picks, fallback: fb) ?? false
                    let ms = Int((CACurrentMediaTime() - t0) * 1000)
                    let line = "borders \(a) picks \(picks) -> \(ok) in \(ms) ms; caption \(map?.count.n ?? -1) of \(map?.count.of ?? -1); dotted \(Borders.dottedPlaces.count)"
                    try? line.write(toFile: Snap.dir + "/borders.log", atomically: true, encoding: .utf8)
                case "shake": NotificationCenter.default.post(name: .wyaShake, object: nil)
                case "redo": NotificationCenter.default.post(name: .wyaRedo, object: nil)
                // card <id>: its stamping card, as a tap on the place opens it; details: that card's Details;
                // close: Details first, then the card (as taps off do)
                case "card":
                    if let m = map, let w = m.world, let i = w.places.firstIndex(where: { $0.id == a }) {
                        let p = w.places[i]
                        CardState.shared.open(i, at: m.screenPoint(SIMD2(p.c[0], p.c[1])), map: m, water: water)
                    }
                // list on|off: the Stamped list, as the caption's number opens and closes it
                case "list": if a == "off" { water?.closeList() } else { water?.openList() }
                // listdetails <id>: a row of the Stamped list swiped right (Details from the list, A4.21)
                case "listdetails": StampedList.testDetails?(a)
                // upload open | close | choose 0|1 | back: the upload sheet (9.3) as the Upload tool, a tap off, a tap on a
                // choice and the swipe right would
                case "upload":
                    switch a {
                    case "open": if let water, let map { UploadState.shared.open(water: water, map: map) }
                    case "close": UploadState.shared.close()
                    case "back": UploadState.shared.back()
                    case "choose": UploadState.shared.choose(Int(p.count > 2 ? p[2] : "0") ?? 0)
                    case "read": UploadState.shared.testRead(empty: p.count > 2 && p[2] == "none", more: p.count > 2 && p[2] == "more")
                    case "more": UploadState.shared.addMore()
                    // upload file <name in snaps>: as Files would hand it over
                    case "file": if p.count > 2 { UploadState.shared.imported([URL(fileURLWithPath: Snap.dir + "/" + p[2])]) }
                    case "cancel": UploadState.shared.cancel()
                    case "go": UploadState.shared.go()
                    case "drop": if let m = map, let w = m.world, let i = w.places.firstIndex(where: { $0.id == (p.count > 2 ? p[2] : "") }) { _ = UploadState.shared.tap(i) }
                    // upload dates <id> | trip <id> <k> | show <id>: the review row's hold menu and a trip's ×
                    case "dates": if p.count > 2 { UploadState.shared.toggleDates(p[2]) }
                    case "trip": if p.count > 3, let k = Int(p[3]) { UploadState.shared.tapTrip(p[2], k) }
                    case "show": if let m = map, let i = m.world?.placeIndex[p.count > 2 ? p[2] : ""] { UploadState.shared.show(i) }
                    default: break
                    }
                // drows <addtime | removelived N | addplace <kind> <name> | removeplace N>: Details' rows (A4.14 / A4.15)
                case "drows": DetailsSheet.test?(Array(p.dropFirst()))
                case "session": restoreSession?()
                case "waterhint": water?.hint()
                // lock on | off | press: the zoom column's lock, and a press on the locked map (A1.9)
                case "lock": if a == "press" { Feel.refuse(); map?.lockedPress() } else { map?.locked = a == "on" }
                // hints: forget that the gestures were used and play the first-time hints (A3.15)
                case "hints":
                    for k in ["hint.water", "hint.pull", "hint.hold"] { UserDefaults.standard.removeObject(forKey: k) }
                    if let water, let head { Hints.shared.start(water: water, head: head) }
                // sideways on | off: the sideways mark, and out of full screen (1.11)
                case "sideways":
                    if a == "off" { Sideways.shared.leave() }
                    // sideways frame 0.5: the turn held at that point (sideways frame none: let go)
                    else if a == "frame" { Sideways.shared.testTurn = p.count > 2 ? Double(p[2]) : nil }
                    else if let water, let head, let map { Sideways.shared.enter(water: water, head: head, map: map) { CardState.shared.close(map: map) } }
                // detailsthing: Details of the first stamped thing (a mountain, a museum, a circuit), to see the form a
                // thing gets; nothing is written unless a field is changed
                case "detailsthing":
                    if let water, let (k, _) = MarkStore.shared.marks.filter({ $0.key.kind == .thing && $0.value.stamped }).min(by: { $0.key.id < $1.key.id }) {
                        let name = ThingStore.shared.thing(k.id)?.1.name ?? ThingIndex.shared.hit(k.id)?.name ?? CollectionStore.shared.item(k)?.name ?? k.id
                        NSLog("wya detailsthing %@ %@", k.description, name)
                        DetailsState.shared.open(k, name: name, water: water)
                    } else { NSLog("wya detailsthing: no stamped thing") }
                case "details":
                    if let m = map, let w = m.world, let i = CardState.shared.place, let water {
                        CardState.shared.heldTop = water.form().top
                        DetailsState.shared.open(.country(w.places[i].id), name: w.places[i].n, water: water)
                    }
                // book [n]: the passport tool pressed (the book out or back); with n, open on page n (1-based)
                // regionpick fr: the Regions list's row for that place tapped (A6.7)
                // regiontap x y: a tap at that screen point on the region map, as a confirmed map tap
                case "regionpick":
                    if let m = map { RegionsMenuModel.shared.build(map: m) }
                    if let r = RegionsMenuModel.shared.rows.first(where: { $0.flag == a.lowercased() }) {
                        RegionsMenuModel.shared.load(r.flag)
                        RegionsMenuModel.shared.onPick?(r)
                    } else { NSLog("wya regionpick %@: not in the list", a) }
                // regiondirect fr: a country's "Open its region map" (A6.14), from whatever mode
                // thingfind jfk: search's first thing found, shown (as its row's tap)
                case "thingfind":
                    ThingIndex.shared.load()
                    for _ in 0 ..< 150 where !ThingIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let t = ThingIndex.shared.hits(p.dropFirst().joined(separator: " "), open: nil).first { map?.showThing(file: t.file, id: t.id) }
                // thingpage louvre museum: the first thing found, its country's things read, its page opened (Part 16)
                case "thingpage":
                    ThingIndex.shared.load()
                    for _ in 0 ..< 150 where !ThingIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let h = ThingIndex.shared.hits(p.dropFirst().joined(separator: " "), open: nil).first {
                        ThingStore.shared.load(h.file)
                        for _ in 0 ..< 100 where ThingStore.shared.things(h.file) == nil { try? await Task.sleep(for: .milliseconds(100)) }
                        if let t = ThingStore.shared.things(h.file)?.first(where: { $0.id == h.id }) {
                            PlacePageState.shared.open(t.key, name: t.name, what: t.line, country: h.file,
                                                       from: CGRect(x: 200, y: 400, width: 44, height: 44))
                        }
                    }
                // pick everywhere | pick it | pick cont Europe | pick reg Southern Europe: a shelf card's tap (7.5)
                case "pick":
                    let rest = p.dropFirst(2).joined(separator: " ")
                    if a == "everywhere" { map?.showPlacesMap(.everywhere) }
                    else if a == "cont" { map?.showPlacesMap(.continent(rest)) }
                    else if a == "reg" { map?.showPlacesMap(.region(rest)) }
                    else if a == "colfirst" {
                        // the first collection (pick colfirst): its map, as picking it in Places' search does
                        CollectionStore.shared.load()
                        for _ in 0 ..< 50 where !CollectionStore.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                        if let c = CollectionStore.shared.all.first { map?.showPlacesMap(.collection(c.id)) }
                    }
                    // pick row <n>: the n-th row of Places' menu (0: Cities), as a tap on it
                    else if a == "row", let n = Int(rest) {
                        CollectionStore.shared.load(); ThingIndex.shared.load()
                        for _ in 0 ..< 80 where !CollectionStore.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                        let menu = CollectionStore.shared.menu
                        if n < menu.count {
                            NSLog("wya pick row %d = %@", n, menu[n])
                            map?.showPlacesSet(menu[n])
                        }
                    }
                    else if a == "type" {
                        // pick type kind:3 / pick type f1-2026: a row of Places' menu tapped
                        CollectionStore.shared.load(); ThingIndex.shared.load()
                        for _ in 0 ..< 80 where !CollectionStore.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                        map?.showPlacesSet(rest)
                        if CollectionStore.shared.types(rest).isEmpty { water?.go(.quarter) }
                    }
                    // pick kind ocean / pick kind none: a kind under the picked set tapped; pick menu: the lime set tapped
                    else if a == "kind" { map?.showPlacesType(rest == "none" ? nil : rest) }
                    else if a == "menu" { map?.clearPlacesSet(); if water?.stop == .quarter { water?.go(.half) } }
                    else if a == "col" {
                        CollectionStore.shared.load()
                        for _ in 0 ..< 50 where !CollectionStore.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                        map?.showPlacesMap(.collection(rest))
                    }
                    else if let i = map?.world?.placeIndex[a] { map?.showPlacesMap(.country(i)) }
                // placeopen de: Places' country opened with its towns (7.4); placeopen off: back to the world
                case "placeopen":
                    if a == "off" { map?.closePlace(); map?.goHome() }
                    else if let m = map, let i = m.world?.placeIndex[a] { m.openPlace(i) }
                // page ru: a country's page opened from its box (Part 16); page off: closed
                case "page":
                    if a == "off" { PlacePageState.shared.close() }
                    // page acts: the open page's first eight activities, logged (to read many countries' lists at once)
                    else if a == "acts" {
                        let f = PlacePageState.shared.facts
                        NSLog("wya page acts %@ (%d): %@", PlacePageState.shared.top?.name ?? "?", f?.activities.count ?? -1,
                              (f?.activities.prefix(8).map { $0.name + " [" + String($0.line.prefix(28)) + "]" } ?? []).joined(separator: " | "))
                        NSLog("wya page highlights %@: %@", PlacePageState.shared.top?.name ?? "?", (f?.highlights.prefix(8).map(\.name) ?? []).joined(separator: " | "))
                        NSLog("wya page lines %@: %@", PlacePageState.shared.top?.name ?? "?", (f?.activities.prefix(6).map(\.line) ?? []).joined(separator: " || "))
                        NSLog("wya page rows %@: %@", PlacePageState.shared.top?.name ?? "?", (f?.rows.map { "\($0.0): \($0.1)" } ?? []).joined(separator: " | "))
                    }
                    else if a == "end" { PlacePageState.shared.toEnd += 1 }
                    // page city: the open page's first city pushed on top (16.7); page back: the top page closed
                    else if a == "city", let c = PlacePageState.shared.facts?.cities.first {
                        PlacePageState.shared.push(c.key, name: c.name, what: "Town in \(c.line)", country: PlacePageState.shared.country,
                                                   from: CGRect(x: 16, y: 520, width: 398, height: 52))
                    }
                    else if a == "back" { PlacePageState.shared.close() }
                    // page region: the open page's first region pushed on top, as its Regions row does
                    else if a == "region", let r = PlacePageState.shared.facts?.regions.first {
                        PlacePageState.shared.push(r.key, name: r.name, what: "Region of \(PlacePageState.shared.top?.name ?? "")",
                                                   country: PlacePageState.shared.country, code: r.code,
                                                   from: CGRect(x: 16, y: 520, width: 398, height: 52))
                    }
                    // page at <0..1>: the top page held part way open, to look at one frame of its growing
                    // page report <reason words>: Report a mistake open with that reason; page send: Send
                    else if a == "report" { PlacePageState.shared.reportTest = p.dropFirst(2).joined(separator: " ") }
                    else if a == "send" { PlacePageState.shared.sendTest += 1 }
                    else if a == "at", p.count > 2, let v = Double(p[2]) { PlacePageState.shared.top?.p = CGFloat(v) }
                    // page highlight: the open page's first highlight's page pushed (16.7)
                    else if a == "highlight", let h = PlacePageState.shared.facts?.highlights.first {
                        let cc = PlacePageState.shared.country
                        ThingStore.shared.load(cc)
                        PlacePageState.shared.push(PlaceKey(.thing, "wd:" + h.id), name: h.name, what: h.line, country: cc,
                                                   from: CGRect(x: 16, y: 500, width: 380, height: 300), photo: h.photo)
                    }
                    else if a == "sources" { PlacePageState.shared.sourcesTest += 1; PlacePageState.shared.toEnd = 5 }
                    else if let m = map, let i = m.world?.placeIndex[a], let pl = m.world?.places[i] {
                        PlacePageState.shared.open(.country(pl.id), name: pl.n, country: pl.id, from: m.screenRect(of: i))
                    }
                // owntest lat lon | owntest off: one own place made for a check (its name "owntest"), and only those taken
                // away again (the person's own places are never touched)
                case "owntest":
                    if a == "off" { for o in OwnPlaces.shared.all where o.name == "owntest" { OwnPlaces.shared.remove(o.id) } }
                    else if p.count > 2, let la = Double(a), let lo = Double(p[2]) {
                        _ = OwnPlaces.shared.make(name: "owntest", lat: la, lon: lo, cc: "es")
                    }
                // appletap x y: a tap on Apple's map under the world (Map: Apple), at that screen point
                case "appletap":
                    if p.count > 2, let x = Double(a), let y = Double(p[2]), let c = AppleWorldView.Coordinator.current,
                       let v = PinsMapState.shared.view { c.tap(at: CGPoint(x: x, y: y), in: v) }
                // ownclear: every own place removed with its stamp (test data)
                // (ownclear drawn: only the places with a drawn outline, the draw tool's test places)
                case "ownclear":
                    for o in OwnPlaces.shared.all where a != "drawn" || o.ring != nil {
                        await MarkStore.shared.unstamp(o.key, name: o.name)
                        OwnPlaces.shared.remove(o.id)
                    }
                // townpage frankf: the first town found's page (Part 16)
                case "townpage":
                    TownIndex.shared.load()
                    for _ in 0 ..< 150 where !TownIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let m = map, let t = TownIndex.shared.hits(p.dropFirst().joined(separator: " "), open: nil).first {
                        let country = m.world?.placeIndex[t.file].map { m.world!.places[$0].n } ?? ""
                        PlacePageState.shared.open(PlaceKey(.town, t.id), name: t.name, what: "Town in \(t.region), \(country)",
                                                   country: t.file, from: CGRect(x: 200, y: 400, width: 44, height: 44))
                    }
                // regionfind bavar: search's first region found from Countries, opened (as its row's tap)
                case "regionfind":
                    RegionIndex.shared.load()
                    for _ in 0 ..< 100 where !RegionIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let m = map, let h = head, let r = RegionIndex.shared.hits(p.dropFirst().joined(separator: " ")).first,
                       let i = m.world?.placeIndex[r.place] {
                        h.searching = false
                        ContentView.openRegionMap(i, head: h, row: r.row, focus: r.id, map: m)
                    }
                // townfind frankf: Places' search's first town shown (as the search key would)
                case "townfind":
                    TownIndex.shared.load()
                    for _ in 0 ..< 150 where !TownIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let m = map, let t = TownIndex.shared.hits(p.dropFirst().joined(separator: " "), open: m.placeOpenID).first {
                        head?.searching = false
                        m.showTown(file: t.file, id: t.id)
                    }
                // pinsfind paris: Pins' search's first town taken to on Apple's map (as a tap on its row would)
                case "pinsfind":
                    TownIndex.shared.load()
                    for _ in 0 ..< 150 where !TownIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let t = TownIndex.shared.hits(p.dropFirst().joined(separator: " "), open: nil).first {
                        head?.searching = false
                        let c = CLLocationCoordinate2D(latitude: t.lat, longitude: t.lon)
                        if !PinRoutes.shared.landTapped(c, country: t.name) {
                            PinsMapState.shared.found = (t.name, t.lat, t.lon)
                            PinStore.shared.selected = nil
                            water?.go(.quarter)
                            PinsMapState.shared.show(lat: t.lat, lon: t.lon, metres: t.people >= 1_000_000 ? 60_000 : 25_000)
                        }
                    }
                // itemfind yellowst: Places' search's first set place shown (as a tap on its row would)
                case "itemfind":
                    if let m = map, let f = CollectionStore.shared.find(p.dropFirst().joined(separator: " "), first: m.placesCollection).first {
                        head?.searching = false
                        CardState.shared.close(map: m); RegionCardState.shared.close(map: m)
                        water?.go(.quarter)
                        m.showSetPlace(f.list, id: f.item.id)
                    }
                case "regiondirect":
                    if let h = head, let i = map?.world?.placeIndex[a] { ContentView.openRegionMap(i, head: h) }
                // regionslow 8: the region borders' change at 1/8 speed (frame checks)
                case "regionslow": RegionLines.slow = Double(a) ?? 1
                // regionlevel 2: the open country's level from that row of its table (the level line's pick)
                case "regionlevel":
                    if let m = map, let sc = m.regionScene, let r = Int(a) {
                        if r == 99 { m.showRegionTowns() } else { m.leaveRegionTowns(); m.openRegions(sc.place, row: r) }
                    }
                // thingtap <words>: a tap on the open collection's stop whose name holds the words, at its mark; its mark
                // state logged a second later (D7: a stop's day as a visit)
                case "thingtap":
                    if let m = map, let c = m.markCollection {
                        let q = p.dropFirst().joined(separator: " ").lowercased()
                        if let it = c.items.first(where: { $0.name.lowercased().contains(q) || $0.label.lowercased().contains(q) }) {
                            // (its name when it is up; otherwise its own point: its mark, or the middle of its shape)
                            let pt = m.thingFrames[it.id].map { CGPoint(x: $0.midX, y: $0.midY) } ?? m.screenPoint(SIMD2(Double(it.at.x), Double(it.at.y)))
                            if let i = m.hit(at: pt) { m.onPlaceTap?(i, pt) } else { m.onSeaTap?() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                let st = MarkStore.shared.state(it.key)
                                NSLog("wya thingtap %@ (%@): stamped %d wished %d visits %d", it.name, it.date, st.stamped ? 1 : 0, st.wished ? 1 : 0, st.visits)
                            }
                        } else { NSLog("wya thingtap %@: no mark", q) }
                    }
                // rcard stamp | wish | close: the region card's place stamped or unstamped (wished or not) through the store,
                // as its buttons do; the card closed
                case "rcard":
                    let card = RegionCardState.shared
                    if a == "close", let m = map { card.close(map: m) }
                    else if let k = card.key {
                        let st = MarkStore.shared.state(k)
                        if a == "stamp" {
                            // (a region of the open map: with its parents, as the card's own button)
                            if let sc = map?.regionScene, let u = sc.unitIDs.firstIndex(of: k.id) {
                                if st.stamped { await RegionStamps.unstamp(u, in: sc) } else { await RegionStamps.stamp(u, in: sc, source: .hand) }
                            }
                            else if st.stamped { await MarkStore.shared.unstamp(k, name: card.name) } else { await MarkStore.shared.stamp(k, name: card.name) }
                        } else if a == "wish" {
                            if st.wished { await MarkStore.shared.unwish(k, name: card.name) } else { await MarkStore.shared.wish(k, name: card.name) }
                        }
                        map?.needsFrame = true
                    }
                // picker on|off | picker at <x 0-1> <y 0-1> | picker strength <0-1>: the colour picker's test host (Part 15)
                case "picker":
                    let t = PickerTest.shared
                    if a == "on" { t.on = true } else if a == "off" { t.on = false }
                    else if a == "at", p.count > 3, let x = Double(p[2]), let y = Double(p[3]) {
                        t.colour = ColourPick.at(CGPoint(x: x, y: y), strength: t.colour.strength); ColourStore.shared.add(t.colour)
                    } else if a == "strength", p.count > 2, let v = Double(p[2]) {
                        t.colour.strength = v; ColourStore.shared.add(t.colour)
                    }
                    NSLog("wya picker %@: P3 %.3f %.3f %.3f, %d kept", ColourNames.name(t.colour), t.colour.p3.x, t.colour.p3.y, t.colour.p3.z, ColourStore.shared.recent.count)
                // pinreview <map|apple|satellite|off> [spread|stacked|lines] | pinreview at <lat> <lon> <span>: the pins review (8.3)
                case "pinreview":
                    let r = PinReview.shared
                    if a == "off" { r.on = false }
                    else if a == "at", p.count > 4, let la = Double(p[2]), let lo = Double(p[3]), let sp = Double(p[4]) {
                        r.centre = CLLocationCoordinate2D(latitude: la, longitude: lo); r.span = sp
                    } else {
                        r.ground = a; if p.count > 2 { r.scene = p[2] }
                        r.on = true
                        if a != "map", let L = water?.layout { r.snapshot(size: CGSize(width: L.W, height: L.H)) }
                    }
                case "regiontap":
                    if let m = map, p.count > 2, let x = Double(p[1]), let y = Double(p[2]) {
                        let pt = CGPoint(x: x, y: y)
                        let mp = m.mapPoint(pt)
                        if let w = m.world, let wi = m.details?.place(at: SIMD2(Float(mp.x), Float(mp.y)), reach: 0, tiny: 0) ?? w.place(at: SIMD2(Float(mp.x), Float(mp.y))) {
                            NSLog("wya regiontap world place there: %@", w.places[wi].id)
                        }
                        if let i = m.hit(at: pt) {
                            NSLog("wya regiontap %.0f %.0f: region %d", x, y, m.regionPressed ?? -1)
                            m.onPlaceTap?(i, pt)
                        } else { NSLog("wya regiontap %.0f %.0f: nothing", x, y) }
                    }
                // regionfile fr: the place's bundled region level read back (D10), logged
                case "regionfile":
                    let cat = RegionCatalog.shared
                    for cc in p.dropFirst() {
                        guard let (row, lv) = cat.first(String(cc)), let f = cat.file(String(cc), row: row) else {
                            NSLog("wya regionfile %@: none", String(cc)); continue
                        }
                        let pts = f.units.flatMap { $0.rings.flatMap { $0 } }
                        let lo = pts.reduce(SIMD2(Double.infinity, .infinity)) { pointwiseMin($0, $1) }
                        let hi = pts.reduce(SIMD2(-Double.infinity, -.infinity)) { pointwiseMax($0, $1) }
                        NSLog("wya regionfile %@-%d %@: %d units, %d regions (table %d), %d points, box %.2f %.2f %.2f %.2f, pieces %@",
                              String(cc), row, lv.many, f.units.count, f.ids.count, lv.n, pts.count, lo.x, lo.y, hi.x, hi.y,
                              Set(f.units.compactMap(\.piece)).sorted().joined(separator: " "))
                    }
                // row labels on: a Map settings row set as a tap on it would (id, value id)
                case "row": if let m = map, p.count > 2 { _ = await MapSettingsRows.set(p[1], p[2], map: m) }
                // pinslook apple-satellite: Pins' map look, as its settings row sets it (not one of the shared rows)
                case "pinslook": MapSettingsStore.shared.change { $0.pinsMap = a }
                // pageturn 45: the passport's leaf held at that angle (> 0 forward, < 0 the previous page coming back)
                case "pageturn": BookState.shared.turn = Double(a) ?? 0
                case "book":
                    // book off: put away if out (a reset's step)
                    if a == "off" { BookState.shared.close(); break }
                    if let n = Int(a) { BookState.shared.page = max(0, n - 1) }
                    BookState.shared.toggle()
                case "verify":
                    if let m = map, let w = m.world, let i = CardState.shared.place, let water {
                        CardState.shared.heldTop = water.form().top
                        VerifyState.shared.open(.country(w.places[i].id), name: w.places[i].n, place: i, water: water)
                    }
                case "close":
                    if VerifyState.shared.isOpen, let water { VerifyState.shared.close(water: water) }
                    else if DetailsState.shared.isOpen, let water { DetailsState.shared.close(water: water) }
                    else if let m = map { CardState.shared.close(map: m) }
                // stamp <id>: a country stamped as a test would (undoable)
                case "stamp": await MarkStore.shared.stamp(.country(a))
                // slowmo N: the stamp's flight N times slower, for frame checks (slowmo 1 = real speed)
                case "slowmo": CardState.slow = Double(a) ?? 1
                // unstamp <id>: a test's stamp taken off again (test residue)
                case "unstamp": await MarkStore.shared.unstamp(.country(a))
                case "marks":
                    // every mark in the store (stamped, then wished), and the places not in the debug demo set
                    let ms = MarkStore.shared.marks
                    let st = ms.filter { $0.value.stamped }.keys.map(\.description).sorted()
                    let wi = ms.filter { $0.value.wished }.keys.map(\.description).sorted()
                    let demo = Set(MarkStore.demoStamped.map { "c:" + $0 })
                    let line = "stamped \(st.count): \(st.joined(separator: " "))\nwished \(wi.count): \(wi.joined(separator: " "))\nnot demo: \(st.filter { !demo.contains($0) }.joined(separator: " "))"
                    try? line.write(toFile: Snap.dir + "/marks.log", atomically: true, encoding: .utf8)
                // historycheck: the history reader's fixtures (shapes A to D, the offsets) against the map's shapes
                case "historycheck":
                    if let m = map {
                        let lines = HistoryCheck.run(map: m)
                        try? lines.joined(separator: "\n").write(toFile: Snap.dir + "/historycheck.log", atomically: true, encoding: .utf8)
                    }
                // photocheck: the photo library read (asks for access the first time)
                case "photocheck":
                    if let m = map {
                        let lines = await HistoryCheck.photos(map: m)
                        try? lines.joined(separator: "\n").write(toFile: Snap.dir + "/photocheck.log", atomically: true, encoding: .utf8)
                    }
                // link <url>: a link into the Map opened as the system would hand it over (19.6)
                case "link": if let m = map, let u = URL(string: a) { await DeepLink.open(u, map: m) {} }
                case "storecheck":
                    let lines = await StoreCheck.run()
                    try? lines.joined(separator: "\n").write(toFile: Snap.dir + "/storecheck.log", atomically: true, encoding: .utf8)
                case "importold":
                    // importold <file in snaps>: the old app's stamps.json read into the store; what came in, into
                    // snaps/import.log (each row's key, state, name, level, and whether details/proof were kept)
                    if let d = try? Data(contentsOf: URL(fileURLWithPath: Snap.dir + "/" + a)) {
                        let n = await MarkStore.shared.importOld(d)
                        var lines = ["imported \(n)"]
                        if let book = try? OldBook(json: d) {
                            lines.append("waiting: \(book.waiting)")
                            for r in book.rows {
                                lines.append("\(r.key) stamped \(r.stamped) wished \(r.wished) want \(r.want) times \(r.times) "
                                    + "name \(r.name) cc \(r.cc) lvl \(r.level) at \(r.at) came \(r.came.map { "\($0)" } ?? "-") "
                                    + "details \(r.details != nil) proof \(r.verification != nil) how \(r.how ?? "-")")
                            }
                        }
                        lines.append("store now: \(MarkStore.shared.marks.count) marks; caption \(map?.count.n ?? -1) of \(map?.count.of ?? -1)")
                        try? lines.joined(separator: "\n").write(toFile: Snap.dir + "/import.log", atomically: true, encoding: .utf8)
                    }
                case "counts":
                    // the Count service's totals per borders view and Count setting (Part 17 D18's check: the world's
                    // total equals what the caption shows; each view as the old app counted it), into snaps/counts.log
                    if let m = map, let w = m.world,
                       let u = Bundle.main.url(forResource: "disputes", withExtension: "json"), let d = try? Data(contentsOf: u),
                       let f = try? JSONDecoder().decode(DisputeFile.self, from: d) {
                        let places = w.places.map { ($0.id, $0.s ?? $0.n, $0.k) }
                        let views: [(String, Borders.View)] = [("de facto", .deFacto), ("UN", .unitedNations)]
                            + ["US", "RU", "CN", "MA", "RS", "KO", "IN", "PK"].map { ($0, Borders.View.country($0)) }
                        let mine = Set(m.stamped.map { w.places[$0].id })
                        var lines = ["counts \(Date())", "caption now: \(m.count.n) of \(m.count.of)"]
                        for (name, v) in views {
                            let pos = Positions(file: f, places: places, view: v)
                            for kind in [CountKind.stamps, .countries] {
                                let sh = MapCounts.shares(stamped: mine, world: w, count: kind, positions: pos)
                                let conts = sh.filter { $0.key != "World" }
                                let sum = conts.filter { $0.key != "Antarctica" }.values.reduce(0) { $0 + $1.total }
                                lines.append("\(name) \(kind.rawValue): world \(sh["World"]?.have ?? 0)/\(sh["World"]?.total ?? 0); "
                                    + conts.keys.sorted().map { "\($0) \(conts[$0]!.have)/\(conts[$0]!.total)" }.joined(separator: ", ")
                                    + "; continents (no Antarctica) sum \(sum)")
                            }
                        }
                        try? lines.joined(separator: "\n").write(toFile: Snap.dir + "/counts.log", atomically: true, encoding: .utf8)
                    }
                case "probe":
                    // probe x y (screen points): the rings there log how the morph laid them (snaps/probe.log)
                    if p.count > 2, let x = Double(p[1]), let y = Double(p[2]), let m = map {
                        let q = m.mapPoint(CGPoint(x: x, y: y))
                        MorphIndex.probeFile = Snap.dir + "/probe.log"
                        MorphIndex.probe = SIMD2(Float(q.x), Float(q.y))
                        MorphIndex.note(String(format: "probe at %.3f %.3f", q.x, q.y))
                        m.details?.dropTiles()
                    }
                case "detail": FrameStats.log("wya detail \(a): " + (map?.details?.debugState ?? "none"))
                case "morph": map?.details?.testMorph = a == "auto" ? nil : Float(a)
                case "coarse": map?.details?.testCoarse = a == "on"
                case "off": Perf.shared.off.insert(a)
                case "on": Perf.shared.off.remove(a)
                case "sun": map?.sunPicked = a == "on"
                case "tabicons": TabIconsTest.on = a == "on"
                // FINGERS ON THE MAP (Step 1b-ii): the same MapController calls the Metal view's touches make, frame by
                // frame, so a scripted gesture is the gesture. pinch <factor> <x> <y> <ms>; pan <dx> <dy> <ms>;
                // flick <dx> <dy> <ms> (a pan let go at its speed); longpress <x> <y> <ms>; twofinger <x> <y>
                case "pinch", "pan", "flick":
                    guard let m = map, p.count > 3 else { break }
                    let n1 = Double(p[1]) ?? 1, n2 = Double(p[2]) ?? 0, n3 = Double(p[3]) ?? 0
                    let ms = Int(p.count > 4 ? p[4] : (c == "pinch" ? "800" : "400")) ?? 400
                    let steps = max(1, ms / 8)
                    m.grab()
                    for _ in 0 ..< steps {
                        if c == "pinch" { m.zoom(by: pow(n1, 1 / Double(steps)), about: CGPoint(x: n2, y: n3)) }
                        else { m.pan(by: SIMD2(n1 / Double(steps), n2 / Double(steps))) }
                        try? await Task.sleep(for: .milliseconds(8))
                    }
                    m.release(velocity: c == "flick" ? SIMD2(n1, n2) / (Double(ms) / 1000) : nil)
                case "longpress":
                    guard let m = map, p.count > 2, let x = Double(p[1]), let y = Double(p[2]) else { break }
                    m.grab(); m.pressed = m.hit(at: CGPoint(x: x, y: y))
                    try? await Task.sleep(for: .milliseconds(Int(p.count > 3 ? p[3] : "700") ?? 700))
                    m.pressed = nil; m.release(velocity: nil)
                case "twofinger":
                    guard let m = map, p.count > 2, let x = Double(p[1]), let y = Double(p[2]) else { break }
                    m.twoFingerTap(at: CGPoint(x: x, y: y))
                case "measure": if a == "on" { FrameStats.start() } else { FrameStats.stop(p.count > 2 ? p[2] : "scene") }
                // draw own x y: your own place drawn on the open country, its first corner there (as Add a place here) |
                // draw pt x y: a corner tapped | draw stroke x1 y1 x2 y2 ...: a finger dragged through the points |
                // draw undo | draw done | draw cancel
                case "draw":
                    let t = DrawTool.shared
                    let n = p.dropFirst(2).compactMap { Double($0) }.map { CGFloat($0) }
                    if a == "own", n.count == 2, let m = map, let open = m.placeOpen {
                        let country = m.world.map { $0.places[open].n } ?? ""
                        if let w = water { ContentView.startOwnPlace(at: CGPoint(x: n[0], y: n[1]), place: open, country: country, map: m, water: w) }
                    } else if a == "pt", n.count == 2 {
                        t.touchBegan(CGPoint(x: n[0], y: n[1])); t.touchEnded(CGPoint(x: n[0], y: n[1]))
                    } else if a == "stroke", n.count >= 4 {
                        let pts = stride(from: 0, to: n.count - 1, by: 2).map { CGPoint(x: n[$0], y: n[$0 + 1]) }
                        t.touchBegan(pts[0])
                        // (the finger's path in 2 pt steps, as a real drag reports it)
                        for (a, b) in zip(pts, pts.dropFirst()) {
                            let k = max(1, Int(hypot(b.x - a.x, b.y - a.y) / 2))
                            for i in 1 ... k { t.touchMoved(CGPoint(x: a.x + (b.x - a.x) * CGFloat(i) / CGFloat(k), y: a.y + (b.y - a.y) * CGFloat(i) / CGFloat(k))) }
                        }
                        t.touchEnded(pts[pts.count - 1])
                    } else if a == "pins", let v = PinsMapState.shared.view, let w = water {
                        // draw pins: the tool on Apple's map (Pins' Draw)
                        PinDrawings.shared.start(on: v, water: w)
                    } else if a == "clearpins" {
                        // draw clearpins: the drawings in Pins made in the last 30 minutes taken away (test data; older
                        // ones are never touched)
                        for d in PinDrawings.shared.all where d.made > Date().addingTimeInterval(-1800) { PinDrawings.shared.remove(d.id, undoable: false) }
                    } else if a == "colour", let w = water, let d = PinDrawings.shared.all.last {
                        // draw colour [hue]: the newest drawing's colour sheet up (its menu's Colour); with a hue, that colour
                        PinDrawings.shared.colouring = d.id
                        w.go(.full)
                        if p.count > 2, let h = Double(p[2]) { PinDrawings.shared.colour(d.id, ColourPick(hue: h, light: 0.55, strength: 0.9)) }
                    } else if a == "redraw", let m = map, let w = water, let o = OwnPlaces.shared.all.last {
                        // draw redraw: the newest own place drawn again (as its menu's Draw its shape / Redraw)
                        ContentView.redrawOwn(o, map: m, water: w)
                    } else if a == "undo" { t.undo() } else if a == "done" { t.done() } else if a == "cancel" { t.cancel() }
                    NSLog("wya draw on %d points %d marks %d area %.2f km2 length %.2f km", t.on ? 1 : 0, t.points.count, t.marks.count, t.areaKm2, t.lengthKm)
                // sample on | off <name>: where the main thread spends its time (Design/Sampler.swift)
                case "sample": if a == "on" { Sampler.start() } else { Sampler.stop(p.count > 2 ? p[2] : "scene") }
                case "layout":
                    if let L = water?.layout {
                        NSLog("wya layout model %@ W %.1f H %.1f safeTop %.1f safeBottom %.1f island %@ corner %.0f", L.model, L.W, L.H, L.safeTop, L.safeBottom, NSCoder.string(for: L.island), L.screenCorner)
                    }
                case "planet": map?.testPlanet = Int(a)
                case "moon": map?.testMoon = a == "off" ? nil : Double(a)
                // filter 0..4: the moon's five looks (1.14)
                case "filter": map?.filter = Int(a) ?? 0
                // nocolour on | off | system: Differentiate Without Colour's patterns (1.14)
                case "nocolour": map?.testWithoutColour = a == "system" ? nil : a == "on"
                default: NSLog("wya test driver: unknown %@", l)
                }
            }
        }
    }
}

/// TEST ONLY: parts switched off to find what costs frames ("off <part>", "on <part>"; observed, so a switch takes
/// effect on the next frame): map, cosmos, planets, sun, stars, caption, sheetglass, sheet, tabs, head, zoom, pull
@MainActor @Observable
final class Perf {
    static let shared = Perf()
    var off: Set<String> = []
}
