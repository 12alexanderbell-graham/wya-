import Foundation

/// STAMPING A REGION STAMPS ITS PARENTS (6.2, A6.12): a department stamped stamps its region too, a commune its canton,
/// arrondissement, department and region. The chain is read from each level's `p` (the unit's parent one level up),
/// going up through the country's levels in use, coarser each time; a level not on the phone is fetched (or the chain
/// stops there). Parents already stamped are left as they are; parents add no second haptic.
enum RegionStamps {
    /// the region `unit` of `scene`, and every parent above it, stamped
    @MainActor
    static func stamp(_ unit: Int, in scene: RegionScene, source: MarkSource) async {
        let id = scene.unitIDs[unit]
        await MarkStore.shared.stamp(PlaceKey(.region, id), name: scene.unitNames[unit], cc: scene.id, level: scene.row,
                                     source: source)
        for (pid, name, row) in await parents(of: unit, in: scene) {
            let key = PlaceKey(.region, pid)
            guard !MarkStore.shared.state(key).stamped else { continue }
            await MarkStore.shared.stamp(key, name: name, cc: scene.id, level: row, source: source)
        }
    }

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
