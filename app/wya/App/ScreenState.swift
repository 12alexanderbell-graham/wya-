import Foundation

/// WHAT IS ON SCREEN (Part 20.7.1), as one value: what the AI is given while it is in use, what Siri and App Intents
/// read, and what a deep link restores. Made on demand from the live objects (`ScreenStateSource.now()`), so it costs
/// nothing while nobody asks; the AI step publishes it on every discrete change and when the camera settles.
/// The fields are the ones the built app has today; each part adds its own as it lands (Part 20.7.1's full list).
nonisolated struct ScreenState: Equatable, Sendable {
    enum Tab: String, Sendable { case map, lists, profile }
    var tab: Tab = .map
    /// the borders view's name ("deFacto", "UN", a country's key)
    var borders = "deFacto"
    var mode = "countries"
    var continent: String?
    /// the camera's box in longitude and latitude: west, south, east, north
    var cameraBox: [Double] = []
    /// the moon's stop: 0 Both, 1 Stamped, 2 Stamped+, 3 Wishlist+, 4 Wishlist
    var filter = 0
    var waterStop = "quarter"
    var searchText: String?
    var locked = false
    var toolsOpen = false
    var settingsOpen = false
    var sunPicked = false
    /// your count as the caption shows it
    var count = 0
    var total = 0
}

/// Who makes the screen state: the Map's live objects, read on the main thread.
@MainActor
struct ScreenStateSource {
    let map: MapController
    let water: Water
    let head: HeadState
    let tab: () -> Int

    func now() -> ScreenState {
        var s = ScreenState()
        s.tab = [ScreenState.Tab.map, .lists, .profile][min(2, max(0, tab()))]
        switch Borders.view {
        case .deFacto: s.borders = "deFacto"
        case .unitedNations: s.borders = "UN"
        case .country(let k): s.borders = k
        }
        s.mode = "\(head.mode)"
        s.continent = map.continent
        s.cameraBox = map.cameraBox()
        s.filter = map.filter
        s.waterStop = "\(water.stop)"
        s.searchText = head.searching ? head.query : nil
        s.locked = map.locked
        s.toolsOpen = head.toolsOpen
        s.settingsOpen = head.settingsOpen
        s.sunPicked = map.sunPicked
        let c = map.count
        s.count = c.n; s.total = c.of
        return s
    }
}
