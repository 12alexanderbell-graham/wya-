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
        /// Highlights (16.4.6): the country's World Heritage sites for now (the server's heritage list)
        var highlights: [Highlight] = []
    }
    struct Highlight: Hashable { let id: String; let name: String; let line: String; let photo: String? }
    /// the server's World Heritage list, read once
    private static var heritage: [String: [String: Any]]?
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
    /// the test driver's scroll to the end, and its opening of Sources (checks)
    var toEnd = 0
    var sourcesTest = 0
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
        if let g = j["guide"] as? [String: Any], let intro = g["intro"] as? String { out.prose = Self.cut(Self.plain(intro), 620) }
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
        if let v = s("timezone") {
            // an IANA zone ("Europe/Rome") as its offset now, as the others are written ("UTC+01:00")
            let zones = v.components(separatedBy: ", ").map { z -> String in
                guard z.contains("/"), let tz = TimeZone(identifier: z) else { return z }
                let sec = tz.secondsFromGMT(), h = abs(sec) / 3600, m = abs(sec) % 3600 / 60
                return String(format: "UTC%@%02d:%02d", sec < 0 ? "-" : "+", h, m)
            }
            out.rows.append(("Time zones", zones.joined(separator: ", ")))
        }
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
        // highlights: the country's World Heritage sites (the list the server's country file names)
        if let ids = j["heritage"] as? [String], !ids.isEmpty {
            if Self.heritage == nil, case .ok(let hd) = await Servers.data.file("heritage.json"),
               let all = try? JSONSerialization.jsonObject(with: hd) as? [String: [String: Any]] { Self.heritage = all }
            out.highlights = ids.compactMap { q in
                guard let h = Self.heritage?[q], let n = h["n"] as? String else { return nil }
                let year = h["year"] as? String
                return Highlight(id: q, name: n, line: year.map { "World Heritage since \($0)" } ?? "World Heritage",
                                 photo: (h["img"] as? [String])?.first)
            }
        }
        // (a page opened since this one began loading keeps its own facts)
        guard key?.id.lowercased() == cc else { return }
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

    /// the source's HTML entities as the characters they stand for
    static func plain(_ s: String) -> String {
        var t = s
        for (e, c) in [("&quot;", "\""), ("&amp;", "&"), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: e, with: c)
        }
        return t
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
                if let f = page.facts, !f.highlights.isEmpty { highlights(f.highlights, L: L).id("highlights") }
                if let f = page.facts, !f.regions.isEmpty { insideList("Regions", f.regions) }
                if let f = page.facts, !f.cities.isEmpty { insideList("Cities", f.cities) }
                if let f = page.facts, !f.visa.isEmpty || !f.advice.isEmpty { forYou(f) }
                if MarkStore.shared.state(key).stamped { record(key) }
                if page.facts != nil { SourcesRow(facts: page.facts!, kind: key.kind) }
                Color.clear.frame(height: 140).id("end")
            }
            .padding(.horizontal, 16)
            // the ground scrolls with the page (one layer behind the whole scroll, 16.3)
            .background(alignment: .top) { groundView(L: L) }
        }
        .scrollIndicators(.hidden)
        // the one blur under the head, only once words scroll under it (16.3)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onChange(of: page.toEnd) { _, n in reader.scrollTo(n == 1 ? "highlights" : "end", anchor: .top) }
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
                    .glassEffect(s.stamped ? PageGlass.on.tint(Palette.lime) : PageGlass.on, in: .capsule)
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
                    .glassEffect(s.wished ? PageGlass.on.tint(Palette.blue) : PageGlass.on, in: .capsule)
            }
        }
        .buttonStyle(.plain)
    }

    /// HIGHLIGHTS (16.4.6): a sideways row, one card wide with the next peeking 24 pt; the photo fills the card's top
    /// (square corners, 16:10; real photos from Wikimedia Commons, credited in Sources), its name 17 pt semibold and one
    /// line 15 pt black 50% under it; the plus at the photo's top right wishes it
    private func highlights(_ all: [PlacePageState.Highlight], L: Layout) -> some View {
        let w = L.W - 32 - 24
        return VStack(alignment: .leading, spacing: 12) {
            Text("Highlights").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(all, id: \.self) { h in highlightCard(h, w: w) }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
    private func highlightCard(_ h: PlacePageState.Highlight, w: CGFloat) -> some View {
        let key = PlaceKey(.thing, h.id)
        let st = MarkStore.shared.state(key)
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let f = h.photo, let u = Self.commons(f, width: 800) {
                        AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Palette.cream }
                    } else { Palette.cream }
                }
                .frame(width: w, height: w * 10 / 16)
                .clipped()
                Button {
                    Feel.tap()
                    Task {
                        if st.wished { await MarkStore.shared.unwish(key, name: h.name) }
                        else { await MarkStore.shared.wish(key, name: h.name, cc: page.country) }
                    }
                } label: {
                    Icon5(key: "plus", ink: Palette.ink, size: 22)
                        .frame(width: 44, height: 44)
                        .glassEffect(st.wished ? PageGlass.on.tint(Palette.blue) : PageGlass.on, in: .circle)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            Text(h.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            Text(h.line).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
        }
        .frame(width: w, alignment: .leading)
    }
    /// a Commons file at a width (Special:FilePath)
    static func commons(_ file: String, width: Int) -> URL? {
        let name = file.replacingOccurrences(of: " ", with: "_")
        guard let e = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/\(e)?width=\(width)")
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
        let top = c[0].opacity(0.85)
        // the ground goes on above the page's top in its strongest colour, so pulling the page down past its top shows
        // more of the same ground, never white (31 Oct 01:22: "There's no need for that to happen in Swift")
        return VStack(spacing: 0) {
            Rectangle().fill(top).frame(height: L.H)
            LinearGradient(stops: [
                .init(color: top, location: 0),
                .init(color: (c.count > 1 ? c[1] : c[0]).opacity(0.45), location: 0.35),
                .init(color: (c.count > 2 ? c[2] : c[0]).opacity(0.12), location: 0.7),
                .init(color: Palette.white.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: L.H * 0.75)
        }
        .offset(y: -L.H)
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
            .glassEffect(PageGlass.on, in: .capsule)
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
                        .glassEffect(PageGlass.on.tint(Palette.lime), in: .capsule)
                } else {
                    Icon5(key: "plus", ink: Palette.ink, size: 22)
                        .frame(width: 44, height: 44)
                        .glassEffect(PageGlass.on, in: .circle)
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

/// SOURCES (16.4.11, 16.6): a row "Sources"; open, the sources the page drew on: Wikivoyage's text (CC BY-SA),
/// Wikidata's and GeoNames' facts, each photo with its author and licence from the server's Commons credits, and the
/// governments whose advice is shown. (The visa rules' and the climate figures' own sources are not recorded in the
/// server's data yet, so they are not named here.) The page's own sheet (16.6, pulled up from the capsule) is not
/// built: the row opens in place for now
private struct SourcesRow: View {
    let facts: PlacePageState.Facts
    let kind: PlaceKey.Kind
    @State private var open = false
    @State private var credits: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Motion.quick) { open.toggle() }
                Feel.tap()
                if open && credits.isEmpty { Task { await loadCredits() } }
            } label: {
                Text("Sources").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines, id: \.self) { l in
                        Text(l).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: PlacePageState.shared.sourcesTest) { _, _ in
            open = true
            if credits.isEmpty { Task { await loadCredits() } }
        }
    }

    private var lines: [String] {
        var out: [String] = []
        if kind == .country, !facts.prose.isEmpty { out.append("Text: Wikivoyage, CC BY-SA") }
        else if !facts.prose.isEmpty { out.append("Text: Wikidata") }
        if !facts.rows.isEmpty { out.append(kind == .town ? "Facts: GeoNames, CC BY 4.0" : "Facts: Wikidata") }
        for h in facts.highlights {
            guard let f = h.photo else { continue }
            out.append("Photo of \(h.name): " + (credits[f] ?? f) + ", Wikimedia Commons")
        }
        for a in facts.advice { out.append("Advice: the \(a.who) government") }
        return out
    }

    /// each photo's author and licence from the server's credits (256 shards by the FNV-1a of the file name)
    private func loadCredits() async {
        var out: [String: String] = [:]
        var shards: [String: [String: Any]] = [:]
        for h in facts.highlights {
            guard let f = h.photo else { continue }
            let sh = Self.shard(f)
            if shards[sh] == nil, case .ok(let d) = await Servers.data.file("credits/\(sh).json"),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { shards[sh] = j }
            if let c = shards[sh]?[f] as? [String: Any] {
                out[f] = [c["by"] as? String, c["lic"] as? String].compactMap { $0 }.joined(separator: ", ")
            }
        }
        // the rest (the World Heritage photos are not in the server's credits) from Commons itself: each file's author and
        // licence short name, in one request
        let missing = facts.highlights.compactMap(\.photo).filter { out[$0] == nil }
        for start in stride(from: 0, to: missing.count, by: 50) {
            let batch = Array(missing[start ..< min(missing.count, start + 50)])
            var c = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
            c.queryItems = [.init(name: "action", value: "query"), .init(name: "format", value: "json"),
                            .init(name: "prop", value: "imageinfo"), .init(name: "iiprop", value: "extmetadata"),
                            .init(name: "titles", value: batch.map { "File:" + $0 }.joined(separator: "|"))]
            guard let u = c.url, let (d, _) = try? await URLSession.shared.data(from: u),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let pages = (j["query"] as? [String: Any])?["pages"] as? [String: Any] else { continue }
            for case let pg as [String: Any] in pages.values {
                guard let title = pg["title"] as? String,
                      let meta = ((pg["imageinfo"] as? [[String: Any]])?.first?["extmetadata"]) as? [String: Any] else { continue }
                func v(_ k: String) -> String? { ((meta[k] as? [String: Any])?["value"] as? String).map(Self.text) }
                let file = String(title.dropFirst(5))
                let key = batch.first { $0.replacingOccurrences(of: "_", with: " ") == file } ?? file
                out[key] = [v("Artist"), v("LicenseShortName")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
        }
        #if DEBUG
        NSLog("wya credits %d of %d, e.g. %@", out.count, facts.highlights.count, out.first.map { "\($0.key): \($0.value)" } ?? "-")
        #endif
        credits = out
    }
    /// a Commons field's HTML as plain words
    static func text(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// FNV-1a of the file name's UTF-8 bytes, its low byte in hex (the server's shard_of)
    static func shard(_ name: String) -> String {
        var h: UInt32 = 0x811c9dc5
        for b in name.utf8 { h ^= UInt32(b); h = h &* 0x01000193 }
        return String(format: "%02x", h & 0xff)
    }
}

/// ONE GLASS ON A PAGE (16.3, Part 0.7; 31 Oct 01:22: "either use frosted glass consistently or not"): everything glass
/// on a place's page (the head's circles and search the whole time the page is up, the marking block, the lists'
/// fields and buttons) is the logically frosted glass, and never changes kind while it moves
enum PageGlass {
    /// a page's own glass
    static let on: SwiftUI.Glass = .regular
    /// the head's glass: frosted while a page is up, clear on the map
    @MainActor static var head: SwiftUI.Glass { PlacePageState.shared.isOpen ? .regular : .clear }
}
