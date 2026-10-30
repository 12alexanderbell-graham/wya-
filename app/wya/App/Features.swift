import Foundation

/// FEATURE FLAGS FOR THE FULL AND THE STRIPPED APP (Part 20.9, 20.12 item 11): one switch per part that can be left
/// out of a build, so the app can ship without the social parts at first and switch them on later without a rework.
/// The edition is read from the Info.plist key `WYAEdition` ("full" or "stripped"; full when absent); a debug build
/// can override one flag with UserDefaults "feature.<name>".
nonisolated enum Feature: String, CaseIterable, Sendable {
    case regions, places, pins, ai, uploads, lists, profile
    case friends, discover, solo, challenges, premium

    /// what the stripped edition leaves out (the social parts and the paid tier, until they are built and wanted)
    private static let strippedOut: Set<Feature> = [.friends, .discover, .solo, .challenges, .premium]

    static var edition: String { (Bundle.main.object(forInfoDictionaryKey: "WYAEdition") as? String) ?? "full" }

    var isOn: Bool {
        #if DEBUG
        if let o = UserDefaults.standard.object(forKey: "feature.\(rawValue)") as? Bool { return o }
        #endif
        return Self.edition == "stripped" ? !Self.strippedOut.contains(self) : true
    }
}
