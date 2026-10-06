import Foundation

func esc(_ d: Date?) -> String {
    guard let d else { return "null" }
    return String(format: "%.6f", d.timeIntervalSince1970)
}

let locations: [(String, Double, Double)] = [
    ("cleveland", 41.5, -82.7), ("polar_north", 70.0, 25.0), ("sydney", -33.9, 151.2),
    ("equator", 0.0, 0.0), ("reykjavik", 64.1, -21.9), ("tokyo", 35.7, 139.7),
    ("anchorage", 61.2, -149.9), ("antarctic", -78.0, 166.0)
]
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!

var solunar: [String] = []
for (name, lat, lon) in locations {
    for month in [1, 3, 6, 9, 12] {
        for day in [1, 8, 15, 22, 28] {
            let date = cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            if let r = SolunarCalculator.calculate(for: date, latitude: lat, longitude: lon) {
                let major = r.majorPeriods.map { "[\(esc($0.start)),\(esc($0.end))]" }.joined(separator: ",")
                let minor = r.minorPeriods.map { "[\(esc($0.start)),\(esc($0.end))]" }.joined(separator: ",")
                solunar.append("{\"loc\":\"\(name)\",\"lat\":\(lat),\"lon\":\(lon),\"date\":\(esc(date)),\"transit\":\(esc(r.transit)),\"antitransit\":\(esc(r.antitransit)),\"moonrise\":\(esc(r.moonrise)),\"moonset\":\(esc(r.moonset)),\"major\":[\(major)],\"minor\":[\(minor)]}")
            } else {
                solunar.append("{\"loc\":\"\(name)\",\"lat\":\(lat),\"lon\":\(lon),\"date\":\(esc(date)),\"none\":true}")
            }
        }
    }
}

var moon: [String] = []
var t = 947_182_440.0 - 3 * 86_400
while t < 947_182_440.0 + 120 * 86_400 {
    let p = MoonPhase(date: Date(timeIntervalSince1970: t))
    moon.append("{\"t\":\(String(format: "%.1f", t)),\"phase\":\"\(p.rawValue)\"}")
    t += 17.3 * 3600
}

var weight: [String] = []
for id in ["largemouth-bass", "walleye", "northern-pike", "bluegill", "tarpon", "custom:foo"] {
    for len in [8.0, 14.5, 22.0, 31.25, 40.0] {
        let w = SpeciesCatalog.estimatedWeightPounds(speciesID: id, lengthInches: len)
        weight.append("{\"id\":\"\(id)\",\"len\":\(len),\"lb\":\(w.map { String(format: "%.9f", $0) } ?? "null")}")
    }
}

print("{\"solunar\":[\(solunar.joined(separator: ",\n"))],\n\"moon\":[\(moon.joined(separator: ",\n"))],\n\"weight\":[\(weight.joined(separator: ",\n"))]}")
