import Foundation
import CoreLocation
import Observation

/// Your carry distance with each club, in yards. Edit them in Course → My club distances.
nonisolated enum ClubYards {
    static let defaults: [String: Int] = [
        "Driver": 225, "3H": 180, "5i": 165, "6i": 158, "7i": 148, "8i": 138, "9i": 128,
        "PW": 122, "AW": 112, "GW": 105, "56": 92, "60": 80,
    ]

    /// Shortest club that still gets there; the longest club if nothing does.
    static func club(for yards: Int, _ table: [String: Int]) -> Club? {
        let carries = Club.allCases.compactMap { c in table[c.rawValue].map { (c, $0) } }
            .sorted { $0.1 < $1.1 }
        return carries.first { $0.1 >= yards }?.0 ?? carries.last?.0
    }
}

/// Wind at the course right now.
nonisolated struct Wind: Codable, Sendable, Equatable {
    var mph: Double
    var fromDegrees: Double       // where it blows from (0 = north)
    var gustMph: Double
    var at: Date

    /// + = into your face, − = helping, for a shot heading `shotBearing`.
    func headwind(shotBearing: Double) -> Double {
        mph * cos((fromDegrees - shotBearing) * .pi / 180)
    }
    func crosswind(shotBearing: Double) -> Double {
        mph * sin((fromDegrees - shotBearing) * .pi / 180)   // + = from the right
    }

    /// Rule of thumb: into the wind adds 1% per mph, helping wind takes off 0.5% per mph.
    func playsLike(_ yards: Int, shotBearing: Double) -> Int {
        let h = headwind(shotBearing: shotBearing)
        let factor = h >= 0 ? 1 + 0.01 * h : 1 + 0.005 * h
        return Int((Double(yards) * factor).rounded())
    }

    /// e.g. "Into 9" · "Helping 6" · "Cross 7 →" · "Calm"
    func label(shotBearing: Double) -> String {
        guard mph >= 3 else { return "Calm" }
        let h = headwind(shotBearing: shotBearing), c = crosswind(shotBearing: shotBearing)
        if abs(h) >= abs(c) { return h > 0 ? "Into \(Int(h.rounded()))" : "Helping \(Int((-h).rounded()))" }
        return c > 0 ? "← Cross \(Int(c.rounded()))" : "Cross \(Int((-c).rounded())) →"
    }

    /// Arrow angle for the wind relative to your shot (0 = straight at the green / helping).
    func arrowDegrees(shotBearing: Double) -> Double { fromDegrees + 180 - shotBearing }
}

/// Fetches the wind at the course from Open-Meteo (free, no account). Only the course's
/// public coordinates are sent, never your location. Refreshes at most every 10 minutes.
@Observable
final class WindModel {
    static let shared = WindModel()
    var wind: Wind?
    @ObservationIgnored private var loading = false

    func refresh() async {
        if let w = wind, Date().timeIntervalSince(w.at) < 600 { return }
        guard !loading, let c = CourseGreens.pins.first?.center else { return }
        loading = true
        defer { loading = false }
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.lat)&longitude=\(c.lon)"
                      + "&current=wind_speed_10m,wind_direction_10m,wind_gusts_10m&wind_speed_unit=mph")!
        struct R: Decodable { struct C: Decodable { let wind_speed_10m: Double; let wind_direction_10m: Double; let wind_gusts_10m: Double }; let current: C }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(R.self, from: data) else { return }
        wind = Wind(mph: r.current.wind_speed_10m, fromDegrees: r.current.wind_direction_10m,
                    gustMph: r.current.wind_gusts_10m, at: Date())
    }
}

extension Coordinate {
    /// Compass bearing from here to `o`, in degrees.
    nonisolated func bearing(to o: Coordinate) -> Double {
        let p1 = lat * .pi / 180, p2 = o.lat * .pi / 180, dl = (o.lon - lon) * .pi / 180
        let y = sin(dl) * cos(p2), x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// One line for under the yardages: wind, plays-like distance and the club for it.
nonisolated struct ShotAdvice: Sendable {
    let windText: String?
    let arrow: Double?
    let playsLike: Int
    let club: Club?

    static func make(from me: CLLocation?, to green: Coordinate?, wind: Wind?, clubs: [String: Int]) -> ShotAdvice? {
        guard let me, let green else { return nil }
        let here = Coordinate(lat: me.coordinate.latitude, lon: me.coordinate.longitude)
        let yards = Int(here.yards(to: green).rounded())
        guard yards > 0, yards < 400 else { return nil }
        let b = here.bearing(to: green)
        let plays = wind?.playsLike(yards, shotBearing: b) ?? yards
        return ShotAdvice(windText: wind?.label(shotBearing: b), arrow: wind?.arrowDegrees(shotBearing: b),
                          playsLike: plays, club: ClubYards.club(for: plays, clubs))
    }
}
