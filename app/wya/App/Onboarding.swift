import SwiftUI
import AuthenticationServices
import PhotosUI

/// THE FIRST OPEN.
/// The loading screen holds still and is the first page: the question under the logo, Sign in with Apple, and a
/// small privacy line at the bottom. Then, swiped through (no Next or Back buttons, no page dots):
/// who are you (the picture and the name on the Profile's own ground, shaking if the name is left empty); then, over
/// the map itself (the loading screen lifts unseen behind "who are you"), on glass where the map's sheet rests: whose
/// borders (the map redrawn as each is picked), which map (Map and Style, as Map settings has them), and location
/// (Apple's own prompt). Then the sheet is there in the card's place and the head and the column come in: the map.
/// Once, ever: an account that already has a name or a handle has had it.
@MainActor @Observable
final class Onboarding {
    static let shared = Onboarding()
    private static let key = "wya.onboarded"
    /// the first open is over (or was never needed)
    private(set) var done: Bool
    /// the page on screen (0 where you at, 1 who are you, 2 whose borders, 3 which map, 4 location)
    var page = 0
    static let pages = 5
    /// past the first page for good: the loading screen (that page's ground) has lifted, so there is no way back to it
    private(set) var pastHello = false

    init() {
        let me = ProfileStore.shared.me
        var d = UserDefaults.standard.bool(forKey: Self.key) || !me.name.isEmpty || !me.handle.isEmpty
        #if DEBUG
        // (a test's first open: -wyaOnboard shows it whatever the account has)
        if ProcessInfo.processInfo.arguments.contains("-wyaOnboard") { d = false }
        #endif
        done = d
    }

    /// over: the card gives way to the map's own sheet in its place, and the head and the column come in from their
    /// edges on the chrome's spring
    func finish() {
        UserDefaults.standard.set(true, forKey: Self.key)
        withAnimation(Motion.chrome) { done = true }
    }
    /// waits until the first open is wholly over (the start credit and the hints wait for it)
    func over() async {
        while !done { try? await Task.sleep(for: .milliseconds(100)) }
    }

    /// waits until the loading screen may lift: the first open over, or "who are you" (whose ground covers it all)
    /// in place, its slide finished, so the lift happens unseen and the map is under the pages that follow
    func wait() async {
        while true {
            while !done, page < 1 { try? await Task.sleep(for: .milliseconds(100)) }
            if done { return }
            try? await Task.sleep(for: .milliseconds(450))
            if done || page >= 1 { pastHello = true; return }
        }
    }
}

struct OnboardingView: View {
    let water: Water
    let map: MapController
    @State private var ob = Onboarding.shared
    @State private var store = ProfileStore.shared
    @State private var drag: CGFloat = 0
    @State private var shake: CGFloat = 0
    @State private var name = ""
    @FocusState private var typing: Bool
    @State private var asking = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            HStack(spacing: 0) {
                hello(W, H).frame(width: W, height: H)
                // (the blank Profile's own ground: the field at the Profile's middle strength)
                who(W, H).frame(width: W, height: H)
                    .background(LivingField(saturation: ProfileView.look.x, power: ProfileView.look.y).ignoresSafeArea())
                borders(W, H).frame(width: W, height: H)
                whichMap(W, H).frame(width: W, height: H)
                location(W, H).frame(width: W, height: H)
            }
            .frame(width: W, alignment: .leading)
            .offset(x: -CGFloat(ob.page) * W + drag)
            .gesture(DragGesture(minimumDistance: 12)
                .onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    // (no page before the first or after the last: the edge gives a little, then holds)
                    let edge = (ob.page == first && v.translation.width > 0) || (ob.page == Onboarding.pages - 1 && v.translation.width < 0)
                    drag = edge ? v.translation.width * 0.25 : v.translation.width
                }
                .onEnded { v in
                    let go = v.translation.width < -W * 0.25 || v.predictedEndTranslation.width < -W * 0.5
                    let back = v.translation.width > W * 0.25 || v.predictedEndTranslation.width > W * 0.5
                    if go { next() } else if back, ob.page > first { typing = false; Feel.tick(); withAnimation(Motion.chrome) { ob.page -= 1; drag = 0 }; return }
                    withAnimation(Motion.chrome) { drag = 0 }
                })
        }
        .ignoresSafeArea()
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images, photoLibrary: .shared())
        .onChange(of: photo) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self) { Feel.tap(); await store.setPhoto(d) }
                else { Feel.refuse() }
                photo = nil
            }
        }
    }

    /// the first page a swipe back can reach (the first one's ground, the loading screen, goes once it is left)
    private var first: Int { ob.pastHello ? 1 : 0 }

    /// on to the next page, unless this one needs something first (an empty name shakes, with a refusing feel)
    private func next() {
        if ob.page == 1, name.trimmingCharacters(in: .whitespaces).isEmpty {
            Feel.refuse()
            withAnimation(Motion.chrome) { drag = 0 }
            withAnimation(.linear(duration: 0.07).repeatCount(5, autoreverses: true)) { shake = 1 } completion: { shake = 0 }
            typing = true
            return
        }
        if ob.page == 1 { store.set { $0.name = String(name.trimmingCharacters(in: .whitespaces).prefix(ProfileStore.nameMax)) } }
        typing = false
        guard ob.page < Onboarding.pages - 1 else { withAnimation(Motion.chrome) { drag = 0 }; return }
        Feel.tick()
        withAnimation(Motion.chrome) { ob.page += 1; drag = 0 }
    }

    /// the question big and close under the logo: the words in the app's black, the "?!" in its blue on the living
    /// field; on the map's glass, over the sea, the blue was lost, so there it is the logo's other colour, its lime
    private func question(_ words: String, mark: Color = Palette.blue) -> some View {
        (Text(words).foregroundStyle(Palette.ink) + Text("?!").foregroundStyle(mark))
            .font(Typeface.nature(44, relativeTo: .largeTitle))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            // (one line on every phone: the longest question all but fills the Pro Max)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
    }

    // MARK: where you at?!

    private func hello(_ W: CGFloat, _ H: CGFloat) -> some View {
        let planet = Launch.planet(W)
        return ZStack(alignment: .top) {
            // (the loading screen's logo is behind this page, in the middle; the question 28 pt under it)
            question("where you at")
                .padding(.top, H / 2 + planet / 2 + 28)
            VStack(spacing: 16) {
                Spacer()
                SignInWithAppleButton(.continue) { r in
                    r.requestedScopes = [.fullName]
                } onCompletion: { result in
                    // (no account server yet: signed in on the phone; the name Apple gives becomes your name)
                    if case .success(let a) = result, let c = a.credential as? ASAuthorizationAppleIDCredential,
                       let given = c.fullName?.givenName, !given.isEmpty {
                        name = [given, c.fullName?.familyName ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    }
                    next()
                }
                .signInWithAppleButtonStyle(.black)
                .frame(width: W * 2 / 3, height: 44)
                .clipShape(Capsule())
                Text("Everything stays on your phone.")
                    .font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                    .padding(.bottom, 44)
            }
            .frame(width: W, height: H)
        }
        .frame(width: W, height: H)
        .contentShape(Rectangle())
    }

    // MARK: who are you?!

    private func who(_ W: CGFloat, _ H: CGFloat) -> some View {
        VStack(spacing: 20) {
            question("who are you")
            // the picture as the Profile has it: white, your first letter on it once there is one; a tap, your photos
            ZStack {
                Circle().fill(Palette.white)
                if store.me.picture == "photo", let p = store.photo {
                    Image(uiImage: p).resizable().interpolation(.high).scaledToFill()
                } else if let first = name.trimmingCharacters(in: .whitespaces).first {
                    Text(String(first).uppercased()).font(Typeface.nature(66, relativeTo: .largeTitle)).foregroundStyle(Palette.ink)
                        .dynamicTypeSize(.large)
                } else {
                    Icon5(key: "plus", ink: Palette.ink.opacity(0.5), size: 30)
                }
            }
            .frame(width: ProfileView.picture, height: ProfileView.picture)
            .clipShape(Circle())
            .contentShape(Circle())
            .onTapGesture { Feel.tap(); typing = false; choosingPhoto = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Picture")
            .accessibilityHint("Chooses a photo")
            TextField("", text: $name, prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                .font(Typeface.nature(34, relativeTo: .title))
                .multilineTextAlignment(.center)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($typing)
                .onSubmit { next() }
                .onChange(of: name) { o, n in if n.count > ProfileStore.nameMax { name = o; Feel.refuse() } }
                .frame(width: W - 64, height: 52)
                .offset(x: sin(shake * .pi * 2) * 10)
        }
        .frame(width: W, height: H)
        .contentShape(Rectangle())
        .onTapGesture { typing = false }
    }

    // MARK: over the map: whose borders, which map, location

    /// A PAGE OVER THE MAP: its question and choices on clear glass in the very shape and place of the map's sheet at
    /// 25%, which takes its place when the first open is over; above it, the map itself, untouched
    private func card<C: View>(_ W: CGFloat, _ H: CGFloat, _ words: String, @ViewBuilder _ choices: () -> C) -> some View {
        let L = water.layout
        let top = L.top(.quarter)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: W, height: H).contentShape(Rectangle())
            WaterShape(form: water.form(level: top))
                .fill(Color.clear)
                .glassEffect(.clear, in: WaterShape(form: water.form(level: top)))
                .frame(width: W, height: H)
                .allowsHitTesting(false)
            VStack(spacing: 16) {
                question(words, mark: Palette.lime)
                choices()
            }
            .frame(width: W)
            .padding(.top, top + 24)
        }
        .frame(width: W, height: H, alignment: .topLeading)
    }

    private func borders(_ W: CGFloat, _ H: CGFloat) -> some View {
        let pick = MapSettingsStore.shared.value.borders ?? "deFacto"
        let half = (W - 64 - 12) / 2
        return card(W, H, "whose borders") {
            HStack(spacing: 12) {
                choice("De facto", on: pick == "deFacto", width: half) { set("borders", "deFacto", now: pick == "deFacto") }
                choice("United Nations", on: pick == "un", width: half) { set("borders", "un", now: pick == "un") }
            }
        }
    }

    /// which map: Map settings' first two rows, Map and Style, their choices as they are there
    private func whichMap(_ W: CGFloat, _ H: CGFloat) -> some View {
        let s = MapSettingsStore.shared.value
        let rows = MapSettingsRows.all.filter { $0.id == "map" || $0.id == "style" }
        return card(W, H, "which map") {
            VStack(spacing: 12) {
                ForEach(rows) { row in
                    let cs = MapSettingsRows.choices(row, s)
                    let w = (W - 64 - 12 * CGFloat(cs.count - 1)) / CGFloat(cs.count)
                    HStack(spacing: 12) {
                        ForEach(cs) { c in
                            choice(c.name, on: row.get(s) == c.id, width: w) { set(row.id, c.id, now: row.get(s) == c.id) }
                        }
                    }
                }
            }
        }
    }

    /// a setting picked here is picked in Map settings, and the map behind follows at once; the page stays, so the
    /// choice is seen on the map and another can be tried, until it is swiped on
    private func set(_ id: String, _ v: String, now: Bool) {
        Feel.tap()
        if !now { Task { await MapSettingsRows.set(id, v, map: map) } }
    }

    private func location(_ W: CGFloat, _ H: CGFloat) -> some View {
        let half = (W - 64 - 12) / 2
        return card(W, H, "can we find you") {
            HStack(spacing: 12) {
                choice("Not now", on: false, width: half) { Feel.tap(); ob.finish() }
                choice("Allow", on: true, width: half) {
                    guard !asking else { return }
                    asking = true
                    Feel.tap()
                    // (Apple's own prompt; whatever the answer, on into the map)
                    Task { _ = await OneFix.shared.get(); ob.finish() }
                }
            }
        }
    }

    /// a choice: half the row, black when it is the one (as the app's chosen chips are), clear glass otherwise
    private func choice(_ t: String, on: Bool, width: CGFloat, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(.body.weight(.semibold)).foregroundStyle(on ? Palette.white : Palette.ink)
                .lineLimit(1)
                .frame(width: width, height: 44)
                .background { if on { Capsule().fill(Palette.ink) } }
                .glassEffect(on ? .clear : Glass.clear.interactive(), in: .capsule)
        }
        .buttonStyle(.press)
    }
}
