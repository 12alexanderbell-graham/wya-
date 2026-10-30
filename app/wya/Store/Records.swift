import Foundation
import SwiftData

// THE RECORDS (Part 0.2.2), version 1 of the schema. Every later change is a new version with a migration, never an
// edit of this one. Every record belongs to an account ("" = no account, Part 20.10).

enum TravelSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [StampRecord.self, VisitRecord.self, EvidenceRecord.self] }

    /// ONE PER PLACE: stamped or wished, never both (the old StampBook's rule: stamping a wished place clears the wish
    /// and keeps when it came, `came`).
    @Model
    final class StampRecord {
        #Unique<StampRecord>([\.account, \.key])
        var account: String = ""
        /// the PlaceKey as text ("c:fr")
        var key: String = ""
        var stamped: Bool = false
        var wished: Bool = false
        /// how badly, 1 to 5 (wishes)
        var want: Int = 0
        /// when, for a wish: someday, soon, next (the old WishDetails.prio)
        var wishWhen: String?
        /// when it was pressed
        var at: Date = Date()
        /// how it was made (MarkSource)
        var source: String = MarkSource.hand.rawValue
        /// the times you typed (the old Stamp.visits; the number shown is the larger of this and the visits kept)
        var times: Int = 1
        var lived: Bool = false
        var note: String = ""
        /// the old Stamp.when ("2026-08"): a month, when only that is known
        var when: String?
        /// the old StampDetails, kept whole as JSON until Details is built (Step 5)
        var details: Data?
        /// the old WishDetails, the same way
        var wishDetails: Data?
        /// the old Verification (how, state, at, when, file), as JSON until Verify is built (Step 7)
        var verification: Data?
        /// a sovereign stamped because of this territory (the old Stamp.via)
        var via: String?
        /// a wish that later became a stamp: when it was wished (the old StampBook.came)
        var came: Date?
        /// the name, its country and level, so lists show it without the map files (the old Region/Town/MarkStamp)
        var name: String = ""
        var cc: String = ""
        var level: Int = 0

        init(account: String, key: PlaceKey) { self.account = account; self.key = key.description }
    }

    /// A DATED STAY at a place; several per place (Part 0.2.2).
    @Model
    final class VisitRecord {
        var id: UUID = UUID()
        var account: String = ""
        var key: String = ""
        /// PartialDate text ("2023", "2023-04", "2023-04-01")
        var arrived: String?
        var left: String?
        var rough: String?
        var lived: Bool = false
        var transit: Bool = false
        /// made inside a dated plan's days
        var planId: String?
        var source: String = MarkSource.hand.rawValue

        init(account: String, key: PlaceKey) { self.account = account; self.key = key.description }
    }

    /// ONE DAY AT ONE PLACE found on the phone (photos, history, tracking, here). Never leaves the phone.
    @Model
    final class EvidenceRecord {
        var id: UUID = UUID()
        var account: String = ""
        var key: String = ""
        /// LocalDay text
        var day: String = ""
        var source: String = MarkSource.photos.rawValue
        /// Photos' local identifiers
        var photos: [String] = []
        /// waiting for the person's yes (the review, Part 9.5)
        var proposed: Bool = true
        var batch: String?

        init(account: String, key: PlaceKey, day: LocalDay) { self.account = account; self.key = key.description; self.day = day.description }
    }
}

typealias StampRecord = TravelSchemaV1.StampRecord
typealias VisitRecord = TravelSchemaV1.VisitRecord
typealias EvidenceRecord = TravelSchemaV1.EvidenceRecord

enum TravelMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TravelSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
