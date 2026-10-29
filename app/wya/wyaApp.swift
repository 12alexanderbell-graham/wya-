import SwiftUI
import CoreText

@main
struct wyaApp: App {
    init() {
        // Tellus, the display font (fonts/Tellus in the repo), registered from the bundle
        for name in ["Tellus-Regular", "Tellus-Light", "Tellus-Medium"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        Snap.start()
        Task { @MainActor in Hitches.start() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
