import SwiftUI
import UIKit

/// THE PULL DOWN FROM A LIST'S TOP (Apple's sheets): at full the rows in the water scroll (the Stamped list, map
/// settings, Details, Verify, a place's page sheet), and a pull down that starts with the list at its top brings the
/// water down instead of bouncing the list (8 Nov: it bounced, and only a thin strip over the rows moved the water).
/// Put inside a scroll view's content as a background; it finds that scroll view and watches its own pan: scrolled,
/// the list scrolls as ever; at its top and pulled down, the list stays put and the water follows the finger, as the
/// water's own drag does (Water.begin/move/end).
extension EnvironmentValues {
    @Entry var handoffWater: Water? = nil
}

struct WaterHandoff: View {
    /// a List: the probe is its background, beside its scroll view rather than inside it, so it looks below
    var beside = false
    @Environment(\.handoffWater) private var water
    var body: some View {
        if let water { HandoffProbe(water: water, beside: beside).frame(width: 0, height: 0).allowsHitTesting(false) }
    }
}

private struct HandoffProbe: UIViewRepresentable {
    let water: Water
    let beside: Bool
    func makeCoordinator() -> Watcher { Watcher(water: water) }
    func makeUIView(context: Context) -> UIView {
        let v = ProbeView()
        v.watcher = context.coordinator
        v.beside = beside
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.water = water }

    final class ProbeView: UIView {
        weak var watcher: Watcher?
        var beside = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // laid out a moment later (a List's scroll view is made after its background)
            DispatchQueue.main.async { [weak self] in self?.find() }
        }
        private func find() {
            guard window != nil else { return }
            if !beside {
                // the nearest scroll view above: the list this probe sits in
                var s = superview
                while let v = s, !(v is UIScrollView) { s = v.superview }
                if let sv = s as? UIScrollView { watcher?.watch(sv) }
                return
            }
            // a List's: the scroll view under the same parents, the one that covers where the probe is
            let here = convert(bounds, to: nil).origin
            var up: UIView? = superview
            for _ in 0 ..< 4 {
                guard let u = up else { break }
                if let sv = Self.scrolls(in: u).first(where: { $0.convert($0.bounds, to: nil).insetBy(dx: -2, dy: -2).contains(here) }) {
                    watcher?.watch(sv); return
                }
                up = u.superview
            }
        }
        private static func scrolls(in v: UIView) -> [UIScrollView] {
            var out: [UIScrollView] = []
            var queue = v.subviews
            while !queue.isEmpty, out.count < 8 {
                let x = queue.removeFirst()
                if let sv = x as? UIScrollView { out.append(sv) } else { queue.append(contentsOf: x.subviews) }
            }
            return out
        }
    }

    @MainActor final class Watcher: NSObject {
        var water: Water
        private weak var scroll: UIScrollView?
        private var startedAtTop = false
        private var handing = false
        private var bounced = true
        init(water: Water) { self.water = water }

        func watch(_ sv: UIScrollView) {
            guard sv !== scroll else { return }
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(pan(_:)))
            scroll = sv
            sv.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
            #if DEBUG
            NSLog("wya handoff watches a %@ %.0f pt high", String(describing: type(of: sv)), sv.bounds.height)
            #endif
        }

        private func atTop(_ sv: UIScrollView) -> Bool { sv.contentOffset.y <= -sv.adjustedContentInset.top + 1 }

        @objc private func pan(_ g: UIPanGestureRecognizer) {
            guard let sv = scroll, let win = sv.window else { return }
            switch g.state {
            case .began:
                // only at full: below it the rows do not scroll and the water's own drag has the finger
                startedAtTop = water.stop == .full && !water.held && atTop(sv)
                handing = false
            case .changed:
                let dy = g.translation(in: win).y
                if !handing, startedAtTop, dy > 0 {
                    handing = true
                    bounced = sv.bounces
                    sv.bounces = false
                    water.onTouch?()
                    // the water takes the finger from where it was when the pull began
                    let p = g.location(in: win)
                    water.begin(at: CGPoint(x: p.x, y: p.y - dy))
                }
                if handing {
                    // the list stays at its top while the water follows
                    sv.contentOffset.y = -sv.adjustedContentInset.top
                    water.move(to: g.location(in: win))
                } else if startedAtTop, dy < 0 {
                    // scrolled up first: the list's, to the end of this pull
                    startedAtTop = false
                }
            case .ended, .cancelled, .failed:
                if handing {
                    handing = false
                    sv.bounces = bounced
                    water.end(velocity: g.state == .ended ? g.velocity(in: win).y : 0)
                }
                startedAtTop = false
            default: break
            }
        }
    }
}
