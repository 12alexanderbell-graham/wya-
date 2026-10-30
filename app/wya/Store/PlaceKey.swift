import Foundation

/// WHAT A PLACE IS CALLED IN THE STORE (Part 0.2.2): the old app's keys, so its data reads as it is.
/// - `c:fr` a country, territory or entity (the map's id)
/// - `r:IRN120` a region (the boundary data's id)
/// - `t:br/6317631` a town (its file's country / its GeoNames id, or its name when it has none)
/// - `m:whs:91` a thing (its source's id)
/// - `y:<uuid>` your own place
/// A pin is not a place (`PinID`).
nonisolated struct PlaceKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    enum Kind: String, Codable, Sendable, CaseIterable { case country = "c", region = "r", town = "t", thing = "m", yours = "y" }
    let kind: Kind
    let id: String

    init(_ kind: Kind, _ id: String) { self.kind = kind; self.id = id }
    static func country(_ id: String) -> PlaceKey { PlaceKey(.country, id) }

    /// "c:fr"; nil for anything else
    init?(_ s: String) {
        guard let colon = s.firstIndex(of: ":"), let k = Kind(rawValue: String(s[..<colon])) else { return nil }
        let rest = String(s[s.index(after: colon)...])
        guard !rest.isEmpty else { return nil }
        self.init(k, rest)
    }

    var description: String { kind.rawValue + ":" + id }
    static func < (a: PlaceKey, b: PlaceKey) -> Bool { a.description < b.description }

    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(description) }
    init(from dec: Decoder) throws {
        let s = try dec.singleValueContainer().decode(String.self)
        guard let v = PlaceKey(s) else { throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: s)) }
        self = v
    }
}

/// A pin's own id (never a place).
nonisolated struct PinID: Hashable, Codable, Sendable { let raw: String }

/// HOW A MARK WAS MADE (Part 9.8's source enum; Part 20.1's Stamp row).
nonisolated enum MarkSource: String, Codable, Sendable, CaseIterable {
    case hand, quick, quickAdd, photos, history, here, tracking, ai, siri, pinNear, onboarding, imported, demo
}

/// WHO ACTED (Part 0.2.3, 20.1): every write carries it, so the undo, the motion and the sound are the same whoever did.
nonisolated enum Who: String, Codable, Sendable { case you, ai, siri, link, importer = "import", undo }

/// WHAT THE MAP READS PER PLACE (Part 0.2.3)
nonisolated struct MarkState: Equatable, Sendable {
    var stamped = false
    var visits = 0
    var transitOnly = false
    var lived = false
    var wished = false
    /// how badly, 1 to 5 (0: not wished)
    var want = 0
    static let none = MarkState()
}
