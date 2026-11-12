import Foundation

/// What the iPhone tells the watch: the round in progress, your hole plans, and rounds that just ended.
nonisolated struct WatchSnapshot: Codable, Sendable {
    var round: Round?
    var plans: [HolePlan]
    var finishedIDs: [UUID]
}

/// Something done on the watch, sent to the iPhone.
nonisolated struct WatchEvent: Codable, Sendable {
    enum Kind: Codable, Sendable {
        case start(Round)
        case score(round: UUID, hole: Int, score: Int?, putts: Int?)
        case hole(round: UUID, hole: Int)
        case tee(round: UUID, hole: Int, result: TeeResult?, miss: MissSize?)
        case end(round: UUID)
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
