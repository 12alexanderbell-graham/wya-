import SwiftUI
import AuthenticationServices

/// THE FIRST OPEN.
/// The loading screen holds still and is the first page: the question under the logo, Sign in with Apple, and a
/// small privacy line at the bottom. Then, swiped through (no Next or Back buttons, no page dots):
/// who are you (the name, shaking if it is left empty), whose borders (de facto or the United Nations' view), and
/// location (Apple's own prompt). Then straight into the map: the loading screen lifts as it always does.
/// Once, ever: an account that already has a name or a handle has had it.
@MainActor @Observable
final class Onboarding {
    static let shared = Onboarding()
    private static let key = "wya.onboarded"
    /// the first open is over (or was never needed)
    private(set) var done: Bool
    /// the page on screen (0 where you at, 1 who are you, 2 whose borders, 3 location)
    var page = 0
    static let pages = 4

    init() {
        let me = ProfileStore.shared.me
        var d = UserDefaults.standard.bool(forKey: Self.key) || !me.name.isEmpty || !me.handle.isEmpty
        #if DEBUG
        // (a test's first open: -wyaOnboard shows it whatever the account has)
        if ProcessInfo.processInfo.arguments.contains("-wyaOnboard") { d = false }
        #endif
        done = d
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.key)
        withAnimation(Motion.quick) { done = true }
    }

    /// waits until the first open is over (the launch lifts the loading screen after it)
    func wait() async {
        while !done { try? await Task.sleep(for: .milliseconds(100)) }
    }
}

struct OnboardingView: View {
    @State private var ob = Onboarding.shared
    @State private var store = ProfileStore.shared
    @State private var drag: CGFloat = 0
    @State private var shake: CGFloat = 0
    @State private var name = ""
    @FocusState private var typing: Bool
    @State private var asking = false

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            HStack(spacing: 0) {
                hello(W, H).frame(width: W, height: H)
                who(W, H).frame(width: W, height: H).background(LivingField().ignoresSafeArea())
                borders(W, H).frame(width: W, height: H).background(LivingField(seed: 3).ignoresSafeArea())
                location(W, H).frame(width: W, height: H).background(LivingField(seed: 7).ignoresSafeArea())
            }
            .frame(width: W, alignment: .leading)
            .offset(x: -CGFloat(ob.page) * W + drag)
            .gesture(DragGesture(minimumDistance: 12)
                .onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    // (no page before the first or after the last: the edge gives a little, then holds)
                    let edge = (ob.page == 0 && v.translation.width > 0) || (ob.page == Onboarding.pages - 1 && v.translation.width < 0)
                    drag = edge ? v.translation.width * 0.25 : v.translation.width
                }
                .onEnded { v in
                    let go = v.translation.width < -W * 0.25 || v.predictedEndTranslation.width < -W * 0.5
                    let back = v.translation.width > W * 0.25 || v.predictedEndTranslation.width > W * 0.5
                    if go { next() } else if back, ob.page > 0 { typing = false; Feel.tick(); withAnimation(Motion.chrome) { ob.page -= 1; drag = 0 }; return }
                    withAnimation(Motion.chrome) { drag = 0 }
                })
        }
        .ignoresSafeArea()
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
        if ob.page == 1 { store.set { $0.name = String(name.trimmingCharacters(in: .whitespaces).prefix(ProfileStore.nameMax)) } }
        typing = false
        guard ob.page < Onboarding.pages - 1 else { withAnimation(Motion.chrome) { drag = 0 }; return }
        Feel.tick()
        withAnimation(Motion.chrome) { ob.page += 1; drag = 0 }
    }

    /// the question big and close under the logo: the words in the app's black, the "?!" in its blue (readable on the
    /// living field)
    private func question(_ words: String) -> some View {
        (Text(words).foregroundStyle(Palette.ink) + Text("?!").foregroundStyle(Palette.blue))
            .font(Typeface.nature(44, relativeTo: .largeTitle))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
            // the picture as the Profile has it: white, your first letter on it once there is one
            ZStack {
                Circle().fill(Palette.white)
                if let first = name.trimmingCharacters(in: .whitespaces).first {
                    Text(String(first).uppercased()).font(Typeface.nature(66, relativeTo: .largeTitle)).foregroundStyle(Palette.ink)
                        .dynamicTypeSize(.large)
                } else {
                    Icon5(key: "plus", ink: Palette.ink.opacity(0.5), size: 30)
                }
            }
            .frame(width: 132, height: 132)
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

    // MARK: whose borders?

    private func borders(_ W: CGFloat, _ H: CGFloat) -> some View {
        let pick = MapSettingsStore.shared.value.borders ?? "deFacto"
        return VStack(spacing: 20) {
            question("whose borders")
            HStack(spacing: 12) {
                choice("De facto", on: pick == "deFacto", width: (W - 64 - 12) / 2) { set("deFacto") }
                choice("United Nations", on: pick == "un", width: (W - 64 - 12) / 2) { set("un") }
            }
        }
        .frame(width: W, height: H)
    }
    private func set(_ b: String) {
        Feel.tap()
        MapSettingsStore.shared.change { $0.borders = b }
        next()
    }

    // MARK: location

    private func location(_ W: CGFloat, _ H: CGFloat) -> some View {
        VStack(spacing: 20) {
            question("can we find you")
            HStack(spacing: 12) {
                choice("Not now", on: false, width: (W - 64 - 12) / 2) { Feel.tap(); ob.finish() }
                choice("Allow", on: true, width: (W - 64 - 12) / 2) {
                    guard !asking else { return }
                    asking = true
                    Feel.tap()
                    // (Apple's own prompt; whatever the answer, on into the map)
                    Task { _ = await OneFix.shared.get(); ob.finish() }
                }
            }
        }
        .frame(width: W, height: H)
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
