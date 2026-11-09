import Foundation
import Observation

/// Holds all app data and saves it to one JSON file on this iPhone after every change.
@Observable
final class Store {
    var data: AppData { didSet { save() } }

    static let fileURL = URL.documentsDirectory.appending(path: "strokelab.json")

    init() {
        if let raw = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder.app.decode(AppData.self, from: raw) {
            data = saved
        } else {
            data = AppData(plans: Self.draftPlans(), pins: (1...18).map { GreenPins(hole: $0) })
        }
    }

    private func save() {
        guard let raw = try? JSONEncoder.app.encode(data) else { return }
        try? raw.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: Plans & pins

    func plan(_ hole: Int) -> HolePlan { data.plans[hole - 1] }
    func pins(_ hole: Int) -> GreenPins { data.pins[hole - 1] }

    // MARK: Rounds

    var currentRound: Round? {
        guard let id = data.currentRoundID else { return nil }
        return data.rounds.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? { data.rounds.firstIndex { $0.id == id } }

    @discardableResult
    func startRound(_ type: RoundType, warmUp: WarmUp) -> UUID {
        var round = Round(type: type)
        round.warmUp = warmUp
        // Pre-fill each hole's tee club from the plan; you only change it when you didn't follow the plan.
        for i in round.holes.indices {
            round.holes[i].teeClub = plan(round.holes[i].hole).teeClub
        }
        data.rounds.insert(round, at: 0)
        data.currentRoundID = round.id
        return round.id
    }

    func finishCurrentRound() {
        if let id = data.currentRoundID, let i = index(of: id) {
            data.rounds[i].finished = true
        }
        data.currentRoundID = nil
    }

    func delete(_ id: UUID) {
        if data.currentRoundID == id { data.currentRoundID = nil }
        data.rounds.removeAll { $0.id == id }
    }

    func addPastRound(_ round: Round) {
        var r = round
        r.finished = true
        data.rounds.append(r)
        data.rounds.sort { $0.date > $1.date }
    }

    // MARK: Backup

    func importBackup(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let raw = try Data(contentsOf: url)
        data = try JSONDecoder.app.decode(AppData.self, from: raw)
    }

    /// Writes a dated copy for sharing (AirDrop, Files, iCloud Drive).
    func exportFile() -> URL {
        let name = "StrokeLab backup \(Date().formatted(.iso8601.year().month().day())).json"
        let url = URL.temporaryDirectory.appending(path: name)
        if let raw = try? JSONEncoder.app.encode(data) { try? raw.write(to: url, options: .atomic) }
        return url
    }

    // MARK: Draft hole plans (edit them in the Course tab)

    static func draftPlans() -> [HolePlan] {
        // Par-3 clubs by yardage; everything else: 3-hybrid off the tee.
        let par3Club: [Int: Club] = [2: .i6, 6: .pw, 9: .i7, 11: .hybrid3, 14: .i6, 16: .pw]
        return Course.holes.map { h in
            switch h.par {
            case 3:
                let short = h.yards < 125
                return HolePlan(hole: h.number, teeClub: par3Club[h.number] ?? .i7,
                                target: short ? 3 : 4,
                                note: short ? "Center of green, not the flag. Par chance." :
                                              "Center of green. Short and on is fine — bogey is a good score.")
            case 5:
                return HolePlan(hole: h.number, teeClub: .hybrid3, target: 6,
                                note: "Hybrid → lay up to a full-wedge number → center of green → two putts.")
            default:
                let long = h.yards > 370
                return HolePlan(hole: h.number, teeClub: .hybrid3, target: 5,
                                note: long ? "Hybrid, hybrid/iron short of trouble, wedge on. Bogey is the plan."
                                           : "Hybrid in play, then center of green. Par chance if the tee shot is good.")
            }
        }
    }
}

extension JSONEncoder {
    static var app: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var app: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
