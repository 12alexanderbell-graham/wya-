import SwiftUI

/// THE CURVES (Part 0.4), all in one place: every animation in the app takes its curve from here, so a recording can be
/// checked against Part 0.4's table and the Reduce Motion version is one switch.
/// - chrome: anything a tap moves (smooth 0.38 s; 0.47 / 0.82 / 0.95 / 0.99 of the way at 25 / 50 / 75 / 100%)
/// - quick: small things (smooth 0.26 s)
/// - settle: anything a finger lets go of (smooth 0.42 s)
/// - tight: the Reduce Motion version of every move (0.2 s, "Part 0.4's tight spring")
/// - camera: flights, the fill front, the border redraw (1 − e^(−wt)(1 + wt), w = 2π / 0.44, time scaled to the flight)
/// - blend: the continent's away blend, his one allowed fade (bez(0.3, 0, 0.3, 1), 0.5 s)
/// The sheet's water has its own critically damped spring (Part 2.3, Water.swift).
@MainActor
enum Motion {
    static var reduce: Bool { UIAccessibility.isReduceMotionEnabled }
    static var chrome: Animation { reduce ? tight : .smooth(duration: 0.38) }
    static var quick: Animation { reduce ? tight : .smooth(duration: 0.26) }
    static var settle: Animation { reduce ? tight : .smooth(duration: 0.42) }
    static let tight = Animation.smooth(duration: 0.2)
    /// the camera curve at t (0...1 of the move's own time): the old app's critically damped 0.44 s curve stretched to
    /// the move (0.67 / 0.94 / 0.99 / 1 at 25 / 50 / 75 / 100%)
    nonisolated static func camera(_ t: Double) -> Double {
        guard t < 1 else { return 1 }
        let w0 = 2 * Double.pi / 0.44, x = max(0, t) * 0.646
        return 1 - exp(-w0 * x) * (1 + w0 * x)
    }
    /// the continent blend at t (0...1 of 0.5 s): the old map.js cubic-bezier(.3, 0, .3, 1) (0.28 / 0.50 / 0.72 / 1)
    nonisolated static func blend(_ x0: Double) -> Double {
        let x = min(1, max(0, x0))
        // solve the curve's x(t) = x by Newton, then y(t)
        var t = x
        for _ in 0 ..< 8 {
            let u = 1 - t
            let fx = 3 * u * u * t * 0.3 + 3 * u * t * t * 0.3 + t * t * t - x
            let dx = 3 * u * u * 0.3 + 3 * t * t * 0.7
            if abs(dx) < 1e-6 { break }
            t = min(1, max(0, t - fx / dx))
        }
        let u = 1 - t
        return 3 * u * t * t + t * t * t
    }
    /// THE WATER'S PHYSICS can be switched off: every water animation reads this; the switch itself comes with the
    /// Settings book
    static var water: Bool {
        get { UserDefaults.standard.object(forKey: "waterPhysics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "waterPhysics") }
    }
}
