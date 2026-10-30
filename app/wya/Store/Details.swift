import Foundation

/// WHAT YOU SAY ABOUT A PLACE YOU STAMPED (Part 4.4): the old app's StampDetails, field for field (so an imported
/// book's details read as they are), plus `with`. Kept as JSON in StampRecord.details; written once when Details
/// closes (one undo step). Dates (from, to, stays) are read and kept but not edited until our own calendar exists.
nonisolated struct StampDetails: Codable, Equatable, Sendable {
    struct Stay: Codable, Equatable, Sendable { var from: String; var to: String }
    struct Went: Codable, Equatable, Sendable { var n: String; var k: String }
    var from: String?
    var to: String?
    /// a visit's time in words when it isn't exact ("Summer 2019", 40 characters)
    var whenRough: String?
    var nights: Int?
    /// Visit / Airport / Through / Other
    var mode: String?
    var modeOther: String?
    /// Holiday / Work / Family and friends / Study / Other
    var purpose: String?
    var purposeOther: String?
    var lived: Bool?
    /// Grew up / Work / Study / Family / Partner / Other
    var livedWhy: String?
    var livedWhyOther: String?
    var livesNow: Bool?
    var livedRough: String?
    var stays: [Stay]?
    /// the visits after the first (one row per trip), each with its own time in words, how and why;
    /// the first visit is the fields above, as the old app kept it
    struct Trip: Codable, Equatable, Sendable {
        var whenRough: String?
        var mode: String?
        var modeOther: String?
        var purpose: String?
        var purposeOther: String?
    }
    var trips: [Trip]?
    /// visit i as one Trip: 0 is the record's own fields, the others `trips` (setting past the end does nothing)
    subscript(trip i: Int) -> Trip {
        get {
            if i == 0 { return Trip(whenRough: whenRough, mode: mode, modeOther: modeOther, purpose: purpose, purposeOther: purposeOther) }
            let t = trips ?? []
            return i - 1 < t.count ? t[i - 1] : Trip()
        }
        set {
            if i == 0 {
                whenRough = newValue.whenRough; mode = newValue.mode; modeOther = newValue.modeOther
                purpose = newValue.purpose; purposeOther = newValue.purposeOther
            } else if var t = trips, i - 1 < t.count {
                t[i - 1] = newValue; trips = t
            }
        }
    }
    var places: [Went]?
    /// activities, 600 characters
    var did: String?
    /// notes, 600 characters
    var note: String?
    /// 1 to 5
    var stars: Int?
    /// who you were with, one 120-character line (new)
    var with: String?

    var isEmpty: Bool { self == StampDetails() }

    init() {}
    init(json: Data?) {
        self = json.flatMap { try? JSONDecoder().decode(StampDetails.self, from: $0) } ?? StampDetails()
    }
    var json: Data? {
        guard !isEmpty else { return nil }
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return try? e.encode(self)
    }
}

/// A STAMP'S PROOF (Part 4.5): the old app's Verification (how, state, at, when, file). States as built here:
/// "waiting" (kept on the phone until it can be sent: there is no server yet), "checking", "verified", "notAccepted".
nonisolated struct Verification: Codable, Equatable, Sendable {
    /// here / history / library / camera / documents / other
    var how: String
    var state: String
    var at: Date
    /// the proving day, "YYYY-MM-DD"
    var when: String?
    var file: String?

    init(how: String, state: String, at: Date = Date(), when: String? = nil) {
        self.how = how; self.state = state; self.at = at; self.when = when
    }
    init?(json: Data?) {
        guard let json, let v = try? JSONDecoder().decode(Verification.self, from: json) else { return nil }
        self = v
    }
    var json: Data? {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return try? e.encode(self)
    }
    /// what the card's button reads (4.5.4)
    var word: String {
        switch state {
        case "verified": return "Verified"
        case "waiting", "checking": return "In process"
        default: return "Verify?"
        }
    }
}

/// WHAT YOU SAY ABOUT A PLACE YOU WISH FOR (Part 4.4.5): the old app's WishDetails, field for field. How badly is the
/// record's own `want` (1 to 5 stars, a new wish is 1), not kept here; `stars` is read and kept for old books.
nonisolated struct WishDetails: Codable, Equatable, Sendable {
    /// someday / soon / next
    var prio: String?
    /// when, in words (40 characters)
    var when: String?
    /// what you would do there (the sheet's Activities, 600 characters)
    var why: String?
    /// notes (600 characters)
    var note: String?
    var stars: Int?

    var isEmpty: Bool { self == WishDetails() }
    init() {}
    init(json: Data?) {
        self = json.flatMap { try? JSONDecoder().decode(WishDetails.self, from: $0) } ?? WishDetails()
    }
    var json: Data? {
        guard !isEmpty else { return nil }
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return try? e.encode(self)
    }
}
