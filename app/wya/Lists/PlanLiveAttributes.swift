import ActivityKit
import Foundation

/// A PLAN ON THE LOCK SCREEN: what the app hands the Live Activity. The words are made by the app (PlanLive), the extension only lays them out;
/// the plan's map square is a picture the app keeps in the app group (live/<plan>.png). The extension holds an
/// identical copy of this file (wyaLive/PlanLiveAttributes.swift): ActivityKit matches the two by name.
nonisolated struct PlanLiveAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// the big line: "3 days to Bangkok", or on the trip the day's place
        var big: String
        /// the dates in numbers ("13–20.10"), or on the trip "Day 2 of 7"
        var dates: String
        /// the plan's other places, or on the trip the day's things
        var line: String
        /// the Dynamic Island's few letters ("3d", "Day 2")
        var short: String
    }
    /// the plan's id (its map square's file) and its name
    var plan: String
    var name: String

    static let group = "group.com.alexanderbell.wya"
    static func mapURL(_ plan: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("live", isDirectory: true).appendingPathComponent(plan + ".png")
    }
}
