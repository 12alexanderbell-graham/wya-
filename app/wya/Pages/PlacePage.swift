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
    struct Facts { var prose = ""; var rows: [(String, String)] = [] }
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
    var isOpen: Bool { key != nil }

    func open(_ key: PlaceKey, name: String, what: String = "", country: String, from origin: CGRect) {
        guard self.key == nil else { return }
        self.key = key; self.name = name; self.what = what; self.country = country.lowercased()
        self.origin = origin; facts = nil; drag = 0; p = 0
        Feel.tap()
        DispatchQueue.main.async { [weak self] in
            withAnimation(Motion.reduce ? Motion.tight : .spring(response: 0.5, dampingFraction: 1)) { self?.p = 1 }
        }
        if key.kind == .country { Task { await loadCountry(key.id.lowercased()) } }
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
        facts = out
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

    var body: some View {
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
        ScrollView {
            VStack(spacing: 32) {
                top(key, L: L)
                marking(key)
                if let f = page.facts, !f.prose.isEmpty {
                    Text(f.prose).font(.body).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let f = page.facts, !f.rows.isEmpty { factsGrid(f.rows) }
                Color.clear.frame(height: 140)
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) { groundView(L: L) }
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
