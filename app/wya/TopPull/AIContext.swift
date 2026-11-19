import Foundation

/// WHAT THE AI KNOWS, for Siri's actions (SiriIntents). Our own AI screen is gone: the pull down is Siri's, Siri is
/// the AI's face, and wya is what Siri asks. This is what goes with each question: your stamps, where you lived, your
/// wishes, your nationality, your name, and what is on the screen.
@MainActor
enum AIContext {
    static weak var map: MapController?
    static weak var head: HeadState?

    /// what it knows about you, and what is on the screen
    static func current() -> AIService.Context {
        var c = AIService.Context()
        let names: [String: String] = Dictionary(
            (map?.world?.places ?? []).map { ($0.id.lowercased(), $0.n) }, uniquingKeysWith: { a, _ in a })
        func name(_ id: String) -> String { names[id.lowercased()] ?? id.uppercased() }
        let marks = MarkStore.shared.marks.filter { $0.key.kind == .country }.sorted { $0.key < $1.key }
        c.stamped = marks.filter { $0.value.stamped }.map { name($0.key.id) }
        c.lived = marks.filter { $0.value.lived }.map { name($0.key.id) }
        c.wished = marks.filter { $0.value.wished }.sorted { $0.value.want > $1.value.want }.map { name($0.key.id) }
        c.nationalities = (UserDefaults.standard.stringArray(forKey: MapController.nationalitiesKey) ?? []).map(name)
        c.name = ProfileStore.shared.me.name
        var screen: [String] = []
        if let h = head { screen.append("the \(h.mode.name) map") }
        if let i = CardState.shared.place, let w = map?.world, i < w.places.count { screen.append("\(w.places[i].n)'s card") }
        if PlacePageState.shared.isOpen, !PlacePageState.shared.name.isEmpty { screen.append("the page of \(PlacePageState.shared.name)") }
        c.screen = screen.joined(separator: ", ")
        // THE TRIP AND THE PLANS (AI-ALL-NOTES 9:; profile notes, lists, plans, trips): the trip shown on top of
        // Lists, with its days, and the rest by name
        let book = ListsStore.shared.book
        let trip = NextTripLine.current()
        if let (t, p) = trip {
            let when: String
            switch t.phase {
            case .before(let n): when = n <= 1 ? "starts tomorrow" : "starts in \(n) days"
            case .during(let d, let all): when = "on day \(d) of \(all) today"
            case .after: when = "just back"
            }
            var days: [String] = []
            for (i, d) in p.days.enumerated() where !d.items.isEmpty {
                let items = d.items.sorted { $0.startMinutes < $1.startMinutes }.prefix(6).map { it in
                    (it.at.map { $0 + " " } ?? "") + it.what + (it.place.isEmpty ? "" : " (\(it.place))")
                }
                days.append("day \(i + 1): " + items.joined(separator: ", "))
            }
            c.trip = "\"\(p.name)\", \(p.start) to \(p.end), \(when)" + (days.isEmpty ? "." : "; " + days.prefix(14).joined(separator: "; ") + ".")
        }
        for p in book.plans where !p.arch && !p.hid && !p.ai && p.id != trip?.1.id && !p.name.isEmpty {
            let places = Array(NSOrderedSet(array: p.days.flatMap { $0.items.map(\.place) }.filter { !$0.isEmpty })) as? [String] ?? []
            c.plans.append("plan \"\(p.name)\"" + (p.start.isEmpty ? " (no dates)" : " (\(p.start))") + (places.isEmpty ? "" : ": " + places.prefix(6).joined(separator: ", ")))
        }
        for l in book.lists where !l.arch && !l.hid && !l.wish && !l.name.isEmpty {
            let things = l.items.filter { $0.k != .section }.prefix(8).map(\.n)
            c.plans.append("list \"\(l.name)\"" + (things.isEmpty ? "" : ": " + things.joined(separator: ", ")))
        }
        c.plans = Array(c.plans.prefix(12))
        c.notes = AINotes.all
        return c
    }
}


/// WHAT YOU TOLD IT TO REMEMBER: short notes in your own words, kept on the phone, sent with every question. Said to
/// Siri, read back and forgotten the same way.
@MainActor
enum AINotes {
    private static let key = "wya.ai.notes"
    static var all: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func add(_ n: String) {
        let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !all.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        UserDefaults.standard.set(Array((all + [t]).suffix(40)), forKey: key)
    }
    /// the notes that have these words in them taken away; what was taken
    @discardableResult static func forget(_ words: String) -> [String] {
        let q = words.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let gone = all.filter { $0.lowercased().contains(q) || q.contains($0.lowercased()) }
        UserDefaults.standard.set(all.filter { !gone.contains($0) }, forKey: key)
        return gone
    }
}
