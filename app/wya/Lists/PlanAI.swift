import SwiftUI

/// THE AI PLANS IT IN FRONT OF YOU. Asked through Siri: wya opens on Lists > Plans with the new plan open, its name
/// at the top and the AI's needle turning; when the AI's plan comes, its days come in one after another, then the
/// line on why it is shaped that way and Keep. Until Keep it is not among your plans (it stays in the app's data).
@MainActor
enum PlanAI {
    /// the plan being made (its page shows the needle turning until its days come)
    static var making: String? {
        get { ListsState.shared.planning }
        set { ListsState.shared.planning = newValue }
    }

    static func make(_ request: String, name: String) {
        let p = Plan(name: name, start: "", days: [], ai: true)
        ListsStore.shared.change { $0.plans.append(p) }
        let s = ListsState.shared
        s.kind = 1
        s.open = p.id
        s.naming = false
        making = p.id
        Task {
            // (from a cold launch the tabs listen only once the app is up)
            for _ in 0 ..< 60 where !(AIContext.map?.ready ?? false) { try? await Task.sleep(for: .milliseconds(100)) }
            NotificationCenter.default.post(name: Notification.Name("wyaTestTab"), object: 1)
            let r = await AIService.plan(request, context: AIContext.current())
            switch r {
            case .success(let d): await reveal(d, into: p.id)
            case .failure(let f):
                change(p.id) { $0.note = f.words }
                making = nil
                Feel.refuse()
            }
        }
    }

    /// the days come in one after another, each thing in its day a beat after the last
    private static func reveal(_ d: AIService.PlanDraft, into id: String) async {
        if !d.name.isEmpty { change(id) { $0.name = String(d.name.prefix(60)) } }
        making = nil
        for day in d.days {
            withAnimation(Motion.chrome) { change(id) { $0.days.append(PlanDay()) } }
            try? await Task.sleep(for: .milliseconds(140))
            for it in day.items {
                let at = it.at.trimmingCharacters(in: .whitespaces)
                let item = PlanItem(at: at.isEmpty ? nil : at, what: it.what, place: it.place, cc: it.cc.isEmpty ? nil : it.cc.lowercased())
                withAnimation(Motion.chrome) { change(id) { p in p.days[p.days.count - 1].items.append(item) } }
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
        withAnimation(Motion.chrome) { change(id) { $0.note = d.note } }
        Feel.notch()
    }

    private static func change(_ id: String, _ f: (inout Plan) -> Void) {
        ListsStore.shared.change { b in if let i = b.plans.firstIndex(where: { $0.id == id }) { f(&b.plans[i]) } }
    }
}
