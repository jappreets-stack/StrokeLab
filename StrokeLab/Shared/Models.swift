import Foundation

// MARK: - Small vocab types

nonisolated enum Club: String, Codable, CaseIterable, Identifiable, Sendable {
    case driver = "Driver", hybrid3 = "3H", i5 = "5i", i6 = "6i", i7 = "7i", i8 = "8i", i9 = "9i"
    case pw = "PW", aw = "AW", gw = "GW", w56 = "56", w60 = "60"
    var id: String { rawValue }
    static let wedges: [Club] = [.pw, .aw, .gw, .w56, .w60]
}

nonisolated enum TeeResult: String, Codable, CaseIterable, Sendable {
    case left = "Left", fairway = "Fairway", green = "Green", right = "Right", short = "Short", long = "Long"
    static func options(par: Int) -> [TeeResult] {
        par == 3 ? [.left, .green, .right, .short, .long] : [.left, .fairway, .right, .short]
    }
}

/// How bad a missed tee shot was: a foot into the first cut is not the same as the trees.
nonisolated enum MissSize: String, Codable, CaseIterable, Sendable {
    case justOff = "Just off", rough = "Rough", trouble = "In trouble"
    var label: String { self == .trouble ? "Trouble" : rawValue }
}

/// How far the first putt finished from the hole when it missed.
nonisolated enum PuttMiss: String, Codable, CaseIterable, Sendable {
    case tapIn = "Tap-in", close = "3–6 ft", far = "6+ ft"
}

nonisolated enum TroubleSide: String, Codable, CaseIterable, Sendable {
    case none = "None", left = "Left", right = "Right", both = "Both sides", short = "Short", long = "Long"
}

nonisolated enum Hazard: String, Codable, CaseIterable, Sendable {
    case ob = "OB", water = "Water", trees = "Trees", bunker = "Bunker"
}

nonisolated enum WarmUp: String, Codable, Sendable {
    case none = "No warm-up", routine = "5-min routine", full = "Full warm-up"
}

nonisolated enum RoundType: String, Codable, CaseIterable, Sendable {
    case front = "Front 9", back = "Back 9", full = "18 holes"
    var holeNumbers: [Int] {
        switch self {
        case .front: Array(1...9)
        case .back: Array(10...18)
        case .full: Array(1...18)
        }
    }
}

nonisolated enum PuttLength: String, Codable, CaseIterable, Sendable {
    case tap = "< 3 ft", short = "3–6", mid = "6–10", medium = "10–20", long = "20–35", lag = "35+"
}

nonisolated enum PuttResult: String, Codable, CaseIterable, Sendable {
    case made = "Made", short = "Short", long = "Long", left = "Left", right = "Right"
}

nonisolated enum UpDown: String, Codable, Sendable {
    case notAttempted, missed, made
}

// MARK: - Plans and pins

nonisolated struct HolePlan: Codable, Sendable, Equatable {
    var hole: Int
    var troubleSide: TroubleSide = .none
    var hazards: [Hazard] = []
    var teeClub: Club = .hybrid3
    var target: Int
    var note: String = ""
    var greenRead: String?          // e.g. "everything breaks toward the clubhouse"

    var troubleText: String {
        if troubleSide == .none && hazards.isEmpty { return "No trouble set" }
        let what = hazards.isEmpty ? "Trouble" : hazards.map(\.rawValue).joined(separator: " + ")
        return troubleSide == .none ? what : "\(what) \(troubleSide.rawValue.lowercased())"
    }
}

nonisolated struct Coordinate: Codable, Sendable, Equatable {
    var lat: Double
    var lon: Double
}

extension Coordinate {
    nonisolated func yards(to o: Coordinate) -> Double {
        let r = 6_371_000.0, p1 = lat * .pi / 180, p2 = o.lat * .pi / 180
        let dp = p2 - p1, dl = (o.lon - lon) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h))) * 1.09361
    }
}

nonisolated struct GreenPins: Codable, Sendable, Equatable {
    var hole: Int
    var front: Coordinate?
    var center: Coordinate?
    var back: Coordinate?
    var isComplete: Bool { front != nil && center != nil && back != nil }
    /// Widest gap between this green's pins, in yards. A real green is under ~50 yds deep.
    var spreadYards: Double {
        let pts = [front, center, back].compactMap { $0 }
        var m = 0.0
        for i in pts.indices { for j in pts.indices where j > i { m = max(m, pts[i].yards(to: pts[j])) } }
        return m
    }
}

// MARK: - Rounds

nonisolated struct HoleScore: Codable, Sendable, Identifiable, Equatable {
    var hole: Int
    var score: Int?
    var putts: Int?
    var teeClub: Club?
    var teeResult: TeeResult?
    var missSize: MissSize?         // only when the tee shot missed
    var greenOverride: Bool?        // nil = work it out from score and putts
    var penalties: Int = 0
    var lostBall: Bool = false
    var upDownOverride: UpDown?     // nil = work it out
    var firstPutt: PuttLength?      // length of the first putt
    var firstPuttResult: PuttResult? // how the first putt finished
    var puttMiss: PuttMiss?         // how far it finished from the hole
    var sand: Bool?                 // were you in a greenside bunker
    var prefilled: Bool?            // true until you change anything on this hole
    var id: Int { hole }
    var teeMissed: Bool { teeResult != nil && teeResult != .fairway && teeResult != .green }

    var par: Int { Course.hole(hole).par }
    var isEntered: Bool { score != nil }

    /// Green in regulation: on the green with two putts' worth of par left.
    var autoGreen: Bool? {
        guard let score, let putts else { return nil }
        return score - putts <= par - 2
    }
    var greenHit: Bool? { greenOverride ?? autoGreen }

    /// Missed the green → an up-and-down chance; made = still made par or better.
    var autoUpDown: UpDown {
        guard let score, let green = greenHit else { return .notAttempted }
        if green { return .notAttempted }
        return score <= par ? .made : .missed
    }
    var upDown: UpDown { upDownOverride ?? autoUpDown }
}

nonisolated struct Round: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var type: RoundType
    var warmUp: WarmUp?
    var scoresOnly = false
    var finished = false
    var currentHole: Int?          // hole number you were last on
    var holes: [HoleScore]

    init(type: RoundType, date: Date = Date(), scoresOnly: Bool = false) {
        self.type = type
        self.date = date
        self.scoresOnly = scoresOnly
        self.holes = type.holeNumbers.map { HoleScore(hole: $0) }
    }

    var entered: [HoleScore] { holes.filter(\.isEntered) }
    var total: Int { entered.compactMap(\.score).reduce(0, +) }
    var parPlayed: Int { entered.map(\.par).reduce(0, +) }
    var toPar: Int { total - parPlayed }
    var putts: Int { entered.compactMap(\.putts).reduce(0, +) }
    var isComplete: Bool { entered.count == holes.count }
}

/// Everything the app saves, in one file.
nonisolated struct AppData: Codable, Sendable {
    var version = 1
    var plans: [HolePlan]
    var pins: [GreenPins]
    var rounds: [Round] = []
    var currentRoundID: UUID?
    var clubYards: [String: Int]?   // nil = ClubYards.defaults
}

func toParText(_ n: Int) -> String { n == 0 ? "E" : (n > 0 ? "+\(n)" : "\(n)") }
