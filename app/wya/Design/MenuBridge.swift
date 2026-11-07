import SwiftUI
import UIKit

/// A UIKIT HOLD MENU DRAWN AS SWIFTUI'S: the same rows, groups, words, red rows and unavailable rows, so a SwiftUI
/// view held (a search result, 11.5) shows the very menu the map gives the same thing. `before` runs with a row's
/// words just before the row acts.
struct MenuBridge: View {
    let menu: UIMenu
    var before: (String) -> Void = { _ in }

    var body: some View {
        Section(menu.title) { elements(menu.children) }
    }

    private func elements(_ es: [UIMenuElement]) -> AnyView {
        AnyView(ForEach(Array(es.enumerated()), id: \.offset) { _, e in element(e) })
    }

    private func element(_ e: UIMenuElement) -> AnyView {
        if let m = e as? UIMenu {
            if m.options.contains(.displayInline) { return AnyView(Section(m.title) { elements(m.children) }) }
            return AnyView(Menu(m.title) { elements(m.children) })
        }
        guard let a = e as? UIAction else { return AnyView(EmptyView()) }
        return AnyView(
            Button(a.title, role: a.attributes.contains(.destructive) ? .destructive : nil) {
                before(a.title)
                a.performWithSender(nil, target: nil)
            }
            .disabled(a.attributes.contains(.disabled))
        )
    }
}
