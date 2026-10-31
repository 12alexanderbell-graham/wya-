import Foundation
import SwiftData
import CoreGraphics

/// ONE CHANGE TO YOUR MARKS (Part 0.2.3's one signature): the places, before and after, where the touch was (nil when
/// no finger caused it), and who acted. The map's colours, the Cosmos, the caption, Count, the Streak, lists' counts
/// and the passport listen to it.
struct MarksChanged {
    let changed: [PlaceKey: (old: MarkState, new: MarkState)]
    let origin: CGPoint?
    let who: Who
    var ids: Set<PlaceKey> { Set(changed.keys) }
}

/// THE STORE'S FACE ON THE MAIN THREAD (Part 0.2.2: "MarkStore is its interface for Stamps, Wishes and Visits"):
/// what every marking surface calls, the marks as they are now for drawing, the change stream, and undo (every write
/// one step, up to 20 in a session; Part 3.10's drop and the shake use it).
@MainActor @Observable
final class MarkStore {
    static let shared = MarkStore()

    /// every mark of the signed-in account (or of no account, "")
    private(set) var marks: [PlaceKey: MarkState] = [:]
    /// the store has been read (until then the map shows nothing of yours, and the caption waits)
    private(set) var loaded = false
    /// the account the records belong to ("": no account, Part 20.10)
    private(set) var account = ""
    /// the words of the last change, for the undo drop ("France stamped")
    private(set) var lastWords: String?
    /// counts every undoable write (not the undos): the undo drop rises when it changes
    private(set) var changes = 0

    @ObservationIgnored private var store: TravelStore?
    @ObservationIgnored private var undoStack: [(snaps: [TravelStore.Snapshot], words: String)] = []
    /// what undo took back, for a three-finger swipe right (Part 3.10, proposal); any new change empties it
    @ObservationIgnored private var redoStack: [(snaps: [TravelStore.Snapshot], words: String)] = []
    @ObservationIgnored private var listeners: [UUID: (MarksChanged) -> Void] = [:]
    @ObservationIgnored let container: ModelContainer?

    /// THE APP GROUP (Part 0.2.2: "SwiftData in an App Group (widgets later need no migration)"); the app's own
    /// container when the group isn't there (a build without the entitlement), never a crash
    static let group = "group.com.alexanderbell.wya"

    private init() {
        let schema = Schema(versionedSchema: TravelSchemaV1.self)
        var made: ModelContainer?
        // SwiftData stops the app (not an error) when the group isn't in the entitlements, so ask first
        let hasGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group) != nil
        var configs = [ModelConfiguration("Travel", schema: schema, groupContainer: .none)]
        if hasGroup { configs.insert(ModelConfiguration("Travel", schema: schema, groupContainer: .identifier(Self.group)), at: 0) }
        for config in configs {
            if let c = try? ModelContainer(for: schema, migrationPlan: TravelMigrationPlan.self, configurations: config) {
                made = c
                #if DEBUG
                NSLog("wya store at %@", config.url.path)
                #endif
                break
            }
        }
        container = made
        if let made { store = TravelStore(modelContainer: made) }
    }

    /// read every mark (once, at launch, off the main thread)
    func load() async {
        guard let store, !loaded else { return }
        #if DEBUG
        await seedDemoIfEmpty()
        #endif
        marks = (try? await store.all(account: account)) ?? [:]
        markDates = (try? await store.markDates(account: account)) ?? []
        loaded = true
        await refreshCalendar()
    }

    /// THE CALENDAR BASE (Part 9.9), rebuilt after every change (a write, an undo, a sign out) and at launch; the
    /// finds waiting for their review are on it too
    private(set) var calendar = CalendarIndex()
    @ObservationIgnored private var calendarJob = 0
    func refreshCalendar() async {
        guard let store else { return }
        calendarJob += 1
        let me = calendarJob
        let acc = account
        let rows = (try? await store.calendarRows(account: acc)) ?? []
        guard me == calendarJob else { return }
        calendar = CalendarIndex(rows: rows, finds: UploadState.shared.calendarFinds)
    }

    /// when each mark was made (the Streak counts weeks with one)
    private(set) var markDates: [Date] = []

    /// listen to every change; returns a token to stop
    @discardableResult
    func listen(_ f: @escaping (MarksChanged) -> Void) -> UUID {
        let id = UUID(); listeners[id] = f; return id
    }
    func stopListening(_ id: UUID) { listeners[id] = nil }

    func state(_ key: PlaceKey) -> MarkState { marks[key] ?? .none }

    // MARK: the writes every marking surface calls (Part 20.1: the same eleven ways in, the same functions)

    func stamp(_ key: PlaceKey, name: String = "", cc: String = "", level: Int = 0, source: MarkSource = .hand,
               who: Who = .you, origin: CGPoint? = nil) async {
        guard let store else { return }
        let acc = account
        guard let r = try? await store.stamp(key, account: acc, source: source, name: name, cc: cc, level: level) else { return }
        apply(r, words: "\(label(key, name)) stamped", origin: origin, who: who)
    }

    func unstamp(_ key: PlaceKey, name: String = "", who: Who = .you, origin: CGPoint? = nil) async {
        // a country unstamped any way is no longer "stamped only through a town" (7.4's unstamp rule)
        if key.kind == .country { TownStamps.forget(key.id) }
        guard let store else { return }
        let acc = account
        guard let r = try? await store.unstamp(key, account: acc) else { return }
        apply(r, words: "\(label(key, name)) unstamped", origin: origin, who: who)
    }

    func wish(_ key: PlaceKey, want: Int = 3, name: String = "", cc: String = "", level: Int = 0,
              source: MarkSource = .hand, who: Who = .you, origin: CGPoint? = nil) async {
        guard let store else { return }
        let acc = account
        guard let r = try? await store.wish(key, account: acc, want: want, source: source, name: name, cc: cc, level: level) else { return }
        apply(r, words: "\(label(key, name)) wished", origin: origin, who: who)
    }

    func unwish(_ key: PlaceKey, name: String = "", who: Who = .you, origin: CGPoint? = nil) async {
        guard let store else { return }
        let acc = account
        guard let r = try? await store.unwish(key, account: acc) else { return }
        apply(r, words: "\(label(key, name)) off the wishlist", origin: origin, who: who)
    }

    /// THE OLD APP'S stamps.json read in (OldStamps.swift): one write, one undo step; returns how many places came in
    @discardableResult
    func importOld(_ data: Data, who: Who = .importer) async -> Int {
        guard let store, let book = try? OldBook(json: data) else { return 0 }
        let acc = account
        guard let r = try? await store.importOld(book, account: acc) else { return 0 }
        apply(r, words: "\(r.changed.count) places from the old app", origin: nil, who: who)
        markDates = (try? await store.markDates(account: acc)) ?? markDates
        return r.changed.count
    }

    /// AN UPLOAD'S FINDS STAMPED with their found trips (Part 9.5's go): one write, one undo step
    /// false when the store refused the write (nothing was changed)
    @discardableResult
    func importFinds(_ finds: [TravelStore.Found], source: MarkSource, words: String) async -> Bool {
        guard let store else { return false }
        let acc = account
        guard let r = try? await store.importFinds(finds, account: acc, source: source) else { return false }
        apply(r, words: words, origin: nil, who: .importer)
        return true
    }

    /// DETAILS (Part 4.4): read a stamped place's, and write them back once when Details closes (one undo step;
    /// nothing changed, nothing written and no undo drop)
    func details(_ key: PlaceKey) async -> (details: StampDetails, times: Int, lived: Bool)? {
        guard let store else { return nil }
        let acc = account
        guard let d = try? await store.detailsOf(key, account: acc) else { return nil }
        return (StampDetails(json: d.details), d.times, d.lived)
    }
    func setDetails(_ key: PlaceKey, name: String, details: StampDetails, times: Int, lived: Bool) async {
        guard let store else { return }
        let acc = account
        guard let r = try? await store.setDetails(key, account: acc, details: details.json, times: times, lived: lived) else { return }
        apply(r, words: "\(label(key, name)) details", origin: nil, who: .you)
    }

    /// a stamp's proof (4.5): read, and written as one undo step
    func verification(_ key: PlaceKey) async -> Verification? {
        guard let store else { return nil }
        let acc = account
        return Verification(json: (try? await store.verificationOf(key, account: acc)) ?? nil)
    }
    func setVerification(_ key: PlaceKey, name: String, _ v: Verification?) async {
        guard let store else { return }
        let acc = account
        guard let r = try? await store.setVerification(key, account: acc, data: v?.json) else { return }
        apply(r, words: "\(label(key, name)) proof", origin: nil, who: .you)
    }

    /// the Stamped list's second line: latest year and verified, by key ("c:fr")
    func listInfo() async -> [String: (year: Int?, verified: Bool)] {
        guard let store else { return [:] }
        let acc = account
        return (try? await store.listInfo(account: acc)) ?? [:]
    }

    /// a wished place's details (4.4.5), read and written once as Details closes
    func wishDetails(_ key: PlaceKey) async -> (details: WishDetails, want: Int)? {
        guard let store else { return nil }
        let acc = account
        guard let d = try? await store.wishDetailsOf(key, account: acc) else { return nil }
        return (WishDetails(json: d.details), d.want)
    }
    func setWishDetails(_ key: PlaceKey, name: String, details: WishDetails, want: Int) async {
        guard let store else { return }
        let acc = account
        guard let r = try? await store.setWishDetails(key, account: acc, details: details.json, want: want) else { return }
        apply(r, words: "\(label(key, name)) details", origin: nil, who: .you)
    }

    /// the passport's order of stamped countries (oldest first), read fresh from the store
    func passportOrder() async -> [String] {
        guard let store else { return [] }
        let acc = account
        return (try? await store.passportOrder(account: acc)) ?? []
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// UNDO the last write (the drop, a shake, a three-finger swipe left; Part 3.10)
    func undo() async {
        guard let store, let last = undoStack.popLast() else { return }
        let acc = account
        guard let r = try? await store.restore(last.snaps, account: acc) else { return }
        take(r)
        redoStack.append((r.undo, last.words))
        if redoStack.count > 20 { redoStack.removeFirst(redoStack.count - 20) }
        lastWords = undoStack.last?.words
        emit(MarksChanged(changed: r.changed, origin: nil, who: .undo))
    }

    var canRedo: Bool { !redoStack.isEmpty }

    /// REDO the last undone write (a three-finger swipe right; Part 3.10, proposal)
    func redo() async {
        guard let store, let last = redoStack.popLast() else { return }
        let acc = account
        guard let r = try? await store.restore(last.snaps, account: acc) else { return }
        take(r)
        undoStack.append((r.undo, last.words))
        lastWords = last.words
        emit(MarksChanged(changed: r.changed, origin: nil, who: .undo))
    }

    /// SIGN OUT (Part 19.3): everything of this account goes, and the map is plain
    func signOut() async {
        guard let store else { return }
        // finds waiting from an upload are this account's too
        UploadState.shared.signedOut()
        let acc = account
        try? await store.empty(account: acc)
        let old = marks
        marks = [:]
        undoStack = []
        redoStack = []
        var changed: [PlaceKey: (old: MarkState, new: MarkState)] = [:]
        for (k, s) in old { changed[k] = (s, .none) }
        emit(MarksChanged(changed: changed, origin: nil, who: .you))
    }

    // MARK: inside

    private func apply(_ r: TravelStore.Result, words: String, origin: CGPoint?, who: Who) {
        guard !r.changed.isEmpty else { return }
        take(r)
        undoStack.append((r.undo, words))
        redoStack = []
        markDates.append(Date())
        if undoStack.count > 20 { undoStack.removeFirst(undoStack.count - 20) }
        lastWords = words
        changes += 1
        emit(MarksChanged(changed: r.changed, origin: origin, who: who))
    }

    private func take(_ r: TravelStore.Result) {
        for (k, c) in r.changed { marks[k] = c.new == .none ? nil : c.new }
    }

    private func emit(_ c: MarksChanged) {
        for f in listeners.values { f(c) }
        Task { await refreshCalendar() }
    }

    private func label(_ key: PlaceKey, _ name: String) -> String { name.isEmpty ? key.id.uppercased() : name }

    #if DEBUG
    /// THE DEMO ACCOUNT, in the store (it was hard-coded in the map, MapController's DemoAccount): the same 34 stamped
    /// and 6 wished countries, put in once when the store is empty, dated over the last three weeks so the streak is
    /// the 3 weeks the sun has shown. Debug builds only.
    static let demoStamped = ["fr", "es", "pt", "it", "gr", "tr", "ma", "eg", "de", "gb", "ch", "at", "hr", "nl", "be", "ie",
                              "no", "se", "dk", "pl", "cz", "tn", "jo", "il", "ae", "in", "th", "jp", "us", "br", "ar", "za",
                              "ke", "tz"]
    static let demoWished = ["na", "is", "ir", "et", "mg", "fi"]
    private func seedDemoIfEmpty() async {
        guard let store, let all = try? await store.all(account: account), all.isEmpty else { return }
        let now = Date()
        for (i, id) in Self.demoStamped.enumerated() {
            let at = now.addingTimeInterval(-Double(i % 3) * 7 * 86_400)
            _ = try? await store.stamp(.country(id), account: account, source: .demo, at: at)
        }
        for id in Self.demoWished { _ = try? await store.wish(.country(id), account: account, source: .demo) }
    }
    #endif
}
