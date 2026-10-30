import Foundation

/// WHERE MAP SETTINGS ARE (one owner for the sheet and for search): the pushed page, the row whose choices are open,
/// the dispute open on the Disputes page, and the row to bring into view
@MainActor
@Observable
final class SettingsNav {
    static let shared = SettingsNav()
    var path: [String] = []
    var open: String?
    var openDispute: String?
    /// a row to scroll to (a search result), cleared once shown
    var show: String?
}

/// SEARCH WITH MAP SETTINGS OPEN (Part 3.4, 5.11): the field searches the settings instead of the map: every row and
/// its choices, every borders view (country) and every dispute. A result opens its page with the row shown (and a
/// row's choices open), so the setting is one tap away.
@MainActor
enum SettingsSearch {
    struct Hit: Hashable {
        /// "row:<id>", "view:<key>", "dispute:<piece>"
        let id: String
        let name: String
        let note: String
    }

    static func hits(_ query: String, map: MapController) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return [] }
        func has(_ s: String) -> Bool { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) }
        func starts(_ s: String) -> Bool { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).hasPrefix(q) }
        let s = MapSettingsStore.shared.value
        var out: [(Hit, Int)] = []
        for row in MapSettingsRows.all where row.shows(s) && row.page != "all" {
            let choices = MapSettingsRows.choices(row, s)
            if has(row.name) {
                out.append((Hit(id: "row:\(row.id)", name: row.name, note: row.page == nil ? row.valueName(s) : ""), starts(row.name) ? 0 : 1))
            } else if let c = choices.first(where: { has($0.name) }) {
                out.append((Hit(id: "row:\(row.id)", name: row.name, note: c.name), 2))
            }
        }
        if has("United Nations") { out.append((Hit(id: "view:un", name: "United Nations", note: "Borders"), 1)) }
        if has("De facto") { out.append((Hit(id: "view:deFacto", name: "De facto", note: "Borders"), 1)) }
        let views = (Bundle.main.url(forResource: "disputes", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(DisputeFile.self, from: $0) }?.views) ?? []
        for k in views {
            let n = BordersNames.name(k, map)
            if has(n) { out.append((Hit(id: "view:\(k)", name: n, note: "Borders"), starts(n) ? 1 : 3)) }
        }
        for d in map.world?.positions?.disputes ?? [] {
            let n = d.name ?? d.id
            if has(n) { out.append((Hit(id: "dispute:\(d.id)", name: n, note: "Disputes"), starts(n) ? 1 : 3)) }
        }
        return out.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name < $1.0.name }.prefix(8).map(\.0)
    }

    /// a result picked: its page, the row shown, a row's choices open
    static func go(_ id: String) {
        let nav = SettingsNav.shared
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "row":
            let row = MapSettingsRows.all.first { $0.id == parts[1] }
            if let page = row?.page { nav.path = [page]; nav.show = nil } else { nav.path = []; nav.open = parts[1]; nav.show = parts[1] }
        case "view":
            nav.path = ["borders"]; nav.show = "view:" + parts[1]
        case "dispute":
            nav.path = ["disputes"]; nav.openDispute = parts[1]; nav.show = "dispute:" + parts[1]
        default: break
        }
    }
}
