import Foundation

/// THE TABS' ONE OWNER (Part 20.2, 20.12 item 1): which tab is chosen, what each tab closes when you leave it (search,
/// the tools, settings, the undo drop, an open card: each registers its own closer), and each tab's reset when its
/// tab is tapped again (the Map: to 25% and home). Built in Step 3; the tab bar is moved onto it in Step 8, with
/// Apple's TabView and each tab kept alive while away.
@MainActor
@Observable
final class TabCoordinator {
    static let shared = TabCoordinator()
    enum Tab: Int, CaseIterable, Sendable { case map, lists, profile }

    private(set) var tab: Tab = .map
    @ObservationIgnored private var closers: [Tab: [String: () -> Void]] = [:]
    @ObservationIgnored private var resets: [Tab: () -> Void] = [:]

    /// something that must close when its tab is left registers here under its own id (registering again replaces it)
    func onLeave(_ tab: Tab, id: String, close: @escaping () -> Void) { closers[tab, default: [:]][id] = close }
    func onReset(_ tab: Tab, reset: @escaping () -> Void) { resets[tab] = reset }

    /// a tab tapped: another tab closes what the current one has open, unseen, in the switch's frame; the same tab resets
    func select(_ t: Tab) {
        if t == tab { resets[t]?(); return }
        for c in (closers[tab] ?? [:]).values { c() }
        tab = t
    }
}
