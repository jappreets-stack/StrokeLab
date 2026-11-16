import Foundation

/// What the iPhone tells the watch: the round in progress, your hole plans, and rounds that just ended.
nonisolated struct WatchSnapshot: Codable, Sendable {
    var round: Round?
    var plans: [HolePlan]
    var finishedIDs: [UUID]
    var clubYards: [String: Int]?
    var recent: [Round]?          // last finished rounds, newest first, for the watch's Past rounds
}

/// Something done on the watch, sent to the iPhone.
nonisolated struct WatchEvent: Codable, Sendable {
    enum Kind: Codable, Sendable {
        case start(Round)
        case score(round: UUID, hole: Int, score: Int?, putts: Int?)
        case hole(round: UUID, hole: Int)
        case tee(round: UUID, hole: Int, result: TeeResult?, miss: MissSize?)
        case end(round: UUID)
        case delete(round: UUID)                    // past round deleted on the watch
        case entry(round: UUID, hole: HoleScore)   // everything you entered for one hole
    }
    var kind: Kind
    var at = Date()
}

extension JSONEncoder {
    nonisolated static var app: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    nonisolated static var app: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
