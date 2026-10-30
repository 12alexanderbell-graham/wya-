import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "DID YOU MEAN" WITH APPLE INTELLIGENCE (Part 1.10, step 2): the on-device model picks the one place among the
/// nearest names that the typed text most likely meant, or nothing. The answer must be one of those names exactly;
/// anything else is no answer. Never waits more than 1.5 s; without Apple Intelligence it answers nothing at once.
enum SmartGuess {
    static func pick(typed: String, among names: [String]) async -> String? {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: """
            You fix typos in a search for a country or territory. Reply with exactly one name copied from the list, \
            or with NONE if none of them is what was meant. No other words.
            """)
        let prompt = "Typed: \(typed)\nList: \(names.joined(separator: "; "))"
        let answer: String? = await withTaskGroup(of: String?.self) { g in
            g.addTask { (try? await session.respond(to: prompt))?.content }
            g.addTask { try? await Task.sleep(for: .milliseconds(1500)); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
        guard let a = answer?.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) else { return nil }
        return names.first { $0.caseInsensitiveCompare(a) == .orderedSame }
        #else
        return nil
        #endif
    }

    /// whether the model can be asked on this phone (logged by the test driver)
    static var available: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }
}
