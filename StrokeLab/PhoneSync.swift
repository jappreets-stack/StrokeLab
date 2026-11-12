import Foundation
import HealthKit
import WatchConnectivity

/// Keeps the iPhone and the watch on the same round. The phone holds the real data;
/// the watch gets the current round + plans, and sends back what you tap on it.
final class PhoneSync: NSObject, WCSessionDelegate {
    static let shared = PhoneSync()
    private weak var store: Store?
    private let health = HKHealthStore()

    func activate(_ store: Store) {
        self.store = store
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push(_ d: AppData) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let current = d.currentRoundID.flatMap { id in d.rounds.first { $0.id == id } }
        let finished = d.rounds.filter(\.finished).sorted { $0.date > $1.date }.prefix(5).map(\.id)
        let snap = WatchSnapshot(round: current, plans: d.plans, finishedIDs: Array(finished))
        guard let raw = try? JSONEncoder.app.encode(snap) else { return }
        try? s.updateApplicationContext(["snapshot": raw])
    }

    /// Opens StrokeLab on the watch and starts the golf workout there.
    func startOnWatch() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor
        health.startWatchApp(with: config) { _, _ in }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in if let d = self.store?.data { self.push(d) } }
    }
    nonisolated func sessionDidBecomeInactive(_ s: WCSession) {}
    nonisolated func sessionDidDeactivate(_ s: WCSession) { s.activate() }
    nonisolated func sessionWatchStateDidChange(_ s: WCSession) {
        Task { @MainActor in if let d = self.store?.data { self.push(d) } }
    }
    nonisolated func session(_ s: WCSession, didReceiveMessage m: [String: Any]) { receive(m) }
    nonisolated func session(_ s: WCSession, didReceiveUserInfo u: [String: Any] = [:]) { receive(u) }

    /// Newest change per hole wins (a message can arrive twice, or late).
    private var lastApplied: [String: Date] = [:]

    nonisolated private func receive(_ m: [String: Any]) {
        guard let raw = m["event"] as? Data,
              let e = try? JSONDecoder.app.decode(WatchEvent.self, from: raw) else { return }
        Task { @MainActor in
            let key: String
            switch e.kind {
            case .start(let r): key = "start-\(r.id)"
            case .score(let id, let hole, _, _): key = "score-\(id)-\(hole)"
            case .hole(let id, _): key = "hole-\(id)"
            case .tee(let id, let hole, _, _): key = "tee-\(id)-\(hole)"
            case .end(let id): key = "end-\(id)"
            }
            if let last = self.lastApplied[key], last >= e.at { return }
            self.lastApplied[key] = e.at
            self.store?.apply(e)
        }
    }
}
