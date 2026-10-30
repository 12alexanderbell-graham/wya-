import Foundation

/// WHOSE EACH PIECE OF LAND IS, under the borders view you pick: the old app's WorldGeometry (positionSays, assign,
/// pieceOwner, drawn, dotted, detailOwners), ported as it was, reading the old app's own disputes (world.json's
/// `disputes`, carried over unchanged into disputes.json: each disputed piece's controller, its options, the UN's
/// answer and every country's own map). His rule: - De facto: every place drawn as it is held (the controller of each
/// piece); nothing is dotted. - United Nations / de jure: a breakaway the UN doesn't recognise is dotted. - A country's
/// own view: a place that country doesn't recognise and gives to nobody is dotted; one it gives to another country is
/// drawn as part of that country.
enum Borders {
    enum View: Equatable, Sendable {
        case deFacto, unitedNations
        /// a country's own map, by Natural Earth's key (South Korea is KO)
        case country(String)
    }

    /// the view the map is drawn in (Map settings will set it; De facto until then)
    nonisolated(unsafe) static var view: View = .deFacto

    /// the places (indices into World.places) drawn dotted in the current view, set when the world is loaded
    nonisolated(unsafe) static var dottedPlaces: Set<Int> = []

    /// whether any place can be dotted in the current view
    static var anyDotted: Bool { !dottedPlaces.isEmpty }

    /// whether the place at this index (World.places) is drawn dotted in the current view
    static func dotted(_ place: Int?) -> Bool {
        guard let place else { return false }
        return dottedPlaces.contains(place)
    }
}

/// One disputed piece of land or disputed place (the old app's Dispute, the fields the map needs).
nonisolated struct Dispute: Decodable, Sendable {
    let id: String
    let name: String?
    let options: [String]
    let controller: String?
    let `default`: String
    let pref: String?
    let un: String?
    let host: String?
    let entity: String?
    let side: String?
    let owner: [String: String]?
    let claimants: [String]?
    /// a piece of land of its own in the topology (Crimea), not a whole place (Taiwan)
    let piece: Bool
}

nonisolated struct DisputeFile: Decodable, Sendable {
    let list: [Dispute]
    let views: [String]?
    let povs: [String]?
    let unrecognised: [String: [String]]?
    let jure: [String: String]?
}

nonisolated final class Positions: @unchecked Sendable {
    let disputes: [Dispute]
    let unrecognised: [String: [String]]
    let jure: [String: String]
    /// place id → kind ("country", "territory", "entity", "antarctica")
    let kind: [String: String]
    /// a place's short name → its id (the UN field names places by it)
    let byShort: [String: String]
    let view: Borders.View

    init(file: DisputeFile, places: [(id: String, short: String, kind: String)], view: Borders.View) {
        disputes = file.list
        unrecognised = file.unrecognised ?? [:]
        jure = file.jure ?? [:]
        var k: [String: String] = [:], s: [String: String] = [:]
        for p in places { k[p.id] = p.kind; s[p.short] = p.id }
        kind = k; byShort = s
        self.view = view
    }

    @inline(__always) private static func some(_ s: String?) -> String? { (s?.isEmpty ?? true) ? nil : s }

    /// ON THE DE FACTO MAP, NOTHING CARVED OUT: Bir Tawil, which no one holds, is drawn with Sudan, on whose side of
    /// the 22nd parallel (the line Egypt itself uses) it lies (author's call). Halaib is Egypt's already (its
    /// controller). Every other view keeps the data's own answer.
    static let deFactoGiven: [String: String] = ["bir-tawil": "sd"]

    /// What a view says about a piece: one of its options, or nil when it says nothing (WorldGeometry.positionSays).
    func says(_ d: Dispute, _ v: Borders.View) -> String? {
        switch v {
        case .deFacto:
            if let g = Self.deFactoGiven[d.id], d.options.contains(g) { return g }
            if let c = Self.some(d.controller), c != "none", d.options.contains(c) { return c }
            return nil
        case .unitedNations:
            if let un = Self.some(d.un), un != "none" {
                let u = byShort[un] ?? un
                return d.options.contains(u) ? u : nil
            }
            if let j = jure[d.id], d.options.contains(j) { return j }
            return nil
        case .country(let k):
            if let o = Self.some(d.owner?[k]), d.options.contains(o) { return o }
            return nil
        }
    }

    /// whose a disputed piece is: the view's answer, else the ground's, else the data's own default (assign/baseOf)
    func assign(_ d: Dispute) -> String {
        says(d, view) ?? says(d, .deFacto) ?? (Self.some(d.pref) ?? d.default)
    }

    /// an entity assigned away (Western Sahara to Morocco on the ground) is not drawn on its own
    func drawn(_ id: String) -> Bool {
        for d in disputes where d.entity == id && !d.piece && assign(d) != id { return false }
        return true
    }

    /// whose a disputed piece is drawn with: whose it is, or, when that place is not drawn because the view gives it
    /// to another (North Korea on South Korea's map), the place it went to (WorldGeometry.pieceOwner, Slice 111)
    func pieceOwner(_ d: Dispute) -> String {
        let a = assign(d)
        guard a != "none", kind[a] != nil, !drawn(a),
              let m = disputes.first(where: { $0.entity == a && !$0.piece && assign($0) != a }) else { return a }
        return assign(m)
    }

    /// an entity counts as a full country under the view (then it has no dots)
    func recognised(_ id: String) -> Bool {
        guard kind[id] == "entity" else { return false }
        guard let d = disputes.first(where: { $0.entity == id && $0.options.contains(id) }) else { return false }
        return says(d, view) == id
    }

    /// WHAT COUNTS AS A COUNTRY under the view (the old WorldGeometry.counts, Slice 88): a country or a breakaway while
    /// it is drawn on its own. A dotted one counts; one merged into another does not.
    func counts(_ id: String) -> Bool {
        guard let k = kind[id], drawn(id) else { return false }
        return k == "country" || k == "entity"
    }

    /// WHO A PLACE COUNTS AS (the old WorldGeometry.countedAs, Slice 88): itself while it is drawn on its own; else the
    /// place the view gives its land to (Taiwan on China's map counts as China). The stamp itself never changes, only
    /// what it counts for.
    func countedAs(_ id: String) -> String {
        var cur = id
        for _ in 0 ..< 4 {
            guard !drawn(cur), let d = disputes.first(where: { $0.entity == cur && !$0.piece && assign($0) != cur })
            else { return cur }
            let o = assign(d)
            guard o != "none", kind[o] != nil else { return cur }
            cur = o
        }
        return cur
    }

    /// A DOTTED PLACE (Slice 88): drawn on its own but not recognised by the view. On a country's own map, the places
    /// that country does not recognise and gives to nobody; on the UN's, a breakaway the UN does not call its own. On
    /// the ground's (De facto) nothing is dotted.
    func dotted(_ id: String) -> Bool {
        guard view != .deFacto, drawn(id), let k = kind[id] else { return false }
        if case .country(let key) = view, let u = unrecognised[key], u.contains(id) { return true }
        return k == "entity" && !recognised(id)
    }

    /// what a search result calls a place in this view: a breakaway held on its own is a country on the ground,
    /// disputed where the view doesn't recognise it or gives its land to another
    func kindName(_ id: String) -> String {
        switch kind[id] {
        case "country": return "Country"
        case "territory": return "Territory"
        case "antarctica": return "Continent"
        case "entity": return drawn(id) && !dotted(id) && (view == .deFacto || recognised(id)) ? "Country" : "Disputed"
        default: return ""
        }
    }

    /// Whose each unit of the world file is ("ru|Europe", "piece:crimea"): a drawn place's own objects, a piece to
    /// whom it is drawn with, and the whole of an entity assigned away to the place it is given to; nil: nobody's
    /// (Bir Tawil). `objOwner` is the place each topology object belongs to.
    func unitOwner(_ key: String, objOwner: [String: String]) -> String? {
        if key.hasPrefix("piece:") {
            let id = String(key.dropFirst(6))
            guard let d = disputes.first(where: { $0.id == id }) else { return nil }
            let o = pieceOwner(d)
            return kind[o] != nil ? o : nil
        }
        guard let p = objOwner[key] else { return nil }
        if drawn(p) { return p }
        guard let d = disputes.first(where: { $0.entity == p && !$0.piece && assign($0) != p }) else { return p }
        let o = assign(d)
        return kind[o] != nil ? o : nil
    }

    /// the detailed tiles' items ("o:<object>", "p:<piece>") with whose each is in this view (WorldGeometry.detailOwners)
    func detailOwners(objOwner: [String: String], pieces: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for o in objOwner.keys { if let w = unitOwner(o, objOwner: objOwner) { out["o:" + o] = w } }
        for p in pieces { if let w = unitOwner("piece:" + p, objOwner: objOwner) { out["p:" + p] = w } }
        return out
    }
}
