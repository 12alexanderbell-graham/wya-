import SwiftUI

/// THE MOMENT A BADGE IS EARNED (P07 §6, Apple's Fitness way): when a count after your marks change takes a badge to a
/// new level, its solid turns in once from the side and comes to rest facing you, its name and level under it; Done
/// shows the next one earned at the same time, then closes. Nothing spins on its own and nothing is played.
/// The levels already shown are kept, so a level is shown once, and the first full count only notes what you have
/// (badges you earned before this moment existed are not shown again).
@MainActor @Observable
final class BadgeMoment {
    static let shared = BadgeMoment()
    /// the badges earned and not yet shown, the highest level first
    private(set) var queue: [Badge] = []
    var current: Badge? { queue.first }
    private static let key = "wya.badges.seen"
    private static let whenKey = "wya.badges.when"

    /// the day a badge reached a level, where the app saw it happen
    static func day(_ id: String, _ level: Int) -> Date? {
        (UserDefaults.standard.dictionary(forKey: whenKey)?["\(id)|\(level)"] as? Double).map { Date(timeIntervalSince1970: $0) }
    }

    /// after a full count (the badges' pack in): the queue is what is above the levels already shown. The first count
    /// notes every badge the app has (0 where none is held), so a badge the app adds later is noted, not shown; a
    /// level is noted as seen when its moment is closed, so one lost to an undo or to quitting is not lost for good.
    /// At most three at once: the rest (an import of a year's photos) are noted without a moment.
    func counted(_ earned: [Badge], catalog: [String]) {
        let d = UserDefaults.standard
        let now = Badges.seen(earned)
        guard var seen = d.dictionary(forKey: Self.key) as? [String: Int] else {
            var s = now
            for id in catalog where s[id] == nil { s[id] = 0 }
            d.set(s, forKey: Self.key)
            return
        }
        // the day each level was first counted (from the first count on: before it, the day is not known)
        var days = d.dictionary(forKey: Self.whenKey) as? [String: Double] ?? [:]
        let today = Date().timeIntervalSince1970
        var dated = false
        for b in earned where b.level > 0 && days["\(b.id)|\(b.level)"] == nil && b.level > (seen[b.id] ?? b.level) {
            days["\(b.id)|\(b.level)"] = today
            dated = true
        }
        if dated { d.set(days, forKey: Self.whenKey) }
        var noted = false
        for id in catalog where seen[id] == nil { seen[id] = now[id] ?? 0; noted = true }
        var fresh = earned.filter { b in seen[b.id].map { b.level > $0 } ?? false }
            .sorted { $0.level != $1.level ? $0.level > $1.level : $0.name < $1.name }
        // (the one up now stays first while it is still earned)
        if let up = queue.first, let i = fresh.firstIndex(where: { $0.id == up.id }) { fresh.insert(fresh.remove(at: i), at: 0) }
        if fresh.count > 3 {
            for b in fresh.dropFirst(3) { seen[b.id] = b.level }
            fresh = Array(fresh.prefix(3))
            noted = true
        }
        if noted { d.set(seen, forKey: Self.key) }
        if fresh.map(\.id) != queue.map(\.id) || fresh.map(\.level) != queue.map(\.level) { queue = fresh }
    }

    #if DEBUG
    /// the test driver's `action review.badgemoment`: the two highest badges you have, as if just earned
    func show(_ bs: [Badge]) { queue = bs }
    #endif

    func next() {
        guard let b = queue.first else { return }
        let d = UserDefaults.standard
        var seen = d.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
        seen[b.id] = max(seen[b.id] ?? 0, b.level)
        d.set(seen, forKey: Self.key)
        queue.removeFirst()
    }

    /// counted again a moment after your marks change (an undo and signing out too), and when the lists the count reads
    /// come in, wherever you are, so a badge earned shows then
    static func watch(map: MapController) async {
        final class Dirty { var on = true }
        let dirty = Dirty()
        let token = MarkStore.shared.listen { _ in dirty.on = true }
        defer { MarkStore.shared.stopListening(token) }
        var asked = ""
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1500))
            let ask = ProfileNumbers.shared.asks
            guard dirty.on || ask != asked, BadgeStore.shared.ready else { continue }
            dirty.on = false
            asked = ask
            await ProfileNumbers.shared.count(map: map)
        }
    }
}

struct BadgeMomentView: View {
    let L: Layout
    @State private var moment = BadgeMoment.shared
    @Environment(\.dynamicTypeSize) private var type
    /// a tap sends it away into the Profile tab's triangle
    @State private var leaving = false

    var body: some View {
        ZStack {
            if let b = moment.current {
                // a sheet of clear Liquid Glass over everything, rising as a sheet does and going down when the last
                // one is sent away
                let sheet = RoundedRectangle(cornerRadius: L.sheetCorner, style: .continuous)
                Color.clear
                    .glassEffect(.clear, in: sheet)
                    .frame(width: L.W - 2 * L.sheetInset, height: L.H - 2 * L.sheetInset)
                    .position(x: L.W / 2, y: L.H / 2)
                    .frame(width: L.W, height: L.H)
                    .transition(.move(edge: .bottom))
                page(b)
                    .id(b.id)
                    .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .identity))
            }
        }
        .animation(Motion.chrome, value: moment.current?.id)
    }

    /// PR05: the badge big in the middle, turning in once, its name and level under it, on the frost; a tap anywhere
    /// sends it into the Profile tab's mark, then the next one comes
    private func page(_ b: Badge) -> some View {
        let w = L.W - 2 * L.side
        // (as wide as the page lets it be, in its own shape: a range's tile was a small strip in a square of nothing)
        let size = min(type.isAccessibilitySize ? 200 : 320, w)
        // the triangle's middle in the tab capsule (the third of three across it)
        let tri = CGPoint(x: L.capsule.minX + 4 + (L.capsule.width - 8) / 3 * 2.5, y: L.capsule.midY)
        let mid = CGPoint(x: L.W / 2, y: L.H * 0.46)
        return ZStack {
            // (every touch is the moment's while it is up)
            Color.clear.contentShape(Rectangle())
            VStack(spacing: 0) {
                BadgeLiveView(badge: b, size: size, intro: true, hug: true)
                Text(b.name).font(.title.weight(.semibold)).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center).padding(.top, 16)
                // (no level word under it: the badge's own look says its level, 10 Oct)
            }
            .frame(width: w)
            .scaleEffect(leaving ? 0.06 : 1)
            .position(leaving ? tri : mid)
        }
        .frame(width: L.W, height: L.H)
        .contentShape(Rectangle())
        .onTapGesture { leave() }
        .onAppear {
            // (the knock only: a badge is not a stamp landing)
            Feel.stamp(sound: false)
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityHint("Double-tap to close")
        .accessibilityAction(.escape) { leave() }
        .accessibilityAction(named: "Close") { leave() }
    }

    private func leave() {
        guard !leaving, let id = moment.current?.id else { return }
        Feel.tap()
        withAnimation(Motion.reduce ? .linear(duration: 0.01) : .easeIn(duration: 0.4)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Motion.reduce ? 0.02 : 0.4)) {
            // (the one sent away goes at once, already small in the triangle; the next rises from the bottom)
            // (only the one sent away is noted as seen: a recount in the meantime may have changed the queue)
            withAnimation(Motion.chrome) {
                leaving = false
                if moment.current?.id == id { moment.next() }
            }
        }
    }
}
