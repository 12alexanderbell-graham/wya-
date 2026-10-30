import SwiftUI
import UIKit

/// A damped spring (study 2.3: one spring family, interruptible, starting from where things are).
/// `response` is the time of one oscillation; `damping` 1 means no bounce.
nonisolated struct Spring1 {
    var value: CGFloat
    var velocity: CGFloat = 0
    var target: CGFloat
    var response: CGFloat
    var damping: CGFloat

    init(_ v: CGFloat, response: CGFloat, damping: CGFloat) {
        value = v; target = v; self.response = response; self.damping = damping
    }

    mutating func step(_ dt: CGFloat) {
        let w = 2 * CGFloat.pi / response
        let a = -w * w * (value - target) - 2 * damping * w * velocity
        velocity += a * dt
        value += velocity * dt
    }

    var settled: Bool { abs(value - target) < 0.05 && abs(velocity) < 0.5 }
    mutating func snap() { value = target; velocity = 0 }
}

/// The water's maths, measured against Apple's sheets and UIScrollView (study 2.3).
nonisolated enum Flow {
    /// past an end things stretch less and less (Apple's rubber band, constant 0.55)
    static func rubber(_ x: CGFloat, _ d: CGFloat) -> CGFloat {
        guard d > 0, x != 0 else { return 0 }
        if x < 0 { return -rubber(-x, d) }
        return (1 - 1 / (x * 0.55 / d + 1)) * d
    }
    /// where a flick coasts to: UIScrollView's normal deceleration, 0.998 a millisecond
    static func project(_ velocity: CGFloat) -> CGFloat {
        let r: CGFloat = 0.998
        return velocity / 1000 * r / (1 - r)
    }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    static func clamp01(_ t: CGFloat) -> CGFloat { min(1, max(0, t)) }
    static func smooth(_ e0: CGFloat, _ e1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = clamp01((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t)
    }
}

/// Haptics are round for water (study 2.3): soft and scaled by speed, nothing on a slow settle; a tick at each stop.
@MainActor
enum Feel {
    /// every haptic, logged in debug builds so a scripted run can be matched to Part 0.3's table (Step 1k)
    static func trace(_ name: String) {
        #if DEBUG
        NSLog("wya feel %@", name)
        #endif
    }
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let tickGen = UISelectionFeedbackGenerator()

    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    static func tap() {
        trace("tap"); light.impactOccurred(intensity: 0.7) }
    /// a stamp landing: heavy, then light 70 ms later (Part 0.3, proposal)
    static func stamp() {
        trace("stamp")
        heavy.impactOccurred(intensity: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { light.impactOccurred(intensity: 0.6) }
    }
    /// a stamp or wish removed
    static func lift() {
        trace("lift"); light.impactOccurred(intensity: 0.5) }
    /// something that can't happen: rigid, twice, 80 ms apart
    static func refuse() {
        trace("refuse")
        rigid.impactOccurred(intensity: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { rigid.impactOccurred(intensity: 0.5) }
    }
    /// the undo drop rising: soft 0.3, 0.45, 0.6 at 0, 0.1, 0.2 s (proposal)
    static func pour() {
        trace("pour")
        for (i, v) in [0.3, 0.45, 0.6].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * Double(i)) { soft.impactOccurred(intensity: v) }
        }
    }
    static func tick() {
        trace("tick"); tickGen.selectionChanged() }
    static func notch() {
        trace("notch"); rigid.impactOccurred(intensity: 0.75) }
    static func land(speed: CGFloat) {
        trace("land")
        let s = min(1, abs(speed) / 2400)
        if s > 0.12 { soft.impactOccurred(intensity: 0.25 + 0.6 * s) }
    }
}

/// One display link for everything SwiftUI-side that moves (the water, the top pull, the camera's buttons):
/// it runs only while something moves, stepping at a fixed 240 Hz so 60 and 120 Hz screens feel the same.
@MainActor
final class Clock: NSObject {
    static let shared = Clock()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var carry: CFTimeInterval = 0
    private var bodies: [ObjectIdentifier: (CGFloat) -> Bool] = [:]
    private var frames: [ObjectIdentifier: () -> Void] = [:]

    /// `step` is called at 240 Hz and returns true while it still moves; `frame` once per screen frame after it.
    func run(_ owner: AnyObject, step: @escaping (CGFloat) -> Bool, frame: @escaping () -> Void = {}) {
        bodies[ObjectIdentifier(owner)] = step
        frames[ObjectIdentifier(owner)] = frame
        if link == nil {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            l.add(to: .main, forMode: .common)
            link = l
            last = 0
        }
    }

    @objc private func tick(_ l: CADisplayLink) {
        if last == 0 { last = l.timestamp; return }
        carry += min(0.1, l.timestamp - last)
        last = l.timestamp
        let h: CFTimeInterval = 1.0 / 240
        var moving: [ObjectIdentifier: Bool] = [:]
        while carry >= h {
            carry -= h
            // the step first: `moving[k] || s(h)` stopped stepping a body after its first step in a tick, so
            // everything ran at one step per frame, not 240 a second (half speed at 120 Hz, a quarter at 52 Hz)
            for (k, s) in bodies {
                let m = s(CGFloat(h))
                moving[k] = (moving[k] ?? false) || m
            }
        }
        for (k, f) in frames where bodies[k] != nil { f() }
        for (k, m) in moving where !m { bodies[k] = nil; frames[k] = nil }
        if bodies.isEmpty {
            link?.invalidate(); link = nil; last = 0; carry = 0
        }
    }
}
