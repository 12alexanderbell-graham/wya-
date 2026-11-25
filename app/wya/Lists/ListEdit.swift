import SwiftUI

/// ADDING TO A LIST, IN THE LIST: a field at the list's foot. As you type, the countries, regions and towns of that
/// name come under it, each with its flag and what it is; one tapped goes in with its country (its flag, its tick).
/// Return with nothing picked puts in what was typed, as it is (a dish, a thing, a link). The best known sights are
/// found too.
struct ListAddRow: View {
    let listID: String
    @State private var text = ""
    @FocusState private var typing: Bool

    struct Found: Hashable {
        let name: String; let cc: String; let line: String; var ref: String? = nil
        /// A READY-MADE SET (17 Sep spec: all of a continent, all regions of a place): "cont:Europe" or
        /// "regions:it", every place of it going in at once; its picture is its count on glass
        var set: String? = nil
        var count = 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: $text, prompt: Text("Add").foregroundStyle(Palette.ink.opacity(0.5)))
                .font(.body).foregroundStyle(Palette.ink)
                .focused($typing)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .onSubmit(submit)
                .frame(height: 48)
                .padding(.leading, 56)
            ForEach(found, id: \.self) { f in
                HStack(spacing: 12) {
                    if f.set != nil {
                        Text("\(f.count)").font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Palette.ink.opacity(0.5))
                            .frame(width: 44, height: 44)
                            .glassEffect(.clear, in: .rect(cornerRadius: 10))
                    } else if let r = f.ref, let l = ListsStore.shared.book.lists.first(where: { $0.id == r }) {
                        Color.clear.frame(width: 44, height: 44)
                            .overlay { listCoverOrGlass(l) }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        // (its flag's square crop in the rows' one picture shape, 25 Nov)
                        Group {
                            if let fl = Flags.square(f.cc) { fl.resizable().interpolation(.high).scaledToFill() } else { Color.clear }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.name).font(.body).foregroundStyle(Palette.ink).lineLimit(1)
                        Text(f.line).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
                .onTapGesture { add(f) }
                .accessibilityAddTraits(.isButton)
            }
        }
        .onAppear { TownIndex.shared.load(); RegionIndex.shared.load(); ThingIndex.shared.load(); CollectionStore.shared.load() }
    }

    /// what is typed, found: countries first (the start of their name), then regions, then towns
    private var found: [Found] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let fq = fold(q)
        var out: [Found] = []
        // YOUR OTHER LISTS of that name first (a list inside a list), never one that would hold this one
        let book = ListsStore.shared.book
        if let me = book.lists.first(where: { $0.id == listID }) {
            for l in book.lists where !l.wish && l.id != listID && fold(l.name).contains(fq) {
                let item = ListItem.mine(.list, l.id)
                guard !book.wouldLoop(me, item), !me.items.contains(where: { $0.ref == l.id }) else { continue }
                out.append(Found(name: l.name, cc: "", line: "List", ref: l.id))
                if out.count >= 2 { break }
            }
        }
        // (only places the map has: the phone's region list holds "European Union", "Eurozone" and "United Nations",
        // which went in as countries with no flag, 25 Nov)
        let onMap = { (c: CountryEntity) in AIContext.map?.world.map { $0.placeIndex[c.id] != nil } ?? true }
        let starts = CountryEntity.all.filter { fold($0.name).hasPrefix(fq) && onMap($0) }
        let inside = CountryEntity.all.filter { !fold($0.name).hasPrefix(fq) && fold($0.name).contains(fq) && onMap($0) }
        for c in (starts + inside).prefix(2) { out.append(Found(name: c.name, cc: c.id, line: "Country")) }
        // READY-MADE SETS: a continent named, all its countries; a country named in full, all its regions
        if fq.count >= 3, let w = AIContext.map?.world {
            for k in MapController.continents where fold(k).hasPrefix(fq) {
                let n = Self.continentCountries(k, w).count
                if n > 0 { out.append(Found(name: "All of " + k, cc: "", line: "\(n) countries", set: "cont:" + k, count: n)) }
            }
        }
        _ = RegionIndex.shared.ready
        if let c = starts.first(where: { fold($0.name) == fq }) {
            let n = RegionIndex.shared.firstLevel(c.id).count
            if n > 1 { out.append(Found(name: "All regions of " + c.name, cc: c.id, line: "\(n) regions", set: "regions:" + c.id, count: n)) }
        }
        // THE PLACE BEFORE WHAT IS IN IT (17 Sep spec: country, region, place first, then deeper; 25 Nov: typing the
        // start of a city found its sights and never the city): a big town right after the countries; smaller towns
        // after the sights, as before
        _ = TownIndex.shared.ready
        let towns = TownIndex.shared.hits(q, open: nil, limit: 4)
        // (only by size: a village named as typed stood before the city)
        let big = towns.filter { $0.people >= 100_000 }.sorted { $0.people > $1.people }
        for t in big.prefix(2) {
            let cc = t.file.lowercased()
            out.append(Found(name: t.name, cc: cc, line: PlacePageState.countryName(cc)))
        }
        _ = ThingIndex.shared.ready
        let fs = q.townFolded
        let sets: [(Found, Bool)] = CollectionStore.shared.find(q, first: nil, limit: 3).compactMap { f in
            let n = f.item.name.townFolded
            guard n == fs || fs.count >= 4 || f.item.fame >= 3 else { return nil }
            let ccs = f.item.ccs.filter { !$0.isEmpty }
            let line = ccs.count > 1 ? ccs.prefix(2).map { PlacePageState.countryName($0) }.joined(separator: ", ") + (ccs.count > 2 ? " and \(ccs.count - 2) more" : "")
                : ccs.first.map { PlacePageState.countryName($0) } ?? ""
            return (Found(name: f.item.name, cc: f.item.cc, line: line), n == fs)
        }
        out += sets.filter(\.1).map(\.0)
        for h in ThingIndex.shared.hits(q, open: nil, limit: 3, near: false).filter({ $0.fame >= 2 }).prefix(2) {
            let cc = h.file.lowercased()
            out.append(Found(name: h.name, cc: cc, line: PlacePageState.countryName(cc)))
        }
        out += sets.filter { !$0.1 }.prefix(2).map(\.0)
        _ = RegionIndex.shared.ready; _ = TownIndex.shared.ready
        // (towns before regions: Tbilisi the city before Tbilisi the region; both shown, each saying what it is)
        for t in towns.filter({ t in !big.contains(t) }).prefix(3) {
            let cc = t.file.lowercased()
            out.append(Found(name: t.name, cc: cc, line: PlacePageState.countryName(cc)))
        }
        for r in RegionIndex.shared.hits(q, limit: 2) {
            let cc = r.place.lowercased()
            out.append(Found(name: r.name, cc: cc, line: "Region of " + PlacePageState.countryName(cc)))
        }
        var seen = Set<String>()
        return Array(out.filter { seen.insert($0.name.lowercased() + "|" + $0.cc + "|" + $0.line).inserted }.prefix(5))
    }

    /// a continent's countries (not its territories), A to Z
    static func continentCountries(_ k: String, _ w: World) -> [World.Place] {
        w.places.filter { $0.cont == k && $0.k == "country" && !$0.junk }
            .sorted { $0.n.localizedStandardCompare($1.n) == .orderedAscending }
    }

    private func add(_ f: Found) {
        Feel.tap()
        if let r = f.ref { put(ListItem.mine(.list, r)); return }
        if let set = f.set {
            // every place of the set, but none the list has already (by name and country)
            var items: [ListItem] = []
            if set.hasPrefix("cont:"), let w = AIContext.map?.world {
                items = Self.continentCountries(String(set.dropFirst(5)), w).map { ListItem(n: $0.n, cc: $0.id) }
            } else if set.hasPrefix("regions:") {
                let cc = String(set.dropFirst(8))
                items = RegionIndex.shared.firstLevel(cc).map { ListItem(n: $0.name, cc: cc) }
            }
            withAnimation(Motion.quick) {
                ListsStore.shared.change { b in
                    guard let i = b.lists.firstIndex(where: { $0.id == listID }) else { return }
                    let have = Set(b.lists[i].items.map { $0.n.lowercased() + "|" + ($0.cc ?? "") })
                    b.lists[i].items += items.filter { !have.contains($0.n.lowercased() + "|" + ($0.cc ?? "")) }
                }
            }
            text = ""
            typing = true
            return
        }
        put(ListItem(n: f.name, cc: f.cc))
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        // the place of exactly that name when there is one, else the words as they are
        if let f = found.first(where: { $0.name.caseInsensitiveCompare(t) == .orderedSame }) { add(f); return }
        Feel.tap()
        put(t.lowercased().hasPrefix("http") ? ListItem.thing(t, link: t) : ListItem.thing(t))
    }

    private func put(_ item: ListItem) {
        withAnimation(Motion.quick) {
            ListsStore.shared.change { b in
                if let i = b.lists.firstIndex(where: { $0.id == listID }) { b.lists[i].items.append(item) }
            }
        }
        text = ""
        typing = true
    }
}

/// LISTS TICK AS YOU STAMP: of a list's places that are a country or one of our towns, how many you have stamped. A
/// list of other things (dishes, links) has none to count.
@MainActor
enum ListTicks {
    static func count(_ items: [ListItem]) -> (been: Int, of: Int) {
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        var been = 0, of = 0
        for it in items where it.k == .place {
            guard let cc = it.cc?.lowercased(), !cc.isEmpty else { continue }
            if fold(CountryEntity(id: cc).name) == fold(it.n) {
                of += 1
                if MarkStore.shared.state(.country(cc)).stamped { been += 1 }
            } else if let t = TownIndex.shared.named(it.n, in: cc), t.people >= 1_000 {
                of += 1
                if MarkStore.shared.state(PlaceKey(.town, t.id)).stamped { been += 1 }
            }
        }
        return (been, of)
    }
    /// one place of a list: true when you have stamped it, false when not yet, nil when it is not a place we count
    static func been(name: String, cc: String?) -> Bool? {
        guard let cc = cc?.lowercased(), !cc.isEmpty else { return nil }
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        if fold(CountryEntity(id: cc).name) == fold(name) { return MarkStore.shared.state(.country(cc)).stamped }
        if let t = TownIndex.shared.named(name, in: cc), t.people >= 1_000 { return MarkStore.shared.state(PlaceKey(.town, t.id)).stamped }
        return nil
    }
}
