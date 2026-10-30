import SwiftUI
import UIKit

/// THE UNDO GESTURES (Part 3.10): a shake or a three-finger swipe left undoes the store's last step, at any time and
/// on any tab, up to the session's 20 steps; a three-finger swipe right redoes (the book's proposal). The window
/// reports the shake and owns the swipes, so they work over the map, the water and every sheet alike; nothing of
/// iOS's own "Undo" alert is used (the store has its own undo).
extension Notification.Name {
    static let wyaShake = Notification.Name("wyaShake")
    static let wyaRedo = Notification.Name("wyaRedo")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .wyaShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

/// the three-finger swipes, put on the app's window once
@MainActor
enum ThreeFingerSwipes {
    private static var installed = false
    private final class Target: NSObject {
        @objc func left() { NotificationCenter.default.post(name: .wyaShake, object: nil) }
        @objc func right() { NotificationCenter.default.post(name: .wyaRedo, object: nil) }
    }
    private static let target = Target()

    static func install() {
        guard !installed else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }.first
        guard let window else { return }
        installed = true
        for (dir, sel) in [(UISwipeGestureRecognizer.Direction.left, #selector(Target.left)),
                           (.right, #selector(Target.right))] {
            let g = UISwipeGestureRecognizer(target: target, action: sel)
            g.direction = dir
            g.numberOfTouchesRequired = 3
            // the map and the sheets keep their touches until the swipe is certain
            g.cancelsTouchesInView = true
            g.delaysTouchesBegan = false
            window.addGestureRecognizer(g)
        }
    }
}

/// the gestures handled once for the whole app
struct ShakeToUndo: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .wyaShake)) { _ in
                guard MarkStore.shared.canUndo else { Feel.refuse(); return }
                Feel.tap()
                Task { await MarkStore.shared.undo() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .wyaRedo)) { _ in
                guard MarkStore.shared.canRedo else { Feel.refuse(); return }
                Feel.tap()
                Task { await MarkStore.shared.redo() }
            }
            .onAppear { DispatchQueue.main.async { ThreeFingerSwipes.install() } }
    }
}
