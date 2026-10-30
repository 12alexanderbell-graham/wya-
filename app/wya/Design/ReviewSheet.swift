import SwiftUI

/// REVIEW SHEETS: any set the build makes, every item drawn by the app's own drawing code at its real size (and larger,
/// to look closely), with its id and name, in a grid, saved as a picture into the test folder
/// (`snaps/review-<name>.png`). Simulator debug builds only.
struct ReviewItem: Identifiable {
    let id: String
    let name: String
    let view: AnyView
}

enum ReviewSheet {
    /// lays the items out `columns` across and writes the picture at 3x
    @MainActor static func save(_ name: String, title: String, items: [ReviewItem], cell: CGSize, columns: Int) {
        #if targetEnvironment(simulator) && DEBUG
        let sheet = VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text("\(items.count) items, drawn by the app's own code. Each: real size, then 3x; its id and name.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink.opacity(0.5))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell.width), spacing: 8), count: columns),
                      alignment: .leading, spacing: 8) {
                ForEach(items) { it in
                    VStack(spacing: 4) {
                        it.view.frame(height: cell.height - 34)
                        Text(it.id).font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                        Text(it.name).font(.system(size: 10)).foregroundStyle(Palette.ink.opacity(0.5))
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .frame(width: cell.width, height: cell.height)
                    .background(Palette.white)
                }
            }
        }
        .padding(16)
        .background(Palette.cream)
        let r = ImageRenderer(content: sheet)
        r.scale = 3
        guard let img = r.uiImage, let data = img.pngData() else { NSLog("wya review %@ failed", name); return }
        let path = Snap.dir + "/review-\(name).png"
        try? data.write(to: URL(fileURLWithPath: path))
        NSLog("wya review %@: %d items -> %@", name, items.count, path)
        #endif
    }

    /// the launch picture (iOS shows it before the app runs; the loading screen's first frame is the same picture, so
    /// nothing jumps): our cream, the logo's light at its start drawn by the same shader, and his logo at rest, on the
    /// Pro Max's screen at 3x, into snaps/launch-screen@3x.jpg
    @MainActor static func launchPicture() {
        #if targetEnvironment(simulator) && DEBUG
        let W: CGFloat = 440, H: CGFloat = 956
        let planet = Launch.planet(W), mark = planet * 1024 / 700
        let c = CGPoint(x: W / 2, y: H / 2)
        guard let light = GlassRender.picture(width: Int(W), height: Int(H), phase: GlassRender.rest,
                                              spot: LoadingScreen.spot(c, planet: planet, size: CGSize(width: W, height: H))) else {
            NSLog("wya launch picture: no light"); return
        }
        let v = ZStack {
            Palette.cream
            Image(decorative: light, scale: 1).resizable()
            LogoMark(phase: GlassRender.rest).frame(width: mark, height: mark).position(c)
        }
        .frame(width: W, height: H)
        let r = ImageRenderer(content: v)
        r.scale = 3
        if let d = r.uiImage?.jpegData(compressionQuality: 0.92) {
            try? d.write(to: URL(fileURLWithPath: Snap.dir + "/launch-screen@3x.jpg"))
        }
        NSLog("wya launch picture written")
        #endif
    }

    /// 1q: the tab icons, both sets (the logical test and the circle, square and triangle), off and on, at their real
    /// 24 pt and at 72 pt
    @MainActor static func tabIcons() {
        let keys = [("tab-map", "Map"), ("tab-lists-b", "Lists (logical)"), ("tab-profile-b", "Profile (logical)"),
                    ("tab-lists", "Lists (square)"), ("tab-profile", "Profile (triangle)")]
        var items: [ReviewItem] = []
        for (k, n) in keys {
            for on in [false, true] {
                let v = HStack(spacing: 14) {
                    Icon5(key: k, on: on, ink: on ? Palette.ink : Palette.ink.opacity(0.5), size: 24)
                    Icon5(key: k, on: on, ink: on ? Palette.ink : Palette.ink.opacity(0.5), size: 72)
                }
                items.append(ReviewItem(id: k + (on ? " on" : " off"), name: n, view: AnyView(v)))
            }
        }
        save("tabicons", title: "Tab icons (1q)", items: items, cell: CGSize(width: 150, height: 120), columns: 4)
    }

    /// 1m: every round flag as the rows draw it (22 pt, then 66 pt), by name
    @MainActor static func flags(world w: World?) {
        let names: [String: String] = {
            var m: [String: String] = [:]
            if let w { for p in w.places { m[p.id] = p.n } }
            return m
        }()
        let items = Flags.ids.sorted { (names[$0] ?? $0) < (names[$1] ?? $1) }.map { id -> ReviewItem in
            let f = Flags.round(id)
            let v = HStack(spacing: 10) {
                Group { if let f { f.resizable() } else { Circle().fill(Palette.grey) } }
                    .frame(width: 22, height: 22).clipShape(Circle())
                Group { if let f { f.resizable() } else { Circle().fill(Palette.grey) } }
                    .frame(width: 66, height: 66).clipShape(Circle())
            }
            return ReviewItem(id: id, name: names[id] ?? "?", view: AnyView(v))
        }
        save("flags", title: "Round flags (1m)", items: items, cell: CGSize(width: 110, height: 104), columns: 12)
        #if targetEnvironment(simulator) && DEBUG
        // the same list, in order, for the side-by-side with the source pictures (made outside the app)
        let list = items.map { ["id": $0.id, "name": $0.name] }
        if let d = try? JSONSerialization.data(withJSONObject: list) { try? d.write(to: URL(fileURLWithPath: Snap.dir + "/review-flags.json")) }
        #endif
    }
}
