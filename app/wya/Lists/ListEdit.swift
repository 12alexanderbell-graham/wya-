import SwiftUI

/// ADDING TO A LIST, IN THE LIST: a field at the list's foot. As you type, the countries, regions and towns of that
/// name come under it, each with its flag and what it is; one tapped goes in with its country (its flag, its tick).
/// Return with nothing picked puts in what was typed, as it is (a dish, a thing, a link). The best known sights are
/// found too.
struct ListAddRow: View {
    let listID: String
    @State private var text = ""
    @FocusState private var typing: Bool

    struct Found: Hashable { let name: String; let cc: String; let line: String }

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
                    Group {
                        if let fl = Flags.row(f.cc) { fl.resizable().interpolation(.high) } else { Color.clear }
                    }
                    .frame(width: 44, height: 33).frame(width: 44, height: 44)
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
        .onAppear { TownIndex.shared.load(); RegionIndex.shared.load(); ThingIndex.shared.load() }
    }

    /// what is typed, found: countries first (the start of their name), then regions, then towns
    private var found: [Found] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let fq = fold(q)
        var out: [Found] = []
        let starts = CountryEntity.all.filter { fold($0.name).hasPrefix(fq) }
        let inside = CountryEntity.all.filter { !fold($0.name).hasPrefix(fq) && fold($0.name).contains(fq) }
        for c in (starts + inside).prefix(2) { out.append(Found(name: c.name, cc: c.id, line: "Country")) }
        _ = ThingIndex.shared.ready
        for h in ThingIndex.shared.hits(q, open: nil, limit: 3, near: false).filter({ $0.fame >= 2 }).prefix(2) {
            let cc = h.file.lowercased()
            out.append(Found(name: h.name, cc: cc, line: CountryEntity(id: cc).name))
        }
        _ = RegionIndex.shared.ready; _ = TownIndex.shared.ready
        // (towns before regions: Tbilisi the city before Tbilisi the region; both shown, each saying what it is)
        for t in TownIndex.shared.hits(q, open: nil, limit: 3) {
            let cc = t.file.lowercased()
            out.append(Found(name: t.name, cc: cc, line: CountryEntity(id: cc).name))
        }
        for r in RegionIndex.shared.hits(q, limit: 2) {
            let cc = r.place.lowercased()
            out.append(Found(name: r.name, cc: cc, line: "Region of " + CountryEntity(id: cc).name))
        }
        var seen = Set<String>()
        return Array(out.filter { seen.insert($0.name.lowercased() + "|" + $0.cc + "|" + $0.line).inserted }.prefix(5))
    }

    private func add(_ f: Found) {
        Feel.tap()
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
}
