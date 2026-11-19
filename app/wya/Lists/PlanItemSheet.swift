import SwiftUI

/// A THING IN A PLAN, ITS SHEET. Half the screen, up to full; no title. What it is, all day or from a time to a time,
/// where, a link, a note, and its colour. Every change is kept at once; dragging the sheet down is done.
struct PlanItemSheet: View {
    let planID: String
    let day: Int
    let itemID: String
    @State private var store = ListsStore.shared
    @Environment(\.dismiss) private var dismiss
    /// a new thing (no words yet) starts with the words being typed
    @FocusState private var naming: Bool

    /// the colours a thing can have (none first), as the app's palette names
    static let colours = ["", "red", "yellow", "lime", "teal", "blue", "brown", "grey"]

    private var item: PlanItem? {
        guard let p = store.book.plans.first(where: { $0.id == planID }), p.days.indices.contains(day) else { return nil }
        return p.days[day].items.first { $0.id == itemID }
    }
    private func change(_ f: @escaping (inout PlanItem) -> Void) {
        ListsStore.shared.change { b in
            guard let pi = b.plans.firstIndex(where: { $0.id == planID }), b.plans[pi].days.indices.contains(day),
                  let ii = b.plans[pi].days[day].items.firstIndex(where: { $0.id == itemID }) else { return }
            f(&b.plans[pi].days[day].items[ii])
            b.plans[pi].sortDay(day)
        }
    }

    var body: some View {
        if let it = item {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("", text: Binding(get: { it.what }, set: { v in change { $0.what = String(v.prefix(120)) } }),
                              prompt: Text("What").foregroundStyle(Palette.ink.opacity(0.5)), axis: .vertical)
                        .font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                        .focused($naming)
                        .onAppear { if it.what.isEmpty { naming = true } }
                        .frame(minHeight: 52)
                    // ALL DAY, OR FROM A TIME TO A TIME
                    Toggle(isOn: Binding(get: { it.at == nil }, set: { allDay in
                        Feel.tap()
                        change { $0.at = allDay ? nil : "09:00"; if allDay { $0.until = nil } }
                    })) { Text("All day").font(.body).foregroundStyle(Palette.ink) }
                    .tint(Palette.ink)
                    .frame(minHeight: 48)
                    if let at = it.at {
                        HStack(spacing: 12) {
                            timeBox(at) { v in change { $0.at = v } }
                            Text("to").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
                            timeBox(it.until ?? Self.plusHour(at)) { v in change { $0.until = v } }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 52)
                    }
                    field("Where", it.place) { v in change { $0.place = v } }
                    field("Link", it.link, keyboard: .URL) { v in change { $0.link = v } }
                    field("Note", it.note, lines: true) { v in change { $0.note = String(v.prefix(300)) } }
                    // ITS COLOUR: a row of the app's colours; the chosen one ringed in black (no ticks)
                    HStack(spacing: 2) {
                        ForEach(Self.colours, id: \.self) { c in
                            Button { Feel.tap(); change { $0.c = c } } label: {
                                Circle()
                                    .fill(c.isEmpty ? Palette.white : Self.colour(c))
                                    .overlay { if c.isEmpty { Circle().strokeBorder(Palette.ink.opacity(0.2), lineWidth: 1) } }
                                    .frame(width: 26, height: 26)
                                    .padding(4)
                                    .overlay { if it.c == c { Circle().strokeBorder(Palette.ink, lineWidth: 2.5) } }
                                    .frame(width: 44, height: 44)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(c.isEmpty ? "No colour" : c.capitalized)
                            .accessibilityAddTraits(it.c == c ? .isSelected : [])
                        }
                    }
                    .frame(minHeight: 60)
                    // out of the plan (the hour view has no × of its own)
                    Button {
                        Feel.lift()
                        ListsStore.shared.change { b in
                            guard let pi = b.plans.firstIndex(where: { $0.id == planID }), b.plans[pi].days.indices.contains(day) else { return }
                            b.plans[pi].days[day].items.removeAll { $0.id == itemID }
                        }
                        dismiss()
                    } label: {
                        Text("Take out").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    static func colour(_ name: String) -> Color {
        guard let v = Palette.named[name] else { return Palette.grey }
        return Color(.sRGB, red: v.x, green: v.y, blue: v.z, opacity: 1)
    }

    static func plusHour(_ t: String) -> String {
        let m = min(23 * 60 + 59, (PlanItem.minutes(t) ?? 9 * 60) + 60)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    private func field(_ label: String, _ v: String, keyboard: UIKeyboardType = .default, lines: Bool = false,
                       set: @escaping (String) -> Void) -> some View {
        TextField("", text: Binding(get: { v }, set: set), prompt: Text(label).foregroundStyle(Palette.ink.opacity(0.5)),
                  axis: lines ? .vertical : .horizontal)
            .font(.body).foregroundStyle(Palette.ink)
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
            .frame(minHeight: 48)
    }

    /// a time on Apple's own wheel, its words the time; the picker drawn clear over the words (as the plan's dates)
    private func timeBox(_ t: String, set: @escaping (String) -> Void) -> some View {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let m = PlanItem.minutes(t) ?? 9 * 60
        let d = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        return Text(t).font(.body.monospacedDigit()).foregroundStyle(Palette.ink)
            .padding(.horizontal, 16).frame(height: 44)
            .glassEffect(PageGlass.control, in: .capsule)
            .overlay {
                DatePicker("", selection: Binding(get: { d }, set: { nd in
                    let c = cal.dateComponents([.hour, .minute], from: nd)
                    Feel.tap()
                    set(String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0))
                }), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .colorMultiply(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(Capsule())
            }
            .fixedSize()
    }
}
