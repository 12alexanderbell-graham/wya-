import Foundation

/// YOUR LISTS, PLANS, TIER LISTS AND BOOKS, kept on the phone (Application Support, lists.json), written once per
/// change. The wishlist list is always there and always first; nothing is ever made up (an empty book is empty).
@MainActor
@Observable
final class ListsStore {
    static let shared = ListsStore()
    private(set) var book = ListsBook()

    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("lists.json")
    }
    private init() {
        // (a file there that can't be read is moved beside itself, never written over by the next change: every list,
        // plan and book would have gone with one bad read, 26 Nov)
        if let u = Self.url, let d = try? Data(contentsOf: u) {
            if let b = try? JSONDecoder().decode(ListsBook.self, from: d) { book = b } else { PinRoutes.putAside(u) }
        }
        if !book.lists.contains(where: \.wish) {
            book.lists.insert(MyList(id: "wish", name: "Wishlist", wish: true), at: 0)
        }
    }

    /// a change to the book, written when it changed anything
    func change(_ f: (inout ListsBook) -> Void) {
        var b = book
        f(&b)
        guard b != book else { return }
        // (a plan changed: the lock screen's plan worked out again, PlanLive)
        let plansChanged = b.plans != book.plans
        book = b
        if plansChanged { PlanLive.changed() }
        guard let u = Self.url else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(b) { try? d.write(to: u, options: .atomic) }
    }
}
