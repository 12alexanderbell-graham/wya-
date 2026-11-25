import AppIntents
import SwiftUI

// SIRI IS THE DOOR, OUR AI IS THE BRAIN. On iOS 27 the pull down from the top centre is Siri's. No app can take
// Siri's screen or its gesture (the system assistant's own model can only be swapped through a private Apple route,
// `_ModelDelegationIntent`, closed to apps). What an app can do, and this does: - Siri can ask wya. (or Siri choosing
// it) sends the question to our AI (the Claude API, with your stamps, lived, wishes and what is on screen); our
// answer comes back as Siri's spoken reply and as our own card in Siri. - Siri knows wya's countries (CountryEntity),
// so, and work, and the country on screen is the one Siri means by "this" (ContentView's user activity). - What Siri
// asks is kept in the AI's history, as if asked in the app.

/// what Siri says back (logged in test builds, so the driver can read it)
func say(_ s: String) -> IntentDialog {
    #if DEBUG
    NSLog("wya siri says %@", s)
    #endif
    return IntentDialog(stringLiteral: s)
}

// MARK: countries Siri understands

/// a country or territory, by the map's id (ISO 3166-1 alpha-2, lowercase), named the phone's way
struct CountryEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Country"
    static let defaultQuery = CountryQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(id: String) {
        self.id = id.lowercased()
        self.name = Locale.current.localizedString(forRegionCode: id.uppercased()) ?? id.uppercased()
    }

    /// every country and territory the phone has a name for
    static let all: [CountryEntity] = Locale.Region.isoRegions
        .filter { $0.identifier.count == 2 && $0.identifier.allSatisfy(\.isLetter) }
        .map { CountryEntity(id: $0.identifier) }
        .filter { $0.name.uppercased() != $0.id.uppercased() }
        .sorted { $0.name < $1.name }
}

struct CountryQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CountryEntity] {
        identifiers.map { CountryEntity(id: $0) }
    }
    func entities(matching string: String) async throws -> [CountryEntity] {
        let q = string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return CountryEntity.all.filter {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) || $0.id == q
        }
    }
    func suggestedEntities() async throws -> [CountryEntity] {
        // your wishes first, then where you've been
        let marks = await MarkStore.shared.marks
        let wished = marks.filter { $0.key.kind == .country && $0.value.wished }.map { CountryEntity(id: $0.key.id) }
        let been = marks.filter { $0.key.kind == .country && $0.value.stamped }.map { CountryEntity(id: $0.key.id) }
        return Array((wished + been).prefix(20))
    }
}

// MARK: ask wya

struct AskWyaIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask wya"
    static let description = IntentDescription("Ask wya's AI anything. It knows what you stamped.")
    static let openAppWhenRun = false

    @Parameter(title: "Question", requestValueDialog: "What do you want to know?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // (the AI off in Settings: Siri says so, and where to turn it back on)
        if !MapSettingsStore.shared.value.ai {
            let off = "wya's AI is off. Turn it on in wya's Settings."
            return .result(dialog: say(off), view: SiriAnswerView(answer: AIService.Answer(answer: off, places: [])))
        }
        await MarkStore.shared.load()
        let r = await AIService.ask([AIService.Turn(role: "user", text: question)], context: AIContext.current())
        switch r {
        case .success(let a):
            // at the length set in Settings (Answers): the same answer, shorter or longer
            let words = a.text(MapSettingsStore.shared.value.aiLength)
            return .result(dialog: say(words), view: SiriAnswerView(answer: a, words: words))
        case .failure(let f):
            return .result(dialog: say(f.words), view: SiriAnswerView(answer: AIService.Answer(answer: f.words, places: [])))
        }
    }
}

/// OUR CARD INSIDE SIRI: the answer as wya writes it, the places in it bold. Siri draws the panel around it; the type
/// follows the system's light or dark so it always reads there.
struct SiriAnswerView: View {
    let answer: AIService.Answer
    var words: String? = nil
    var body: some View {
        Text(Self.words(answer, words ?? answer.answer))
            .font(.system(size: 17))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }
    static func words(_ a: AIService.Answer, _ text: String) -> AttributedString {
        var out = AttributedString(text)
        for pl in a.places {
            if let r = out.range(of: pl.name, options: [.caseInsensitive, .diacriticInsensitive]) {
                out[r].font = .system(size: 17, weight: .semibold)
            }
        }
        return out
    }
}

// MARK: doing things in wya

struct StampCountryIntent: AppIntent {
    static let title: LocalizedStringResource = "Stamp a country"
    static let description = IntentDescription("Stamp a country in your wya passport.")
    static let openAppWhenRun = false

    @Parameter(title: "Country") var country: CountryEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MarkStore.shared.load()
        if MarkStore.shared.state(.country(country.id)).stamped {
            return .result(dialog: say("\(country.name) is already stamped."))
        }
        await MarkStore.shared.stamp(.country(country.id), name: country.name, who: .siri)
        return .result(dialog: say("Stamped \(country.name)."))
    }
}

struct WishCountryIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to wishlist"
    static let description = IntentDescription("Add a country to your wya wishlist.")
    static let openAppWhenRun = false

    @Parameter(title: "Country") var country: CountryEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MarkStore.shared.load()
        let st = MarkStore.shared.state(.country(country.id))
        if st.stamped { return .result(dialog: say("You've already been to \(country.name).")) }
        if st.wished { return .result(dialog: say("\(country.name) is already on your wishlist.")) }
        await MarkStore.shared.wish(.country(country.id), name: country.name, who: .siri)
        return .result(dialog: say("Added \(country.name) to your wishlist."))
    }
}

/// : counted as the map counts (the Count setting, the world's own view), so it says what the caption says
struct CountIntent: AppIntent {
    static let title: LocalizedStringResource = "How many places have I been to"
    static let description = IntentDescription("Your wya count, as the map shows it.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MarkStore.shared.load()
        let stamped = Set(MarkStore.shared.marks.filter { $0.key.kind == .country && $0.value.stamped }.map { $0.key.id.lowercased() })
        if let w = AIContext.map?.world, let world = MapCounts.shares(stamped: stamped, world: w, count: CountKind.current)["World"] {
            return .result(dialog: say("\(world.have) of \(world.total)."))
        }
        return .result(dialog: say("\(stamped.count) so far."))
    }
}

struct OpenPassportIntent: AppIntent {
    static let title: LocalizedStringResource = "Open my passport"
    static let description = IntentDescription("Open your wya passport.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // (from a cold launch the book waits for the map, as a link does)
        for _ in 0 ..< 60 where !(AIContext.map?.ready ?? false) { try? await Task.sleep(for: .milliseconds(100)) }
        if !BookState.shared.isOpen { BookState.shared.open() }
        return .result()
    }
}

struct ShowCountryIntent: AppIntent {
    static let title: LocalizedStringResource = "Show a country"
    static let description = IntentDescription("Open wya's map on a country.")
    static let openAppWhenRun = false

    @Parameter(title: "Country") var country: CountryEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "wya://country/\(country.id)")!))
    }
}

struct PlanTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Plan a trip"
    static let description = IntentDescription("wya's AI makes a day-by-day plan, in front of you, in Plans.")
    static let openAppWhenRun = true

    @Parameter(title: "Country") var country: CountryEntity

    /// (Siri hands over at once: the plan is made in the app, in front of you, and kept only if you keep it)
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard MapSettingsStore.shared.value.ai else { return .result(dialog: say("wya's AI is off. Turn it on in wya's Settings.")) }
        PlanAI.make("Plan me a trip to \(country.name).", name: country.name)
        return .result(dialog: say("Planning \(country.name) in wya."))
    }
}

// MARK: your trip and your lists

/// : the line on top of Lists (,,)
struct NextTripIntent: AppIntent {
    static let title: LocalizedStringResource = "My next trip"
    static let description = IntentDescription("How long till your next trip in wya, or what's on today.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let (t, p) = NextTripLine.current() else {
            return .result(dialog: say("No trip coming up. Give a plan its dates in wya and it shows here."))
        }
        var words = NextTripLine.words(t, p, today: PlanDates.key(local: Date()))
        if case .before = t.phase, !p.start.isEmpty, let d = PlanDates.date(p.start) {
            let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
            words += ", on " + f.string(from: d)
        }
        return .result(dialog: say(words + "."))
    }
}

/// one of your lists, by name (the wishlist is the map's: does that)
struct ListEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let defaultQuery = ListQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ListQuery: EntityStringQuery {
    @MainActor private func mine() -> [ListEntity] {
        ListsStore.shared.book.lists.filter { !$0.wish && !$0.arch && !$0.hid && !$0.name.isEmpty }.map { ListEntity(id: $0.id, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [ListEntity] {
        await mine().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [ListEntity] {
        let q = string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return await mine().filter { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) }
    }
    func suggestedEntities() async throws -> [ListEntity] { await mine() }
}

/// OPEN A LIST (in Shortcuts and Siri's suggestions; Apple's ten spoken phrases are taken): the list open in Lists,
/// through its link
struct OpenListIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a list"
    static let description = IntentDescription("Open one of your wya lists.")
    static let openAppWhenRun = false

    @Parameter(title: "List") var list: ListEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "wya://list/\(list.id)")!))
    }
}

/// : the thing goes in the list (a country's name gets its flag)
struct AddToListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to a list"
    static let description = IntentDescription("Put something in one of your wya lists.")
    static let openAppWhenRun = false

    @Parameter(title: "What", requestValueDialog: "What should go in it?") var thing: String
    @Parameter(title: "List", requestValueDialog: "Which list?") var list: ListEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let n = thing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return .result(dialog: say("Nothing to add.")) }
        guard let l = ListsStore.shared.book.lists.first(where: { $0.id == list.id }) else {
            return .result(dialog: say("That list isn't in wya any more."))
        }
        if let had = l.items.first(where: { $0.n.caseInsensitiveCompare(n) == .orderedSame }) {
            return .result(dialog: say("\(had.n) is already in \(l.name)."))
        }
        // a country by its name gets its country (the row's flag)
        let cc = CountryEntity.all.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }?.id
        ListsStore.shared.change { b in
            if let i = b.lists.firstIndex(where: { $0.id == l.id }) { b.lists[i].items.append(ListItem(n: n, cc: cc)) }
        }
        return .result(dialog: say("Added \(n) to \(l.name)."))
    }
}

// MARK: what it remembers about you

struct RememberIntent: AppIntent {
    static let title: LocalizedStringResource = "Remember something"
    static let description = IntentDescription("Tell wya's AI something about you to keep in mind.")
    static let openAppWhenRun = false
    @Parameter(title: "What", requestValueDialog: "What should it remember?") var note: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        for lead in ["that ", "That "] where n.hasPrefix(lead) { n = String(n.dropFirst(lead.count)) }
        guard !n.isEmpty else { return .result(dialog: say("Nothing to remember.")) }
        AINotes.add(n)
        return .result(dialog: say("Got it."))
    }
}

struct WhatYouKnowIntent: AppIntent {
    static let title: LocalizedStringResource = "What do you know about me"
    static let description = IntentDescription("What you've told wya's AI to remember.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let n = AINotes.all
        if n.isEmpty { return .result(dialog: say("Only your map, lists and plans. You haven't told me anything to remember.")) }
        return .result(dialog: say("Besides your map, lists and plans: " + n.joined(separator: "; ") + "."))
    }
}

struct ForgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Forget something"
    static let description = IntentDescription("Take something out of what wya's AI remembers.")
    static let openAppWhenRun = false
    @Parameter(title: "What", requestValueDialog: "What should it forget?") var words: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let gone = AINotes.forget(words)
        return .result(dialog: say(gone.isEmpty ? "I wasn't keeping that." : "Forgotten: " + gone.joined(separator: "; ") + "."))
    }
}

struct WyaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskWyaIntent(), phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) something"],
                    shortTitle: "Ask", systemImageName: "location.north.line")
        AppShortcut(intent: StampCountryIntent(), phrases: ["Stamp \(\.$country) in \(.applicationName)",
                                                           "Add \(\.$country) to my \(.applicationName) passport"],
                    shortTitle: "Stamp a country", systemImageName: "checkmark.seal")
        AppShortcut(intent: WishCountryIntent(), phrases: ["Add \(\.$country) to my \(.applicationName) wishlist",
                                                          "I want to go to \(\.$country) \(.applicationName)"],
                    shortTitle: "Add to wishlist", systemImageName: "star")
        AppShortcut(intent: CountIntent(), phrases: ["How many countries have I been to in \(.applicationName)",
                                                    "What's my \(.applicationName) count"],
                    shortTitle: "My count", systemImageName: "number")
        AppShortcut(intent: OpenPassportIntent(), phrases: ["Open my \(.applicationName) passport",
                                                           "Show my passport in \(.applicationName)"],
                    shortTitle: "My passport", systemImageName: "book.closed")
        AppShortcut(intent: ShowCountryIntent(), phrases: ["Show \(\.$country) in \(.applicationName)",
                                                          "Open \(\.$country) in \(.applicationName)"],
                    shortTitle: "Show a country", systemImageName: "map")
        AppShortcut(intent: PlanTripIntent(), phrases: ["Plan a trip to \(\.$country) with \(.applicationName)",
                                                       "Plan \(\.$country) in \(.applicationName)"],
                    shortTitle: "Plan a trip", systemImageName: "airplane")
        AppShortcut(intent: NextTripIntent(), phrases: ["What's my next trip in \(.applicationName)",
                                                       "When is my trip in \(.applicationName)"],
                    shortTitle: "My next trip", systemImageName: "calendar")
        AppShortcut(intent: AddToListIntent(), phrases: ["Add to my \(\.$list) list in \(.applicationName)",
                                                        "Add something to a \(.applicationName) list"],
                    shortTitle: "Add to a list", systemImageName: "list.bullet")
        AppShortcut(intent: RememberIntent(), phrases: ["Remember something in \(.applicationName)",
                                                       "Tell \(.applicationName) something about me"],
                    shortTitle: "Remember", systemImageName: "brain")
        // (Apple allows ten App Shortcuts: and are actions in Shortcuts, without a phrase)
    }
}


#if DEBUG
/// the test driver's "siri" commands, each action run as Siri would run it
@MainActor
enum SiriTest {
    static func run(_ a: String, _ rest: String, map: MapController?) async {
        do {
            switch a {
            case "ask": var i = AskWyaIntent(); i.question = rest; _ = try await i.perform()
            case "stamp": var i = StampCountryIntent(); i.country = CountryEntity(id: rest); _ = try await i.perform()
            case "plan": var i = PlanTripIntent(); i.country = CountryEntity(id: rest); _ = try await i.perform()
            case "wish": var i = WishCountryIntent(); i.country = CountryEntity(id: rest); _ = try await i.perform()
            case "count": _ = try await CountIntent().perform()
            case "trip": _ = try await NextTripIntent().perform()
            case "remember": var i = RememberIntent(); i.note = rest; _ = try await i.perform()
            case "knows": _ = try await WhatYouKnowIntent().perform()
            case "forget": var i = ForgetIntent(); i.words = rest; _ = try await i.perform()
            case "listadd":
                // siri listadd <list name>|<thing>
                let parts = rest.components(separatedBy: "|")
                if parts.count == 2, let l = ListsStore.shared.book.lists.first(where: { $0.name == parts[0] }) {
                    var i = AddToListIntent()
                    i.list = ListEntity(id: l.id, name: l.name)
                    i.thing = parts[1]
                    _ = try await i.perform()
                }
            case "passport": _ = try await OpenPassportIntent().perform()
            case "show":
                var i = ShowCountryIntent(); i.country = CountryEntity(id: rest); _ = try await i.perform()
                if let u = URL(string: "wya://country/\(rest)"), let m = map { _ = await DeepLink.open(u, map: m) {} }
            default: break
            }
            NSLog("wya siri %@ %@ done", a, rest)
        } catch { NSLog("wya siri %@ failed %@", a, "\(error)") }
    }
}
#endif
