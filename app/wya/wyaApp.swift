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
        // the loading screen's turning logo opened before any view is built (Design/LogoTurn.swift)
        LogoTurnUIView.warm()
        Snap.start()
        Task { @MainActor in Hitches.start(); HangWatch.start() }
        // Pins' tracking, when it is on in Map settings (Map/PinTracker.swift)
        Task { @MainActor in PinTracker.shared.follow(MapSettingsStore.shared.value.pinsTrack) }
        Task.detached(priority: .utility) { await DevDataClient.refresh() }
    }

    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                // the app put away: a review or round up is kept on disk (iOS may end the app before it is back)
                .onChange(of: phase) { _, p in if p == .background { UploadState.shared.backgrounded() } }
        }
    }
}
