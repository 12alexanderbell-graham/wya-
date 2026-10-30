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
        let id = scene.unitIDs[unit]
        await MarkStore.shared.stamp(PlaceKey(.region, id), name: scene.unitNames[unit], cc: scene.id, level: scene.row,
                                     source: source)
        // stamped by hand at its own level: no longer "only through a child"
        forget(id)
        for (pid, name, row) in await parents(of: unit, in: scene) {
            let key = PlaceKey(.region, pid)
            guard !MarkStore.shared.state(key).stamped else { continue }
            await MarkStore.shared.stamp(key, name: name, cc: scene.id, level: row, source: source)
            remember(pid)
        }
    }

    /// THE UNSTAMP RULE (23 Oct 16:17: a parent goes only if it was stamped through that region; one you
    /// stamped yourself, or one another stamped child still holds, stays): the region, then each parent stamped only
    /// through it, nearest first, stopping at the first that stays
    @MainActor
    static func unstamp(_ unit: Int, in scene: RegionScene) async {
        let id = scene.unitIDs[unit]
        await MarkStore.shared.unstamp(PlaceKey(.region, id), name: scene.unitNames[unit])
        forget(id)
        // the level the children are on, starting with this one
        var childRow = scene.row
        for (pid, name, row) in await parents(of: unit, in: scene) {
            guard through.contains(pid), MarkStore.shared.state(PlaceKey(.region, pid)).stamped,
                  let f = await RegionCatalog.shared.fetch(scene.id, row: childRow) else { break }
            let held = f.units.contains { $0.parent == pid && MarkStore.shared.state(PlaceKey(.region, $0.id)).stamped }
            if held { break }
            await MarkStore.shared.unstamp(PlaceKey(.region, pid), name: name)
            forget(pid)
            childRow = row
        }
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
        // the levels coarser than this one, nearest first (the table's `used` order is coarsest first)
        let used = RegionCatalog.shared.used(scene.id).map(\.row)
        guard let at = used.firstIndex(of: scene.row) else { return [] }
        var out: [(String, String, Int)] = []
        var parent = scene.unitParents[unit]
        for row in used[..<at].reversed() {
            guard let pid = parent, let f = await RegionCatalog.shared.fetch(scene.id, row: row),
                  let u = f.units.first(where: { $0.id == pid }) else { break }
            out.append((u.id, u.name, row))
            parent = u.parent
        }
        return out
    }
}
