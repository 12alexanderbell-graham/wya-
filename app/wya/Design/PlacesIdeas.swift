import SwiftUI

/// PLACES SHEET IDEAS (31 Oct): five ways
/// the Places water could hold your maps, each drawn at 50% over the real Places map (a snapshot from the simulator),
/// in the app's own type and colours. A review sheet only (simulator debug builds): nothing here is in the app.
enum PlacesIdeas {
    // the Pro Max, in points
    static let W: CGFloat = 440, H: CGFloat = 956, inset: CGFloat = 8, half: CGFloat = 430

    struct Row: Identifiable { let id = UUID(); let flag: String?; let icon: String?; let title: String; let line: String; let have: Int; let of: Int }
    static let rows: [Row] = [
        Row(flag: nil, icon: "map-places", title: "Formula 1 2026", line: "3 of 23 races", have: 3, of: 23),
        Row(flag: nil, icon: "map-places", title: "UNESCO World Heritage", line: "5 of 1,273 sites", have: 5, of: 1273),
        Row(flag: "de", icon: nil, title: "Germany", line: "6 places", have: 6, of: 0),
        Row(flag: "fr", icon: nil, title: "France", line: "4 places", have: 4, of: 0),
        Row(flag: "ch", icon: nil, title: "Switzerland", line: "2 places", have: 2, of: 0),
    ]

    @MainActor static func make() {
        #if targetEnvironment(simulator) && DEBUG
        let back = UIImage(contentsOfFile: Snap.dir + "/ideas-map.jpg")
        let items: [ReviewItem] = [
            ReviewItem(id: "A", name: "Your maps as rows", view: AnyView(phone(back) { a() })),
            ReviewItem(id: "B", name: "Text tiles, two across", view: AnyView(phone(back) { b() })),
            ReviewItem(id: "C", name: "The map you're on, then Change", view: AnyView(phone(back) { c() })),
            ReviewItem(id: "D", name: "Circles", view: AnyView(phone(back) { d() })),
            ReviewItem(id: "E", name: "Three groups", view: AnyView(phone(back) { e() })),
        ]
        ReviewSheet.save("places-ideas", title: "Places sheet: five ideas (at 50%, over the real Places map)",
                         note: "Drawn by the app's own code, at the phone's real size. Each: All my places on top, then the same four maps (Formula 1 2026, UNESCO World Heritage, Germany, France).", items: items,
                         cell: CGSize(width: W, height: H + 34), columns: 3)
        #endif
    }

    // MARK: the phone and the water

    static func phone<C: View>(_ back: UIImage?, @ViewBuilder content: () -> C) -> some View {
        ZStack(alignment: .top) {
            if let back { Image(uiImage: back).resizable().frame(width: W, height: H) } else { Palette.white }
            water().offset(y: half)
            VStack(spacing: 0) {
                caption("All my places", "15", "places").padding(.top, half + 22)
                content().padding(.top, 18)
                Spacer(minLength: 0)
            }
            .frame(width: W, height: H)
            tabs().position(x: W / 2, y: H - 52)
        }
        .frame(width: W, height: H)
        .clipShape(RoundedRectangle(cornerRadius: 60, style: .continuous))
    }
    static func water() -> some View {
        RoundedRectangle(cornerRadius: 52, style: .continuous)
            // (opaque here: the snapshot under it has the real 25% water and its caption, which must not show through)
            .fill(Palette.white)
            .overlay(RoundedRectangle(cornerRadius: 52, style: .continuous).fill(Palette.blue.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 52, style: .continuous).stroke(Palette.white.opacity(0.7), lineWidth: 1))
            .frame(width: W - 2 * inset, height: H - half - inset)
    }
    static func caption(_ name: String, _ n: String, _ tail: String) -> some View {
        VStack(spacing: 0) {
            Text(name).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
            Text(n).font(.system(size: 64, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink).padding(.top, -6)
            Text(tail).font(.headline).foregroundStyle(Palette.ink.opacity(0.5)).padding(.top, -8)
        }
    }
    static func tabs() -> some View {
        HStack(spacing: 92) {
            Circle().fill(Palette.ink).frame(width: 22, height: 22)
            Rectangle().stroke(Palette.ink.opacity(0.5), lineWidth: 2.4).frame(width: 20, height: 20)
            Triangle().stroke(Palette.ink.opacity(0.5), lineWidth: 2.4).frame(width: 22, height: 19)
        }
    }
    struct Triangle: Shape {
        func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath() } }
    }
    @ViewBuilder static func mark(_ r: Row, _ size: CGFloat) -> some View {
        if let f = r.flag, let img = Flags.round(f) {
            img.resizable().frame(width: size, height: size).clipShape(Circle())
        } else {
            ZStack { Circle().fill(Palette.ink); Icon5(key: r.icon ?? "map-places", ink: .white, size: size * 0.5) }.frame(width: size, height: size)
        }
    }

    // MARK: A. rows: what each map is, how far along you are (a collection's ring; a country's count)
    static func a() -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.prefix(4).enumerated()), id: \.offset) { n, r in
                if n > 0 { Rectangle().fill(Palette.ink.opacity(0.12)).frame(height: 0.5).padding(.leading, 78).padding(.trailing, 24) }
                HStack(spacing: 14) {
                    mark(r, 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text(r.line).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                    if r.of > 0 {
                        ZStack {
                            Circle().stroke(Palette.ink.opacity(0.12), lineWidth: 3)
                            Circle().trim(from: 0, to: max(0.02, CGFloat(r.have) / CGFloat(r.of))).stroke(Palette.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                        }.frame(width: 26, height: 26)
                    }
                }
                .padding(.horizontal, 24).frame(height: 58)
            }
        }
    }

    // MARK: B. tiles: two across, words and numbers only, the same size each (no pictures)
    static func b() -> some View {
        let cols = [GridItem(.fixed(186), spacing: 12), GridItem(.fixed(186), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(rows.prefix(4)) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2, reservesSpace: true)
                    Spacer(minLength: 0)
                    Text("\(r.have)").font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                    Text(r.of > 0 ? "of \(r.of.formatted())" : "places").font(.footnote).foregroundStyle(Palette.ink.opacity(0.5))
                }
                .padding(14)
                .frame(width: 186, height: 124, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.white.opacity(0.75)))
            }
        }
    }

    // MARK: C. the map you're on, one line of what's next, and one way to the others
    static func c() -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                mark(rows[0], 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next: Abu Dhabi").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("Yas Marina Circuit · 6 Dec").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            Text("Change map")
                .font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 28).frame(height: 48)
                .background(Capsule().fill(Palette.white.opacity(0.8)))
        }
    }

    // MARK: D. circles: four across, the current one ringed, its name under each
    static func d() -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(rows.prefix(4).enumerated()), id: \.offset) { n, r in
                VStack(spacing: 8) {
                    mark(r, 64)
                        .overlay(Circle().stroke(Palette.ink, lineWidth: n == 0 ? 3 : 0).padding(-5))
                    Text(r.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(width: 84)
                    Text(r.of > 0 ? "\(r.have) of \(r.of.formatted())" : "\(r.have)").font(.caption).foregroundStyle(Palette.ink.opacity(0.5))
                }
            }
        }
    }

    // MARK: E. three groups, a word each, the rows of the one picked under them
    static func e() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                ForEach(["Mine", "Collections", "Countries"], id: \.self) { t in
                    Text(t).font(.subheadline.weight(.semibold))
                        .foregroundStyle(t == "Collections" ? Palette.white : Palette.ink)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(Capsule().fill(t == "Collections" ? Palette.ink : .clear))
                }
            }
            .padding(4).background(Capsule().fill(Palette.white.opacity(0.75)))
            .padding(.horizontal, 24)
            VStack(spacing: 0) {
                ForEach(Array(rows.prefix(2).enumerated()), id: \.offset) { n, r in
                    if n > 0 { Rectangle().fill(Palette.ink.opacity(0.12)).frame(height: 0.5) }
                    HStack {
                        Text(r.title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(r.line).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                    }
                    .frame(height: 50)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}
