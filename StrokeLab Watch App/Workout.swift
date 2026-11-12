import HealthKit
import Observation

/// Runs the round as a golf workout. While it's running, watchOS keeps StrokeLab on screen
/// when you raise your wrist, and the GPS stays on. The round is saved to Apple Fitness when you end it.
@Observable
final class GolfWorkout: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = GolfWorkout()
    var running = false
    var started: Date?
    var calories: Double = 0
    var error: String?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?

    func start() async {
        guard !running, session == nil else { return }
        guard HKHealthStore.isHealthDataAvailable() else { error = "Health isn't available on this watch."; return }
        do {
            // Saved as a Golf workout in Apple Fitness, with heart rate, calories and distance walked.
            let samples: Set<HKSampleType> = [HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate),
                                              HKQuantityType(.distanceWalkingRunning)]
            try await store.requestAuthorization(toShare: samples.union([HKQuantityType.workoutType()]), read: samples)
            let config = HKWorkoutConfiguration()
            config.activityType = .golf
            config.locationType = .outdoor
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            started = now
            running = true
        } catch {
            self.error = "Couldn't start the workout: \(error.localizedDescription)"
        }
    }

    func end() async {
        guard let session, let builder else { return }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
        } catch {}
        self.session = nil
        self.builder = nil
        running = false
        started = nil
    }

    // MARK: Delegates

    nonisolated func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState,
                                    from: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.error = error.localizedDescription; self.running = false }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        let kcal = b.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        Task { @MainActor in self.calories = kcal }
    }
}
