import UIKit

/// THE FIRST SEARCH WITHOUT A STALL: the first time any text field takes the keyboard, iOS sets up its whole text input
/// system on the main thread, which held the screen still for about half a second as search opened (measured: the
/// frames stopped for 520 ms after the field appeared). That setup is done once at launch instead, while the map is
/// still loading, with a field the user never sees and an empty keyboard (so nothing rises), then dropped.
@MainActor
enum Prewarm {
    private static var done = false
    static func textInput() {
        guard !done, let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first else { return }
        done = true
        let field = UITextField(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
        field.inputView = UIView()
        field.autocorrectionType = .no
        window.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
    }
}
