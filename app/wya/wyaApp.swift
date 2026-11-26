import SwiftUI
import CoreText

@main
struct wyaApp: App {
    init() {
        // (before anything reads the map settings: whether this phone has run the app before, for the first open)
        Onboarding.noteEarlierRuns()
        // Tellus, the display font (fonts/Tellus in the repo), registered from the bundle
        for name in ["Tellus-Regular", "Tellus-Light", "Tellus-Medium"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        // the stamps' type (Passport/RealStamps): Barlow Condensed, Caveat, Noto Serif, Noto Sans Arabic (SIL OFL 1.1, their
        // licences beside them in Resources/Fonts)
        for name in ["BarlowCondensed-Medium", "BarlowCondensed-SemiBold", "BarlowCondensed-Bold", "Caveat-SemiBold",
                     "NotoSerif-SemiBold", "NotoSerif-Bold", "NotoSansArabic-Bold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
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
                // the app's accent is its ink: the text caret, Apple's calendar's chosen day and the rest of the
                // system's accents in black, never the system blue
                .tint(Palette.ink)
                // the app put away: a review or round up is kept on disk (iOS may end the app before it is back)
                .onChange(of: phase) { _, p in
                    if p == .background { UploadState.shared.backgrounded() }
                    // (the app up: the plan near now on the lock screen, its days counted again)
                    if p == .active { Task { await PlanLive.refresh() } }
                }
        }
        // (the plan on the lock screen counted again after midnight, the app closed: PlanLive)
        .backgroundTask(.appRefresh(PlanLive.task)) {
            #if DEBUG
            NSLog("wya planlive: woken in the background")
            #endif
            await PlanLive.refresh()
        }
    }
}
