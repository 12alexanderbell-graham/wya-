import SwiftUI
import PhotosUI

/// A LIST MADE YOUR OWN (25 Nov): name, what it is for, an icon (one of six, each three pieces, each piece its own
/// colour) or a photo, when, who can see it; archive, hide, delete. The icon is a stack of see-through pieces, the
/// front one see-through too.

/// the six icons, each three pieces, back to front
enum ListIcon: String, CaseIterable, Sendable {
    // ("fan", not "cascade": every list stored before 25 Nov says "cascade", the old default, and keeps its map)
    case fan, stripes, rings, wedges, steps, peaks

    /// piece `i` (0 back, 2 front) in a unit square
    func piece(_ i: Int, in r: CGRect) -> Path {
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        switch self {
        case .fan:
            // three cards fanned back to front, each a rounded square
            let s = w * 0.56, o = w * 0.14
            let c = CGRect(x: x + w * 0.08 + CGFloat(i) * o, y: y + w * 0.08 + CGFloat(i) * o, width: s, height: s)
            return Path(roundedRect: c, cornerRadius: s * 0.22, style: .continuous)
        case .stripes:
            let band = h * 0.26, gap = h * 0.07
            let top = y + (h - 3 * band - 2 * gap) / 2
            return Path(roundedRect: CGRect(x: x + w * 0.12, y: top + CGFloat(i) * (band + gap), width: w * 0.76, height: band),
                        cornerRadius: band * 0.3, style: .continuous)
        case .rings:
            // three discs overlapping, as a Venn
            let d = w * 0.5
            let centres = [CGPoint(x: x + w * 0.38, y: y + h * 0.38), CGPoint(x: x + w * 0.62, y: y + h * 0.38),
                           CGPoint(x: x + w * 0.5, y: y + h * 0.6)]
            let c = centres[i]
            return Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
        case .wedges:
            // a disc cut into three
            let c = CGPoint(x: r.midX, y: r.midY), rad = w * 0.4
            var p = Path()
            p.move(to: c)
            p.addArc(center: c, radius: rad, startAngle: .degrees(-90 + Double(i) * 120 + 3),
                     endAngle: .degrees(-90 + Double(i + 1) * 120 - 3), clockwise: false)
            p.closeSubpath()
            return p
        case .steps:
            let bw = w * 0.22, gap = w * 0.05
            let left = x + (w - 3 * bw - 2 * gap) / 2
            let bh = h * [0.34, 0.54, 0.74][i]
            return Path(roundedRect: CGRect(x: left + CGFloat(i) * (bw + gap), y: y + h * 0.87 - bh, width: bw, height: bh),
                        cornerRadius: bw * 0.25, style: .continuous)
        case .peaks:
            // three mountains, the far one high at the back
            let base = y + h * 0.84
            let peaks: [(CGFloat, CGFloat, CGFloat)] = [(0.58, 0.16, 0.36), (0.32, 0.36, 0.30), (0.70, 0.44, 0.28)]
            let (px, py, half) = peaks[i]
            var p = Path()
            p.move(to: CGPoint(x: x + w * (px - half), y: base))
            p.addLine(to: CGPoint(x: x + w * px, y: y + h * py))
            p.addLine(to: CGPoint(x: x + w * (px + half), y: base))
            p.closeSubpath()
            return p
        }
    }
}

/// the colours a piece can take: the app's own eight
enum ListColours {
    static let names = ["lime", "teal", "blue", "yellow", "red", "brown", "grey", "ink"]
    /// the colour as the map's renderer takes it
    static func vector(_ n: String) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(colour(n)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), 1)
    }
    static func colour(_ n: String) -> Color {
        switch n {
        case "teal": Palette.teal
        case "blue": Palette.blue
        case "yellow": Palette.yellow
        case "red": Palette.red
        case "brown": Palette.brown
        case "grey": Palette.grey
        case "ink": Palette.ink
        default: Palette.lime
        }
    }
}

/// A LIST'S ICON AS ITS COVER: its three pieces in their colours, each a little see-through so they read as a stack
/// of coloured glass, the front one see-through too,
/// on a pale ground of its front colour
struct ListIconCover: View {
    let icon: ListIcon
    let cols: [String]
    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size).insetBy(dx: g.size.width * 0.06, dy: g.size.height * 0.06)
            let side = min(r.width, r.height)
            let box = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
            ZStack {
                // (its ground its own three colours blended soft, corner to corner: one flat pale wash read unfinished
                // on a list's wide cover, 25 Nov)
                LinearGradient(colors: (0 ..< 3).map { ListColours.colour($0 < cols.count ? cols[$0] : "lime").opacity(0.34) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(0 ..< 3, id: \.self) { i in
                    icon.piece(i, in: box)
                        .fill(ListColours.colour(i < cols.count ? cols[i] : "lime").opacity(0.82))
                }
            }
        }
    }
}

/// where a list's own photo cover is kept
enum ListCoverPhotos {
    static func url(_ id: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("list-covers").appendingPathComponent(id + ".jpg")
    }
    static func image(_ id: String) -> UIImage? { url(id).flatMap { UIImage(contentsOfFile: $0.path) } }
    static func save(_ data: Data, for id: String) -> Bool {
        guard let u = url(id), let img = UIImage(data: data) else { return false }
        // (kept no bigger than a cover needs)
        let side: CGFloat = 1200, k = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
        let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpg = small.jpegData(compressionQuality: 0.85) else { return false }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? jpg.write(to: u)) != nil
    }
}

/// A LIST'S COVER as chosen: its map (the default), its photo, or its icon; nil for the map (drawn by the caller)
@MainActor func listOwnCover(_ l: MyList) -> AnyView? {
    if l.cov == "photo", let img = ListCoverPhotos.image(l.id) {
        return AnyView(Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }.clipped())
    }
    if let icon = ListIcon(rawValue: l.cov) { return AnyView(ListIconCover(icon: icon, cols: l.cols)) }
    return nil
}

/// a list's cover for its little pictures (its sheet, the archive): its own, else its map, else plain glass while it
/// has no places (a blank gap stood where its picture should be, 25 Nov)
@MainActor func listCoverOrGlass(_ l: MyList) -> AnyView {
    if let own = listOwnCover(l) { return own }
    let ccs = Array(l.countries.prefix(4))
    if ccs.isEmpty { return AnyView(Color.clear.glassEffect(.clear, in: .rect(cornerRadius: 12))) }
    return AnyView(ListCover(ccs: ccs, world: AIContext.map?.world, spots: []))
}

/// A LIST'S OWN SHEET (tapping its name, or Edit in its hold menu): everything that makes it yours, with no title and
/// nothing to save (every change is kept as it is made)
struct ListInfoSheet: View {
    let id: String
    var close: () -> Void
    @State private var store = ListsStore.shared
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    /// which of the icon's pieces is being coloured
    @State private var piece = 2
    @State private var confirmDelete = false
    @FocusState private var naming: Bool

    private var l: MyList? { store.book.lists.first { $0.id == id } }
    private func change(_ f: (inout MyList) -> Void) {
        ListsStore.shared.change { b in if let i = b.lists.firstIndex(where: { $0.id == id }) { f(&b.lists[i]) } }
    }
    private func text(_ kp: WritableKeyPath<MyList, String>, limit: Int) -> Binding<String> {
        Binding(get: { l?[keyPath: kp] ?? "" }, set: { v in change { $0[keyPath: kp] = String(v.prefix(limit)) } })
    }

    var body: some View {
        ScrollView {
            if let l {
                VStack(alignment: .leading, spacing: 24) {
                    // the cover as it will show, at the top (whatever you make looks as it will to others, 26 Sep)
                    HStack(alignment: .top, spacing: 16) {
                        Color.clear.frame(width: 96, height: 96)
                            .overlay { listOwnCover(l) ?? listCoverOrGlass(l) }
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("", text: text(\.name, limit: 60), prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                                .font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
                                .focused($naming)
                                .submitLabel(.done)
                                // (a new list: its name first, the keyboard up for it)
                                .onAppear { if l.name.isEmpty { naming = true } }
                            TextField("", text: text(\.what, limit: 140), prompt: Text("What it's for").foregroundStyle(Palette.ink.opacity(0.5)),
                                      axis: .vertical)
                                .font(.body).foregroundStyle(Palette.ink).lineLimit(1 ... 3)
                        }
                    }
                    section("Note") {
                        TextField("", text: text(\.note, limit: 1000), prompt: Text("Anything about this list").foregroundStyle(Palette.ink.opacity(0.5)),
                                  axis: .vertical)
                            .font(.body).foregroundStyle(Palette.ink).lineLimit(1 ... 6)
                            .frame(minHeight: 44)
                    }
                    section("Cover") { coverPicker(l) }
                    // ITS COLOUR ON THE MAP: its countries in it
                    // when you tap its cover to see it on the map
                    section("On the map") {
                        HStack(spacing: 8) {
                            ForEach(ListColours.names.filter { $0 != "ink" && $0 != "grey" }, id: \.self) { n in
                                Circle().fill(ListColours.colour(n))
                                    .overlay { Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 0.5) }
                                    .frame(width: 30, height: 30)
                                    .overlay { if l.mapc == n { Circle().strokeBorder(Palette.ink, lineWidth: 2).frame(width: 38, height: 38) } }
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                                    .onTapGesture { Feel.tap(); change { $0.mapc = n } }
                                    .accessibilityLabel(n)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    section("When") {
                        TextField("", text: text(\.when, limit: 60), prompt: Text("Any time, summer, 25 Oct 2027").foregroundStyle(Palette.ink.opacity(0.5)))
                            .font(.body).foregroundStyle(Palette.ink)
                            .frame(minHeight: 44)
                    }
                    section("Who can see it") {
                        choices(["me": "Only me", "friends": "Friends", "all": "Everyone"], order: ["me", "friends", "all"],
                                on: l.vis) { v in change { $0.vis = v } }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        // (no share picture: share cards are not to be built, 15 Nov)
                        rowButton(l.arch ? "Take out of the archive" : "Archive") {
                            change { $0.arch.toggle() }
                            // (archived: back to the shelf, the list's page closed with the sheet)
                            if self.l?.arch == true { ListsState.shared.open = nil; close() }
                        }
                        rowButton(l.hid ? "Show again" : "Hide") {
                            change { $0.hid.toggle() }
                            if self.l?.hid == true { ListsState.shared.open = nil; close() }
                        }
                        if !l.wish {
                            rowButton("Delete list", red: true) { confirmDelete = true }
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 140)
            }
        }
        .scrollIndicators(.hidden)
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images, photoLibrary: .shared())
        .onChange(of: picked) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self), ListCoverPhotos.save(d, for: id) {
                    Feel.tap(); change { $0.cov = "photo" }
                } else { Feel.refuse() }
                picked = nil
            }
        }
        .confirmationDialog("Delete this list?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Feel.lift()
                ListsStore.shared.change { b in b.lists.removeAll { $0.id == id } }
                if let u = ListCoverPhotos.url(id) { try? FileManager.default.removeItem(at: u) }
                ListsState.shared.open = nil
                close()
            }
        }
    }

    // MARK: the cover: Map · Photo · one of the six icons, and its three pieces' colours

    @ViewBuilder private func coverPicker(_ l: MyList) -> some View {
        let icon = ListIcon(rawValue: l.cov)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                pill("Map", on: icon == nil && l.cov != "photo") { change { $0.cov = "map" } }
                pill("Photo", on: l.cov == "photo") {
                    if ListCoverPhotos.image(id) != nil && l.cov != "photo" { change { $0.cov = "photo" } } else { picking = true }
                }
                if l.cov == "photo" { pill("New photo", on: false) { picking = true } }
            }
            // the six icons, each in this list's colours; the chosen one ringed
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                ForEach(ListIcon.allCases, id: \.self) { ic in
                    ListIconCover(icon: ic, cols: l.cols)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay { if ic == icon { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2) } }
                        .contentShape(Rectangle())
                        .onTapGesture { Feel.tap(); change { $0.cov = ic.rawValue } }
                        .accessibilityLabel("Icon " + ic.rawValue)
                        .accessibilityAddTraits(ic == icon ? [.isButton, .isSelected] : .isButton)
                }
            }
            if icon != nil {
                // ITS THREE PIECES: each tapped, then given its colour: the piece chosen,
                // then its colour from the app's eight; the front piece marked white, the middle grey, so you know
                // which goes where
                HStack(spacing: 12) {
                    ForEach([2, 1, 0], id: \.self) { i in
                        let c = i < l.cols.count ? l.cols[i] : "lime"
                        Circle().fill(ListColours.colour(c))
                            .overlay { Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 0.5) }
                            .frame(width: 36, height: 36)
                            .overlay { Circle().fill(i == 2 ? Palette.white : i == 1 ? Palette.grey : .clear).frame(width: 10, height: 10) }
                            .overlay { if piece == i { Circle().strokeBorder(Palette.ink, lineWidth: 2).frame(width: 44, height: 44) } }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .onTapGesture { Feel.tick(); piece = i }
                            .accessibilityLabel(["Back piece", "Middle piece", "Front piece"][i])
                    }
                    Spacer(minLength: 0)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                    ForEach(ListColours.names, id: \.self) { n in
                        let on = piece < l.cols.count && l.cols[piece] == n
                        Circle().fill(ListColours.colour(n))
                            .overlay { Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 0.5) }
                            .frame(width: 30, height: 30)
                            .overlay { if on { Circle().strokeBorder(Palette.ink, lineWidth: 2).frame(width: 38, height: 38) } }
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Feel.tap()
                                change { m in
                                    while m.cols.count < 3 { m.cols.append("lime") }
                                    m.cols[piece] = n
                                }
                            }
                            .accessibilityLabel(n)
                    }
                }
            }
        }
    }

    // MARK: parts

    private func section<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.5))
            content()
        }
    }
    private func pill(_ t: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button { Feel.tap(); act() } label: {
            Text(t).font(.body.weight(.semibold)).foregroundStyle(on ? Palette.white : Palette.ink)
                .padding(.horizontal, 16).frame(height: 44)
                .background { if on { Capsule().fill(Palette.ink) } }
                .glassEffect(on ? .clear : PageGlass.control.interactive(), in: .capsule)
        }
        .buttonStyle(.press)
    }
    private func choices(_ words: [String: String], order: [String], on: String, set: @escaping (String) -> Void) -> some View {
        HStack(spacing: 12) {
            ForEach(order, id: \.self) { k in pill(words[k] ?? k, on: on == k) { set(k) } }
            Spacer(minLength: 0)
        }
    }
    private func rowButton(_ t: String, red: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button { Feel.tap(); act() } label: {
            Text(t).font(.body).foregroundStyle(red ? Palette.red : Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// THE ARCHIVE (25 Nov): every archived or hidden list, its cover, its name and which it is; tapped, it opens; held,
/// it comes back to the shelf
struct ListArchiveSheet: View {
    var open: (String) -> Void
    @State private var store = ListsStore.shared
    var body: some View {
        let away = store.book.lists.filter { $0.arch || $0.hid }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if away.isEmpty {
                    Text("Nothing archived or hidden").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 88)
                }
                ForEach(away) { l in
                    HStack(spacing: 14) {
                        Color.clear.frame(width: 56, height: 56)
                            .overlay { listOwnCover(l) ?? listCoverOrGlass(l) }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.name.isEmpty ? "New list" : l.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(l.hid && l.arch ? "Archived, hidden" : l.hid ? "Hidden" : "Archived")
                                .font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                        Button {
                            Feel.tap()
                            ListsStore.shared.change { b in if let i = b.lists.firstIndex(where: { $0.id == l.id }) { b.lists[i].arch = false; b.lists[i].hid = false } }
                        } label: {
                            Text("Back on the shelf").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                                .padding(.horizontal, 16).frame(height: 44)
                                .glassEffect(PageGlass.control.interactive(), in: .capsule)
                        }
                        .buttonStyle(.press)
                    }
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                    .onTapGesture { Feel.tap(); open(l.id) }
                }
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
    }
}

/// APPLE'S SHARE SHEET as iOS itself brings it up, from the screen (wrapped in a SwiftUI sheet it stood at full height
/// with a blank preview, 25 Nov)
enum ShareSheet {
    @MainActor static func present(_ items: [Any]) {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
        #if DEBUG
        // (the test driver's eye: the picture as sent, kept where the snaps go)
        if let img = items.first as? UIImage, let png = img.pngData() { try? png.write(to: URL(fileURLWithPath: Snap.dir + "/share-card.png")) }
        #endif
    }
}

