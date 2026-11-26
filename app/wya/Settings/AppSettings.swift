import SwiftUI

/// THE APP'S OWN SETTINGS (Part 6): their own page, pushed from the Profile's settings circle as Stats and Badges are
/// (settings open as a whole page, not a sheet; they live in the Profile; Map settings stay on the map's dot). Only rows
/// that do something, no empty boxes: Units (the phone's own by default, changed here), Sounds, and the version. Rows
/// as Map settings' rows: the name, the value at 50%, a tap; a row of three opens its choices under it with the black
/// band on the one in use. Kept in the app's defaults the moment it changes. ABOUT, last: the app's own type in one
/// line (what its letters are, no paragraph; a letter viewer comes later), Sources (pushed inside the page as
/// Map settings pushes it: everything the app's maps, words, pictures, sounds and type come from, each with its
/// licence), and the version.
nonisolated enum AppSettings {
    static let unitsKey = "wya.units"
    static let soundsKey = "wya.sounds"
    /// "phone" (the phone's region decides), "metric" or "imperial"
    static var units: String { UserDefaults.standard.string(forKey: unitsKey) ?? "phone" }
    /// the app's sounds (a stamp's thud and the few others): on unless turned off here
    static var sounds: Bool { UserDefaults.standard.object(forKey: soundsKey) as? Bool ?? true }
}

/// THE SETTINGS PAGE'S LIST: the whole screen's height as the Stats page's list, its name in the top row
struct AppSettingsList: View {
    let room: CGFloat
    let top: CGFloat
    let foot: CGFloat
    let title: String
    let titleY: CGFloat
    @AppStorage(AppSettings.unitsKey) private var units = "phone"
    @AppStorage(AppSettings.soundsKey) private var sounds = true
    /// Units' choices are open under it
    @State private var open = false
    @State private var edit = ProfileEdit.shared

    private static let unitChoices: [(String, String)] = [("phone", "Phone"), ("metric", "Metric"), ("imperial", "Imperial")]

    var body: some View {
        let sources = edit.settingsPage == "sources"
        // (a push of its own, as Map settings': the list out to the left as Sources comes in from the right; back the
        // other way, by the page's back circle)
        ZStack(alignment: .top) {
            if sources {
                ScrollView { SourcesPage().padding(.top, 8) }
                    .scrollBlur()
                    .scrollIndicators(.hidden)
                    .modifier(TopBar(title: "Sources", titleY: titleY, top: top))
                    .safeAreaPadding(.bottom, foot)
                    .transition(.move(edge: .trailing))
            } else {
                list.transition(.move(edge: .leading))
            }
        }
        .frame(height: room, alignment: .top)
        .clipped()
        // (every line up to the size Map settings' rows hold, as those rows are: the type's line and Sources' rows grew
        // past them at the largest text)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button {
                    Feel.tap()
                    withAnimation(Motion.chrome) { open.toggle() }
                } label: {
                    RowWords(name: "Units", value: Self.unitChoices.first { $0.0 == units }?.1 ?? "Phone")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the choices")
                if open {
                    ForEach(Array(Self.unitChoices.enumerated()), id: \.element.0) { i, c in
                        ChoiceRow(name: c.1, picked: units == c.0, delay: 0.04 * Double(i)) { pick(c.0) }
                            .transition(.identity)
                    }
                }
                // two choices: one tap switches (notch, as Map settings' two-choice rows)
                Button {
                    Feel.notch()
                    sounds.toggle()
                } label: {
                    RowWords(name: "Sounds", value: sounds ? "On" : "Off")
                }
                .buttonStyle(.plain)
                Color.clear.frame(height: 24)
                // ABOUT: the type in one line, Sources, the version
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tellus").font(Typeface.nature(22, relativeTo: .body)).foregroundStyle(Palette.ink)
                    Text("Its letters are rivers and lakes seen from above.").font(.subheadline)
                        .foregroundStyle(Palette.ink.opacity(0.5))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button {
                    Feel.tap()
                    withAnimation(Motion.chrome) { edit.settingsPage = "sources" }
                } label: {
                    RowWords(name: "Sources", value: "", chevron: true)
                }
                .buttonStyle(.plain)
                RowWords(name: "Version", value: Self.version)
                    .accessibilityElement(children: .combine)
            }
            .padding(.top, 8)
        }
        .scrollBlur()
        .scrollIndicators(.hidden)
        .modifier(TopBar(title: title, titleY: titleY, top: top))
        .safeAreaPadding(.bottom, foot)
        .frame(height: room, alignment: .top)
    }

    private func pick(_ id: String) {
        Feel.tap()
        units = id
        // (the choices close 0.15 s after the pick, so the black is seen on the new choice first, as Map settings')
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(Motion.chrome) { open = false } }
    }

    /// "1.0 (12)"
    private static var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? ""
        let b = i?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty || b == v ? v : "\(v) (\(b))"
    }
}
