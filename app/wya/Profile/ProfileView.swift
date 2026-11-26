import SwiftUI

/// THE PROFILE AT REST: one screen that does not scroll. The living gradient edge to edge, and on it one centred
/// column: your picture, your name in the app's own font, your handle, your code and your bio. Every size is one the
/// app already has: the picture is three 44 pt controls across, the gaps are the 16 pt side margin, the words are
/// Apple's text sizes. The column is placed once, for a name of one line and a bio of two: that column's middle is the
/// middle of the room between the top safe edge and the water at 25%. The picture stays exactly there whatever the
/// words under it are (a longer name or bio runs further down; a missing line leaves its room), and wherever the water
/// is pulled. The three numbers are in the water (ProfileWater).
struct ProfileView: View {
    let water: Water
    @State private var store = ProfileStore.shared
    @State private var edit = ProfileEdit.shared
    @FocusState private var typing: ProfileEdit.Field?
    /// WHAT IS BEING TYPED, past the limit too: the saved name or bio is what fits, the typed words stay on screen
    /// until the line is left
    @State private var draft: String?
    /// THE PHOTO BEING MOVED OR ZOOMED: its frame under the fingers (kept when they lift), and the one they began on
    @State private var live: [Double]?
    @State private var began: [Double]?
    /// the photo was moved by this touch: its lift is not a tap (which would open the photos)
    @State private var moved = false

    static let picture: CGFloat = 132
    static let gap: CGFloat = 16
    /// the column the page is placed for: the picture, the name's line, the handle's, the code's, two lines of bio
    static let column: CGFloat = picture + 20 + 41 + 2 + 20 + 16 + 2 * 22 + 4 + 44 + 32
    /// the gradient's strength (saturation, power): the stronger pair the first app kept for a picture's gradient; at
    /// the field's own (1.16, 2.0) the page was pale. The test driver can set it to compare (0 0 = the field's own)
    static var look = SIMD2<Double>(1.42, 2.9)

    var body: some View {
        let L = water.layout
        let me = store.me
        let mid = (L.safeTop + L.top(.quarter)) / 2
        // (a code line adds its 8 pt and its line)
        let top = (mid - (Self.column + (me.code.isEmpty ? 0 : 28)) / 2).rounded()
        ZStack(alignment: .topLeading) {
            // (two to four colours of your own; the field draws four, so two are each twice and three the first again;
            // the strength from calm to strong, the middle the first app's picture gradient)
            let s = me.groundStrength ?? 0.5
            LivingField(custom: me.ground.map { g in (0 ..< 4).map { g[$0 % max(1, g.count)].srgb } },
                        saturation: Self.look.x * (0.7 + 0.6 * s), power: Self.look.y * (0.62 + 0.76 * s))
                .frame(width: L.W, height: L.H)
            // the ground: a tap on it keeps what is typed and puts a sheet away; with nothing open, it brings the
            // background's colours (the map under the page takes nothing)
            Color.clear
                .frame(width: L.W, height: L.H)
                .contentShape(Rectangle())
                .onTapGesture {
                    if edit.field != nil || edit.sheet != nil { edit.end(water: water) }
                    else { Feel.tap(); edit.open(.ground, water: water) }
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
                .accessibilityElement()
                .accessibilityLabel("Background")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { edit.open(.ground, water: water) }
            VStack(spacing: 0) {
                Button {
                    if moved { return }
                    Feel.tap()
                    if edit.sheet == .picture { edit.choosingPhoto = true } else { edit.open(.picture, water: water) }
                } label: { picture(me) }
                    .buttonStyle(.plain)
                    .simultaneousGesture(moving, isEnabled: me.picture == "photo" && edit.sheet == .picture)
                    .simultaneousGesture(zooming, isEnabled: me.picture == "photo" && edit.sheet == .picture)
                    .accessibilityLabel("Picture")
                    .accessibilityHint(edit.sheet == .picture ? "Chooses a photo" : "Changes your picture")
                nameLine(me)
                    .padding(.top, 20)
                if !store.handleShown.isEmpty || edit.field == .handle {
                    handleLine
                        .padding(.top, 2)
                }
                if !me.code.isEmpty {
                    Text(me.code)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .padding(.top, 8)
                }
                bioLine(me)
                    .frame(maxWidth: 300)
                    .padding(.top, 16)
                nationalitiesLine
                    .padding(.top, 4)
                homeLine(me)
            }
            .multilineTextAlignment(.center)
            .frame(width: L.W - 2 * L.circle)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .frame(width: L.W, alignment: .top)
            .offset(y: top)
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        // (under a page, the Profile is not read by VoiceOver)
        .accessibilityHidden(edit.sheet == .stats || edit.sheet == .badges)
        // YOUR STATS, YOUR BADGES: their own pages, slid in from the right over all of it
        .overlay(alignment: .topLeading) {
            if let s = edit.sheet, s == .stats || s == .badges {
                ProfilePushedPage(kind: s, water: water)
                    .transition(.move(edge: .trailing))
            }
        }
        .onChange(of: edit.field) { _, f in typing = f }
        // (the keyboard put away: that line is kept; a tap from one line to another keeps typing)
        .onChange(of: typing) { was, t in if t == nil, let w = was, w == edit.field { edit.field = nil } }
        // (leaving the tab: typing kept, a sheet put away)
        .onDisappear { edit.field = nil; edit.close(water: water, move: false) }
        .accessibilityElement(children: .contain)
    }

    // MARK: the lines, each its own text box when tapped

    private func nameLine(_ me: ProfileStore.Me) -> some View {
        let font = Typeface.nature(34, relativeTo: .largeTitle)
        return Group {
            if edit.field == .name {
                VStack(spacing: 4) {
                    TextField("", text: Binding(get: { draft ?? store.me.name }, set: { v in
                        if v.count > ProfileStore.nameMax, (draft ?? "").count <= ProfileStore.nameMax { Feel.refuse() }
                        draft = v
                        store.set { $0.name = String(v.prefix(ProfileStore.nameMax)) }
                    }), prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                    .font(font)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .onSubmit { edit.field = nil }
                    .focused($typing, equals: .name)
                    .onAppear { draft = nil; typing = .name }
                    .onDisappear { draft = nil }
                    if let d = draft, d.count > ProfileStore.nameMax { overCount(d.count, ProfileStore.nameMax) }
                }
            } else {
                Text(me.name.isEmpty ? "Name" : me.name)
                    .font(font)
                    .lineLimit(2)
                    .onTapGesture { Feel.tap(); edit.field = .name }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Edits your name")
            }
        }
        .foregroundStyle(me.name.isEmpty && edit.field != .name ? Palette.ink.opacity(0.5) : Palette.ink)
    }

    private var handleLine: some View {
        Group {
            if edit.field == .handle {
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        Text("@")
                        TextField("", text: Binding(get: { draft ?? store.me.handle }, set: { v in
                            // lowercase letters, digits and "_" (anything else refused); past 20 the letters go on
                            // with the count in red,, and the saved handle is what fits
                            let h = String(v.lowercased().filter { ($0.isLetter && $0.isASCII) || $0.isNumber || $0 == "_" })
                            if h.count < v.count || (h.count > ProfileStore.handleMax && (draft ?? "").count <= ProfileStore.handleMax) { Feel.refuse() }
                            draft = h
                            store.set { $0.handle = String(h.prefix(ProfileStore.handleMax)) }
                        }), prompt: Text(String(store.handleShown.dropFirst())).foregroundStyle(Palette.ink.opacity(0.5)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .onSubmit { edit.field = nil }
                        .focused($typing, equals: .handle)
                        .onAppear { draft = nil; typing = .handle }
                        .onDisappear { draft = nil }
                        .fixedSize()
                    }
                    if let d = draft, d.count > ProfileStore.handleMax { overCount(d.count, ProfileStore.handleMax) }
                }
            } else {
                // (twice in 14 days: a tap while it is shut says from when, in the handle's place, for 2 s)
                Text(edit.handleLockedNote ? store.handleFreeFrom.map { "Again from " + $0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_GB"))) } ?? store.handleShown : store.handleShown)
                    .lineLimit(1)
                    // (words change at once, as everywhere: the note was cross-faded into the handle and back)
                    .contentTransition(.identity)
                    .onTapGesture {
                        if store.handleFreeFrom != nil {
                            Feel.refuse()
                            withAnimation(Motion.quick) { edit.handleLockedNote = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation(Motion.quick) { edit.handleLockedNote = false } }
                            return
                        }
                        Feel.tap(); edit.field = .handle
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Edits your handle")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Palette.ink.opacity(0.5))
    }

    /// a line typed past its limit: its count in red under it ("34/30")
    private func overCount(_ n: Int, _ max: Int) -> some View {
        Text("\(n)/\(max)").font(.subheadline.monospacedDigit()).foregroundStyle(Palette.red)
    }

    private func bioLine(_ me: ProfileStore.Me) -> some View {
        Group {
            if edit.field == .bio {
                VStack(spacing: 4) {
                    TextField("", text: Binding(get: { draft ?? store.me.bio }, set: { v in
                        // (one paragraph: Return is Done)
                        if v.contains("\n") { edit.field = nil; return }
                        if v.count > ProfileStore.bioMax, (draft ?? "").count <= ProfileStore.bioMax { Feel.refuse() }
                        draft = v
                        store.set { $0.bio = String(v.prefix(ProfileStore.bioMax)) }
                    }), prompt: Text("Bio").foregroundStyle(Palette.ink.opacity(0.5)), axis: .vertical)
                    .lineLimit(1 ... 4)
                    .submitLabel(.done)
                    .focused($typing, equals: .bio)
                    .onAppear { draft = nil; typing = .bio }
                    .onDisappear { draft = nil }
                    // the count, while typing only, under the words and centred with them; red past the limit
                    let n = (draft ?? store.me.bio).count
                    Text("\(n)/\(ProfileStore.bioMax)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(n > ProfileStore.bioMax ? Palette.red : Palette.ink.opacity(0.5))
                }
            } else {
                Text(me.bio.isEmpty ? "Bio" : me.bio)
                    .lineLimit(3)
                    .lineSpacing(2)
                    .foregroundStyle(me.bio.isEmpty ? Palette.ink.opacity(0.5) : Palette.ink)
                    .onTapGesture { Feel.tap(); edit.field = .bio }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Edits your bio")
            }
        }
        .font(.body)
        .foregroundStyle(Palette.ink)
    }

    /// your nationalities' flags in a row, the passport's first; none yet, the word at 50%
    private var nationalitiesLine: some View {
        Group {
            if edit.nationalities.isEmpty {
                Text("Passport").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
            } else {
                HStack(spacing: 8) {
                    ForEach(edit.nationalities, id: \.self) { FlagCircle(cc: $0, size: 24) }
                }
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { Feel.tap(); edit.open(.nationalities, water: water) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Passports")
        .accessibilityAddTraits(.isButton)
    }

    /// your home town, under your passports; none yet, the word at 50% (a tap: the towns to pick it from)
    private func homeLine(_ me: ProfileStore.Me) -> some View {
        Text(me.home?.name ?? "Home")
            .font(.subheadline)
            .foregroundStyle(me.home == nil ? Palette.ink.opacity(0.5) : Palette.ink)
            .lineLimit(1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            // (both lines keep their 44 pt touch, overlapping: as two lines of one block, 32 pt apart, not 44)
            .padding(.top, -12)
            .onTapGesture { Feel.tap(); edit.open(.home, water: water) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(me.home.map { "Home, " + $0.name } ?? "Home")
            .accessibilityAddTraits(.isButton)
    }

    /// the whole photo in the circle, its frame's middle at the circle's middle and its short side the circle's
    /// width at zoom 1
    private func framed(_ w: UIImage, _ frame: [Double]) -> some View {
        let f = ProfileStore.clamped(frame, size: w.size)
        let k = Self.picture * f[2] / min(w.size.width, w.size.height)
        return Image(uiImage: w).resizable().interpolation(.high)
            .frame(width: w.size.width * k, height: w.size.height * k)
            .offset(x: Self.picture / 2 - f[0] * w.size.width * k, y: Self.picture / 2 - f[1] * w.size.height * k)
            .frame(width: Self.picture, height: Self.picture, alignment: .topLeading)
    }

    /// a finger on the photo moves it under the circle, as far as its edges
    private var moving: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                guard let w = store.photoWhole else { return }
                let b = began ?? live ?? store.me.photoFrame ?? [0.5, 0.5, 1]
                if began == nil { began = b }
                moved = true
                // (with two fingers zooming as well, at the zoom they have reached)
                let z = live?[2] ?? b[2]
                let k = Self.picture * z / min(w.size.width, w.size.height)
                live = ProfileStore.clamped([b[0] - v.translation.width / (w.size.width * k),
                                             b[1] - v.translation.height / (w.size.height * k), z], size: w.size)
            }
            .onEnded { _ in keepFrame() }
    }

    /// two fingers zoom it, from once to four times
    private var zooming: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                guard let w = store.photoWhole else { return }
                let b = began ?? live ?? store.me.photoFrame ?? [0.5, 0.5, 1]
                if began == nil { began = b }
                moved = true
                let z = min(4, max(1, b[2] * v.magnification))
                if (z == 1 || z == 4), z != live?[2] { Feel.refuse() }
                live = ProfileStore.clamped([live?[0] ?? b[0], live?[1] ?? b[1], z], size: w.size)
            }
            .onEnded { _ in keepFrame() }
    }

    /// the fingers lifted: the frame kept and the circle's square cut again
    private func keepFrame() {
        began = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { moved = false }
        guard let f = live else { return }
        Task { await store.framePhoto(f); live = nil }
    }

    /// the picture: a full circle with no outline. Your photo, or a flag of yours, or your initial on the colour you
    /// picked (on black when none is); the initial is white on a deep colour and black on a pale one
    private func picture(_ me: ProfileStore.Me) -> some View {
        ZStack {
            if me.picture == "photo", let w = store.photoWhole, edit.sheet == .picture {
                // (its sheet up: the whole photo, moved with a finger and zoomed with two, the circle cutting it)
                framed(w, live ?? me.photoFrame ?? [0.5, 0.5, 1])
            } else if me.picture == "photo", let p = store.photo {
                Image(uiImage: p).resizable().interpolation(.high).scaledToFill()
            } else if let f = me.picture, f.hasPrefix("flag:") {
                FlagCircle(cc: String(f.dropFirst(5)), size: Self.picture)
            } else {
                // (no colour picked: white, never black:)
                Circle().fill(me.colour?.color ?? Palette.white)
                if let first = me.name.trimmingCharacters(in: .whitespaces).first ?? me.handle.first(where: { $0.isLetter }) {
                    Text(String(first).uppercased())
                        .font(Typeface.nature(Self.picture * 0.5, relativeTo: .largeTitle))
                        .foregroundStyle(me.letter?.color ?? ((me.colour?.light ?? 1) > 0.72 ? Palette.ink : Palette.white))
                        .dynamicTypeSize(.large)
                } else if me.colour == nil {
                    Icon5(key: "plus", ink: Palette.ink.opacity(0.5), size: Self.picture * 0.22)
                }
            }
        }
        .frame(width: Self.picture, height: Self.picture)
        .clipShape(Circle())
    }
}

/// THE PROFILE'S WATER AT 25%: the three numbers, your stats, your stamps and your badge levels, in three equal
/// columns across the water, each the map sheet's own big number at the very height the map's number has (76 pt under
/// the water's top), so your stamps in the middle stand where the map's count stands, each its word under it as the
/// map's; no boxes, no marks. They count up the first time the Profile is opened after the app starts; they are there
/// only while the whole line fits above the capsule and roll out before the water's edge comes down to them, as the
/// map's caption does.
struct ProfileWater: View {
    let water: Water
    let form: Water.Form
    let map: MapController
    /// the Map tab, as its button opens it (the stamps number's tap)
    var openMap: () -> Void = {}
    @State private var numbers = ProfileNumbers.shared
    @State private var edit = ProfileEdit.shared
    @State private var shown = false
    /// how far the count up has come, 0...1 (1 once it has run)
    @State private var run: Double = ProfileWater.counted ? 1 : 0
    /// the count up has run since the app started
    static var counted = false
    @ScaledMetric(relativeTo: .largeTitle) private var big: CGFloat = 64
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let L = water.layout
        let column = (L.W - 2 * L.sheetInset - 32) / 3
        let values = [numbers.stats, numbers.stamps, numbers.badges]
        let names = ["stats", "stamps", "badge levels"]
        let words = ["stats", "stamps", "badges"]
        // (four digits and more: all three a size down together, so each still fits its column)
        let size: CGFloat = (values.max() ?? 0) >= 1000 ? big * 0.75 : big
        let fits = form.top <= L.capsule.minY - 134 && !(water.stop == .closed && !water.held)
            // (a sheet up: they give it their place)
            && !(edit.sheet != nil && (water.stop == .half || water.stop == .full))
        ZStack(alignment: .topLeading) {
            if numbers.ready {
                ForEach(0 ..< 3, id: \.self) { i in
                    let v = Int((Double(values[i]) * run).rounded())
                    Text(shown ? v.formatted() : Caption.blank(values[i].formatted(), "\u{2007}"))
                        .font(.system(size: size, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .contentTransition(run < 1 ? .identity : .numericText(value: shown ? Double(v) : -1))
                        .frame(width: column)
                        .position(x: L.W / 2 + CGFloat(i - 1) * column, y: form.top + 76)
                        .accessibilityLabel("\(values[i]) \(names[i])")
                        // (the three numbers are read as their buttons, below)
                        .accessibilityHidden(true)
                    // ITS WORD under it, as the map's caption writes under its number: the body size, semibold, the
                    // one grey
                    Text(shown ? words[i] : Caption.blank(words[i], "\u{2002}"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink.opacity(0.5))
                        .lineLimit(1)
                        .contentTransition(.numericText(value: shown ? 1 : 0))
                        .frame(width: column)
                        .position(x: L.W / 2 + CGFloat(i - 1) * column, y: form.top + 76 + size * 0.59 + 3)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        // (never drawn over the tabs)
        .mask(alignment: .top) { Rectangle().frame(height: L.capsule.minY - 2) }
        .allowsHitTesting(false)
        // THE STAMPS NUMBER OPENS YOUR MAP, as you left it (each number opens what it counts; the stats and the badge
        // levels have no pages yet, so they take no tap)
        .overlay(alignment: .topLeading) {
            if numbers.ready, shown {
                // YOUR STATS: the left number opens their list (the water at full)
                Color.clear
                    .frame(width: column, height: max(44, size + 12))
                    .contentShape(Rectangle())
                    .onTapGesture { Feel.tap(); edit.open(.stats, water: water) }
                    .position(x: L.W / 2 - column, y: form.top + 76)
                    .accessibilityElement()
                    .accessibilityLabel("\(numbers.stats) stats")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { edit.open(.stats, water: water) }
                // YOUR BADGES: the right number opens them (the water at full)
                Color.clear
                    .frame(width: column, height: max(44, size + 12))
                    .contentShape(Rectangle())
                    .onTapGesture { Feel.tap(); edit.open(.badges, water: water) }
                    .position(x: L.W / 2 + column, y: form.top + 76)
                    .accessibilityElement()
                    .accessibilityLabel("\(numbers.badges) badge levels")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { edit.open(.badges, water: water) }
                Color.clear
                    .frame(width: column, height: max(44, size + 12))
                    .contentShape(Rectangle())
                    .onTapGesture { openMap() }
                    .position(x: L.W / 2, y: form.top + 76)
                    .accessibilityElement()
                    .accessibilityLabel("\(numbers.stamps) stamps")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { openMap() }
            }
        }
        // THE PICTURE'S AND THE NATIONALITIES' SHEETS, in the numbers' place once the water is at 50%
        .overlay(alignment: .topLeading) {
            let w = L.W - 2 * L.sheetInset - 32
            if let s = edit.sheet, water.stop == .half || water.stop == .full, form.top <= L.top(.half) + 24 {
                Group {
                    switch s {
                    case .picture: ProfilePictureSheet(water: water, width: w)
                    case .ground: ProfileGroundSheet(width: w)
                    // (stats and badges are their own pages, ProfilePushedPage)
                    case .stats, .badges: EmptyView()
                    case .nationalities:
                        NationalitiesSheet(water: water, map: map, width: w, room: max(56, L.capsule.minY - 8 - max(form.top + 16, L.safeTop + 8)))
                    case .home:
                        HomeSheet(water: water, width: w, room: max(56, L.capsule.minY - 8 - max(form.top + 16, L.safeTop + 8)))
                    }
                }
                .offset(x: L.sheetInset + 16, y: s == .stats || s == .badges ? max(form.top + 16, L.safeTop)
                        : max(form.top + (s == .nationalities || s == .home ? 16 : 24), L.safeTop + 8))
            }
        }
        // (the water pulled down from 50%: the sheet is put away with it)
        .onChange(of: water.stop) { _, st in
            // (stats and badges close the water under their pages: their back circle closes them)
            if let s = edit.sheet, s != .stats, s != .badges, st == .quarter || st == .closed { edit.close(water: water, move: false) }
            // (Stats or Badges up and the water pulled up from closed: the page goes, the water where it was pulled)
            if let s = edit.sheet, s == .stats || s == .badges, st != .closed { withAnimation(Motion.chrome) { edit.close(water: water, move: false) } }
        }
        .onChange(of: fits, initial: true) { was, f in
            guard shown != f else { return }
            // (the tab opening: the numbers are simply there; the water pulled: they roll out and in at its edge)
            if was == f || water.tabSwitching { shown = f }
            else { withAnimation(f ? Motion.quick : .smooth(duration: Motion.reduce ? 0.1 : 0.15)) { shown = f } }
        }
        // (counted again when your marks change, and when the map's own count does: the Count setting, the borders)
        .task(id: numbers.asks + " \(map.shares["World"]?.have ?? -1)/\(map.shares["World"]?.total ?? -1) \(CountKind.current) "
              + edit.nationalities.joined(separator: ",") + "|" + (ProfileStore.shared.me.home?.id ?? "")) {
            await numbers.count(map: map)
        }
        .task(id: numbers.ready) {
            // THE COUNT UP, once: from nought to each number over 0.8 s, quick first and slowing to the end
            guard numbers.ready, !Self.counted else { return }
            Self.counted = true
            if Motion.reduce { run = 1; return }
            // (plain steps, each digit simply the next: a roll on every step smeared the digits into each other)
            let steps = 24
            for k in 1 ... steps {
                try? await Task.sleep(for: .milliseconds(34))
                let t = Double(k) / Double(steps)
                run = 1 - pow(1 - t, 3)
            }
            run = 1
        }
        // the Badges page's first pictures made while the Profile sits still (after the count up), so its tap is instant
        .task {
            try? await Task.sleep(for: .milliseconds(1400))
            await ProfileBadgesList.prewarm(width: water.layout.W - 2 * water.layout.side, scale: displayScale)
        }
    }
}
