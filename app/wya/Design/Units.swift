import Foundation

/// DISTANCES AND AREAS IN THE PHONE'S OWN UNITS (his 14 Oct: units "should just default to your location's ... and then
/// you edit it in settings"): miles and feet where the phone's region uses them (the US, the UK, Liberia, Myanmar), km
/// and metres everywhere else. The badges' levels stay as they were set, in km (their goals are round numbers).
nonisolated enum Units {
    /// the phone reads distances in miles
    static var miles: Bool {
        let m = system
        return m == .us || m == .uk
    }

    /// the phone's own measures, unless Settings' Units picked Metric or Imperial (the US measures)
    static var system: Locale.MeasurementSystem {
        switch AppSettings.units {
        case "metric": .metric
        case "imperial": .us
        default: Locale.current.measurementSystem
        }
    }

    /// "850 m", "2.4 km", "12 km"; "900 ft", "1.5 mi", "8 mi"
    static func distance(km d: Double) -> String {
        if miles {
            let mi = d * 0.621371
            if mi < 0.2 { return "\(Int((d * 3280.84 / 50).rounded()) * 50) ft" }
            return mi < 10 ? String(format: "%.1f mi", mi) : "\(Int(mi.rounded()).formatted()) mi"
        }
        return d < 1 ? "\(Int((d * 1000 / 10).rounded()) * 10) m" : d < 10 ? String(format: "%.1f km", d) : "\(Int(d.rounded()).formatted()) km"
    }

    /// a whole number of km in the phone's unit, as "9,840 km" or "6,114 mi"
    static func distance(wholeKm km: Int) -> String {
        miles ? "\(Int((Double(km) * 0.621371).rounded()).formatted()) mi" : "\(km.formatted()) km"
    }

    /// an area: "0.3 ha", "12 km²"; "75 acres", "4.6 sq mi" (only the US reads areas in square miles)
    static func area(km2 a: Double) -> String {
        if system == .us {
            let sq = a * 0.386102
            return sq < 1 ? "\(Int((a * 247.105).rounded()).formatted()) acres" : sq < 10 ? String(format: "%.1f sq mi", sq) : "\(Int(sq.rounded()).formatted()) sq mi"
        }
        return a < 1 ? String(format: "%.1f ha", a * 100) : a < 10 ? String(format: "%.1f km²", a) : "\(Int(a.rounded()).formatted()) km²"
    }

    /// the phone reads heights in feet, areas in square miles and temperatures in Fahrenheit (the US)
    static var us: Bool { system == .us }

    /// a height: "1,085 m" or "3,560 ft"
    static func height(m: Double) -> String {
        us ? "\(Int((m * 3.28084).rounded()).formatted()) ft" : "\(Int(m.rounded()).formatted()) m"
    }
    /// a large area in whole numbers: "357,022 km²" or "137,847 sq mi"
    static func area(wholeKm2 a: Double) -> String {
        us ? "\(Int((a * 0.386102).rounded()).formatted()) sq mi" : "\(Int(a.rounded()).formatted()) km²"
    }
    /// a temperature's number in the phone's scale (the degree sign is the caller's)
    static func degrees(c: Double) -> Int { Int((us ? c * 9 / 5 + 32 : c).rounded()) }
}
