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
            if rounds.round != nil { holeScreen } else { NavigationStack { startScreen } }
        }
        .sheet(item: Binding(get: { rounds.summary }, set: { rounds.summary = $0 })) { r in
            WatchScorecard(round: r, done: { rounds.summary = nil })
        }
        .onAppear { gps.start(); keepWorkoutGoing() }
        .task(id: rounds.hole) { await WindModel.shared.refresh() }
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
                if !rounds.history.isEmpty {
                    NavigationLink {
                        WatchPastRounds()
                    } label: {
                        Label("Past rounds", systemImage: "list.number").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
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
            // Left side only: the clock sits top right.
            Text("Hole \(hole)").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            (Text("Par \(h.par)").foregroundStyle(.green).bold()
                + Text(planLine.isEmpty ? "" : " · " + planLine).foregroundStyle(.secondary))
                .font(.caption2)
                .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(text(gps.yards(to: pins.center)))
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text("CENTER" + (gps.accuracyYards.map { " · ±\($0)" } ?? " · GPS…"))
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            if let a = ShotAdvice.make(from: gps.location, to: pins.center, wind: WindModel.shared.wind, clubs: rounds.clubYards) {
                HStack(spacing: 3) {
                    if let deg = a.arrow, a.windText != "Calm" {
                        Image(systemName: "location.north.fill").rotationEffect(.degrees(deg))
                    }
                    Text([a.windText, "\(a.playsLike)", a.club?.rawValue].compactMap { $0 }.joined(separator: " · "))
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
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

/// Everything for this hole, same buttons as the iPhone. Big targets, one tap each.
struct WatchScoreView: View {
    let close: () -> Void
    private let rounds = WatchRound.shared
    @State private var confirmEnd = false

    private var hole: Int { rounds.hole }
    private var par: Int { Course.hole(hole).par }
    private var e: HoleScore { rounds.score(hole) ?? HoleScore(hole: hole) }

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
                row("SCORE", Array(max(1, par - 1)...(par + 6)), { "\($0)" }, e.score, cols: 4, big: true) { v in rounds.update { $0.score = v } }
                row("PUTTS", [0, 1, 2, 3, 4], { "\($0)" }, e.putts, cols: 5, big: true) { v in rounds.update { $0.putts = v } }
                row("TEE SHOT", TeeResult.options(par: par), \.rawValue, e.teeResult, cols: 2) { v in rounds.update { $0.teeResult = v } }
                if e.teeMissed {
                    row("HOW FAR OFF?", MissSize.allCases, \.label, e.missSize, cols: 3) { v in rounds.update { $0.missSize = v } }
                }
                if par > 3 {
                    row("APPROACH FROM (YDS)", ApproachDistance.allCases, \.rawValue, e.approachDistance, cols: 2) { v in rounds.update { $0.approachDistance = v } }
                    row("APPROACH FINISHED", ApproachResult.allCases, \.rawValue, e.approachResult, cols: 3) { v in rounds.update { $0.approachResult = v } }
                }
                row("CHIPS BEFORE PUTTING", [0, 1, 2, 3], { $0 == 3 ? "3+" : "\($0)" }, e.chips, cols: 4) { v in rounds.update { $0.chips = v } }
                row("SHOTS INSIDE 100 (PUTTS COUNT)", Array(1...8), { "\($0)" }, e.inside100, cols: 4) { v in rounds.update { $0.inside100 = v } }
                if (e.putts ?? 0) > 0 {
                    row("FIRST PUTT (FT)", PuttLength.allCases, \.rawValue, e.firstPutt, cols: 3) { v in rounds.update { $0.firstPutt = v } }
                    row("FIRST PUTT", PuttResult.allCases, \.rawValue, e.firstPuttResult ?? (e.putts == 1 ? .made : nil), cols: 3) { v in
                        rounds.update { $0.firstPuttResult = v }
                    }
                    if let r = e.firstPuttResult, r != .made {
                        row("FINISHED", PuttMiss.allCases, \.rawValue, e.puttMiss, cols: 3) { v in rounds.update { $0.puttMiss = v } }
                    }
                }
                row("GREENSIDE BUNKER", [false, true], { $0 ? "Yes" : "No" }, e.sand, cols: 2) { v in rounds.update { $0.sand = v } }
                row("PENALTIES", [0, 1, 2, 3], { "\($0)" }, e.penalties, cols: 4) { v in rounds.update { $0.penalties = v } }
                row("LOST BALL", [false, true], { $0 ? "Yes" : "No" }, e.lostBall, cols: 2) { v in rounds.update { $0.lostBall = v } }
                row("TEE CLUB", Club.allCases, \.rawValue, e.teeClub, cols: 4) { v in rounds.update { $0.teeClub = v } }

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

    private func row<T: Hashable>(_ label: String, _ options: [T], _ title: @escaping (T) -> String, _ selected: T?,
                                  cols: Int, big: Bool = false, set: @escaping (T) -> Void) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols), spacing: 4) {
                ForEach(options, id: \.self) { o in
                    Button { set(o) } label: {
                        Text(title(o)).font(big ? .title3.weight(.bold) : .footnote.weight(.bold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, minHeight: big ? 40 : 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selected == o ? .green : Color.gray.opacity(0.35))
                }
            }
        }
    }
}

/// Your last rounds, newest first. Tap one for its scorecard.
struct WatchPastRounds: View {
    private let rounds = WatchRound.shared
    @State private var toDelete: Round?
    var body: some View {
        List(rounds.history) { r in
            NavigationLink {
                WatchScorecard(round: r, done: nil, delete: { toDelete = r })
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.date.formatted(.dateTime.month(.abbreviated).day())).font(.headline)
                        Text(r.type.rawValue).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(r.total)").font(.title3.weight(.bold)).monospacedDigit()
                        Text(toParText(r.toPar) + (r.isComplete ? "" : " · \(r.entered.count)h"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .swipeActions {
                Button(role: .destructive) { toDelete = r } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .navigationTitle("Past rounds")
        .overlay { if rounds.history.isEmpty { Text("No rounds").foregroundStyle(.secondary) } }
        .confirmationDialog("Delete this round?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let r = toDelete { rounds.delete(r.id) }
                toDelete = nil
            }
            Button("Cancel", role: .cancel) { toDelete = nil }
        } message: {
            Text(toDelete.map { "\($0.date.formatted(.dateTime.month(.abbreviated).day())) · \($0.total). Also deletes it on your iPhone. Can't be undone." } ?? "")
        }
    }
}

/// Score, to par, putts and every hole. Shown when a round ends and from Past rounds.
struct WatchScorecard: View {
    let round: Round
    let done: (() -> Void)?
    var delete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(round.type.rawValue + " · " + round.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(round.total)").font(.system(size: 52, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(toParText(round.toPar)).font(.title3.weight(.bold)).foregroundStyle(.green)
                }
                HStack {
                    stat("\(round.putts)", "PUTTS")
                    stat("\(round.entered.filter { $0.greenHit == true }.count)", "GREENS")
                    stat("\(round.entered.count)", "HOLES")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(round.holes) { h in
                        VStack(spacing: 0) {
                            Text("\(h.hole) · P\(h.par)").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                            Text(h.score.map { "\($0)" } ?? "–").font(.title3.weight(.bold)).monospacedDigit()
                                .foregroundStyle(color(h))
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if let done {
                    Button(action: done) { Text("Done").frame(maxWidth: .infinity, minHeight: 34) }
                        .buttonStyle(.borderedProminent).tint(.green)
                }
                if let delete {
                    Button(role: .destructive) { dismiss(); delete() } label: {
                        Label("Delete round", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).padding(.top, 8)
                }
            }
        }
    }

    private func color(_ h: HoleScore) -> Color {
        guard let s = h.score else { return .secondary }
        switch s - h.par {
        case ..<0: return .green
        case 0: return .white
        case 1: return .orange
        default: return .red
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(v).font(.headline).monospacedDigit()
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
