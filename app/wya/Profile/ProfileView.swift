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

    static let picture: CGFloat = 132
    static let gap: CGFloat = 16
    /// the column the page is placed for: the picture, the name's line, the handle's, the code's, two lines of bio
    static let column: CGFloat = picture + gap + 41 + 4 + 22 + gap + 25 + gap + 44
    /// the gradient's strength (saturation, power): the stronger pair the first app kept for a picture's gradient; at
    /// the field's own (1.16, 2.0) the page was pale. The test driver can set it to compare (0 0 = the field's own)
    static var look = SIMD2<Double>(1.42, 2.9)

    var body: some View {
        let L = water.layout
        let me = store.me
        let mid = (L.safeTop + L.top(.quarter)) / 2
        let top = (mid - Self.column / 2).rounded()
        ZStack(alignment: .topLeading) {
            LivingField(custom: me.ground?.map(\.srgb), saturation: Self.look.x, power: Self.look.y)
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
                Button { Feel.tap(); edit.open(.picture, water: water) } label: { picture(me) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Picture")
                    .accessibilityHint("Changes your picture")
                nameLine(me)
                    .padding(.top, Self.gap)
                if !store.handleShown.isEmpty || edit.field == .handle {
                    handleLine
                        // (clear of the name's descenders)
                        .padding(.top, 4)
                }
                if !me.code.isEmpty {
                    Text(me.code)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .padding(.top, Self.gap)
                }
                bioLine(me)
                    .padding(.top, Self.gap)
                nationalitiesLine
                    .padding(.top, Self.gap)
            }
            .multilineTextAlignment(.center)
            .frame(width: L.W - 2 * L.circle)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .frame(width: L.W, alignment: .top)
            .offset(y: top)
            // (under your stats at full the column goes, so the black picture is no smudge through the glass)
            .opacity(edit.sheet == .stats && water.stop == .full ? 0 : 1)
            .animation(Motion.quick, value: edit.sheet == .stats && water.stop == .full)
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
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
                TextField("", text: Binding(get: { store.me.name }, set: { v in
                    if v.count > ProfileStore.nameMax { Feel.refuse() }
                    store.set { $0.name = String(v.prefix(ProfileStore.nameMax)) }
                }), prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                .font(font)
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit { edit.field = nil }
                .focused($typing, equals: .name)
                .onAppear { typing = .name }
            } else {
                Text(me.name.isEmpty ? "Name" : me.name)
                    .font(font)
                    .lineLimit(2)
                    // (a long name a little smaller rather than cut short)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
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
                HStack(spacing: 0) {
                    Text("@")
                    TextField("", text: Binding(get: { store.me.handle }, set: { v in
                        // lowercase letters, digits and "_", 20 at most
                        let h = String(v.lowercased().filter { ($0.isLetter && $0.isASCII) || $0.isNumber || $0 == "_" }.prefix(ProfileStore.handleMax))
                        if h.count < v.count { Feel.refuse() }
                        store.set { $0.handle = h }
                    }), prompt: Text(String(store.handleShown.dropFirst())).foregroundStyle(Palette.ink.opacity(0.5)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .onSubmit { edit.field = nil }
                    .focused($typing, equals: .handle)
                    .onAppear { typing = .handle }
                    .fixedSize()
                }
            } else {
                Text(store.handleShown)
                    .lineLimit(1)
                    .onTapGesture { Feel.tap(); edit.field = .handle }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Edits your handle")
            }
        }
        .font(.body)
        .foregroundStyle(Palette.ink.opacity(0.5))
    }

    private func bioLine(_ me: ProfileStore.Me) -> some View {
        Group {
            if edit.field == .bio {
                VStack(spacing: 4) {
                    TextField("", text: Binding(get: { store.me.bio }, set: { v in
                        // (one paragraph: Return is Done)
                        if v.contains("\n") { edit.field = nil; return }
                        if v.count > ProfileStore.bioMax { Feel.refuse() }
                        store.set { $0.bio = String(v.prefix(ProfileStore.bioMax)) }
                    }), prompt: Text("Bio").foregroundStyle(Palette.ink.opacity(0.5)), axis: .vertical)
                    .lineLimit(1 ... 3)
                    .submitLabel(.done)
                    .focused($typing, equals: .bio)
                    .onAppear { typing = .bio }
                    // the count, while typing only
                    Text("\(store.me.bio.count)/\(ProfileStore.bioMax)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Palette.ink.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                Text(me.bio.isEmpty ? "Bio" : me.bio)
                    .lineLimit(3)
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
                Text("Nationality").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
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
        .accessibilityLabel("Nationalities")
        .accessibilityAddTraits(.isButton)
    }

    /// the picture: a full circle with no outline. Your photo, or a flag of yours, or your initial on the colour you
    /// picked (on black when none is); the initial is white on a deep colour and black on a pale one
    private func picture(_ me: ProfileStore.Me) -> some View {
        ZStack {
            if me.picture == "photo", let p = store.photo {
                Image(uiImage: p).resizable().interpolation(.high).scaledToFill()
            } else if let f = me.picture, f.hasPrefix("flag:") {
                FlagCircle(cc: String(f.dropFirst(5)), size: Self.picture)
            } else {
                Circle().fill(me.colour?.color ?? Palette.ink)
                if let first = me.name.trimmingCharacters(in: .whitespaces).first {
                    Text(String(first).uppercased())
                        .font(Typeface.nature(Self.picture * 0.5, relativeTo: .largeTitle))
                        .foregroundStyle((me.colour?.light ?? 0) > 0.72 ? Palette.ink : Palette.white)
                        .dynamicTypeSize(.large)
                }
            }
        }
        .frame(width: Self.picture, height: Self.picture)
        .clipShape(Circle())
    }
}

/// THE PROFILE'S WATER AT 25%: the three numbers, your stats, your stamps and your badge levels, in three equal columns
/// across the water, each the map sheet's own big number at the very height the map's number has (76 pt under the
/// water's top), so your stamps in the middle stand where the map's count stands. No words, no boxes, no marks. They count up the first time the Profile is opened after
/// the app starts; they are there only while the whole line fits above the capsule and roll out before the water's
/// edge comes down to them, as the map's caption does.
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

    var body: some View {
        let L = water.layout
        let column = (L.W - 2 * L.sheetInset) / 3
        let values = [numbers.stats, numbers.stamps, numbers.badges]
        let names = ["stats", "stamps", "badge levels"]
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
                        // (the stats and stamps numbers are read as their buttons, below)
                        .accessibilityHidden(i <= 1)
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
                    case .stats: ProfileStatsList(width: w, room: max(56, L.capsule.minY - 8 - max(form.top + 16, L.safeTop)))
                    case .nationalities:
                        NationalitiesSheet(water: water, map: map, width: w, room: max(56, L.capsule.minY - 8 - (form.top + 16)))
                    }
                }
                // (at full, clear of the clock and the island)
                .offset(x: L.sheetInset + 16, y: s == .stats ? max(form.top + 16, L.safeTop) : form.top + (s == .nationalities ? 16 : 24))
            }
        }
        // (the water pulled down from 50%: the sheet is put away with it)
        .onChange(of: water.stop) { _, st in
            if edit.sheet != nil, st == .quarter || st == .closed { edit.close(water: water, move: false) }
        }
        .onChange(of: fits, initial: true) { was, f in
            guard shown != f else { return }
            // (the tab opening: the numbers are simply there; the water pulled: they roll out and in at its edge)
            if was == f || water.tabSwitching { shown = f }
            else { withAnimation(f ? Motion.quick : .smooth(duration: Motion.reduce ? 0.1 : 0.15)) { shown = f } }
        }
        // (counted again when your marks change, and when the map's own count does: the Count setting, the borders)
        .task(id: numbers.asks + " \(map.shares["World"]?.have ?? -1)/\(map.shares["World"]?.total ?? -1) \(CountKind.current) "
              + edit.nationalities.joined(separator: ",")) {
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
    }
}
