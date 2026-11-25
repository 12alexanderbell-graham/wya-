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
                    } else {
                        // THE PAGES, one at a time, a swipe turning them; a page held: its words, take it out
                        TabView(selection: $at) {
                            ForEach(Array(b.pages.enumerated()), id: \.element.id) { i, pg in
                                BookPageView(page: pg)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .contextMenu {
                                        Button("Take out page", role: .destructive) {
                                            Feel.lift()
                                            withAnimation(Motion.quick) { change { $0.pages.removeAll { $0.id == pg.id } } }
                                            at = max(0, min(at, b.pages.count - 2))
                                        }
                                    }
                                    .tag(i)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(width: w, height: w * 4 / 3)
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

    /// a page of up to six photos, or a page of words alone
    private var addPage: some View {
        HStack(spacing: 12) {
            pill("Photos") { picking = true }
            pill("Words") {
                withAnimation(Motion.quick) { change { $0.pages.append(BookPage(text: "")) } }
                at = (book?.pages.count ?? 1) - 1
            }
            Spacer(minLength: 0)
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
