import SwiftUI
import PhotosUI
import PencilKit
import AVFoundation
import UniformTypeIdentifiers
import ImageIO

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
    /// a page's sketch (PencilKit's own drawing, kept as its data)
    static func drawing(_ name: String) -> PKDrawing? {
        guard let u = url(name), let d = try? Data(contentsOf: u) else { return nil }
        return try? PKDrawing(data: d)
    }
    static func saveDrawing(_ d: PKDrawing, as name: String) {
        guard let u = url(name) else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.dataRepresentation().write(to: u)
    }
    /// WHERE A PHOTO WAS TAKEN, from its own GPS (as Photos keeps it); nil when it has none
    static func whereTaken(_ data: Data) -> (lat: Double, lon: Double)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              var lat = gps[kCGImagePropertyGPSLatitude] as? Double, var lon = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
        return (lat, lon)
    }
    /// where a video was filmed, from its ISO 6709 location ("+38.7139-009.1394+012.000/")
    static func whereFilmed(_ url: URL) async -> (lat: Double, lon: Double)? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata),
              let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierLocation).first,
              let iso = try? await item.load(.stringValue) else { return nil }
        let nums = iso.matches(of: /[+-][0-9.]+/).compactMap { Double(String($0.output)) }
        return nums.count >= 2 ? (nums[0], nums[1]) : nil
    }
    /// A PLACE'S NAME FOR A SPOT, from the app's own towns (offline): the biggest town within 12 km and its country
    /// ("Lisbon, Portugal"), else the country under it; nil at sea or before the map is there
    @MainActor
    static func placeName(lat: Double, lon: Double) async -> String? {
        let towns = TownIndex.shared
        towns.load()
        for _ in 0 ..< 40 where !towns.ready { try? await Task.sleep(for: .milliseconds(150)) }
        guard let w = AIContext.map?.world else { return nil }
        let land = w.place(at: EqualEarth.project(lon: lon, lat: lat))
        // (the biggest town within 12 km, not the nearest name: a photo at the Sagrada Família is "Barcelona", one in
        // the Baixa is "Lisbon", as a person says it)
        let k = cos(lat * .pi / 180), reach = 12.0 / 111.2
        let near = towns.nearest(lat: lat, lon: lon, count: 40).filter { h in
            let dx = (h.lon - lon) * k, dy = h.lat - lat
            return dx * dx + dy * dy <= reach * reach
        }
        if let t = near.max(by: { $0.people < $1.people }) {
            let c = (w.placeIndex[t.file] ?? w.placeIndex[t.file.uppercased()]).map { w.places[$0].n }
            return [t.name, c].compactMap { $0 }.joined(separator: ", ")
        }
        return land.map { w.places[$0].n }
    }
    /// a picked video kept as its own copy, and its first frame kept as a photo (the page's picture while it is not
    /// playing, and a cover); their file names, or nil
    static func saveVideo(from src: URL) async -> (video: String, poster: String)? {
        let name = UUID().uuidString + "." + (src.pathExtension.isEmpty ? "mov" : src.pathExtension.lowercased())
        guard let u = url(name) else { return nil }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try FileManager.default.copyItem(at: src, to: u) } catch { return nil }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: u))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 2000, height: 2000)
        guard let cg = try? await gen.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image,
              let jpg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85), let poster = save(jpg)
        else { try? FileManager.default.removeItem(at: u); return nil }
        return (name, poster)
    }
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

/// a video from the photo picker, as a file (copied into the book before the picker's own copy goes)
struct BookMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { got in
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + got.file.pathExtension)
            try FileManager.default.copyItem(at: got.file, to: tmp)
            return BookMovie(url: tmp)
        }
    }
}

/// A VIDEO PAGE PLAYING: on the page you are on it plays by itself, quietly, round and round, as a memory in Photos
/// does; its sound only when you ask for it (a page held: Sound on)
struct BookVideo: UIViewRepresentable {
    let name: String
    let playing: Bool
    let sound: Bool
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var looper: AVPlayerLooper?
        var name = ""
    }
    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.playerLayer.videoGravity = .resizeAspectFill
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: PlayerView, context: Context) {
        if v.name != name, let u = BookPhotos.url(name) {
            let q = AVQueuePlayer()
            v.looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: u))
            v.playerLayer.player = q
            v.name = name
        }
        guard let q = v.playerLayer.player else { return }
        q.isMuted = !sound
        if playing { q.play() } else { q.pause() }
    }
    static func dismantleUIView(_ v: PlayerView, coordinator: ()) { v.playerLayer.player?.pause() }
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
    /// the words left off (while they are being moved, drawn by the mover)
    var noWords = false
    /// the page you are on: a video plays (elsewhere its first frame stands still), with its sound if asked
    var live = false
    var sound = false
    /// room kept under words at the foot (full screen: above the home bar)
    var foot: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            let p = page.photos, gap: CGFloat = 3
            // (a video's first frame counts as its photo: words over it white, as over a photo)
            let pictured = !p.isEmpty || page.poster != nil
            ZStack(alignment: .bottomLeading) {
                Palette.white
                switch p.count {
                case 0:
                    if let v = page.video, live {
                        ZStack {
                            if let po = page.poster { BookPhoto(name: po) }
                            BookVideo(name: v, playing: true, sound: sound)
                        }
                    } else if let po = page.poster {
                        BookPhoto(name: po)
                    }
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
                // ITS SKETCH, over whatever else is on the page
                if let d = page.drawing, let dr = BookPhotos.drawing(d), !dr.bounds.isEmpty {
                    Image(uiImage: dr.image(from: CGRect(origin: .zero, size: g.size), scale: UIScreen.main.scale))
                        .resizable().frame(width: g.size.width, height: g.size.height)
                }
                // WORDS PUT WHERE YOU WANT THEM: at their place on
                // the page, a soft shadow under white words on a photo
                if !noWords, let t = page.text, !t.isEmpty, let at = page.words {
                    BookWordsBox(text: t, onPhoto: pictured, width: g.size.width * 0.8)
                        .position(x: at.tx * g.size.width, y: at.ty * g.size.height)
                } else if !noWords, let t = page.text, !t.isEmpty, !pictured {
                    Text(t)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // A PHOTO'S FOOT: where it was, small, and
                // its words under it when they are not put somewhere else; white, read by a soft dark foot, as Photos'
                // memories do
                if pictured {
                    let words = !noWords && page.words == nil ? (page.text ?? "") : ""
                    let place = page.place ?? ""
                    if !words.isEmpty || !place.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            if !place.isEmpty {
                                Text(place).font(.footnote.weight(.semibold)).foregroundStyle(Palette.white.opacity(0.85))
                            }
                            if !words.isEmpty {
                                Text(words).font(.body.weight(.semibold)).foregroundStyle(Palette.white)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .padding(16)
                        .padding(.bottom, foot)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(alignment: .bottom) {
                            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                        }
                    }
                } else if let place = page.place, !place.isEmpty {
                    // (a page of words or a sketch: where it was, small, in 50% ink at its foot)
                    Text(place).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.5))
                        .padding(16).padding(.bottom, foot)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// A BOOK'S COVER for the shelf: its cover photo, else its first page's first photo, else plain glass
struct BookCover: View {
    let book: PhotoBook
    var body: some View {
        let first = book.cover ?? book.pages.first(where: { $0.picture != nil })?.picture
        if let first { BookPhoto(name: first) } else { Color.clear }
    }
}

/// A BOOK OPEN: its name, its pages one at a time (swiped), the page you are on's words, and Add a page
struct BookOpenView: View {
    let id: String
    let w: CGFloat
    var naming: FocusState<Bool>.Binding
    /// the water, its tabs drawn in to their middle while a page is drawn on (Apple's pen sits where the capsule's left
    /// end was: the two lay over each other, 25 Nov)
    let water: Water
    @State private var store = ListsStore.shared
    @State private var s = ListsState.shared
    @State private var at = 0
    @State private var picking = false
    @State private var picked: [PhotosPickerItem] = []
    /// the page whose place is being set by hand (its id), what is typed, and the field's focus
    @State private var whereFor: String?
    @State private var whereQuery = ""
    @FocusState private var whereTyping: Bool
    /// the cover being picked (a book's first step after its name)
    @State private var coverPicking = false
    @State private var coverItem: PhotosPickerItem?
    /// every page shown at once, small, to go to one or put them in order
    @State private var overview = false
    /// the page being drawn on (its id): the page becomes Apple's canvas with Apple's tools
    @State private var sketching: String?
    /// the page whose words are being moved (its id), and where the finger has them now (0...1 of the page)
    @State private var placing: String?
    @State private var placeAt: CGPoint?
    /// where the words were when the finger took them (they move by how far the finger goes, not jump under it)
    @State private var placeFrom: CGPoint?
    /// the video page whose sound is on (its id); a video plays without it until asked
    @State private var soundFor: String?
    /// the sketch's ink, from our colours (nil: whatever Apple's tool picker has), and a count bumped to clear it
    @State private var sketchInk: String?
    @State private var sketchClears = 0
    /// the book read full screen, grown out of its page (Apple's zoom, as a photo opens in Photos)
    @State private var reading = false
    @Namespace private var zoom

    private var book: PhotoBook? { store.book.books.first { $0.id == id } }
    /// a page's height: 3 to 4 of its width, but never more than about half the screen, so what is under it (its words,
    /// Photos, Words, Sketch) is above the tabs at rest (they sat half under the capsule, 25 Nov)
    private var pageH: CGFloat { min(w * 4 / 3, UIScreen.main.bounds.height * 0.5) }
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
                        // A NEW BOOK: ITS NAME, ITS COVER, THEN ITS PAGES: the cover's place as big as a page, tapped for a
                        // photo; under it the first page's kinds
                        Button { Feel.tap(); coverPicking = true } label: {
                            ZStack {
                                if b.cover != nil {
                                    BookCover(book: b)
                                } else {
                                    Text("Pick a cover").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.5))
                                }
                            }
                            .frame(width: w, height: pageH)
                            .glassEffect(PageGlass.control, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel(b.cover == nil ? "Pick a cover" : "Change the cover")
                        .photosPicker(isPresented: $coverPicking, selection: $coverItem, matching: .images, photoLibrary: .shared())
                        .onChange(of: coverItem) { _, it in
                            guard let it else { return }
                            Task {
                                if let d = try? await it.loadTransferable(type: Data.self), let n = BookPhotos.save(d) {
                                    Feel.tap()
                                    withAnimation(Motion.quick) { change { $0.cover = n } }
                                } else { Feel.refuse() }
                                coverItem = nil
                            }
                        }
                        addPage
                    } else if let wid = whereFor {
                        // WHERE IT WAS, BY HAND: for a page of words or a sketch, or a photo
                        // with none of its own; the app's own towns, as Places' search finds them, offline
                        whereSetter(wid)
                    } else if let mid = placing, let pg = b.pages.first(where: { $0.id == mid }) {
                        // THE WORDS MOVED: the page alone (no turning under the finger), its words dragged where you
                        // want them; Done keeps the place
                        // (they start where the page has them: the middle of a words page, the foot of a photo, no jump)
                        let start = pg.words.map { CGPoint(x: $0.tx, y: $0.ty) }
                            ?? CGPoint(x: 0.5, y: pg.picture == nil ? 0.5 : 0.9)
                        let now = placeAt ?? start
                        ZStack {
                            BookPageView(page: pg, noWords: true)
                            GeometryReader { g in
                                BookWordsBox(text: pg.text ?? "", onPhoto: pg.picture != nil, width: g.size.width * 0.8)
                                    .position(x: now.x * g.size.width, y: now.y * g.size.height)
                                    .gesture(DragGesture(minimumDistance: 0)
                                        .onChanged { v in
                                            let from = placeFrom ?? now
                                            if placeFrom == nil { placeFrom = now }
                                            placeAt = CGPoint(x: min(0.95, max(0.05, from.x + v.translation.width / g.size.width)),
                                                              y: min(0.95, max(0.05, from.y + v.translation.height / g.size.height)))
                                        }
                                        .onEnded { _ in placeFrom = nil })
                            }
                        }
                        .frame(width: w, height: pageH)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        HStack {
                            pill("Done") {
                                let p = placeAt ?? start
                                change { bk in if let i = bk.pages.firstIndex(where: { $0.id == mid }) {
                                    bk.pages[i].words = BookWords(text: "", tx: p.x, ty: p.y) } }
                                withAnimation(Motion.quick) { placing = nil; placeAt = nil; placeFrom = nil }
                            }
                            Text("Drag the words where you want them")
                                .font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                                .padding(.leading, 8)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 52)
                    } else if let sid = sketching, let pg = b.pages.first(where: { $0.id == sid }) {
                        // A SKETCH: Apple's canvas over the page, Apple's tool picker (any colour, the rubber, thickness)
                        // under it; Done keeps it
                        ZStack {
                            BookPageView(page: BookPage(photos: pg.photos, text: pg.text, poster: pg.poster))
                            SketchCanvas(name: pg.drawing ?? (pg.id + ".drawing"),
                                         ink: sketchInk.map { UIColor(ListColours.colour($0)) }, clears: sketchClears) { name in
                                change { bk in if let i = bk.pages.firstIndex(where: { $0.id == sid }) { bk.pages[i].drawing = name } }
                            }
                        }
                        .frame(width: w, height: pageH)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        // OUR COLOURS FIRST, Apple's picker for the rest: tapped, the pen you hold takes it; any other colour is in
                        // Apple's picker below
                        HStack(spacing: 10) {
                            ForEach(Self.inks, id: \.self) { n in
                                Button { Feel.tap(); sketchInk = n } label: {
                                    Circle().fill(ListColours.colour(n))
                                        .overlay(Circle().strokeBorder(Palette.ink.opacity(0.18), lineWidth: 0.5))
                                        .padding(4)
                                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: sketchInk == n ? 1.5 : 0))
                                        .frame(width: 36, height: 36)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.press)
                                .accessibilityLabel(n)
                            }
                            Spacer(minLength: 0)
                        }
                        .transaction { $0.animation = nil }
                        HStack {
                            pill("Done") {
                                // (a page made for a sketch and left blank is not kept)
                                let blank = pg.photos.isEmpty && pg.video == nil && (pg.text ?? "").isEmpty
                                    && (pg.drawing.flatMap { BookPhotos.drawing($0) }.map { $0.strokes.isEmpty } ?? true)
                                withAnimation(Motion.quick) {
                                    if blank {
                                        change { $0.pages.removeAll { $0.id == sid } }
                                        at = max(0, min(at, (book?.pages.count ?? 1) - 1))
                                    }
                                    sketching = nil; sketchInk = nil
                                }
                            }
                            Spacer(minLength: 8)
                            // (Clear: the drawing taken off this page)
                            lineButton("Clear") { sketchClears += 1 }
                        }
                        .frame(minHeight: 52)
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
                        HStack {
                            Spacer(minLength: 0)
                            lineButton("Back to the page") { overview = false }
                        }
                        addPage
                    } else {
                        // THE PAGES, TURNED AS APPLE BOOKS TURNS THEM: the page curls over under the finger; a page
                        // held: make it the cover, take it out
                        PageCurl(pages: b.pages.map(\.id), at: $at) { pid in
                            AnyView(
                                Group {
                                    if let pg = book?.pages.first(where: { $0.id == pid }) {
                                        BookPageView(page: pg, live: b.pages.indices.contains(at) && b.pages[at].id == pid,
                                                     sound: soundFor == pid)
                                            .contextMenu {
                                                if pg.video != nil {
                                                    Button(soundFor == pid ? "Sound off" : "Sound on") {
                                                        Feel.tap(); soundFor = soundFor == pid ? nil : pid
                                                    }
                                                }
                                                if let first = pg.picture {
                                                    // THE COVER, changed any time
                                                    Button("Make it the cover") { Feel.tap(); change { $0.cover = first } }
                                                }
                                                // (any page drawn on, a photo's too)
                                                Button("Draw on it") { withAnimation(Motion.quick) { sketching = pid } }
                                                if !(pg.text ?? "").isEmpty {
                                                    Button("Move the words") { withAnimation(Motion.quick) { placing = pid } }
                                                }
                                                Button(pg.place == nil ? "Where it was" : "Change the place") {
                                                    Feel.tap(); whereQuery = ""
                                                    withAnimation(Motion.quick) { whereFor = pid }
                                                }
                                                if pg.place != nil {
                                                    Button("Take off the place") {
                                                        Feel.tap()
                                                        change { bk in if let i = bk.pages.firstIndex(where: { $0.id == pid }) { bk.pages[i].place = nil } }
                                                    }
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
                        .frame(width: w, height: pageH)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .matchedTransitionSource(id: id, in: zoom) { $0.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)) }
                        // where you are, in words (no dots), and All pages at its right (four pills in a row wrapped
                        // "All pages" onto two lines, 25 Nov); FULL SCREEN beside it
                        HStack(spacing: 20) {
                            Text("Page \(min(at, b.pages.count - 1) + 1) of \(b.pages.count)")
                                .font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                                .contentTransition(.numericText(value: Double(at)))
                            Spacer(minLength: 0)
                            Button { Feel.tap(); reading = true } label: {
                                Text("Full screen").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                                    .frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if b.pages.count > 1 { lineButton("All pages") { overview = true } }
                        }
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
            .onChange(of: sketching) { _, v in
                let want: CGFloat = v == nil ? 0 : 1
                if water.mini != want { withAnimation(Motion.chrome) { water.mini = want } }
            }
            .onDisappear { if water.mini != 0 { withAnimation(Motion.chrome) { water.mini = 0 } } }
            .fullScreenCover(isPresented: $reading) {
                BookFullView(id: id, at: $at) { reading = false }
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
            // (videos too, as Apple's Photos keeps them with the photos)
            .photosPicker(isPresented: $picking, selection: $picked, maxSelectionCount: 6,
                          matching: .any(of: [.images, .videos]), photoLibrary: .shared())
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    // the photos picked share one page; each video picked is a page of its own, after them
                    // (each page named where its first photo, or its video, was taken: the app's own towns)
                    var names: [String] = []
                    var photoAt: (lat: Double, lon: Double)?
                    var videos: [BookPage] = []
                    for it in items {
                        if it.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                            if let m = try? await it.loadTransferable(type: BookMovie.self) {
                                let at = await BookPhotos.whereFilmed(m.url)
                                if let v = await BookPhotos.saveVideo(from: m.url) {
                                    let place = if let at { await BookPhotos.placeName(lat: at.lat, lon: at.lon) } else { String?.none }
                                    videos.append(BookPage(video: v.video, poster: v.poster, place: place))
                                }
                                try? FileManager.default.removeItem(at: m.url)
                            }
                        } else if let d = try? await it.loadTransferable(type: Data.self), let n = BookPhotos.save(d) {
                            names.append(n)
                            if photoAt == nil { photoAt = BookPhotos.whereTaken(d) }
                        }
                    }
                    picked = []
                    let photoPlace = if let photoAt { await BookPhotos.placeName(lat: photoAt.lat, lon: photoAt.lon) } else { String?.none }
                    let new = (names.isEmpty ? [] : [BookPage(photos: names, place: photoPlace)]) + videos
                    guard !new.isEmpty else { Feel.refuse(); return }
                    Feel.tap()
                    withAnimation(Motion.quick) { change { $0.pages.append(contentsOf: new) } }
                    at = (book?.pages.count ?? 1) - new.count
                }
            }
        }
    }

    /// the field and the towns it finds; a town tapped names the page ("Lisbon, Portugal")
    private func whereSetter(_ pid: String) -> some View {
        let world = AIContext.map?.world
        let q = whereQuery.trimmingCharacters(in: .whitespaces)
        let found = q.count >= 2 ? TownIndex.shared.hits(q, open: nil, limit: 6) : []
        func country(_ h: TownIndex.Hit) -> String {
            guard let w = world, let i = w.placeIndex[h.file] ?? w.placeIndex[h.file.uppercased()] else { return "" }
            return w.places[i].n
        }
        return VStack(alignment: .leading, spacing: 0) {
            TextField("", text: $whereQuery, prompt: Text("Where it was").foregroundStyle(Palette.ink.opacity(0.5)))
                .font(.body).foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .focused($whereTyping)
                .submitLabel(.done)
                .frame(minHeight: 52)
                .onAppear { TownIndex.shared.load(); whereTyping = true }
            ForEach(found, id: \.self) { h in
                let c = country(h)
                Button {
                    Feel.tap()
                    let name = c.isEmpty || c == h.name ? h.name : "\(h.name), \(c)"
                    change { bk in if let i = bk.pages.firstIndex(where: { $0.id == pid }) { bk.pages[i].place = name } }
                    whereTyping = false
                    withAnimation(Motion.quick) { whereFor = nil }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        if !c.isEmpty {
                            Text(h.region.isEmpty ? c : "\(h.region), \(c)").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                pill("Done") { whereTyping = false; withAnimation(Motion.quick) { whereFor = nil } }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 52)
            .padding(.top, 8)
        }
    }

    /// our colours for a sketch, ink first
    static let inks = ["ink", "lime", "teal", "blue", "yellow", "red", "brown", "grey"]

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
            pill("Sketch") {
                let pg = BookPage()
                withAnimation(Motion.quick) { change { $0.pages.append(pg) } }
                at = (book?.pages.count ?? 1) - 1
                withAnimation(Motion.quick) { sketching = pg.id }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
    }
    /// a quiet word to tap, on a line of its own words (All pages, Back to the page)
    private func lineButton(_ t: String, _ act: @escaping () -> Void) -> some View {
        Button { Feel.tap(); withAnimation(Motion.quick) { act() } } label: {
            Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// A BOOK READ FULL SCREEN: its pages to the screen's edges, turned as before (a video plays on the page you are on);
/// back in the app's glass circle where the Lists' back always is, or a swipe down, and it shrinks into its page again
struct BookFullView: View {
    let id: String
    @Binding var at: Int
    let close: () -> Void
    @State private var store = ListsStore.shared
    var body: some View {
        let pages = store.book.books.first { $0.id == id }?.pages ?? []
        ZStack(alignment: .topLeading) {
            Palette.white.ignoresSafeArea()
            if !pages.isEmpty {
                PageCurl(pages: pages.map(\.id), at: $at) { pid in
                    AnyView(
                        Group {
                            if let pg = store.book.books.first(where: { $0.id == id })?.pages.first(where: { $0.id == pid }) {
                                BookPageView(page: pg, live: pages.indices.contains(at) && pages[at].id == pid, foot: 28)
                            }
                        }
                        .ignoresSafeArea()
                    )
                }
                .ignoresSafeArea()
            }
            Button { Feel.tap(); close() } label: {
                Icon5(key: "back", ink: Palette.ink, size: 22)
                    .frame(width: 44, height: 44)
                    .glassEffect(PageGlass.head.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            // (16 pt in, where every tab's head circles are)
            .padding(.leading, 16)
            .accessibilityLabel("Back")
        }
        .statusBarHidden()
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

/// APPLE'S CANVAS (PencilKit) with Apple's tool picker: pens, colours (any colour, its own picker), the rubber,
/// thickness, undo; a finger draws. Each stroke kept as it is made.
struct SketchCanvas: UIViewRepresentable {
    let name: String
    /// one of our colours for the pen held (its kind and thickness kept), and a count that clears the page when it grows
    var ink: UIColor? = nil
    var clears = 0
    let saved: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.drawingPolicy = .anyInput
        v.tool = PKInkingTool(.pen, color: .black, width: 4)
        if let d = BookPhotos.drawing(name) { v.drawing = d }
        v.delegate = context.coordinator
        let picker = PKToolPicker()
        picker.setVisible(true, forFirstResponder: v)
        picker.addObserver(v)
        context.coordinator.picker = picker
        DispatchQueue.main.async { v.becomeFirstResponder() }
        return v
    }
    func updateUIView(_ v: PKCanvasView, context: Context) {
        let c = context.coordinator
        if let ink, ink != c.ink {
            let held = v.tool as? PKInkingTool
            v.tool = PKInkingTool(held?.inkType ?? .pen, color: ink, width: held?.width ?? 4)
        }
        c.ink = ink
        if clears != c.clears {
            c.clears = clears
            v.drawing = PKDrawing()
        }
    }
    static func dismantleUIView(_ v: PKCanvasView, coordinator: Coordinator) {
        coordinator.picker?.setVisible(false, forFirstResponder: v)
        v.resignFirstResponder()
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: SketchCanvas
        var picker: PKToolPicker?
        var ink: UIColor?
        var clears: Int
        init(_ p: SketchCanvas) { parent = p; clears = p.clears }
        func canvasViewDrawingDidChange(_ v: PKCanvasView) {
            BookPhotos.saveDrawing(v.drawing, as: parent.name)
            parent.saved(parent.name)
        }
    }
}

/// YOUR PASSPORT AS A BOOK ON THE SHELF: its first page, as the passport book shows it
struct PassportCover: View {
    @State private var order: [String] = []
    var body: some View {
        GeometryReader { g in
            ZStack {
                Palette.white.opacity(0.6)
                if !order.isEmpty {
                    PassportPage(id: "", order: order, hidden: nil, size: g.size, pageIndex: 0)
                }
            }
        }
        .task { order = await MarkStore.shared.passportOrder() }
    }
}

/// a page's words as a little box: black on a white page, white on a photo with a soft shadow under them
struct BookWordsBox: View {
    let text: String
    let onPhoto: Bool
    /// how wide a line may run (most of the page, so a line does not break anew when the words are taken to move)
    var width: CGFloat = 280
    var body: some View {
        Text(text)
            // (as big as the page's own words: title2 on a words page, a step smaller over a photo)
            .font(onPhoto ? .title3.weight(.semibold) : .title2.weight(.semibold))
            .foregroundStyle(onPhoto ? Palette.white : Palette.ink)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(onPhoto ? 0.45 : 0), radius: 6, y: 1)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: width)
    }
}
