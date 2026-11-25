import SwiftUI
import PhotosUI

/// BOOKS (25 Nov, step one): a book works like a book without having to look like one; it is its pages, each one photo
/// or up to six, with words on it if you like. Pages turn by
/// a swipe; a page held: words, take out.

/// where a book's photos are kept: their own copies, so a book stays whole when a photo leaves your library
enum BookPhotos {
    static func url(_ name: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("book-photos").appendingPathComponent(name)
    }
    static func image(_ name: String) -> UIImage? { url(name).flatMap { UIImage(contentsOfFile: $0.path) } }
    /// a picked photo kept (no bigger than a page needs); its file name, or nil
    static func save(_ data: Data) -> String? {
        guard let img = UIImage(data: data) else { return nil }
        let side: CGFloat = 2000, k = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
        let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        let name = UUID().uuidString + ".jpg"
        guard let u = url(name), let jpg = small.jpegData(compressionQuality: 0.85) else { return nil }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? jpg.write(to: u)) != nil ? name : nil
    }
}

/// a photo of a book, filling its frame
struct BookPhoto: View {
    let name: String
    var body: some View {
        Color.clear.overlay {
            if let img = BookPhotos.image(name) { Image(uiImage: img).resizable().scaledToFill() }
            else { Palette.ink.opacity(0.06) }
        }
        .clipped()
    }
}

/// ONE PAGE: its photos laid out to fill it (one whole; two side by side; three, one big and two; four in a square;
/// five or six in pairs), its words over the foot of it; a page of words alone is white with its words in the middle
/// (a blank page is white)
struct BookPageView: View {
    let page: BookPage
    var body: some View {
        GeometryReader { g in
            let p = page.photos, gap: CGFloat = 3
            ZStack(alignment: .bottomLeading) {
                Palette.white
                switch p.count {
                case 0:
                    EmptyView()
                case 1:
                    BookPhoto(name: p[0])
                case 2:
                    HStack(spacing: gap) { ForEach(p, id: \.self) { BookPhoto(name: $0) } }
                case 3:
                    VStack(spacing: gap) {
                        BookPhoto(name: p[0]).frame(height: g.size.height * 0.6)
                        HStack(spacing: gap) { BookPhoto(name: p[1]); BookPhoto(name: p[2]) }
                    }
                default:
                    let rows = stride(from: 0, to: p.count, by: 2).map { Array(p[$0 ..< min($0 + 2, p.count)]) }
                    VStack(spacing: gap) {
                        ForEach(rows.indices, id: \.self) { r in
                            HStack(spacing: gap) { ForEach(rows[r], id: \.self) { BookPhoto(name: $0) } }
                        }
                    }
                }
                if let t = page.text, !t.isEmpty {
                    Text(t)
                        .font(p.isEmpty ? .title2.weight(.semibold) : .body.weight(.semibold))
                        .foregroundStyle(p.isEmpty ? Palette.ink : Palette.white)
                        .multilineTextAlignment(p.isEmpty ? .center : .leading)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: p.isEmpty ? .infinity : nil,
                               alignment: p.isEmpty ? .center : .leading)
                        // (white words on a photo read by a soft dark foot, as Photos' memories do)
                        .background(alignment: .bottom) {
                            if !p.isEmpty {
                                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                            }
                        }
                }
            }
        }
    }
}

/// A BOOK'S COVER for the shelf: its cover photo, else its first page's first photo, else plain glass
struct BookCover: View {
    let book: PhotoBook
    var body: some View {
        let first = book.cover ?? book.pages.first(where: { !$0.photos.isEmpty })?.photos.first
        if let first { BookPhoto(name: first) } else { Color.clear }
    }
}

/// A BOOK OPEN: its name, its pages one at a time (swiped), the page you are on's words, and Add a page
struct BookOpenView: View {
    let id: String
    let w: CGFloat
    var naming: FocusState<Bool>.Binding
    @State private var store = ListsStore.shared
    @State private var s = ListsState.shared
    @State private var at = 0
    @State private var picking = false
    @State private var picked: [PhotosPickerItem] = []
    /// every page shown at once, small, to go to one or put them in order
    @State private var overview = false

    private var book: PhotoBook? { store.book.books.first { $0.id == id } }
    private func change(_ f: (inout PhotoBook) -> Void) {
        ListsStore.shared.change { b in if let i = b.books.firstIndex(where: { $0.id == id }) { f(&b.books[i]) } }
    }

    var body: some View {
        if let b = book {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if s.naming || b.name.isEmpty {
                        TextField("", text: Binding(get: { b.name }, set: { v in change { $0.name = String(v.prefix(60)) } }),
                                  prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                            .font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                            .focused(naming)
                            .submitLabel(.done)
                            .onSubmit { s.naming = false }
                            .onAppear { naming.wrappedValue = true }
                            .frame(minHeight: 44)
                    } else {
                        Text(b.name).font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                            .frame(minHeight: 44)
                            .onTapGesture { Feel.tap(); s.naming = true }
                    }
                    if b.pages.isEmpty {
                        // (no pages yet: the first is made from photos, one or many, or words)
                        addPage
                    } else if overview {
                        // ALL PAGES, to go to one or put them in order: small, three
                        // across, in order; tapped, that page; held, earlier, later, out
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(Array(b.pages.enumerated()), id: \.element.id) { i, pg in
                                VStack(spacing: 4) {
                                    BookPageView(page: pg)
                                        .aspectRatio(3 / 4, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(Palette.ink, lineWidth: i == at ? 2 : 0)
                                        }
                                    Text("\(i + 1)").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { Feel.tap(); at = i; withAnimation(Motion.quick) { overview = false } }
                                .contextMenu {
                                    if i > 0 { Button("Move earlier") { move(pg.id, by: -1) } }
                                    if i < b.pages.count - 1 { Button("Move later") { move(pg.id, by: 1) } }
                                    Button("Take out page", role: .destructive) {
                                        Feel.lift()
                                        withAnimation(Motion.quick) { change { $0.pages.removeAll { $0.id == pg.id } } }
                                        at = max(0, min(at, b.pages.count - 2))
                                    }
                                }
                            }
                        }
                        .transition(.blurReplace)
                        addPage
                    } else {
                        // THE PAGES, TURNED AS APPLE BOOKS TURNS THEM: the page curls over under the finger; a page
                        // held: make it the cover, take it out
                        PageCurl(pages: b.pages.map(\.id), at: $at) { pid in
                            AnyView(
                                Group {
                                    if let pg = book?.pages.first(where: { $0.id == pid }) {
                                        BookPageView(page: pg)
                                            .contextMenu {
                                                if let first = pg.photos.first {
                                                    // THE COVER, changed any time
                                                    Button("Make it the cover") { Feel.tap(); change { $0.cover = first } }
                                                }
                                                Button("Take out page", role: .destructive) {
                                                    Feel.lift()
                                                    let n = book?.pages.count ?? 1
                                                    withAnimation(Motion.quick) { change { $0.pages.removeAll { $0.id == pid } } }
                                                    at = max(0, min(at, n - 2))
                                                }
                                            }
                                    }
                                }
                            )
                        }
                        .frame(width: w, height: w * 4 / 3)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        // where you are, in words (no dots)
                        Text("Page \(min(at, b.pages.count - 1) + 1) of \(b.pages.count)")
                            .font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                            .contentTransition(.numericText(value: Double(at)))
                        // THE WORDS ON THIS PAGE, typed here
                        if b.pages.indices.contains(at) {
                            let pid = b.pages[at].id
                            TextField("", text: Binding(get: { book?.pages.first { $0.id == pid }?.text ?? "" }, set: { v in
                                change { bk in if let i = bk.pages.firstIndex(where: { $0.id == pid }) { bk.pages[i].text = String(v.prefix(300)) } }
                            }), prompt: Text("Words on this page").foregroundStyle(Palette.ink.opacity(0.5)), axis: .vertical)
                                .font(.body).foregroundStyle(Palette.ink)
                                .lineLimit(1 ... 4)
                                .frame(minHeight: 44)
                        }
                        addPage
                    }
                }
                .frame(width: w, alignment: .leading)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
            .photosPicker(isPresented: $picking, selection: $picked, maxSelectionCount: 6, matching: .images, photoLibrary: .shared())
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var names: [String] = []
                    for it in items {
                        if let d = try? await it.loadTransferable(type: Data.self), let n = BookPhotos.save(d) { names.append(n) }
                    }
                    picked = []
                    guard !names.isEmpty else { Feel.refuse(); return }
                    Feel.tap()
                    withAnimation(Motion.quick) { change { $0.pages.append(BookPage(photos: names)) } }
                    at = (book?.pages.count ?? 1) - 1
                }
            }
        }
    }

    /// a page moved one place earlier (-1) or later (+1), the place you are on following it
    private func move(_ pid: String, by d: Int) {
        Feel.tap()
        withAnimation(Motion.quick) {
            change { bk in
                guard let i = bk.pages.firstIndex(where: { $0.id == pid }), bk.pages.indices.contains(i + d) else { return }
                bk.pages.swapAt(i, i + d)
                at = i + d
            }
        }
    }

    /// a page of up to six photos, or a page of words alone; and every page at once
    private var addPage: some View {
        HStack(spacing: 12) {
            pill("Photos") { picking = true }
            pill("Words") {
                withAnimation(Motion.quick) { change { $0.pages.append(BookPage(text: "")) } }
                at = (book?.pages.count ?? 1) - 1
            }
            Spacer(minLength: 0)
            if (book?.pages.count ?? 0) > 1 {
                // (back from all pages: the word says where you would go)
                pill(overview ? "Back to the page" : "All pages") { withAnimation(Motion.quick) { overview.toggle() } }
            }
        }
        .frame(minHeight: 52)
    }
    private func pill(_ t: String, _ act: @escaping () -> Void) -> some View {
        Button { Feel.tap(); act() } label: {
            Text(t).font(.body).foregroundStyle(Palette.ink)
                .padding(.horizontal, 16).frame(height: 44)
                .glassEffect(PageGlass.control.interactive(), in: .capsule)
        }
        .buttonStyle(.press)
    }
}

/// APPLE'S PAGE CURL (UIPageViewController, .pageCurl): each page a hosted SwiftUI page, keyed by its id, turned by a
/// drag at its edge or a tap at its side, as in Books
struct PageCurl: UIViewControllerRepresentable {
    let pages: [String]
    @Binding var at: Int
    let content: (String) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                       options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)])
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.isDoubleSided = false
        pvc.view.backgroundColor = .clear
        if let first = context.coordinator.page(at: min(at, pages.count - 1)) {
            pvc.setViewControllers([first], direction: .forward, animated: false)
        }
        return pvc
    }
    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        let c = context.coordinator
        c.parent = self
        // (a page added or taken out, or the place moved from outside: shown at once, the other pages rebuilt)
        let shown = (pvc.viewControllers?.first as? Hosted)?.pid
        let want = pages.indices.contains(at) ? pages[at] : pages.last
        if shown != want || c.lastPages != pages, let w = want, let i = pages.firstIndex(of: w), let vc = c.page(at: i) {
            let back = shown.flatMap { pages.firstIndex(of: $0) }.map { $0 > i } ?? false
            pvc.setViewControllers([vc], direction: back ? .reverse : .forward, animated: shown != nil && c.lastPages == pages)
        }
        c.lastPages = pages
        // (the page on show drawn again with what changed on it: its words typed below, the cover made; a hosted page
        // otherwise keeps what it was first made with)
        if let h = pvc.viewControllers?.first as? Hosted { h.rootView = content(h.pid) }
    }

    final class Hosted: UIHostingController<AnyView> {
        var pid = ""
    }
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurl
        var lastPages: [String] = []
        init(_ p: PageCurl) { parent = p }
        func page(at i: Int) -> Hosted? {
            guard parent.pages.indices.contains(i) else { return nil }
            let id = parent.pages[i]
            let h = Hosted(rootView: parent.content(id))
            h.pid = id
            h.view.backgroundColor = .white
            return h
        }
        private func index(of vc: UIViewController) -> Int? { (vc as? Hosted).flatMap { parent.pages.firstIndex(of: $0.pid) } }
        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            index(of: vc).flatMap { page(at: $0 - 1) }
        }
        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            index(of: vc).flatMap { page(at: $0 + 1) }
        }
        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted done: Bool) {
            guard done, let v = pvc.viewControllers?.first, let i = index(of: v) else { return }
            Feel.tick()
            parent.at = i
        }
    }
}
