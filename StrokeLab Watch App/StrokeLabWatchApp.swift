import SwiftUI
import CoreLocation
import Observation

@main
struct StrokeLabWatchApp: App {
    var body: some Scene {
        WindowGroup { WatchHoleView() }
    }
}

/// Wrist GPS. Runs while the app is open.
@Observable
final class WatchLocation {
    var location: CLLocation?
    var accuracyYards: Int? { location.map { Int(($0.horizontalAccuracy * 1.09361).rounded()) } }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var session: CLServiceSession?

    func start() {
        guard task == nil else { return }
        session = CLServiceSession(authorization: .whenInUse)
        task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self else { return }
                    if let loc = update.location, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 25 {
                        self.location = loc
                    }
                }
            } catch {}
        }
    }

    func stop() { task?.cancel(); task = nil; session = nil }

    func yards(to c: Coordinate?) -> Int? {
        guard let c, let location else { return nil }
        return Int((location.distance(from: CLLocation(latitude: c.lat, longitude: c.lon)) * 1.09361).rounded())
    }
}

struct WatchHoleView: View {
    @AppStorage("watchHole") private var hole = 1
    @State private var gps = WatchLocation()
    @State private var crown = 1.0
    @Environment(\.scenePhase) private var phase

    private var h: Hole { Course.hole(hole) }
    private var pins: GreenPins { CourseGreens.pins[hole - 1] }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Hole \(hole)").font(.headline)
                Spacer()
                Text("Par \(h.par)").font(.headline).foregroundStyle(.green)
            }
            Spacer(minLength: 0)
            Text(text(gps.yards(to: pins.center)))
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text("CENTER").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            HStack {
                small(text(gps.yards(to: pins.front)), "FRONT")
                Spacer()
                small(text(gps.yards(to: pins.back)), "BACK")
            }
            Spacer(minLength: 0)
            HStack {
                Button { change(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(hole == 1)
                Text(gps.accuracyYards.map { "±\($0)" } ?? "GPS…")
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Button { change(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(hole == 18)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 4)
        .focusable()
        .digitalCrownRotation($crown, from: 1, through: 18, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, v in
            let n = Int(v.rounded())
            if n != hole { hole = n }
        }
        .onAppear { crown = Double(hole); gps.start() }
        .onChange(of: phase) { _, p in if p == .active { gps.start() } }
    }

    private func change(_ d: Int) {
        hole = min(18, max(1, hole + d))
        crown = Double(hole)
    }

    private func text(_ y: Int?) -> String {
        guard let y else { return "—" }
        return y > 999 ? "—" : "\(y)"
    }

    private func small(_ v: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(v).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
        }
    }
}
