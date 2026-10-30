import SwiftUI

/// THE FIRST-TIME HINTS (Part 3, A3.15): once the map is ready and nothing has been touched for 1.2 s, the water rises
/// 24 pt and settles back (0.8 s); 0.4 s later the dot plays the first quarter of its own pull and goes back (0.8 s);
/// 0.4 s after that the dot shows a quarter of its gear and goes back (0.8 s); one soft landing each. A part never
/// plays again once you have done that gesture yourself (the hold's: once you have opened Map settings by holding the
/// dot), and plays again after 30 days without it; the pull's also after three short top pulls within a minute that
/// reach nothing (struggling). Any touch stops it where it is and it goes back on the settle curve.
@MainActor
final class Hints {
    static let shared = Hints()
    private let d = UserDefaults.standard
    private enum Part: String { case water, pull, hold }
    private var job = 0
    private var lastTouch = Date()
    private var shortPulls: [Date] = []
    private weak var water: Water?
    private weak var head: HeadState?

    /// the gestures, as you do them yourself
    func usedWater() { used(.water) }
    func usedPull() { used(.pull); shortPulls = [] }
    func usedHold() { used(.hold) }
    private func used(_ p: Part) { d.set(Date().timeIntervalSince1970, forKey: "hint.\(p.rawValue)") }
    private func due(_ p: Part) -> Bool {
        let t = d.double(forKey: "hint.\(p.rawValue)")
        return t == 0 || Date().timeIntervalSince1970 - t > 30 * 24 * 3600
    }

    /// a touch anywhere: a hint playing stops where it is and goes back
    func touched() {
        lastTouch = Date()
        guard job > 0 else { return }
        job += 1
        stopNow()
    }

    /// a top pull let go short of the AI: three within a minute is struggling, and the pull's hint plays again
    func shortPull() {
        let now = Date()
        shortPulls = shortPulls.filter { now.timeIntervalSince($0) < 60 } + [now]
        if shortPulls.count >= 3 {
            shortPulls = []
            d.removeObject(forKey: "hint.pull")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
                guard Date().timeIntervalSince(lastTouch) >= 1.2 else { return }
                play(only: [.pull])
            }
        }
    }

    /// at launch, once the map is ready and the loading screen has gone
    func start(water w: Water, head h: HeadState) {
        water = w; head = h
        lastTouch = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
            guard Date().timeIntervalSince(lastTouch) >= 1.19 else { return }
            play(only: [.water, .pull, .hold].filter(due))
        }
    }

    private func play(only parts: [Part]) {
        guard !parts.isEmpty, let w = water, let h = head, !w.upload, w.stop == .quarter, !h.searching, !h.toolsOpen,
              !h.settingsOpen, h.pull < 0.5, !Sideways.shared.on else { return }
        job += 1
        let me = job
        var at = 0.0
        for p in parts {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [self] in
                guard me == job else { return }
                switch p {
                case .water: w.hint()
                case .pull:
                    // as an 18 pt pull (the lime 34.8 pt, the dot 17.4 pt), there and back
                    withAnimation(.smooth(duration: 0.4)) { h.pull = 18 } completion: { [self] in
                        guard me == job else { return }
                        withAnimation(.smooth(duration: 0.4)) { h.pull = 0 }
                    }
                case .hold:
                    // a quarter of the gear shown round the dot, there and back; no settings
                    withAnimation(.smooth(duration: 0.4)) { h.gear = 0.25 } completion: { [self] in
                        guard me == job else { return }
                        withAnimation(.smooth(duration: 0.4)) { h.gear = 0 }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                    guard me == job else { return }
                    Feel.land(speed: 0)
                    if p == parts.last { job = 0 }
                }
            }
            at += 1.2
        }
    }

    private func stopNow() {
        guard let h = head else { return }
        job = 0
        if h.pullStop == 0, h.pull > 0.5, h.pull < 19 { withAnimation(Motion.settle) { h.pull = 0 } }
        if !h.settingsOpen, !h.dotHeld, h.gear > 0, h.gear < 0.3 { withAnimation(Motion.settle) { h.gear = 0 } }
    }
}
