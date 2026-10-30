import SwiftUI
import simd

/// A PLACE'S PAGE (Part 16), first build: a country's page from the data server's country facts (D9 as it is on the
/// server: `country/<cc>.json`), any other place with what the app carries (16.2 "No page yet": the top, the marking
/// block, your record). It grows out of what opened it (A16.1: one rounded rectangle from the origin's frame to the
/// screen, its corners always rounded, nothing fading) under the head, and goes back into it by a drag down on its top.
@MainActor
@Observable
final class PlacePageState {
    static let shared = PlacePageState()
    struct Facts {
        var prose = ""
        var rows: [(String, String)] = []
        /// For you (16.4.9): the visa line for each of your nationalities first, then each government's advice
        var visa: [String] = []
        var advice: [(who: String, text: String, when: String)] = []
        /// What is in it (16.4.8): a country's regions (first level) and its cities, most peopled first
        var regions: [Inside] = []
        var cities: [Inside] = []
    }
    struct Inside: Hashable { let key: PlaceKey; let name: String; let line: String; let code: String?; var at: SIMD2<Float>? = nil }
    private(set) var key: PlaceKey?
    private(set) var name = ""
    /// one line of what it is ("City in Hessen, Germany"); empty for a country
    private(set) var what = ""
    /// the country it is in (its flag and colours)
    private(set) var country: String = ""
    private(set) var facts: Facts?
    private(set) var origin: CGRect = .zero
    /// 0 at the origin to 1 full screen
    var p: CGFloat = 0
    var drag: CGFloat = 0
    /// the test driver's scroll to the end (checks)
    var toEnd = 0
    var isOpen: Bool { key != nil }

    /// a region's ISO 3166-2 code (its facts on the server are keyed by it)
    private var code: String?
    func open(_ key: PlaceKey, name: String, what: String = "", country: String, code: String? = nil, from origin: CGRect) {
        self.code = code
        guard self.key == nil else { return }
        self.key = key; self.name = name; self.what = what; self.country = country.lowercased()
        self.origin = origin; facts = nil; drag = 0; p = 0
        Feel.tap()
        DispatchQueue.main.async { [weak self] in
            withAnimation(Motion.reduce ? Motion.tight : .spring(response: 0.5, dampingFraction: 1)) { self?.p = 1 }
        }
        if key.kind == .country { Task { await loadCountry(key.id.lowercased()) } }
        if key.kind == .town { Task { await loadTown(self.country, id: key.id) } }
        if key.kind == .region, let code { Task { await loadRegion(self.country, code: code) } }
    }
    /// another place's page in this one's place (a row tapped on a page; a pushed page waits for its navigation)
    func replace(_ key: PlaceKey, name: String, what: String, country: String, code: String?) {
        self.key = key; self.name = name; self.what = what; self.country = country.lowercased(); self.code = code
        facts = nil
        Feel.tap()
        if key.kind == .town { Task { await loadTown(self.country, id: key.id) } }
        if key.kind == .region, let code { Task { await loadRegion(self.country, code: code) } }
    }
    func close() {
        guard key != nil else { return }
        withAnimation(Motion.reduce ? Motion.tight : .spring(response: 0.42, dampingFraction: 1)) { p = 0; drag = 0 } completion: { [weak self] in
            guard let self, self.p < 0.01 else { return }
            self.key = nil
        }
    }

    private func loadCountry(_ cc: String) async {
        guard case .ok(let d) = await Servers.data.file("country/\(cc).json"),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], key?.id.lowercased() == cc else { return }
        let f = j["facts"] as? [String: Any] ?? [:]
        var out = Facts()
        if let g = j["guide"] as? [String: Any], let intro = g["intro"] as? String { out.prose = Self.cut(intro, 620) }
        else if let desc = f["desc"] as? String { out.prose = desc.prefix(1).uppercased() + desc.dropFirst() + "." }
        func s(_ k: String) -> String? {
            switch f[k] {
            case let v as String: return v
            case let v as [String]: return v.prefix(3).joined(separator: ", ")
            case let v as NSNumber: return v.stringValue
            default: return nil
            }
        }
        if let v = s("capital") { out.rows.append(("Capital", v)) }
        if let v = f["population"] as? NSNumber { out.rows.append(("People", Self.big(v.doubleValue))) }
        if let v = f["area"] as? NSNumber { out.rows.append(("Area", Self.big(v.doubleValue) + " km²")) }
        if let v = s("timezone") { out.rows.append(("Time zones", v)) }
        if let c = f["currency"] as? [[String: Any]], let first = c.first {
            let n = (first["name"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            out.rows.append(("Currency", [n, (first["sym"] as? String).map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")))
        }
        if let v = s("officialLanguage") { out.rows.append(("Languages", v)) }
        if let v = s("drivingSide") { out.rows.append(("Driving side", v.capitalized)) }
        if let v = s("plug") { out.rows.append(("Plugs", v)) }
        if let v = s("callingCode") { out.rows.append(("Calling code", v)) }
        if let e = f["emergency"] as? [String], let first = e.first { out.rows.append(("Emergency", first)) }
        if let v = s("highestPoint") { out.rows.append(("Highest point", v)) }
        // each government's advice, with who says it and when it was checked
        let adv = j["advisories"] as? [String: Any] ?? [:]
        if let ca = adv["ca"] as? [String: Any], let t = ca["text"] as? String {
            out.advice.append(("Canada", t, Self.day(ca["updated"] as? String)))
        }
        if let us = adv["us"] as? [String: Any], let l = us["level"] as? String {
            out.advice.append(("United States", l.replacingOccurrences(of: #"^Level \d+: "#, with: "", options: .regularExpression),
                               Self.day(us["updated"] as? String)))
        }
        if let uk = adv["uk"] as? [String: Any], let a = uk["alert"] as? String, !a.isEmpty {
            let t = a.replacingOccurrences(of: "_", with: " ")
            out.advice.append(("United Kingdom", t.prefix(1).uppercased() + t.dropFirst(), Self.day(uk["updated"] as? String)))
        }
        // what is in it: the first level's regions (by people, from the server's regions where it has them) and the cities
        if let first = RegionCatalog.shared.first(cc), let file = await RegionCatalog.shared.fetch(cc, row: first.row) {
            var pop: [String: Double] = [:]
            if case .ok(let rd) = await Servers.data.file("regions/\(cc).json"),
               let all = try? JSONSerialization.jsonObject(with: rd) as? [String: Any] {
                for (k, v) in all { pop[k] = ((v as? [String: Any])?["pop"] as? NSNumber)?.doubleValue }
            }
            var seen = Set<String>()
            let word = RegionsMenuModel.word(first.level.one)
            out.regions = file.units.filter { seen.insert($0.id).inserted }
                .sorted { (pop[$0.code ?? ""] ?? 0) > (pop[$1.code ?? ""] ?? 0) }
                .map { u in Inside(key: PlaceKey(.region, u.id), name: u.name,
                                   line: pop[u.code ?? ""].map { "\(word.prefix(1).uppercased() + word.dropFirst()) · \(Self.big($0)) people" }
                                       ?? word.prefix(1).uppercased() + word.dropFirst(),
                                   code: u.code) }
        }
        if case .ok(let cd) = await Servers.data.file("cities/\(cc).json"),
           let all = try? JSONSerialization.jsonObject(with: cd) as? [[String: Any]] {
            out.cities = all.compactMap { t in
                guard let n = t["n"] as? String, let gid = (t["gid"] as? NSNumber)?.intValue else { return nil }
                let r = t["r"] as? String ?? ""
                let ll = t["ll"] as? [NSNumber]
                return Inside(key: PlaceKey(.town, "\(cc)/\(gid)"), name: n, line: r, code: nil,
                              at: ll.flatMap { $0.count == 2 ? EqualEarth.project(lon: $0[1].doubleValue, lat: $0[0].doubleValue) : nil })
            }
        }
        facts = out
        // the visa lines: for each of your nationalities (Profile), what its passport needs here
        let name = (f["name"] as? String) ?? (j["name"] as? String) ?? ""
        let nats = (UserDefaults.standard.stringArray(forKey: MapController.nationalitiesKey) ?? []).filter { $0 != cc }
        var visa: [String] = []
        for n in nats {
            guard case .ok(let nd) = await Servers.data.file("country/\(n).json"),
                  let nj = try? JSONSerialization.jsonObject(with: nd) as? [String: Any],
                  let v = (nj["visaFromHere"] as? [String: Any])?[name] as? String else { continue }
            let who = ((nj["facts"] as? [String: Any])?["name"] as? String) ?? (nj["name"] as? String) ?? n.uppercased()
            visa.append(Self.visa(v) + "\n" + "With your passport from \(who)")
        }
        guard key?.id.lowercased() == cc else { return }
        facts?.visa = visa
    }

    /// A TOWN'S FACTS (16.4.5: People, Height, Local time, Climate) from the server's cities (D9 as it is), by its
    /// GeoNames id
    private func loadTown(_ cc: String, id: String) async {
        guard let gid = Int(id.split(separator: "/").last ?? ""),
              case .ok(let d) = await Servers.data.file("cities/\(cc).json"),
              let all = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]],
              let t = all.first(where: { ($0["gid"] as? NSNumber)?.intValue == gid }), key?.id == id else { return }
        var out = Facts()
        if let p = t["p"] as? NSNumber, p.intValue > 0 { out.rows.append(("People", Self.big(p.doubleValue))) }
        if let e = t["ele"] as? NSNumber { out.rows.append(("Height", "\(e.intValue) m")) }
        if let z = t["tz"] as? String, let tz = TimeZone(identifier: z) {
            let f = DateFormatter(); f.timeZone = tz; f.dateFormat = "HH:mm"
            out.rows.append(("Local time", f.string(from: Date())))
        }
        if let c = t["climate"] as? [String: Any], let hi = c["hi"] as? [NSNumber], let lo = c["lo"] as? [NSNumber], hi.count == 12, lo.count == 12 {
            out.rows.append(("Climate", "\(Int(hi[6].doubleValue.rounded()))° Jul · \(Int(lo[0].doubleValue.rounded()))° Jan"))
        }
        facts = out
    }

    /// A REGION'S FACTS (16.4.5: People, Area, Capital, its parent) from the server's regions (level 1, by ISO code)
    private func loadRegion(_ cc: String, code: String) async {
        guard case .ok(let d) = await Servers.data.file("regions/\(cc).json"),
              let all = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = all[code] as? [String: Any], self.code == code else { return }
        var out = Facts()
        if let desc = r["d"] as? String { out.prose = desc.prefix(1).uppercased() + desc.dropFirst() + "." }
        if let p = r["pop"] as? NSNumber { out.rows.append(("People", Self.big(p.doubleValue))) }
        if let a = r["area"] as? NSNumber { out.rows.append(("Area", Self.big(a.doubleValue) + " km²")) }
        if let c = r["cap"] as? String { out.rows.append(("Capital", c)) }
        facts = out
    }

    /// "90" -> "visa free for 90 days"; the rest as they are written
    static func visa(_ v: String) -> String {
        if let d = Int(v) { return d < 0 ? "no entry" : "visa free for \(d) days" }
        return v.prefix(1).uppercased() + v.dropFirst()
    }
    /// a checked date as "21 Sep 2026" where it can be read, else as it is
    static func day(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        for f in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "EEE, dd MMM yyyy"] {
            let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = f
            if let d = df.date(from: String(s.prefix(f.count + 2)).trimmingCharacters(in: .whitespaces)) ?? df.date(from: s) {
                return d.formatted(.dateTime.day().month(.abbreviated).year())
            }
        }
        return s
    }

    /// up to n characters, cut at a whole sentence (16.4: prose)
    static func cut(_ s: String, _ n: Int) -> String {
        guard s.count > n else { return s }
        let head = String(s.prefix(n))
        if let r = head.range(of: ". ", options: .backwards) { return String(head[..<r.lowerBound]) + "." }
        return head
    }
    static func big(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1f billion", v / 1e9) }
        if v >= 1_000_000 { return String(format: "%.1f million", v / 1e6) }
        return Int(v).formatted()
    }
}

/// THE PAGE (16.3, 16.4)
struct PlacePageView: View {
    let map: MapController
    let water: Water
    @State private var page = PlacePageState.shared
    @State private var ground: [Color] = []
    /// the water's stop before the page came (it goes back there when the page closes)
    @State private var before: Water.Stop?

    var body: some View {
        ZStack { pageBody }
            .onChange(of: page.key == nil) { _, closed in
                if !closed { before = water.stop; water.go(.closed) }
                else if let b = before { water.go(b); before = nil }
            }
    }

    @ViewBuilder private var pageBody: some View {
        let L = water.layout
        if let key = page.key {
            let full = CGRect(x: 0, y: 0, width: L.W, height: L.H)
            let p = page.p * (1 - min(0.6, page.drag / (L.H * 1.2)))
            let r = CGRect(x: page.origin.minX + (full.minX - page.origin.minX) * p,
                           y: page.origin.minY + (full.minY - page.origin.minY) * p + page.drag * 0.5,
                           width: page.origin.width + (full.width - page.origin.width) * p,
                           height: page.origin.height + (full.height - page.origin.height) * p)
            let corner = min(page.origin.height / 2, 22) + (Self.screenCorner - min(page.origin.height / 2, 22)) * p
            content(key, L: L)
                .frame(width: L.W, height: L.H)
                .scaleEffect(x: r.width / L.W, y: r.height / L.H, anchor: .topLeading)
                .offset(x: r.minX, y: r.minY)
                .frame(width: L.W, height: L.H, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous).offset(x: r.minX, y: r.minY).size(r.size))
                .allowsHitTesting(page.p > 0.98)
                .onAppear { ground = Self.colours(page.country) }
                .onChange(of: page.country) { _, c in ground = Self.colours(c) }
        }
    }

    private static let screenCorner: CGFloat = 55

    @ViewBuilder private func content(_ key: PlaceKey, L: Layout) -> some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(spacing: 32) {
                top(key, L: L)
                marking(key)
                if let f = page.facts, !f.prose.isEmpty {
                    Text(f.prose).font(.body).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let f = page.facts, !f.rows.isEmpty { factsGrid(f.rows) }
                if let f = page.facts, !f.regions.isEmpty { insideList("Regions", f.regions) }
                if let f = page.facts, !f.cities.isEmpty { insideList("Cities", f.cities) }
                if let f = page.facts, !f.visa.isEmpty || !f.advice.isEmpty { forYou(f) }
                if MarkStore.shared.state(key).stamped { record(key) }
                Color.clear.frame(height: 140).id("end")
            }
            .padding(.horizontal, 16)
            // the ground scrolls with the page (one layer behind the whole scroll, 16.3)
            .background(alignment: .top) { groundView(L: L) }
        }
        .scrollIndicators(.hidden)
        // the one blur under the head, only once words scroll under it (16.3)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onChange(of: page.toEnd) { _, _ in reader.scrollTo("end", anchor: .bottom) }
        }
        .background(Palette.white)
    }

    /// THE TOP (16.4.1): a country's flag (4:3, 64 pt tall) centred 24 pt under the head's foot, its name under it; any
    /// other place its country's flag small and its line of what it is. Pulling it down closes the page (A16.1)
    private func top(_ key: PlaceKey, L: Layout) -> some View {
        VStack(spacing: 12) {
            if key.kind == .country, let f = Flags.wide(page.country) {
                f.resizable().aspectRatio(4 / 3, contentMode: .fit).frame(height: 64)
            } else if let f = Flags.square(page.country) {
                f.resizable().frame(width: 29, height: 29)
            }
            Text(page.name).font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !page.what.isEmpty {
                Text(page.what).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, L.headBottom + 24)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { v in page.drag = max(0, v.translation.height) }
            .onEnded { v in
                if v.translation.height > 120 || v.predictedEndTranslation.height > 260 { page.close() }
                else { withAnimation(.spring(response: 0.42, dampingFraction: 1)) { page.drag = 0 } }
            })
    }

    /// THE MARKING BLOCK (16.4.2): the stamping card's own buttons
    private func marking(_ key: PlaceKey) -> some View {
        let s = MarkStore.shared.state(key)
        return HStack(spacing: 12) {
            Button {
                Task {
                    if s.stamped { Feel.lift(); await MarkStore.shared.unstamp(key, name: page.name) }
                    else { Feel.stamp(); await MarkStore.shared.stamp(key, name: page.name) }
                }
            } label: {
                Text(s.stamped ? "Stamped" : "Stamp").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .glassEffect(s.stamped ? .clear.tint(Palette.lime) : .clear, in: .capsule)
            }
            Button {
                guard !s.stamped else { Feel.refuse(); return }
                Feel.tap()
                Task {
                    if s.wished { await MarkStore.shared.unwish(key, name: page.name) }
                    else { await MarkStore.shared.wish(key, name: page.name) }
                }
            } label: {
                Text("Wishlist").font(.body.weight(.semibold)).foregroundStyle(Palette.ink.opacity(s.stamped ? 0.5 : 1))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .glassEffect(s.wished ? .clear.tint(Palette.blue) : .clear, in: .capsule)
            }
        }
        .buttonStyle(.plain)
    }

    /// WHAT IS IN IT (16.4.8): a list with its own search field, five rows (the most peopled), then Show more; a row is a
    /// flag, its name and one line; its plus stamps it; a tap opens its page
    private func insideList(_ title: String, _ all: [PlacePageState.Inside]) -> some View {
        InsideList(title: title, all: all, country: page.country, countryName: page.name, map: map)
    }

    /// YOUR RECORD (16.4.10, only when stamped): big numbers in the Profile's style (64 pt rounded over 15 pt labels):
    /// the times; on a country its regions ("12 of 16") and cities. The month waits for the visits' dates (Part 9.9)
    private func record(_ key: PlaceKey) -> some View {
        let st = MarkStore.shared.state(key)
        var items: [(String, String)] = []
        if st.visits > 0 { items.append(("\(st.visits)", st.visits == 1 ? "time" : "times")) }
        if key.kind == .country, let f = page.facts {
            if !f.regions.isEmpty {
                let n = f.regions.filter { MarkStore.shared.state($0.key).stamped }.count
                items.append(("\(n)", "of \(f.regions.count) regions"))
            }
            let cc = page.country + "/"
            let towns = MarkStore.shared.marks.filter { $0.key.kind == .town && $0.value.stamped && $0.key.id.hasPrefix(cc) }.count
            items.append(("\(towns)", towns == 1 ? "city" : "cities"))
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your record").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            HStack(alignment: .top, spacing: 24) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    VStack(spacing: 0) {
                        Text(it.0).font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Palette.ink).contentTransition(.numericText())
                        Text(it.1).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// FOR YOU (16.4.9): the visa line first, then each government's advice with who says it and when it was checked
    private func forYou(_ f: PlacePageState.Facts) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("For you").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            ForEach(f.visa, id: \.self) { v in
                let parts = v.components(separatedBy: "\n")
                VStack(alignment: .leading, spacing: 2) {
                    Text(parts[0]).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    if parts.count > 1 { Text(parts[1]).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)) }
                }
            }
            ForEach(Array(f.advice.enumerated()), id: \.offset) { _, a in
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.text).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    Text(a.when.isEmpty ? a.who : "\(a.who) · checked \(a.when)").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// FACTS (16.4.5): two columns, each value 17 pt semibold over its label 15 pt black 50%, a thin line between rows
    private func factsGrid(_ rows: [(String, String)]) -> some View {
        let pairs = stride(from: 0, to: rows.count, by: 2).map { (rows[$0], $0 + 1 < rows.count ? rows[$0 + 1] : nil) }
        return VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { n, pair in
                if n > 0 { Rectangle().fill(Palette.ink.opacity(0.5)).frame(height: 0.5) }
                HStack(alignment: .top, spacing: 16) {
                    fact(pair.0)
                    if let b = pair.1 { fact(b) } else { Color.clear.frame(maxWidth: .infinity) }
                }
                .padding(.vertical, 12)
            }
        }
    }
    private func fact(_ f: (String, String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(f.1).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            Text(f.0).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// THE GROUND (16.3): the flag's colours, each the nearest of the palette's, strong at the top and gentle further
    /// down, one layer behind the whole top
    private func groundView(L: Layout) -> some View {
        let c = ground.isEmpty ? [Palette.cream] : ground
        return LinearGradient(stops: [
            .init(color: c[0].opacity(0.85), location: 0),
            .init(color: (c.count > 1 ? c[1] : c[0]).opacity(0.45), location: 0.35),
            .init(color: (c.count > 2 ? c[2] : c[0]).opacity(0.12), location: 0.7),
            .init(color: Palette.white.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: L.H * 0.75)
        .allowsHitTesting(false)
    }

    /// a flag's colours: drawn small, each pixel the nearest of the twelve, the commonest first (white and ink left
    /// out where others exist, so the ground is the flag's own colour)
    static func colours(_ id: String) -> [Color] {
        let entries = Array(Palette.named)
        let names: [(Color, SIMD3<Double>)] = entries.map { (Color(red: $0.value.x, green: $0.value.y, blue: $0.value.z), $0.value) }
        guard let ui = Flags.wideImage(id), let cg = ui.cgImage else { return [] }
        let w = 16, h = 12
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var count = [Int](repeating: 0, count: names.count)
        for i in 0 ..< w * h {
            let c = SIMD3(Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2])) / 255
            var best = 0, bd = Double.infinity
            for (n, v) in names.enumerated() { let d = simd_length_squared(v.1 - c); if d < bd { bd = d; best = n } }
            count[best] += 1
        }
        let order = count.indices.filter { count[$0] > 0 }.sorted { count[$0] > count[$1] }
        let plain: Set<String> = ["white", "ink", "cream"]
        let coloured = order.filter { !plain.contains(entries[$0].key) }
        let use = coloured.isEmpty ? order : coloured
        return use.prefix(3).map { names[$0].0 }
    }
}

/// one of a page's "What is in it" lists (16.4.8)
private struct InsideList: View {
    let title: String
    let all: [PlacePageState.Inside]
    let country: String
    let countryName: String
    let map: MapController
    @State private var query = ""
    @State private var shown = 5

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let rows = q.isEmpty ? all : all.filter { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) }
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            HStack(spacing: 8) {
                Icon5(key: "search", ink: Palette.ink, size: 22)
                TextField("Search \(title.lowercased())", text: $query).font(.body)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 14).frame(height: 44)
            .glassEffect(.clear, in: .capsule)
            ForEach(rows.prefix(shown), id: \.self) { r in row(r) }
            if rows.count > shown {
                Button { withAnimation(Motion.quick) { shown += 10 } } label: {
                    Text("Show more").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ r: PlacePageState.Inside) -> some View {
        let s = MarkStore.shared.state(r.key)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(.body).foregroundStyle(Palette.ink).lineLimit(1)
                if !r.line.isEmpty { Text(r.line).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Button {
                Task {
                    if r.key.kind == .town {
                        // a town with its region chain and its country (A16.7, the unstamp rule)
                        if s.stamped { Feel.lift(); await TownStamps.unstamp(r.key, name: r.name, cc: country) }
                        else {
                            Feel.stamp()
                            await TownStamps.stamp(r.key, name: r.name, cc: country, source: .hand,
                                                   place: map.world?.placeIndex[country], at: r.at)
                        }
                    } else if s.stamped { Feel.lift(); await MarkStore.shared.unstamp(r.key, name: r.name) }
                    else { Feel.stamp(); await MarkStore.shared.stamp(r.key, name: r.name, cc: country) }
                }
            } label: {
                // the plus; stamped, the card's own "Stamped" capsule (no tick, 0.8.4; no lone lime circle, 30 Oct 21:42)
                if s.stamped {
                    Text("Stamped").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).frame(height: 44)
                        .glassEffect(.clear.tint(Palette.lime), in: .capsule)
                } else {
                    Icon5(key: "plus", ink: Palette.ink, size: 22)
                        .frame(width: 44, height: 44)
                        .glassEffect(.clear, in: .circle)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(height: 52)
        .contentShape(Rectangle())
        .onTapGesture {
            // its page (pushed pages wait: this one turns into it)
            let page = PlacePageState.shared
            page.replace(r.key, name: r.name, what: r.key.kind == .town ? "Town in \(r.line), \(countryName)" : "\(r.line.components(separatedBy: " · ").first ?? "Region") of \(countryName)",
                         country: country, code: r.code)
        }
    }
}
