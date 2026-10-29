import SwiftUI

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
    private var lostOwner = false
    /// where the whole content is on screen (to see whether the keyboard moves it)
    var contentFrame: CGRect = .zero

    func start(map: MapController, water: Water, head: HeadState) {
        #if targetEnvironment(simulator) && DEBUG
        self.map = map; self.water = water; self.head = head
        NSLog("wya test driver started")
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in NSLog("wya t keyboard will show") }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in NSLog("wya t keyboard did show") }
        let path = Snap.dir + "/cmd.txt"
        // a command left over from the last run is not run again
        lastID = (try? String(contentsOfFile: path, encoding: .utf8))?.split(separator: "\n").first.map(String.init) ?? ""
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated {
                if !Snap.isOwner {
                    // another copy of the app (another simulator) took the test files over: say so once
                    if !self.lostOwner {
                        self.lostOwner = true
                        let o = (try? String(contentsOfFile: Snap.dir + "/owner.txt", encoding: .utf8)) ?? "unreadable"
                        NSLog("wya test driver: owner is now %@, I am %@", o, Snap.me)
                    }
                    return
                }
                guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return }
                var lines = s.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
                guard let id = lines.first, id != self.lastID else { return }
                self.lastID = id
                lines.removeFirst()
                NSLog("wya test driver runs %@", lines.joined(separator: " | "))
                // "quiet" anywhere in the commands: no screen grabs (measuring lag, the grabs would be the lag)
                Snap.activeUntil = lines.contains("quiet") ? 0 : CACurrentMediaTime() + 20
                self.run(lines)
            }
        }
        #endif
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
                case "quick": head?.quickStamp = a == "on"
                case "dial": head?.testDial = a == "off" ? nil : CGFloat(Double(a) ?? 0)
                case "mode": head?.mode = HeadState.Mode(rawValue: Int(a) ?? 0) ?? .countries
                case "search":
                    if a == "off" { head?.searching = false }
                    else { NSLog("wya t search open"); head?.searching = true; head?.query = p.dropFirst().joined(separator: " ") }
                case "zoom":
                    if a == "in" { map?.zoomIn() } else if a == "out" { map?.zoomOut() } else { map?.goHome() }
                case "show":
                    if let m = map, let i = m.world?.placeIndex[a] { m.show(place: i) }
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
                case "streak": map?.streakWeeks = Int(a) ?? 0
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
                case "tap":
                    // tap x y (screen points): what a finger there would press, logged and pressed
                    if p.count > 2, let x = Double(p[1]), let y = Double(p[2]), let m = map {
                        let h = m.hit(at: CGPoint(x: x, y: y))
                        NSLog("wya tap %.0f %.0f -> %@", x, y, h.flatMap { m.world?.places[$0].id } ?? "nothing")
                        m.pressed = h
                    }
                case "off": Perf.shared.off.insert(a)
                case "on": Perf.shared.off.remove(a)
                case "sun": map?.sunPicked = a == "on"
                case "planet": map?.testPlanet = Int(a)
                case "moon": map?.testMoon = a == "off" ? nil : Double(a)
                default: NSLog("wya test driver: unknown %@", l)
                }
            }
        }
    }
}

/// TEST ONLY: parts of the screen switched off to find what costs frames ("off stars", "on stars")
@MainActor @Observable
final class Perf {
    static let shared = Perf()
    var off: Set<String> = []
}
