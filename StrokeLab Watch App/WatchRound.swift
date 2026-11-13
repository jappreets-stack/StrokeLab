import Foundation
import Observation
import WatchConnectivity

/// The round on the watch. Starts here or on the iPhone; whichever you use, the other follows.
@Observable
final class WatchRound: NSObject, WCSessionDelegate {
    static let shared = WatchRound()

    var round: Round? { didSet { save() } }
    var plans: [HolePlan] = [] { didSet { save() } }
    var hole = 1 { didSet { save() } }
    var clubYards: [String: Int] = ClubYards.defaults { didSet { save() } }

    /// Scores tapped here that the iPhone hasn't confirmed yet (so a late update can't undo them).
    @ObservationIgnored private var pending: [Int: HoleScore] = [:]
    /// Hole picked here that the iPhone hasn't confirmed yet.
    @ObservationIgnored private var pendingHole: (hole: Int, at: Date)?

    override init() {
        super.init()
        let d = UserDefaults.standard
        if let raw = d.data(forKey: "round") { round = try? JSONDecoder.app.decode(Round.self, from: raw) }
        if let raw = d.data(forKey: "plans"), let p = try? JSONDecoder.app.decode([HolePlan].self, from: raw), p.count == 18 { plans = p }
        hole = max(1, min(18, d.integer(forKey: "hole")))
        if let raw = d.data(forKey: "clubs"), let c = try? JSONDecoder.app.decode([String: Int].self, from: raw) { clubYards = c }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(round.flatMap { try? JSONEncoder.app.encode($0) }, forKey: "round")
        d.set(try? JSONEncoder.app.encode(plans), forKey: "plans")
        d.set(hole, forKey: "hole")
        d.set(try? JSONEncoder.app.encode(clubYards), forKey: "clubs")
    }

    func plan(_ n: Int) -> HolePlan? { plans.first { $0.hole == n } }
    func score(_ n: Int) -> HoleScore? { round?.holes.first { $0.hole == n } }

    // MARK: Actions on the watch

    func start(_ type: RoundType) {
        var r = Round(type: type)
        let first = type.holeNumbers.first ?? 1
        r.currentHole = first
        round = r
        hole = first
        pending = [:]
        send(.start(r))
    }

    func go(to n: Int) {
        hole = min(18, max(1, n))
        guard var r = round else { return }
        r.currentHole = hole
        round = r
        pendingHole = (hole, Date())
        send(.hole(round: r.id, hole: hole))
    }

    /// Change anything about the current hole; the iPhone gets the whole hole.
    func update(_ change: (inout HoleScore) -> Void) {
        guard var r = round else { return }
        if !r.holes.contains(where: { $0.hole == hole }) {
            var h = HoleScore(hole: hole)
            h.teeClub = plan(hole)?.teeClub
            r.holes.append(h); r.holes.sort { $0.hole < $1.hole }
        }
        let i = r.holes.firstIndex { $0.hole == hole }!
        change(&r.holes[i])
        if !r.holes[i].teeMissed { r.holes[i].missSize = nil }
        if r.holes[i].firstPuttResult == nil || r.holes[i].firstPuttResult == .made { r.holes[i].puttMiss = nil }
        round = r
        pending[hole] = r.holes[i]
        send(.entry(round: r.id, hole: r.holes[i]))
    }

    func end() {
        if let r = round { send(.end(round: r.id)) }
        round = nil
        pending = [:]
        hole = 1
    }

    private func send(_ kind: WatchEvent.Kind) {
        guard let raw = try? JSONEncoder.app.encode(WatchEvent(kind: kind)) else { return }
        let msg: [String: Any] = ["event": raw]
        let s = WCSession.default
        if s.activationState == .activated, s.isReachable {
            s.sendMessage(msg, replyHandler: nil) { _ in s.transferUserInfo(msg) }
        } else {
            s.transferUserInfo(msg)
        }
    }

    // MARK: From the iPhone

    private func apply(_ snap: WatchSnapshot) {
        if snap.plans.count == 18 { plans = snap.plans }
        clubYards = snap.clubYards ?? ClubYards.defaults
        if let r = round, snap.finishedIDs.contains(r.id) {
            round = nil; pending = [:]; hole = 1
            return
        }
        guard var p = snap.round else { return }
        if round?.id == p.id {
            // Same round: take the phone's copy, but keep scores tapped here that it hasn't seen yet.
            for (n, v) in pending {
                if let i = p.holes.firstIndex(where: { $0.hole == n }) {
                    if p.holes[i] == v { pending[n] = nil } else { p.holes[i] = v }
                }
            }
            round = p
            // Follow the hole you picked on the iPhone.
            if let ph = p.currentHole {
                if let mine = pendingHole {
                    if mine.hole == ph || Date().timeIntervalSince(mine.at) > 30 { pendingHole = nil; if ph != hole { hole = ph } }
                } else if ph != hole {
                    hole = ph
                }
            }
        } else if round == nil || p.date >= round!.date {
            // A round started on the iPhone: pick it up.
            pending = [:]
            round = p
            hole = p.currentHole ?? p.holes.first { !$0.isEntered }?.hole ?? p.holes.first?.hole ?? 1
        }
    }

    nonisolated func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let ctx = s.receivedApplicationContext
        if let raw = ctx["snapshot"] as? Data, let snap = try? JSONDecoder.app.decode(WatchSnapshot.self, from: raw) {
            Task { @MainActor in self.apply(snap) }
        }
    }
    nonisolated func session(_ s: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        guard let raw = ctx["snapshot"] as? Data,
              let snap = try? JSONDecoder.app.decode(WatchSnapshot.self, from: raw) else { return }
        Task { @MainActor in self.apply(snap) }
    }
}
