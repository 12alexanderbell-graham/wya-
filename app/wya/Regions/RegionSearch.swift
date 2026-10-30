import Foundation

/// SEARCH ON A REGION MAP (6.5: "search: this country's regions at every level"): the open country's regions at every
/// level the phone has (the bundled first level and any finer one already come), names starting with what was typed
/// first, then names holding it; coarser levels before finer ones; at most eight.
@MainActor
enum RegionSearch {
    struct Hit: Hashable {
        let row: Int
        let id: String
        let name: String
        /// what it is, the level's singular word ("department")
        let word: String
        var key: String { "\(row)|\(id)" }
    }
    /// each level's names folded once (key "fr-2")
    private static var names: [String: [(folded: String, id: String, name: String)]] = [:]

    static func hits(_ query: String, place id: String) -> [Hit] {
        let q = SearchResults.fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return [] }
        var starts: [Hit] = [], inside: [Hit] = []
        for (row, level) in RegionCatalog.shared.used(id) {
            let key = "\(id)-\(row)"
            if names[key] == nil, let f = RegionCatalog.shared.file(id, row: row) {
                var seen = Set<String>()
                names[key] = f.units.compactMap { u in seen.insert(u.id).inserted ? (SearchResults.fold(u.name), u.id, u.name) : nil }
            }
            let word = RegionsMenuModel.word(level.one)
            for n in names[key] ?? [] {
                if n.folded.hasPrefix(q) { starts.append(Hit(row: row, id: n.id, name: n.name, word: word)) }
                else if q.count >= 3, n.folded.contains(q) { inside.append(Hit(row: row, id: n.id, name: n.name, word: word)) }
                if starts.count >= 8 { break }
            }
            if starts.count >= 8 { break }
        }
        return Array((starts + inside).prefix(8))
    }
}
