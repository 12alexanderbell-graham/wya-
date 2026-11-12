import SwiftUI
import PhotosUI

/// EDITING YOUR PROFILE ON THE PROFILE ITSELF: no Edit button and no other screen. A tap on your name, handle or bio
/// makes that line its own text box where it stands (the keyboard's Done, or a tap anywhere else, keeps it); a tap on
/// the picture brings the picture sheet into the water at 50% (the colour picker, Upload, your flags); a tap on the
/// nationalities line brings your nationalities there. Pulling the water down puts a sheet away.
@MainActor
@Observable
final class ProfileEdit {
    static let shared = ProfileEdit()
    enum Field: Hashable { case name, handle, bio }
    enum Sheet { case picture, nationalities }
    /// the line being typed in
    var field: Field?
    /// what the water holds instead of the three numbers
    private(set) var sheet: Sheet?
    /// the nationalities' search is being typed in (the water goes to full, clear of the keyboard)
    var searching = false
    /// what is typed in the nationalities' search
    var query = ""

    func open(_ s: Sheet, water: Water) {
        field = nil
        searching = false
        sheet = s
        water.go(.half)
        // (the water could not rise: no sheet left hidden under 25%)
        if water.stop != .half { sheet = nil }
    }
    /// the sheet put away; `move: false` when the water has already gone down by itself
    func close(water: Water, move: Bool = true) {
        guard sheet != nil else { return }
        sheet = nil
        searching = false
        query = ""
        if move { water.go(.quarter) }
    }
    /// a tap off whatever is being edited: typing ends (kept), a sheet goes
    func end(water: Water) {
        field = nil
        close(water: water)
    }

    // MARK: your nationalities

    /// as place ids ("de", "us"), the first being the passport the app shows (Part 14): the map's home, search's
    /// suggestions and a place's visa line read the same list
    var nationalities: [String] = UserDefaults.standard.stringArray(forKey: MapController.nationalitiesKey) ?? []
    func setNationalities(_ n: [String], map: MapController) {
        nationalities = n
        if n.isEmpty { UserDefaults.standard.removeObject(forKey: MapController.nationalitiesKey) }
        else { UserDefaults.standard.set(n, forKey: MapController.nationalitiesKey) }
        map.refreshHome()
        // a flag picture whose nationality went is your initial again
        if let p = ProfileStore.shared.me.picture, p.hasPrefix("flag:"), !n.contains(String(p.dropFirst(5))) {
            ProfileStore.shared.set { $0.picture = nil }
        }
    }
}

/// a country's flag in a circle (the picture's and the sheets' own size); nothing when the flag is missing
struct FlagCircle: View {
    let cc: String
    let size: CGFloat
    var body: some View {
        Group {
            if let f = Flags.square(cc) { f.resizable().interpolation(.high).scaledToFill() } else { Palette.ink.opacity(0.5) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().inset(by: -0.25).stroke(Palette.ink.opacity(0.15), lineWidth: 0.5))
    }
}

/// THE PICTURE SHEET (water at 50%): the colour picker, the picture above taking the colour as the finger moves; then
/// Upload (Apple's photo picker: no permission asked, the photo's middle square kept) and your nationalities' flags.
/// No preset colours, no premium.
struct ProfilePictureSheet: View {
    let water: Water
    let width: CGFloat
    @State private var store = ProfileStore.shared
    @State private var edit = ProfileEdit.shared
    @State private var item: PhotosPickerItem?
    @State private var pick = ProfileStore.shared.me.colour ?? ProfilePictureSheet.start

    /// the picker's spot before any colour is picked: the field at its full colour, the marker at its deepest (the
    /// picture stays black until a colour is touched)
    static let start = ColourPick(hue: 250, light: ColourPick.lightBottom, strength: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ColourPicker(colour: Binding(get: { pick }, set: { c in
                pick = c
                store.set({ $0.colour = c; $0.picture = nil }, keep: false)
            }), suggested: nil, width: width) { c in
                store.set { $0.colour = c; $0.picture = nil }
            }
            HStack(spacing: 12) {
                PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                    Text("Upload").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 20).frame(height: 44)
                        .glassEffect(PageGlass.control.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                ForEach(edit.nationalities, id: \.self) { cc in
                    Button {
                        Feel.tap()
                        store.set { $0.picture = "flag:" + cc }
                    } label: { FlagCircle(cc: cc, size: 44) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Flag")
                }
                Spacer(minLength: 0)
            }
            .frame(width: width, height: 44)
        }
        .frame(width: width, alignment: .leading)
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self) { Feel.tap(); await store.setPhoto(d) }
                else { Feel.refuse() }
                item = nil
            }
        }
    }
}

/// YOUR NATIONALITIES (water at 50%): one row each (flag, name), the first the passport the app shows; a tap on a row
/// makes it the first; its × takes it away. Under them, a field to add one: the countries whose names start with
/// what is typed (any word of the name from three letters), a tap adds it.
struct NationalitiesSheet: View {
    let water: Water
    let map: MapController
    let width: CGFloat
    let room: CGFloat
    @State private var edit = ProfileEdit.shared
    @FocusState private var typing: Bool
    private var query: String { edit.query }

    static let rowH: CGFloat = 56

    private func name(_ cc: String) -> String { map.world.flatMap { w in w.placeIndex[cc].map { w.places[$0].n } } ?? cc.uppercased() }
    private var found: [(id: String, n: String)] {
        let q = query.trimmingCharacters(in: .whitespaces).townFolded
        guard !q.isEmpty, let w = map.world else { return [] }
        let have = Set(edit.nationalities)
        var start: [(String, String)] = [], inside: [(String, String)] = []
        for p in w.places where !have.contains(p.id) {
            let f = p.n.townFolded
            if f.hasPrefix(q) { start.append((p.id, p.n)) }
            else if q.count >= 3, f.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { inside.append((p.id, p.n)) }
        }
        return Array((start.sorted { $0.1 < $1.1 } + inside.sorted { $0.1 < $1.1 }).prefix(5)).map { (id: $0.0, n: $0.1) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(edit.nationalities.enumerated()), id: \.element) { i, cc in
                    HStack(spacing: 12) {
                        FlagCircle(cc: cc, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name(cc)).font(.headline).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                            if i == 0 { Text("Passport").font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)) }
                        }
                        Spacer(minLength: 8)
                        Button {
                            Feel.lift()
                            withAnimation(Motion.quick) { edit.setNationalities(edit.nationalities.filter { $0 != cc }, map: map) }
                        } label: {
                            Icon5Still(key: "cross", progress: 0, ink: Palette.white, size: 13)
                                .frame(width: 24, height: 24).background(Palette.ink, in: .circle)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove")
                    }
                    .frame(minHeight: Self.rowH)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard i > 0 else { return }
                        Feel.tap()
                        var n = edit.nationalities; n.remove(at: i); n.insert(cc, at: 0)
                        withAnimation(Motion.quick) { edit.setNationalities(n, map: map) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Show as passport") {
                        var n = edit.nationalities; n.remove(at: i); n.insert(cc, at: 0)
                        edit.setNationalities(n, map: map)
                    }
                }
                TextField("", text: Binding(get: { edit.query }, set: { edit.query = String($0.prefix(40)) }),
                          prompt: Text("Add a nationality").foregroundStyle(Palette.ink.opacity(0.5)))
                    .font(.body).foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit { if let f = found.first { add(f.id) } }
                    .frame(minHeight: Self.rowH)
                ForEach(found, id: \.id) { f in
                    HStack(spacing: 12) {
                        FlagCircle(cc: f.id, size: 28)
                        Text(f.n).font(.headline).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: Self.rowH)
                    .contentShape(Rectangle())
                    .onTapGesture { add(f.id) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            }
            .frame(width: width)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: room)
        .onChange(of: typing) { _, t in
            edit.searching = t
            water.go(t ? .full : .half)
        }
    }
    private func add(_ cc: String) {
        Feel.tap()
        edit.query = ""
        withAnimation(Motion.quick) { edit.setNationalities(edit.nationalities + [cc], map: map) }
    }
}
