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
/// Once, ever: an account that already has a name or a handle, or a phone the app has run on before, has had it.
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

    /// THE APP HAS RUN HERE BEFORE: the map settings write their count into the app's defaults every launch, and have
    /// since long before the first open existed, so finding it before they load this time means an earlier version
    /// ran on this phone. Someone updating, with stamps but never a name typed, goes straight to their map.
    private static var ranBefore = false
    /// (an app that has shown its first open and was left before the end shows it again: only runs from before the
    /// first open existed count)
    private static let shownKey = "wya.onboardShown"
    static func noteEarlierRuns() {
        let d = UserDefaults.standard
        ranBefore = d.object(forKey: "mapCount") != nil && !d.bool(forKey: shownKey)
    }

    init() {
        let me = ProfileStore.shared.me
        var d = UserDefaults.standard.bool(forKey: Self.key) || !me.name.isEmpty || !me.handle.isEmpty || Self.ranBefore
        #if DEBUG
        // (a test's first open: -wyaOnboard shows it whatever the account has)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-wyaOnboard") { d = false }
        // (-wyaOnboardPage N opens it on page N, for a look at a page on a phone the test cannot swipe)
        if let i = args.firstIndex(of: "-wyaOnboardPage"), i + 1 < args.count, let n = Int(args[i + 1]) {
            d = false
            page = max(0, min(Self.pages - 1, n))
        }
        #endif
        done = d
        if !d { UserDefaults.standard.set(true, forKey: Self.shownKey) }
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
    @State private var bio = ""
    @FocusState private var typing: Bool
    @FocusState private var typingBio: Bool
    @State private var asking = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    /// whose borders picked here (nothing shows chosen until one is tapped: no default), and the
    /// countries' list up
    @State private var bordersPicked: String?
    @State private var pickingCountry = false

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            HStack(spacing: 0) {
                hello(W, H).frame(width: W, height: H).accessibilityHidden(ob.page != 0)
                // (the blank Profile's own ground: the field at the Profile's middle strength)
                who(W, H).frame(width: W, height: H)
                    .background(LivingField(saturation: ProfileView.look.x, power: ProfileView.look.y).ignoresSafeArea())
                    .accessibilityHidden(ob.page != 1)
                borders(W, H).frame(width: W, height: H).accessibilityHidden(ob.page != 2)
                whichMap(W, H).frame(width: W, height: H).accessibilityHidden(ob.page != 3)
                location(W, H).frame(width: W, height: H).accessibilityHidden(ob.page != 4)
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
                    if go { next() } else if back, ob.page > first { previous(); return }
                    withAnimation(Motion.chrome) { drag = 0 }
                })
            // (VoiceOver: the three-finger swipe turns the pages as the drag does; only the page on screen is read)
            .accessibilityElement(children: .contain)
            .accessibilityScrollAction { edge in
                if edge == .trailing { next() }
                else if edge == .leading, ob.page > first { previous() }
            }
        }
        .ignoresSafeArea()
        // (its words up to the size its 44 pt buttons still hold on one line, as the country card's; at AX5 the
        // pills' words ran out of them and the card)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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

    /// back a page (the drag's, or VoiceOver's)
    private func previous() {
        typing = false; typingBio = false
        Feel.tick()
        withAnimation(Motion.chrome) { ob.page -= 1; drag = 0 }
    }

    /// on to the next page, unless this one needs something first (an empty name shakes, with a refusing feel)
    private func next() {
        if ob.page == 1, name.trimmingCharacters(in: .whitespaces).isEmpty {
            Feel.refuse()
            withAnimation(Motion.chrome) { drag = 0 }
            withAnimation(.linear(duration: 0.07).repeatCount(5, autoreverses: true)) { shake = 1 } completion: { shake = 0 }
            typing = true
            return
        }
        if ob.page == 1 {
            let b = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            store.set {
                $0.name = String(name.trimmingCharacters(in: .whitespaces).prefix(ProfileStore.nameMax))
                if !b.isEmpty { $0.bio = String(b.prefix(ProfileStore.bioMax)) }
            }
        }
        typing = false; typingBio = false
        guard ob.page < Onboarding.pages - 1 else { withAnimation(Motion.chrome) { drag = 0 }; return }
        Feel.tick()
        withAnimation(Motion.chrome) { ob.page += 1; drag = 0 }
    }

    /// the question big and close under the logo: the words in the app's black, the "?!" in its blue on the living
    /// field; on the map's glass, over the sea, the blue was lost, so there it is the logo's other colour, its lime
    private func question(_ words: String, mark: Color = Palette.blue) -> some View {
        (Text(words).foregroundStyle(Palette.ink) + Text("?!").foregroundStyle(mark))
            // (one size on every page and phone, chosen so the longest question stands on one line on the narrowest
            // phone; never shrunk to fit; at the largest type it takes a second line)
            .font(Typeface.nature(38, relativeTo: .largeTitle))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
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
                // CONTINUE WITH APPLE IN CLEAR GLASS (14 Oct: glass, not a solid button): Apple's own
                // sign-in behind a glass pill of the app's, its logo (the one symbol Apple asks for here) and its words
                Button {
                    Feel.tap()
                    Task {
                        // (no account server yet: signed in on the phone; the name Apple gives becomes your name)
                        if let n = await AppleSignIn.run(), !n.isEmpty { name = n }
                        next()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo").font(.body.weight(.semibold))
                        Text("Continue with Apple").font(.body.weight(.semibold))
                    }
                    .foregroundStyle(Palette.ink)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .frame(width: W * 2 / 3, height: 44)
                    .glassEffect(Glass.clear.interactive(), in: .capsule)
                }
                .buttonStyle(.press)
                .accessibilityLabel("Continue with Apple")
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
            // the name and the bio as the Profile has them: the name in the app's own type, the bio a reading line under
            // it (Return in the name goes on to the bio; in the bio, Done)
            VStack(spacing: 8) {
                TextField("", text: $name, prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                    .font(Typeface.nature(34, relativeTo: .title))
                    .multilineTextAlignment(.center)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .focused($typing)
                    .onSubmit { typingBio = true }
                    .onChange(of: name) { o, n in if n.count > ProfileStore.nameMax { name = o; Feel.refuse() } }
                    .frame(width: W - 64, height: 52)
                    .offset(x: sin(shake * .pi * 2) * 10)
                TextField("", text: $bio, prompt: Text("Bio").foregroundStyle(Palette.ink.opacity(0.5)), axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(1 ... 3)
                    .submitLabel(.done)
                    .focused($typingBio)
                    .onChange(of: bio) { o, n in
                        // (one paragraph: Return is Done)
                        if n.contains("\n") { bio = o; typingBio = false; return }
                        if n.count > ProfileStore.bioMax { bio = o; Feel.refuse() }
                    }
                    .frame(maxWidth: 300)
                    .frame(minHeight: 44)
            }
        }
        .frame(width: W, height: H)
        .contentShape(Rectangle())
        .onTapGesture { typing = false; typingBio = false }
    }

    // MARK: over the map: whose borders, which map, location

    /// A PAGE OVER THE MAP: its question and choices on clear glass in the very shape and place of the map's sheet at
    /// 25%, which takes its place when the first open is over; above it, the map itself, untouched
    private func card<C: View>(_ W: CGFloat, _ H: CGFloat, _ words: String, level: SheetStop = .quarter,
                               @ViewBuilder _ choices: () -> C) -> some View {
        let L = water.layout
        let top = L.top(level)
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

    /// WHOSE BORDERS (14 Oct): the three, nothing chosen until one
    /// is tapped (a swipe on with none keeps de facto, the map's own); Pick a country raises the card to half the
    /// screen with every country that has a view of its own, as Map settings > Borders lists them
    private func borders(_ W: CGFloat, _ H: CGFloat) -> some View {
        let pick = MapSettingsStore.shared.value.borders ?? "deFacto"
        let shown = bordersPicked == nil ? nil : pick
        let half = (W - 64 - 12) / 2
        let country = shown.flatMap { $0 == "deFacto" || $0 == "un" ? nil : BordersNames.name($0, map) }
        return card(W, H, "whose borders", level: pickingCountry ? .half : .quarter) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    choice("De facto", on: shown == "deFacto", width: half) { pickBorders("deFacto") }
                    choice("United Nations", on: shown == "un", width: half) { pickBorders("un") }
                }
                choice(country ?? "Pick a country", on: country != nil || pickingCountry, width: W - 64) {
                    Feel.tap()
                    withAnimation(Motion.chrome) { pickingCountry.toggle() }
                }
                if pickingCountry {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Self.viewCountries(map), id: \.key) { c in
                                let on = shown == c.key
                                HStack(spacing: 12) {
                                    if let f = Flags.row(BordersNames.placeId(c.key)) {
                                        f.resizable().interpolation(.high).frame(width: 28, height: 21)
                                    }
                                    Text(c.name).font(.body).foregroundStyle(on ? Palette.white : Palette.ink).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 32)
                                .frame(width: W, height: 48)
                                // (the one picked a black bar side to side, as every chosen row)
                                .background { if on { Rectangle().fill(Palette.ink) } }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    pickBorders(c.key)
                                    withAnimation(Motion.chrome) { pickingCountry = false }
                                }
                                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                    }
                    .scrollBlur()
                    .scrollIndicators(.hidden)
                    // (down to the screen's foot: the card's top at half, its question, two rows of choices and their gaps above)
                    .frame(width: W, height: max(96, H - water.layout.top(.half) - 232))
                }
            }
        }
    }

    private func pickBorders(_ v: String) {
        bordersPicked = v
        set("borders", v, now: MapSettingsStore.shared.value.borders == v)
    }

    /// the countries with a view of their own (disputes.json), by name
    static func viewCountries(_ map: MapController) -> [(key: String, name: String)] {
        (Bundle.main.url(forResource: "disputes", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(DisputeFile.self, from: $0) }?.views ?? [])
            .map { ($0, BordersNames.name($0, map)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
                            // The Map row's pair names itself as maps so the grid reads as two questions.
                            choice(row.id == "map" ? c.name + " map" : c.name, on: row.get(s) == c.id, width: w) {
                                set(row.id, c.id, now: row.get(s) == c.id)
                            }
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
                // (never shrunk: the words stop growing at the size the half-width pill holds whole)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .frame(width: width, height: 44)
                .background { if on { Capsule().fill(Palette.ink) } }
                .glassEffect(on ? .clear : Glass.clear.interactive(), in: .capsule)
        }
        .buttonStyle(.press)
    }
}

/// APPLE'S SIGN-IN, asked from the app's own button: the name Apple gives (given and family), or nil when it gives
/// none or the sign-in is put away
@MainActor
final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var done: ((String?) -> Void)?
    private static var current: AppleSignIn?

    static func run() async -> String? {
        await withCheckedContinuation { c in
            let me = AppleSignIn()
            current = me
            me.done = { n in c.resume(returning: n); current = nil }
            let r = ASAuthorizationAppleIDProvider().createRequest()
            r.requestedScopes = [.fullName]
            let ctl = ASAuthorizationController(authorizationRequests: [r])
            ctl.delegate = me
            ctl.presentationContextProvider = me
            ctl.performRequests()
        }
    }
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization a: ASAuthorization) {
        let n = (a.credential as? ASAuthorizationAppleIDCredential)?.fullName
        let words = [n?.givenName ?? "", n?.familyName ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        MainActor.assumeIsolated { done?(words.isEmpty ? nil : words) }
    }
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { done?(nil) }
    }
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
