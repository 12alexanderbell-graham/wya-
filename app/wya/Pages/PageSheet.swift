import SwiftUI

/// THE PAGE'S OWN SHEET (16.6): pulled up from the tab capsule, or Sources tapped, the water comes to 50% over the page
/// (the page does not move) holding, in order: the page's actions as rows (the same as the name's hold menu, 16.7: Share,
/// Show in passport when stamped; Add to a list and Its book wait for Lists and the books), then Sources under its name
/// (every data credit, each photo's author and licence), then Report a mistake. Report a mistake changes the sheet in
/// place to the six reasons as chips, a note and Send. Pull down or tap the page: back.
struct PageSheet: View {
    let water: Water
    let map: MapController
    let form: Water.Form
    @State private var stack = PlacePageState.shared
    @State private var marks = MarkStore.shared
    @State private var credits: [String: String] = [:]
    @State private var reporting = false
    @State private var reason: String?
    @State private var note = ""
    @State private var sent = false
    @FocusState private var noteFocused: Bool

    static let reasons = ["Wrong number", "Wrong place", "Wrong photo", "Bad text", "Missing", "Something else"]

    var body: some View {
        let L = water.layout
        let top = form.top + 20
        let bottom = L.capsule.minY - 16
        let w = L.W - 2 * L.sheetInset
        if let page = stack.top {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if reporting { report(page, width: w - 32) } else { list(page) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(width: w, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(width: w, height: max(0, bottom - top))
            .position(x: L.W / 2, y: top + max(0, bottom - top) / 2)
            .onChange(of: stack.reportTest) { _, r in reporting = true; reason = Self.reasons.contains(r) ? r : nil }
            .onChange(of: stack.sendTest) { _, _ in send(page) }
            .task(id: page.key.description) {
                reporting = false; reason = nil; note = ""; sent = false
                if let f = page.facts { credits = await SourcesRow.credits(f) }
            }
        }
    }

    // MARK: the actions, Sources and the report row

    @ViewBuilder private func list(_ page: PlacePageState.OnePage) -> some View {
        let key = page.key
        // Share: the system share sheet with the page's own link and its name
        if let u = URL(string: "wya://page/\(key.description)") {
            ShareLink(item: u, subject: Text(page.name), message: Text(page.name)) { actionWords("Share") }
                .buttonStyle(.plain)
        }
        // Show in passport (a stamped country): the page closes and the passport opens on its stamp (the book is under
        // the page in the screen's layers, so it can't open over it)
        if key.kind == .country, marks.state(key).stamped {
            Button {
                Feel.tap()
                water.pageSheet = false
                PlacePageState.shared.closeAll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { BookState.shared.open(showing: key.id) }
            } label: { actionWords("Show in passport") }
            .buttonStyle(.plain)
        }
        // SOURCES, 24 pt below under its name
        Text("Sources").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.5))
            .padding(.top, 24).padding(.bottom, 4)
        if let f = page.facts {
            ForEach(Array(SourcesRow.lines(f, kind: key.kind, credits: credits).enumerated()), id: \.offset) { _, l in
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.0).font(.subheadline).foregroundStyle(Palette.ink)
                    Text(l.1).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        // REPORT A MISTAKE, last
        Button {
            Feel.tap()
            withAnimation(Motion.quick) { reporting = true }
        } label: { actionWords("Report a mistake") }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private func actionWords(_ s: String) -> some View {
        Text(s).font(.body).foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
    }

    // MARK: Report a mistake (16.6): six reasons as chips, two per row, a 300-character note, Send

    @ViewBuilder private func report(_ page: PlacePageState.OnePage, width: CGFloat) -> some View {
        let chipW = (width - 12) / 2
        Text("Report a mistake").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
            .frame(minHeight: 52, alignment: .leading)
        VStack(spacing: 12) {
            ForEach(0 ..< 3, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(Self.reasons[row * 2 ..< row * 2 + 2], id: \.self) { r in chip(r, width: chipW) }
                }
            }
        }
        TextField("A note (if it helps)", text: $note, axis: .vertical)
            .font(.body)
            .lineLimit(1 ... 4)
            .focused($noteFocused)
            .onChange(of: note) { _, n in if n.count > 300 { note = String(n.prefix(300)) } }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 44)
            .glassEffect(PageGlass.on, in: .rect(cornerRadius: 22))
            .padding(.top, 16)
        Button { send(page) } label: {
            // nowhere to send yet: the report waits on the phone for the server's ledger, said plainly (as Verify's
            // "Waiting to send")
            Text(sent ? "Waiting to send" : "Send")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(Palette.ink.opacity(reason == nil ? 0.3 : 1)))
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }

    private func send(_ page: PlacePageState.OnePage) {
        guard let reason, !sent else { Feel.refuse(); return }
        Feel.tap()
        noteFocused = false
        Reports.shared.add(key: page.key.description, name: page.name, reason: reason, note: note)
        withAnimation(Motion.quick) { sent = true }
    }

    private func chip(_ r: String, width: CGFloat) -> some View {
        let on = reason == r
        return Button {
            Feel.tap()
            reason = on ? nil : r
        } label: {
            Text(r).font(.subheadline).foregroundStyle(Palette.ink)
                .frame(width: width, height: 44)
                .background(Capsule().fill(on ? Palette.lime : Color.clear))
                .glassEffect(on ? .identity : PageGlass.control, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// REPORTS WAITING (16.6): a report of a mistake on a page, kept on the phone until the server takes them (it has no
/// mistakes ledger to receive them yet); each with the page, the reason, the note and when
@MainActor
final class Reports {
    static let shared = Reports()
    struct Report: Codable { let key: String; let name: String; let reason: String; let note: String; let at: Date }
    private var url: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("reports-waiting.json")
    }
    private(set) var all: [Report] = []
    private init() {
        if let d = try? Data(contentsOf: url), let a = try? JSONDecoder().decode([Report].self, from: d) { all = a }
    }
    func add(key: String, name: String, reason: String, note: String) {
        all.append(Report(key: key, name: name, reason: reason, note: note.trimmingCharacters(in: .whitespacesAndNewlines), at: Date()))
        if let d = try? JSONEncoder().encode(all) { try? d.write(to: url, options: .atomic) }
        #if DEBUG
        NSLog("wya report waiting: %@ %@ (%d waiting)", key, reason, all.count)
        #endif
    }
}
