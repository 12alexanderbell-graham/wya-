import Foundation

enum StampDate {
    static let names: [String: [String]] = {
        let mon = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        return [
            "MON": mon,
            "Mon": mon.map { $0.prefix(1) + $0.dropFirst().lowercased() },
            "MONd": mon.map { $0 == "MAY" ? $0 : $0 + "." },
            "ROM": ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"],
            "DE": ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November",
                   "Dezember"],
            "FRMC": ["JANV.", "FEV.", "MARS", "AVR.", "MAI", "JUIN", "JUIL.", "AOUT", "SEPT.", "OCT.", "NOV.", "DEC."],
            "FRLB": ["JANV.", "FÉVR.", "MARS", "AVR.", "MAI", "JUIN", "JUIL.", "AOÛT", "SEPT.", "OCT.", "NOV.", "DÉC."],
            "FRAF": ["JAN.", "FEV.", "MARS", "AVR.", "MAI", "JUIN", "JUIL.", "AOUT", "SEPT.", "OCT.", "NOV.", "DEC."],
            "FRCG": ["JAN", "FEV", "MARS", "AVR", "MAI", "JUIN", "JUIL", "AOUT", "SEPT", "OCT", "NOV", "DEC"],
            "ES": ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"],
            "ESL": ["ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO", "JULIO", "AGOSTO", "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE",
                    "DICIEMBRE"],
            "DKd": ["JAN.", "FEB.", "MAR.", "APR.", "MAJ", "JUN.", "JUL.", "AUG.", "SEP.", "OKT.", "NOV.", "DEC."],
            "SY": ["كانون الثاني", "شباط", "آذار", "نيسان", "أيار", "حزيران", "تموز", "آب", "أيلول", "تشرين الأول", "تشرين الثاني",
                   "كانون الأول"],
            "PE": ["ENE.", "FEB.", "MAR.", "ABR.", "MAY.", "JUN.", "JUL.", "AGO.", "SET.", "OCT.", "NOV.", "DIC."],
            "ESd": ["ENE.", "FEB.", "MAR.", "ABR.", "MAY.", "JUN.", "JUL.", "AGO.", "SEP.", "OCT.", "NOV.", "DIC."],
            "CA": ["JA", "FE", "MR", "AL", "MA", "JN", "JL", "AU", "SE", "OC", "NO", "DE"],
            "TN": ["جانفي", "فيفري", "مارس", "أفريل", "ماي", "جوان", "جويلية", "أوت", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"],
            "IT": ["GEN.", "FEB.", "MAR.", "APR.", "MAG.", "GIU.", "LUG.", "AGO.", "SET.", "OTT.", "NOV.", "DIC."],
            "TR": ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım",
                   "Aralık"],
            "EG": ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر",
                   "ديسمبر"],
            "HM": ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال",
                   "ذو القعدة", "ذو الحجة"],
        ]
    }()
    static let digits: [String: [Character]] = ["ar": Array("٠١٢٣٤٥٦٧٨٩"), "fa": Array("۰۱۲۳۴۵۶۷۸۹")]

    /// the template's words for a stamp dated `day`
    static func render(_ template: String, _ day: RealStamps.Day) -> String {
        var out = ""
        var i = template.startIndex
        while i < template.endIndex {
            if template[i] == "{", let j = template[i...].firstIndex(of: "}") {
                out += field(String(template[template.index(after: i)..<j]), day)
                i = template.index(after: j)
            } else {
                out.append(template[i])
                i = template.index(after: i)
            }
        }
        return out
    }

    /// one field: "dd",,, "hHM"
    static func field(_ spec: String, _ day: RealStamps.Day) -> String {
        var name = spec, plus = 0
        if let p = name.firstIndex(of: "+") {
            plus = Int(name[name.index(after: p)...]) ?? 0
            name = String(name[..<p])
        }
        var dg = ""
        if let a = name.firstIndex(of: "@") {
            dg = String(name[name.index(after: a)...])
            name = String(name[..<a])
        }
        let t = plus == 0 ? day : day.plus(plus)
        var (y, m, d) = (t.y, t.m, t.d)
        let calendarParts: Set<String> = ["d", "dd", "d-", "d_", "M", "MM", "yy", "yyyy", "HM"]
        if let f = name.first, f == "j" || f == "h", calendarParts.contains(String(name.dropFirst())) {
            (y, m, d) = f == "j" ? persian(t) : hijri(t)
            name = String(name.dropFirst())
        }
        let v: String
        if let list = names[name] {
            v = list[m - 1]
        } else {
            switch name {
            case "d": v = "\(d)"
            case "dd": v = two(d)
            case "d-": v = d < 10 ? "-\(d)" : two(d)
            case "d_": v = d < 10 ? "- \(d)" : "\(d)"
            case "d1": v = String(two(d).first!)
            case "d2": v = String(two(d).last!)
            case "M": v = "\(m)"
            case "MM": v = two(m)
            case "yy": v = two(((y % 100) + 100) % 100)
            case "yyyy": v = "\(y)"
            default: return "{\(spec)}"
            }
        }
        guard let set = digits[dg] else { return v }
        return String(v.map { c in c.wholeNumberValue.map { set[$0] } ?? c })
    }

    static func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// the Iranian (Solar Hijri) year, month and day, as Iran's stamp counts them
    static func persian(_ t: RealStamps.Day) -> (Int, Int, Int) {
        let gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        let gy = t.y, gm = t.m, gd = t.d
        let gy2 = gm > 2 ? gy + 1 : gy
        var days = 355666 + 365 * gy + fdiv(gy2 + 3, 4) - fdiv(gy2 + 99, 100) + fdiv(gy2 + 399, 400) + gd + gdm[gm - 1]
        var jy = -1595 + 33 * fdiv(days, 12053)
        days = mod(days, 12053)
        jy += 4 * fdiv(days, 1461)
        days = mod(days, 1461)
        if days > 365 {
            jy += fdiv(days - 1, 365)
            days = mod(days - 1, 365)
        }
        let jm = days < 186 ? 1 + days / 31 : 7 + (days - 186) / 30
        let jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30)
        return (jy, jm, jd)
    }

    /// the Hijri year, month and day by the Umm al-Qura calendar, as Saudi Arabia's stamp counts them
    static func hijri(_ t: RealStamps.Day) -> (Int, Int, Int) {
        var g = Calendar(identifier: .gregorian)
        g.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents()
        c.year = t.y; c.month = t.m; c.day = t.d; c.hour = 12
        guard let at = g.date(from: c) else { return (0, 1, 1) }
        var h = Calendar(identifier: .islamicUmmAlQura)
        h.timeZone = TimeZone(identifier: "UTC")!
        let r = h.dateComponents([.year, .month, .day], from: at)
        return (r.year ?? 0, r.month ?? 1, r.day ?? 1)
    }

    static func fdiv(_ a: Int, _ b: Int) -> Int { Int((Double(a) / Double(b)).rounded(.down)) }
    static func mod(_ a: Int, _ b: Int) -> Int { ((a % b) + b) % b }
}
