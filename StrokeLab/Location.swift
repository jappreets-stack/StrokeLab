import CoreLocation
import Observation

/// Live GPS for yardages. Only runs while a screen that shows yards is open.
@Observable
final class LocationModel {
    var location: CLLocation?
    var denied = false
    private var task: Task<Void, Never>?
    private var session: CLServiceSession?
    private var users = 0

    func start() {
        users += 1
        guard task == nil else { return }
        session = CLServiceSession(authorization: .whenInUse)
        task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let self else { return }
                    self.denied = update.authorizationDenied
                    if let loc = update.location, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 50 {
                        self.location = loc
                    }
                }
            } catch {}
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        task?.cancel(); task = nil; session = nil
    }

    func yards(to c: Coordinate?) -> Int? {
        guard let c, let location else { return nil }
        let meters = location.distance(from: CLLocation(latitude: c.lat, longitude: c.lon))
        return Int((meters * 1.09361).rounded())
    }
}
