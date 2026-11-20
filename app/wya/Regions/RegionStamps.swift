import Foundation

/// STAMPING A REGION STAMPS ITS PARENTS (6.2, A6.12): a department stamped stamps its region too, a commune its canton,
/// arrondissement, department and region. The chain is read from each level's `p` (the unit's parent one level up),
/// going up through the country's levels in use, coarser each time; a level not on the phone is fetched (or the chain
/// stops there). Parents already stamped are left as they are; parents add no second haptic. Unstamping takes back the
/// parents stamped only through that region.
enum RegionStamps {
    /// the region `unit` of `scene`, and every parent above it, stamped
    @MainActor
    static func stamp(_ unit: Int, in scene: RegionScene, source: MarkSource) async {
        // one undo step for the region and its parents, named by the region tapped
        await MarkStore.shared.grouped { await stampChain(unit, in: scene, source: source) }
    }
    /// the same for a region named without its map drawn (Details' region chips): its id, name and parent at level
    /// `row` of place `cc`
    @MainActor
    static func stamp(id: String, name: String, parent: String?, cc: String, row: Int, source: MarkSource) async {
        await MarkStore.shared.grouped { await stampChain(id: id, name: name, parent: parent, cc: cc, row: row, source: source) }
    }
    @MainActor
    private static func stampChain(_ unit: Int, in scene: RegionScene, source: MarkSource) async {
        await stampChain(id: scene.unitIDs[unit], name: RegionNames.english(scene.id, scene.unitNames[unit]), parent: scene.unitParents[unit],
                         cc: scene.id, row: scene.row, source: source)
    }
    @MainActor
    private static func stampChain(id: String, name unitName: String, parent: String?, cc: String, row: Int,
                                   source: MarkSource) async {
        // (the country the region stamps with it, when it was not stamped before, is held only through it)
        let had = MarkStore.shared.state(.country(cc)).stamped
        await MarkStore.shared.stamp(PlaceKey(.region, id), name: unitName, cc: cc, level: row, source: source)
        if !had, MarkStore.shared.state(.country(cc)).stamped { TownStamps.remember(cc) }
        // stamped by hand at its own level: no longer
        forget(id)
        for (pid, name, row) in await parents(parent, cc: cc, row: row) {
            let key = PlaceKey(.region, pid)
            guard !MarkStore.shared.state(key).stamped else { continue }
            await MarkStore.shared.stamp(key, name: name, cc: cc, level: row, source: source)
            remember(pid)
        }
    }

    /// THE UNSTAMP RULE: the region, then each parent stamped only through it, nearest first, stopping at the first
    /// that stays
    @MainActor
    static func unstamp(_ unit: Int, in scene: RegionScene) async {
        await MarkStore.shared.grouped { await unstampChain(unit, in: scene) }
    }
    /// the same for a region named without its map drawn (Details' region chips)
    @MainActor
    static func unstamp(id: String, name: String, parent: String?, cc: String, row: Int) async {
        await MarkStore.shared.grouped { await unstampChain(id: id, name: name, parent: parent, cc: cc, row: row) }
    }
    @MainActor
    private static func unstampChain(_ unit: Int, in scene: RegionScene) async {
        await unstampChain(id: scene.unitIDs[unit], name: RegionNames.english(scene.id, scene.unitNames[unit]), parent: scene.unitParents[unit],
                           cc: scene.id, row: scene.row)
    }
    @MainActor
    private static func unstampChain(id: String, name unitName: String, parent: String?, cc: String, row: Int) async {
        await MarkStore.shared.unstamp(PlaceKey(.region, id), name: unitName)
        forget(id)
        // the level the children are on, starting with this one
        var childRow = row
        for (pid, name, row) in await parents(parent, cc: cc, row: row) {
            guard through.contains(pid), MarkStore.shared.state(PlaceKey(.region, pid)).stamped,
                  let f = await RegionCatalog.shared.fetch(cc, row: childRow) else { break }
            let held = f.units.contains { $0.parent == pid && MarkStore.shared.state(PlaceKey(.region, $0.id)).stamped }
            if held { break }
            await MarkStore.shared.unstamp(PlaceKey(.region, pid), name: name)
            forget(pid)
            childRow = row
        }
        // and its country, if this region was all that held it
        await TownStamps.release(cc)
    }

    /// the regions stamped only through a child (kept on the phone with the marks' account)
    private static let throughKey = "wya.regions.through"
    @MainActor private static var through: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: throughKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: throughKey) }
    }
    @MainActor private static func remember(_ id: String) { through.insert(id) }
    @MainActor private static func forget(_ id: String) { through.remove(id) }

    /// the parents of a region, nearest first: (id, name, row)
    static func parents(of unit: Int, in scene: RegionScene) async -> [(String, String, Int)] {
        await parents(scene.unitParents[unit], cc: scene.id, row: scene.row)
    }
    /// the same from a region's parent id, its place and level
    static func parents(_ first: String?, cc: String, row at0: Int) async -> [(String, String, Int)] {
        // the levels coarser than this one, nearest first (the table's `used` order is coarsest first)
        let used = RegionCatalog.shared.used(cc).map(\.row)
        guard let at = used.firstIndex(of: at0) else { return [] }
        var out: [(String, String, Int)] = []
        var parent = first
        for row in used[..<at].reversed() {
            guard let pid = parent, let f = await RegionCatalog.shared.fetch(cc, row: row),
                  let u = f.units.first(where: { $0.id == pid }) else { break }
            out.append((u.id, u.name, row))
            parent = u.parent
        }
        return out
    }
}
