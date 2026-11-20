import SwiftUI

/// UNDER A PLAN'S DAYS: its Ideas and its Suggestions. IDEAS (audit D672-D688:): things you might do on the trip, on
/// no day yet. Typed in, or added from Suggestions. Its plus puts it on a day; its place opens it on the map; held,
/// it can be taken out. SUGGESTIONS: when the section comes on screen, the AI offers up to three things the plan
/// doesn't have, near where it goes, each with why it suits you. A plus puts one in Ideas. With the AI off it is not
/// there at all.
struct PlanIdeasSection: View {
    let p: Plan
    let dayName: (Int) -> String
    let change: ((inout Plan) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ideas").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                .padding(.top, 28).padding(.bottom, 4)
            ForEach(p.ideas) { it in idea(it) }
            PlanAddRow(day: -1) { at, what in
                change { $0.ideas.append(PlanItem(at: at, what: what, place: "")) }
            }
            if MapSettingsStore.shared.value.ai, p.count + p.ideas.count > 0 {
                PlanSuggestions(p: p, change: change)
            }
        }
    }

    private func idea(_ it: PlanItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(it.what).font(.body).foregroundStyle(Palette.ink).lineLimit(2)
                if !it.place.isEmpty, it.place.lowercased() != it.what.lowercased() {
                    Text(it.place).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture { PlanPlaces.open(it.place, cc: it.cc) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens it on the map")
                }
            }
            Spacer(minLength: 0)
            // put on a day: the plan's days, by name
            Menu {
                ForEach(Array(p.days.indices), id: \.self) { i in
                    Button(dayName(i)) {
                        Feel.notch()
                        withAnimation(Motion.quick) {
                            change { pl in
                                guard let k = pl.ideas.firstIndex(where: { $0.id == it.id }), pl.days.indices.contains(i) else { return }
                                pl.days[i].items.append(pl.ideas.remove(at: k))
                                pl.sortDay(i)
                            }
                        }
                    }
                }
            } label: {
                Icon5(key: "plus", ink: Palette.ink, size: 22)
                    .frame(width: 44, height: 44)
                    .glassEffect(PageGlass.control, in: .circle)
            }
            .accessibilityLabel("Put on a day")
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Take out", role: .destructive) {
                withAnimation(Motion.quick) { change { $0.ideas.removeAll { $0.id == it.id } } }
            }
        }
    }
}

/// the plan's Suggestions, asked for once the section is on screen; kept for this plan until it changes
private struct PlanSuggestions: View {
    let p: Plan
    let change: ((inout Plan) -> Void) -> Void
    @State private var picks: [AIService.PlanPick] = []
    @State private var asked: String?

    /// what was suggested for a plan as it was (its id and what is in it), for this run of the app
    @MainActor static var kept: [String: [AIService.PlanPick]] = [:]

    var body: some View {
        // (only what isn't already in the plan or its ideas)
        let have = Set((p.days.flatMap(\.items) + p.ideas).map { $0.what.lowercased() })
        let shown = picks.filter { !have.contains($0.what.lowercased()) }
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 0)
            if !shown.isEmpty {
                Text("Suggestions").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    .padding(.top, 28)
                Text("Based on your passport and history").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
            }
            ForEach(shown, id: \.self) { pk in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pk.what).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                        Text(pk.place.isEmpty ? pk.why : "\(pk.place) · \(pk.why)").font(.subheadline)
                            .foregroundStyle(Palette.ink.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Feel.tap()
                        withAnimation(Motion.quick) {
                            change { $0.ideas.append(PlanItem(at: nil, what: pk.what, place: pk.place, cc: pk.cc.isEmpty ? nil : pk.cc.lowercased())) }
                        }
                    } label: {
                        Icon5(key: "plus", ink: Palette.ink, size: 22)
                            .frame(width: 44, height: 44)
                            .glassEffect(PageGlass.control, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(pk.what) to Ideas")
                }
                .padding(.vertical, 6)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
                .onTapGesture { if !pk.place.isEmpty { PlanPlaces.open(pk.place, cc: pk.cc) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: Bool.self) { g in
            let f = g.frame(in: .global)
            return f.minY < UIScreen.main.bounds.height && f.maxY > 0
        } action: { on in if on { load() } }
    }

    /// the plan in words: its name, dates and each day's things
    private var words: String {
        var out = "\"\(p.name)\"" + (p.start.isEmpty ? " (no dates yet)" : " (\(p.start) to \(p.end))") + "."
        for (i, d) in p.days.enumerated() where !d.items.isEmpty {
            out += " Day \(i + 1): " + d.items.map { $0.what + ($0.place.isEmpty ? "" : " (\($0.place))") }.joined(separator: ", ") + "."
        }
        if !p.ideas.isEmpty { out += " Ideas, no day yet: " + p.ideas.map(\.what).joined(separator: ", ") + "." }
        return out
    }

    private func load() {
        // asked once per plan as it is: the plan's id and its first thing (adding one of the picks does not ask again)
        let key = p.id + "|" + (p.days.flatMap(\.items).first?.what ?? "")
        guard asked != key else { return }
        asked = key
        if let k = Self.kept[key] { picks = k; return }
        let w = words
        Task {
            if case .success(let ps) = await AIService.planSuggestions(w, context: AIContext.current()) {
                Self.kept[key] = ps
                withAnimation(Motion.chrome) { picks = ps }
            }
        }
    }
}


/// SUGGESTIONS ON ONE OF YOUR LISTS: up to three more of what the list is, each with why for you; a plus puts it in the
/// list (a place with its country, for its flag). Asked once the section is on screen; with the AI off, not there.
struct ListSuggestions: View {
    /// a pick that is a known sight of its country (its name exactly): its Wikidata id, for its photo
    @MainActor static func sight(_ pk: AIService.PlanPick) -> String? { sight(pk.what, pk.cc) }
    /// a name that is a known sight of that country (exactly): its Wikidata id
    @MainActor static func sight(_ name: String, _ cc: String) -> String? {
        guard ThingIndex.shared.ready, !cc.isEmpty else { return nil }
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        return ThingIndex.shared.hits(name, open: cc.lowercased(), limit: 6, near: false)
            .first { $0.file.lowercased() == cc.lowercased() && fold($0.name) == fold(name) }?.id
    }
    let listID: String
    let name: String
    let things: [ListsThing]
    @State private var picks: [AIService.PlanPick] = []
    @State private var asked: String?
    @MainActor static var kept: [String: [AIService.PlanPick]] = [:]

    var body: some View {
        let have = Set(things.map { $0.name.lowercased() })
        let shown = picks.filter { !have.contains($0.what.lowercased()) }
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 0)
            if !shown.isEmpty {
                Text("Suggestions").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                    .padding(.top, 28)
                Text("Based on your passport and history").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
            }
            ForEach(shown, id: \.self) { pk in
                HStack(spacing: 12) {
                    if let wd = Self.sight(pk), SetPlaceThumb.file(own: "", thing: wd) != nil {
                        SetPlaceThumb(own: "", thing: wd, cc: pk.cc)
                    } else {
                        Group {
                            if let f = Flags.row(pk.cc.lowercased()) { f.resizable().interpolation(.high) } else { Color.clear }
                        }
                        .frame(width: 44, height: 33)
                        .frame(width: 44, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pk.what).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                        Text(pk.place.isEmpty ? pk.why : "\(pk.place) · \(pk.why)").font(.subheadline)
                            .foregroundStyle(Palette.ink.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Feel.tap()
                        let item = ListItem(n: pk.what, cc: pk.cc.isEmpty ? nil : pk.cc.lowercased(),
                                            note: pk.place.isEmpty ? "" : pk.place)
                        withAnimation(Motion.quick) {
                            ListsStore.shared.change { b in
                                if let i = b.lists.firstIndex(where: { $0.id == listID }) { b.lists[i].items.append(item) }
                            }
                        }
                    } label: {
                        Icon5(key: "plus", ink: Palette.ink, size: 22)
                            .frame(width: 44, height: 44)
                            .glassEffect(PageGlass.control, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(pk.what) to \(name)")
                }
                .padding(.vertical, 6)
                .frame(minHeight: 56)
                // (its country's sights, for its photo)
                .onAppear { if !pk.cc.isEmpty { ThingStore.shared.load(pk.cc.lowercased()); ThingIndex.shared.load() } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: Bool.self) { g in
            let f = g.frame(in: .global)
            return f.minY < UIScreen.main.bounds.height && f.maxY > 0
        } action: { on in if on { load() } }
    }

    private func load() {
        // asked once per list as it first was (adding a pick does not ask again)
        let key = listID + "|" + (things.first?.name ?? "")
        guard asked != key, !things.isEmpty else { return }
        asked = key
        if let k = Self.kept[key] { picks = k; return }
        let words = "\"\(name)\": " + things.prefix(40).map { $0.name }.joined(separator: ", ") + "."
        Task {
            if case .success(let ps) = await AIService.listSuggestions(words, context: AIContext.current()) {
                Self.kept[key] = ps
                withAnimation(Motion.chrome) { picks = ps }
            }
        }
    }
}
