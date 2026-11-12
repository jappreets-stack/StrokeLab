import SwiftUI
import CoreLocation
import HealthKit
import Observation
import WatchKit

@main
struct StrokeLabWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    var body: some Scene {
        WindowGroup { WatchHoleView() }
    }
}

/// Starting a round on the iPhone opens StrokeLab here and starts the golf workout.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() { _ = WatchRound.shared }
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { await GolfWorkout.shared.start() }
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
    private let rounds = WatchRound.shared
    private let workout = GolfWorkout.shared
    @State private var gps = WatchLocation()
    @State private var showScore = false
    @Environment(\.scenePhase) private var phase

    private var hole: Int { rounds.hole }
    private var h: Hole { Course.hole(hole) }
    private var pins: GreenPins { CourseGreens.pins[hole - 1] }

    var body: some View {
        Group {
            if rounds.round != nil { holeScreen } else { startScreen }
        }
        .onAppear { gps.start(); keepWorkoutGoing() }
        .onChange(of: phase) { _, p in if p == .active { gps.start(); keepWorkoutGoing() } }
        .onChange(of: rounds.round?.id) { old, new in
            if new == nil, old != nil { Task { await workout.end() } }   // ended here or on the iPhone
            else { keepWorkoutGoing() }
        }
    }

    /// While a round is on, the golf workout runs so StrokeLab stays on screen.
    private func keepWorkoutGoing() {
        if rounds.round != nil, !workout.running { Task { await workout.start() } }
    }

    private var startScreen: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "flag.fill").font(.title2).foregroundStyle(.green)
                ForEach(RoundType.allCases, id: \.self) { t in
                    Button { rounds.start(t) } label: {
                        Text(t.rawValue).font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                }
                Text(workout.error ?? "Starts a Golf workout in Apple Fitness and keeps yardages on screen. Shows up on your iPhone too.")
                    .font(.caption2).foregroundStyle(workout.error == nil ? Color.secondary : Color.orange)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var planLine: String {
        guard let p = rounds.plan(hole) else { return "" }
        var parts = ["\(p.teeClub.rawValue) · aim \(p.target)"]
        if p.troubleSide != .none || !p.hazards.isEmpty { parts.append(p.troubleText) }
        return parts.joined(separator: " · ")
    }

    private var scoreLabel: String {
        guard let s = rounds.score(hole), let score = s.score else { return "Score" }
        return s.putts.map { "\(score) · \($0)p" } ?? "\(score)"
    }

    private var holeScreen: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Hole \(hole)").font(.headline)
                Spacer()
                Text("Par \(h.par)").font(.headline).foregroundStyle(.green)
            }
            if !planLine.isEmpty {
                Text(planLine).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            Text(text(gps.yards(to: pins.center)))
                .font(.system(size: 60, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text("CENTER" + (gps.accuracyYards.map { " · ±\($0)" } ?? " · GPS…"))
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            HStack {
                small(text(gps.yards(to: pins.front)), "FRONT")
                Spacer()
                small(text(gps.yards(to: pins.back)), "BACK")
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Button { rounds.go(to: hole - 1) } label: { Image(systemName: "chevron.left").frame(maxWidth: 30) }
                    .disabled(hole == 1)
                Button { showScore = true } label: {
                    Text(scoreLabel).font(.headline).lineLimit(1).frame(maxWidth: .infinity)
                }
                .tint(rounds.score(hole)?.score == nil ? .green : .gray)
                Button { rounds.go(to: hole + 1) } label: { Image(systemName: "chevron.right").frame(maxWidth: 30) }
                    .disabled(hole == 18)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showScore) { WatchScoreView(close: { showScore = false }) }
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

/// Score and putts for this hole: big buttons, one tap each.
struct WatchScoreView: View {
    let close: () -> Void
    private let rounds = WatchRound.shared
    @State private var confirmEnd = false

    private var hole: Int { rounds.hole }
    private var par: Int { Course.hole(hole).par }
    private var current: HoleScore? { rounds.score(hole) }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack {
                    Text("Hole \(hole) · Par \(par)").font(.headline)
                    Spacer()
                    if let r = rounds.round, !r.entered.isEmpty {
                        Text(toParText(r.toPar)).font(.headline).foregroundStyle(.green)
                    }
                }
                label("SCORE")
                grid(Array(2...9), columns: 4, selected: current?.score) { n in
                    rounds.set(score: n, putts: current?.putts)
                }
                label("PUTTS")
                grid(Array(0...4), columns: 5, selected: current?.putts) { n in
                    rounds.set(score: current?.score, putts: n)
                }
                if hole < 18 {
                    Button {
                        rounds.go(to: hole + 1); close()
                    } label: {
                        Label("Next hole", systemImage: "chevron.right").frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                }
                Button("Done", action: close).buttonStyle(.bordered)
                Button("End round", role: .destructive) { confirmEnd = true }
                    .buttonStyle(.bordered).padding(.top, 8)
            }
        }
        .confirmationDialog("End round?", isPresented: $confirmEnd) {
            Button("End round", role: .destructive) { close(); rounds.end() }
            Button("Keep playing", role: .cancel) {}
        } message: { Text("Saves the round on your iPhone and the golf workout in Apple Fitness.") }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func grid(_ values: [Int], columns: Int, selected: Int?, tap: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(values, id: \.self) { n in
                Button { tap(n) } label: {
                    Text("\(n)").font(.title3.weight(.bold)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(selected == n ? .green : Color.gray.opacity(0.35))
            }
        }
    }
}
