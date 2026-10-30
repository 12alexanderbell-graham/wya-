import SwiftUI
import UIKit

/// THE UNDO GESTURES (Part 3.10): a shake undoes the store's last step, at any time and on any tab, up to the session's
/// 20 steps. The window reports the shake; nothing of iOS's own "Undo" alert is used (the store has its own undo).
extension Notification.Name {
    static let wyaShake = Notification.Name("wyaShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .wyaShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

/// the shake handled once for the whole app
struct ShakeToUndo: ViewModifier {
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .wyaShake)) { _ in
            guard MarkStore.shared.canUndo else { Feel.refuse(); return }
            Feel.tap()
            Task { await MarkStore.shared.undo() }
        }
    }
}
