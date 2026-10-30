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
        // the first of the answer and the 1.5 s cap wins; the model is never waited for past it (a task group would
        // wait for every child, so the cap would hold only if the model stopped when cancelled)
        let answer: String? = await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let once = Once(c)
            let work = Task { once.resume((try? await session.respond(to: prompt))?.content) }
            Task { try? await Task.sleep(for: .milliseconds(1500)); work.cancel(); once.resume(nil) }
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

/// resumes a continuation once; later calls do nothing
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var c: CheckedContinuation<String?, Never>?
    init(_ c: CheckedContinuation<String?, Never>) { self.c = c }
    func resume(_ v: String?) {
        lock.lock(); let k = c; c = nil; lock.unlock()
        k?.resume(returning: v)
    }
}
