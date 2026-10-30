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
