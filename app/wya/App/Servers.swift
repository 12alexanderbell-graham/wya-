import Foundation

/// THE SERVERS, BEHIND PROTOCOLS (Part 20.10, 20.12 item 12): every part asks through one of these, so the Map works
/// with no account and offline, and the real clients (the Mac's dev server first, then Cloudflare R2 and Supabase,
/// Step 16) drop in without touching the parts. Until then each is its offline answer.
nonisolated enum ServerAnswer<T: Sendable>: Sendable {
    case ok(T)
    /// no network, or the server could not be reached: the part says so in its own place ("Needs internet")
    case offline
    /// the server has no such thing (a page that doesn't exist)
    case missing
}

/// place pages not bundled (Part 16)
protocol PageClient: Sendable { func page(_ key: PlaceKey) async -> ServerAnswer<Data> }
/// the data files on the server: finer region levels, other towns, things, collections (Part 17.7)
protocol DataClient: Sendable { func file(_ path: String) async -> ServerAnswer<Data> }
/// Verify: the server agrees a stamp is proven (Part 4.5)
protocol VerifyClient: Sendable { func verify(_ key: PlaceKey, proof: Data) async -> ServerAnswer<Bool> }
/// the AI (its key never in the app: a small server holds it, Part 20.10)
protocol AIClient: Sendable { func ask(_ request: Data) async -> ServerAnswer<Data> }

/// the offline answer for all four, used until the real clients exist
nonisolated struct OfflineServers: PageClient, DataClient, VerifyClient, AIClient {
    func page(_ key: PlaceKey) async -> ServerAnswer<Data> { .offline }
    func file(_ path: String) async -> ServerAnswer<Data> { .offline }
    func verify(_ key: PlaceKey, proof: Data) async -> ServerAnswer<Bool> { .offline }
    func ask(_ request: Data) async -> ServerAnswer<Data> { .offline }
}

/// which client each part uses (one place to switch them)
nonisolated enum Servers {
    static let pages: PageClient = OfflineServers()
    /// the data files: the Mac's dev server while developing (DataServer.swift)
    static let data: DataClient = DevDataClient()
    static let verify: VerifyClient = OfflineServers()
    static let ai: AIClient = OfflineServers()
}
