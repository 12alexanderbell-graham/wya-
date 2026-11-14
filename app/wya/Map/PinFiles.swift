import SwiftUI
import MapKit
import UniformTypeIdentifiers

/// PINS' FILES (the Files circle, Google Maps' and Google Earth's file tools): what the shown map holds goes out as
/// GeoJSON, KML and GPX together (the share sheet offers all three), and a GeoJSON, KML or GPX file comes in: its points
/// become pins, its lines and its shapes become drawings, all in the map shown.
@MainActor
enum PinFiles {
    static let types: [UTType] = [
        UTType(filenameExtension: "geojson") ?? .json, .json,
        UTType(filenameExtension: "kml") ?? .xml,
        UTType(filenameExtension: "gpx") ?? .xml,
        .xml,
    ]

    // MARK: out

    /// what is shown: the map's pins, routes and drawings (All pins: everything)
    private static func shown() -> (pins: [Pin], routes: [PinRoute], drawings: [PinDrawing]) {
        let maps = PinMaps.shared
        return (PinStore.shared.pins.filter { maps.shows(pin: $0.map) },
                PinRoutes.shared.routes.filter { maps.shows(extra: $0.map) },
                PinDrawings.shared.all.filter { maps.shows(extra: $0.map) })
    }

    private static var name: String { PinMaps.shared.map(PinMaps.shared.shown)?.name ?? "All pins" }

    static func geoJSON() -> Data {
        let s = shown()
        var features: [[String: Any]] = []
        for p in s.pins {
            features.append(["type": "Feature", "properties": ["name": p.title, "note": p.note ?? ""],
                             "geometry": ["type": "Point", "coordinates": [p.lon, p.lat]]])
        }
        for r in s.routes {
            features.append(["type": "Feature", "properties": ["name": "Route", "kind": "route"],
                             "geometry": ["type": "LineString", "coordinates": r.points.map { [$0[1], $0[0]] }]])
        }
        for d in s.drawings {
            let line = d.points.map { [$0[1], $0[0]] }
            features.append(["type": "Feature", "properties": ["name": d.name, "note": d.note],
                             "geometry": d.isShape ? ["type": "Polygon", "coordinates": [line + (line.first.map { [$0] } ?? [])]]
                                                   : ["type": "LineString", "coordinates": line]])
        }
        let all: [String: Any] = ["type": "FeatureCollection", "name": name, "features": features]
        return (try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func kml() -> Data {
        let s = shown()
        var o = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document><name>\(esc(name))</name>\n"
        for p in s.pins {
            o += "<Placemark><name>\(esc(p.title))</name><description>\(esc(p.note ?? ""))</description><Point><coordinates>\(p.lon),\(p.lat),0</coordinates></Point></Placemark>\n"
        }
        for r in s.routes {
            o += "<Placemark><name>Route</name><LineString><coordinates>\(r.points.map { "\($0[1]),\($0[0]),0" }.joined(separator: " "))</coordinates></LineString></Placemark>\n"
        }
        for d in s.drawings {
            let c = d.points.map { "\($0[1]),\($0[0]),0" }
            if d.isShape {
                o += "<Placemark><name>\(esc(d.name))</name><Polygon><outerBoundaryIs><LinearRing><coordinates>\((c + c.prefix(1)).joined(separator: " "))</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>\n"
            } else {
                o += "<Placemark><name>\(esc(d.name))</name><LineString><coordinates>\(c.joined(separator: " "))</coordinates></LineString></Placemark>\n"
            }
        }
        return Data((o + "</Document></kml>\n").utf8)
    }

    static func gpx() -> Data {
        let s = shown()
        var o = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"wya?!\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n<metadata><name>\(esc(name))</name></metadata>\n"
        for p in s.pins { o += "<wpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><name>\(esc(p.title))</name></wpt>\n" }
        for r in s.routes {
            o += "<rte><name>Route</name>\(r.points.map { "<rtept lat=\"\($0[0])\" lon=\"\($0[1])\"/>" }.joined())</rte>\n"
        }
        for d in s.drawings {
            let pts = d.isShape ? d.points + d.points.prefix(1) : d.points
            o += "<trk><name>\(esc(d.name))</name><trkseg>\(pts.map { "<trkpt lat=\"\($0[0])\" lon=\"\($0[1])\"/>" }.joined())</trkseg></trk>\n"
        }
        return Data((o + "</gpx>\n").utf8)
    }

    /// the share sheet with all three files, named after the map
    static func export() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pins-out", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = name.replacingOccurrences(of: "/", with: "-")
        let files: [(String, Data)] = [("geojson", geoJSON()), ("kml", kml()), ("gpx", gpx())]
        var urls: [URL] = []
        for (ext, d) in files {
            let u = dir.appendingPathComponent("\(base).\(ext)")
            if (try? d.write(to: u, options: .atomic)) != nil { urls.append(u) }
        }
        guard !urls.isEmpty else { Feel.refuse(); return }
        var top = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        while let next = top?.presentedViewController { top = next }
        top?.present(UIActivityViewController(activityItems: urls, applicationActivities: nil), animated: true)
    }

    // MARK: in

    struct Found { var points: [(name: String, lat: Double, lon: Double)] = []; var lines: [[DrawTool.Geo]] = []; var shapes: [[DrawTool.Geo]] = [] }

    /// a file read into pins and drawings in the map shown; how many came in, or nil when nothing could be read
    @discardableResult
    static func bring(_ url: URL, country: (CLLocationCoordinate2D) -> (id: String, name: String)?) -> Int? {
        let open = url.startAccessingSecurityScopedResource()
        defer { if open { url.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: url) else { return nil }
        let f = read(d)
        let n = f.points.count + f.lines.count + f.shapes.count
        guard n > 0 else { return nil }
        for p in f.points {
            let c = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
            guard CLLocationCoordinate2DIsValid(c) else { continue }
            PinStore.shared.drop(at: c, named: p.name, country: country(c))
        }
        for l in f.lines where l.count >= 2 { PinDrawings.shared.add(.line, l) }
        for s in f.shapes where s.count >= 3 { PinDrawings.shared.add(.shape, s) }
        return n
    }

    /// a file's contents read: GeoJSON, else KML or GPX
    static func read(_ d: Data) -> Found {
        if let j = try? JSONSerialization.jsonObject(with: d) { return fromGeoJSON(j) }
        return XMLRead.read(d)
    }

    private static func geo(_ a: Any) -> DrawTool.Geo? {
        guard let c = a as? [Any], c.count >= 2, let lon = (c[0] as? NSNumber)?.doubleValue, let lat = (c[1] as? NSNumber)?.doubleValue else { return nil }
        return DrawTool.Geo(lat: lat, lon: lon)
    }

    static func fromGeoJSON(_ j: Any) -> Found {
        var f = Found()
        func geometry(_ g: [String: Any], name: String) {
            let c = g["coordinates"]
            switch g["type"] as? String {
            case "Point": if let p = c.flatMap(geo) { f.points.append((name, p.lat, p.lon)) }
            case "MultiPoint": for p in (c as? [Any] ?? []).compactMap(geo) { f.points.append((name, p.lat, p.lon)) }
            case "LineString": f.lines.append((c as? [Any] ?? []).compactMap(geo))
            case "MultiLineString": for l in c as? [Any] ?? [] { f.lines.append((l as? [Any] ?? []).compactMap(geo)) }
            case "Polygon": if let r = (c as? [Any])?.first { f.shapes.append(Array((r as? [Any] ?? []).compactMap(geo).dropLast())) }
            case "MultiPolygon": for poly in c as? [Any] ?? [] { if let r = (poly as? [Any])?.first { f.shapes.append(Array((r as? [Any] ?? []).compactMap(geo).dropLast())) } }
            case "GeometryCollection": for g2 in g["geometries"] as? [[String: Any]] ?? [] { geometry(g2, name: name) }
            default: break
            }
        }
        guard let o = j as? [String: Any] else { return f }
        let features = (o["features"] as? [[String: Any]]) ?? (o["type"] as? String == "Feature" ? [o] : [])
        for ft in features {
            let name = ((ft["properties"] as? [String: Any])?["name"] as? String) ?? ""
            if let g = ft["geometry"] as? [String: Any] { geometry(g, name: name) }
        }
        if features.isEmpty, o["coordinates"] != nil { geometry(o, name: "") }
        return f
    }
}

/// KML and GPX read with Apple's XML parser: KML's Placemarks (Point, LineString, Polygon's outer ring), GPX's
/// waypoints, routes and tracks
private final class XMLRead: NSObject, XMLParserDelegate {
    var found = PinFiles.Found()
    private var text = ""
    private var name = ""
    private var inPlacemark = false
    private var kind = ""
    private var gpxPoints: [DrawTool.Geo] = []
    private var wpt: DrawTool.Geo?

    static func read(_ d: Data) -> PinFiles.Found {
        let r = XMLRead()
        let p = XMLParser(data: d)
        p.delegate = r
        p.parse()
        return r.found
    }

    private static func coords(_ s: String) -> [DrawTool.Geo] {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).compactMap { t in
            let v = t.split(separator: ",").compactMap { Double($0) }
            return v.count >= 2 ? DrawTool.Geo(lat: v[1], lon: v[0]) : nil
        }
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        switch e {
        case "Placemark": inPlacemark = true; name = ""; kind = ""
        case "Point", "LineString", "Polygon": if kind != "Polygon" { kind = e }
        case "wpt", "rtept", "trkpt":
            if let la = a["lat"].flatMap(Double.init), let lo = a["lon"].flatMap(Double.init) {
                if e == "wpt" { wpt = DrawTool.Geo(lat: la, lon: lo); name = "" } else { gpxPoints.append(DrawTool.Geo(lat: la, lon: lo)) }
            }
        case "rte", "trkseg": gpxPoints = []
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }

    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch e {
        case "name": if inPlacemark || wpt != nil { name = t }
        case "coordinates" where inPlacemark:
            let c = Self.coords(t)
            switch kind {
            case "Point": if let p = c.first { found.points.append((name, p.lat, p.lon)) }
            case "Polygon": found.shapes.append(c.count > 1 && c.first == c.last ? Array(c.dropLast()) : c)
            default: found.lines.append(c)
            }
        case "Placemark": inPlacemark = false
        case "wpt": if let w = wpt { found.points.append((name, w.lat, w.lon)) }; wpt = nil
        case "rte", "trkseg": if gpxPoints.count >= 2 { found.lines.append(gpxPoints) }; gpxPoints = []
        default: break
        }
        text = ""
    }
}
