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
        if let u = Self.url, let d = try? Data(contentsOf: u), let b = try? JSONDecoder().decode(ListsBook.self, from: d) { book = b }
        if !book.lists.contains(where: \.wish) {
            book.lists.insert(MyList(id: "wish", name: "Wishlist", wish: true), at: 0)
        }
    }

    /// a change to the book, written when it changed anything
    func change(_ f: (inout ListsBook) -> Void) {
        var b = book
        f(&b)
        guard b != book else { return }
        book = b
        guard let u = Self.url else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(b) { try? d.write(to: u, options: .atomic) }
    }
}
