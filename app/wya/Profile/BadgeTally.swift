import Foundation

// THE CATALOG'S COUNTS, from what you have (BadgeInput) against the world (BadgeWorld): each badge's number by its id,
// and a level reached another way (a place's regions all marked at its deepest level).

nonisolated extension Badges {
    static func tally(_ w: BadgeWorld, _ y: BadgeInput) -> (more: [String: Int], fixed: [String: Int], steps: [String: [Int]]) {
        var m = y.numbers
        var fixed: [String: Int] = [:]
        let mine = y.stamped.union(y.counted)
        let places = mine.compactMap { w.places[$0] }
        let countries = w.countries.filter { mine.contains($0.id) }

        if !w.countries.isEmpty { m["share-of-the-world"] = countries.count * 100 / w.countries.count }
        let pop = w.countries.reduce(0) { $0 + $1.pop }, land = w.countries.reduce(0) { $0 + $1.area }
        if pop > 0 { m["world-s-people"] = Int((countries.reduce(0) { $0 + $1.pop } / pop * 100).rounded(.down)) }
        if land > 0 { m["world-s-land"] = Int((countries.reduce(0) { $0 + $1.area } / land * 100).rounded(.down)) }

        m["islandnations"] = countries.filter { islandCountries.contains($0.id) }.count
        m["landlocked"] = countries.filter(\.landlocked).count
        m["microstates"] = countries.filter { $0.area > 0 && $0.area < microstateArea }.count
        for r in unRegions { m[slug(r)] = countries.filter { $0.sub == r }.count }
        for (g, ms) in groups { m[slug(g)] = ms.filter { mine.contains($0) }.count }
        for l in languageAreas { m[slug(l) + "-speaking"] = countries.filter { $0.lang.contains(l) }.count }
        for (n, code) in currencies { m[slug(n)] = countries.filter { $0.cur.contains(code) }.count }
        m["languages"] = Set(places.flatMap(\.lang)).count
        m["currencies"] = Set(places.flatMap(\.cur)).count

        var byPlace: [String: [Int: Int]] = [:]
        for r in y.regions { byPlace[r.cc, default: [:]][r.lvl, default: 0] += 1 }
        var whole = 0, deepest = 0, districts = 0, local = 0
        for (cc, lv) in byPlace {
            deepest = max(deepest, lv.values.reduce(0, +))
            guard let r = w.regions[cc] else { continue }
            let have = lv[r.first] ?? 0
            m["regions-" + cc] = have
            if have >= r.n { whole += 1 }
            if r.deep != r.first, have >= r.n, (lv[r.deep] ?? 0) >= r.deepN { fixed["regions-" + cc] = 5 }
            if let d = r.below.first { districts += lv[d] ?? 0 }
            for l in r.below.dropFirst() { local += lv[l] ?? 0 }
        }
        m["whole-countries"] = whole
        m["deep-in-one-country"] = deepest
        m["districts"] = districts
        m["local-areas"] = local

        for (cc, n) in y.towns { m["towns-" + cc] = n }
        let tf = y.townFacts
        m["regional-capitals"] = tf.filter { $0.kind == 1 }.count
        m["big-cities"] = tf.filter { $0.p >= 1_000_000 }.count
        m["small-towns"] = tf.filter { $0.p > 0 && $0.p < 5000 }.count
        let capitalOf = Set(tf.filter { $0.kind == 2 }.map(\.cc))
        for c in ["Europe", "Asia", "Africa", "North America", "South America", "Oceania"] {
            m["capitals-" + slug(c)] = w.countries.filter { $0.cont == c && capitalOf.contains($0.id) }.count
        }

        for (id, kinds) in markBadges { m[id] = y.marks.filter { kinds.contains($0) }.count }

        let pts = y.points + tf.map { BadgeInput.Point(lat: $0.lat, lon: $0.lon) }
        let boxes = places.compactMap { $0.bb.count == 4 ? $0.bb : nil }
        m["arctic"] = pts.filter { $0.lat >= arcticCircle }.count + boxes.filter { $0[1] >= arcticCircle }.count
        m["the-antarctic-circle"] = pts.filter { $0.lat <= -arcticCircle }.count + boxes.filter { $0[3] <= -arcticCircle }.count
        m["the-tropics"] = pts.filter { abs($0.lat) <= tropic }.count + boxes.filter { $0[1] >= -tropic && $0[3] <= tropic }.count
        let north = pts.filter { $0.lat > 0 }.count + boxes.filter { $0[1] > 0 }.count
        let south = pts.filter { $0.lat < 0 }.count + boxes.filter { $0[3] < 0 }.count
        m["equator"] = min(north, south)
        let east = pts.filter { lon($0.lon) > 0 && lon($0.lon) <= lineBand }.count + boxes.filter { $0[0] > 0 && $0[2] <= lineBand }.count
        let west = pts.filter { lon($0.lon) < 0 && lon($0.lon) >= -lineBand }.count + boxes.filter { $0[2] < 0 && $0[0] >= -lineBand }.count
        m["the-prime-meridian"] = min(east, west)
        let dlWest = pts.filter { lon($0.lon) >= 180 - lineBand }.count + boxes.filter { $0[0] >= 180 - lineBand && $0[2] <= 180 }.count
        let dlEast = pts.filter { lon($0.lon) <= -180 + lineBand }.count
            + boxes.filter { ($0[0] >= -180 && $0[2] <= -180 + lineBand) || ($0[0] >= 180 && $0[2] <= 180 + lineBand) }.count
        m["the-date-line"] = min(dlWest, dlEast)
        let north10 = pts.map(\.lat) + boxes.map { $0[1] }, south10 = pts.map { -$0.lat } + boxes.map { -$0[3] }
        if let n = north10.max() { m["furthest-north"] = Int((n * 10).rounded(.down)) }
        if let s = south10.max() { m["furthest-south"] = Int((s * 10).rounded(.down)) }
        var quarters = Set<Int>()
        for p in pts where p.lat != 0 && lon(p.lon) != 0 { quarters.insert((p.lat > 0 ? 0 : 2) + (lon(p.lon) > 0 ? 0 : 1)) }
        for b in boxes {
            let ns = b[1] > 0 ? 0 : (b[3] < 0 ? 2 : -1)
            let ew = b[0] > 0 && b[2] <= 180 ? 0 : (b[2] < 0 ? 1 : -1)
            if ns >= 0 && ew >= 0 { quarters.insert(ns + ew) }
        }
        m["four-hemispheres"] = quarters.count
        m["antipodes"] = antipodes(pts)

        var months = Set<Int>(), seasons = Set<Int>()
        var yearConts: [String: Set<String>] = [:]
        for d in y.dated {
            guard d.month.count >= 7, let mo = Int(d.month.dropFirst(5).prefix(2)), (1...12).contains(mo) else { continue }
            months.insert(mo)
            let p = w.places[d.cc]
            let lat = d.lat ?? p.map { $0.bb.count == 4 ? ($0.bb[1] + $0.bb[3]) / 2 : 1 } ?? 1
            var s = (mo % 12) / 3
            if lat < 0 { s = (s + 2) % 4 }
            seasons.insert(s)
            if let c = p?.cont { yearConts[String(d.month.prefix(4)), default: []].insert(c) }
        }
        m["every-month"] = months.count
        m["every-season"] = seasons.count
        m["continents-in-one-year"] = yearConts.values.map(\.count).max() ?? 0
        m["dated"] = y.dated.count

        var steps: [String: [Int]] = [:]
        if let h = y.home {
            let nb = w.places[h.cc]?.borders.filter { w.places[$0]?.k == "country" } ?? []
            m["neighbours"] = nb.filter { mine.contains($0) }.count
            let n = nb.count, d = Double(n)
            steps["neighbours"] = n <= 1 ? [1] : increasing([1, Int((0.3 * d).rounded(.up)), Int((0.55 * d).rounded(.up)), Int((0.8 * d).rounded(.up)), n])
            var far = 0.0
            for p in pts { far = max(far, gcKm(h.lat, h.lon, p.lat, p.lon)) }
            for b in boxes where !(b[0] <= h.lon && h.lon <= b[2] && b[1] <= h.lat && h.lat <= b[3]) {
                let la = min(max(h.lat, b[1]), b[3])
                var lo = h.lon
                if !(b[0] <= lo && lo <= b[2]) && !(b[0] <= lo + 360 && lo + 360 <= b[2]) {
                    let d0 = abs(lon(h.lon - b[0])), d1 = abs(lon(h.lon - b[2]))
                    lo = d0 < d1 ? b[0] : b[2]
                }
                far = max(far, gcKm(h.lat, h.lon, la, lo))
            }
            m["far"] = Int(far.rounded(.down))
        }

        if let t = w.tables {
            m["scripts"] = Set(places.flatMap(\.lang).compactMap { t.scripts[$0] }).count
            m["zones"] = zones(t, places: places.map(\.id), towns: tf)
            let mine2 = y.points
            m["highpoints"] = t.highPoints.values.filter { pk in mine2.contains { gcKm($0.lat, $0.lon, pk.lat, pk.lon) <= 1 } }.count
            let qids = Set(y.markIds.compactMap { id -> String? in
                guard let r = id.range(of: "Q", options: .backwards), id[r.lowerBound...].dropFirst().allSatisfy(\.isNumber) else { return nil }
                return String(id[r.lowerBound...])
            })
            let gids = Set(tf.map(\.gid).filter { $0 != 0 })
            let arctic = (m["arctic"] ?? 0) > 0
            for g in t.sets {
                let got = g.members.filter { reached($0, qids: qids, markIds: y.markIds, gids: gids, points: pts, mine: mine, arctic: arctic) }
                m[g.id] = g.by == "continent" ? Set(got.compactMap(\.cont)).count : got.count
            }
            var tri = Set(y.markIds.filter { $0.hasPrefix("tp:") })
            for tp in t.tripoints ?? [] where tp.p.count == 2 && mine2.contains(where: { gcKm($0.lat, $0.lon, tp.p[0], tp.p[1]) <= 2 }) {
                tri.insert(tp.id)
            }
            m["tripoints"] = tri.count
            var hs = y.markHeights
            for tm in tf { if let h = t.heights?[String(tm.gid)] { hs.append(Double(h)) } }
            for pk in t.highPoints.values where pk.m != nil && mine2.contains(where: { gcKm($0.lat, $0.lon, pk.lat, pk.lon) <= 1 }) {
                hs.append(pk.m!)
            }
            m["highest-place"] = max(0, Int((hs.max() ?? 0).rounded(.down)))
            m["lowest-place"] = max(0, Int((-(hs.min() ?? 0)).rounded(.down)))
        } else {
            m["tripoints"] = Set(y.markIds.filter { $0.hasPrefix("tp:") }).count
            m["highest-place"] = max(0, Int((y.markHeights.max() ?? 0).rounded(.down)))
            m["lowest-place"] = max(0, Int((-(y.markHeights.min() ?? 0)).rounded(.down)))
        }
        return (m, fixed, steps)
    }

    static func zones(_ t: BadgeTables, places: [String], towns: [BadgeInput.TownMark]) -> Int {
        var sure = Set<Int>()
        var withTown = Set<String>()
        for tm in towns {
            guard let z = t.zones[tm.cc] else { continue }
            sure.insert(z.except[String(tm.gid)] ?? (z.zones.count == 1 ? z.zones[0] : z.town))
            withTown.insert(tm.cc)
        }
        var unsure: [[Int]] = []
        for id in places {
            guard let z = t.zones[id] else { continue }
            if z.zones.count == 1 { sure.insert(z.zones[0]) }
            else if !withTown.contains(id) { unsure.append(z.zones) }
        }
        var extra = 0
        for zs in unsure where !zs.contains(where: sure.contains) { extra += 1 }
        return sure.count + extra
    }

    static func reached(_ x: BadgeTables.Member, qids: Set<String>, markIds: Set<String> = [], gids: Set<Int>,
                        points: [BadgeInput.Point], mine: Set<String>, arctic: Bool) -> Bool {
        for id in [x.q].compactMap({ $0 }) + (x.qs ?? []) {
            if id.contains(":") ? markIds.contains(id) : qids.contains(id) { return true }
        }
        if let g = x.gid, gids.contains(g) { return true }
        if let p = x.place, mine.contains(p) { return true }
        if x.arctic == true && arctic { return true }
        if let r = x.r, let la = x.lat, let lo = x.lon, points.contains(where: { gcKm($0.lat, $0.lon, la, lo) <= r }) { return true }
        if let sh = x.shape, !sh.isEmpty, points.contains(where: { inside($0, sh) }) { return true }
        return false
    }

    static func inside(_ p: BadgeInput.Point, _ rings: [[[Double]]]) -> Bool {
        var c = false
        for r in rings where r.count >= 3 {
            var j = r.count - 1
            for i in 0..<r.count {
                let xi = r[i][0], yi = r[i][1], xj = r[j][0], yj = r[j][1]
                if (yi > p.lat) != (yj > p.lat), p.lon < (xj - xi) * (p.lat - yi) / (yj - yi) + xi { c.toggle() }
                j = i
            }
        }
        return c
    }

    static func gcKm(_ lat0: Double, _ lon0: Double, _ lat1: Double, _ lon1: Double) -> Double {
        let k = Double.pi / 180
        let a = sin((lat1 - lat0) * k / 2), b = sin((lon1 - lon0) * k / 2)
        let h = a * a + cos(lat0 * k) * cos(lat1 * k) * b * b
        return 2 * 6371.0 * asin(min(1, h.squareRoot()))
    }

    private static func lon(_ x: Double) -> Double {
        var v = x.truncatingRemainder(dividingBy: 360)
        if v > 180 { v -= 360 } else if v < -180 { v += 360 }
        return v
    }

    static func antipodes(_ pts: [BadgeInput.Point]) -> Int {
        var seen = Set<Int>(), cells: [BadgeInput.Point] = []
        for p in pts {
            let k = Int((p.lat + 90).rounded(.down)) * 1000 + Int((lon(p.lon) + 180).rounded(.down))
            if seen.insert(k).inserted { cells.append(p) }
        }
        func square(_ p: BadgeInput.Point) -> Int { Int((p.lat + 90) / 10) * 100 + Int((lon(p.lon) + 180) / 10) }
        var pairs = Set<Int>()
        for i in cells.indices {
            let a = cells[i]
            for j in cells.indices where j > i {
                let b = cells[j]
                guard gcKm(a.lat, a.lon, -b.lat, lon(b.lon + 180)) <= 500 else { continue }
                let s0 = square(a), s1 = square(b)
                pairs.insert(min(s0, s1) * 100_000 + max(s0, s1))
            }
        }
        return pairs.count
    }

    static func bigYear(_ years: [Int]) -> Int {
        var by: [Int: Int] = [:]
        for y in years { by[y, default: 0] += 1 }
        return by.values.max() ?? 0
    }
}
