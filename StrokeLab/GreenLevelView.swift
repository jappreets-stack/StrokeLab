import SwiftUI
import CoreMotion
import Observation

/// Phone-as-a-level for the practice green: lay it flat and see which way and how steeply the ground falls.
@Observable
final class LevelModel {
    var x = 0.0                   // gravity on the screen axes (after zeroing)
    var y = 0.0
    var zeroX: Double { didSet { UserDefaults.standard.set(zeroX, forKey: "levelZeroX") } }
    var zeroY: Double { didSet { UserDefaults.standard.set(zeroY, forKey: "levelZeroY") } }
    @ObservationIgnored private var rawX = 0.0
    @ObservationIgnored private var rawY = 0.0
    @ObservationIgnored private let motion = CMMotionManager()

    init() {
        zeroX = UserDefaults.standard.double(forKey: "levelZeroX")
        zeroY = UserDefaults.standard.double(forKey: "levelZeroY")
    }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            // Smooth so the arrow doesn't jitter.
            rawX = rawX * 0.85 + g.x * 0.15
            rawY = rawY * 0.85 + g.y * 0.15
            x = rawX - zeroX
            y = rawY - zeroY
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
    func zero() { zeroX = rawX; zeroY = rawY }

    /// Slope in percent (rise over run).
    var percent: Double {
        let s = min(hypot(x, y), 0.99)
        return tan(asin(s)) * 100
    }
    /// Downhill direction on screen, radians (0 = right, clockwise positive because screen y points down).
    var downhill: Double { atan2(-y, x) }
}

struct GreenLevelView: View {
    @State private var level = LevelModel()

    var body: some View {
        VStack(spacing: 24) {
            Label("Practice green only. Measuring slope with a device isn’t allowed in rounds you post or play in league.",
                  systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(.orange)

            ZStack {
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1).padding(70)
                if level.percent > 0.3 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 120, weight: .black))
                        .foregroundStyle(Color.fairway)
                        .rotationEffect(.radians(level.downhill))
                        .animation(.easeOut(duration: 0.2), value: level.downhill)
                } else {
                    Text("FLAT").font(.system(size: 48, weight: .heavy, design: .rounded)).foregroundStyle(Color.fairway)
                }
            }
            .frame(width: 280, height: 280)

            VStack(spacing: 4) {
                Text(String(format: "%.1f%%", level.percent))
                    .font(.system(size: 64, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(feel(level.percent)).font(.headline).foregroundStyle(.secondary)
                Text("The arrow points downhill: the way the ball will break.").font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer()
            ChoiceButton(title: "Zero it (on a flat table)", selected: false, height: 48, font: .headline) { level.zero() }
            Text("Lay the phone flat on the green, screen up. Do “Zero it” once at home on a flat table, because the camera bump tilts the phone a little.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Green level")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { level.start() }
        .onDisappear { level.stop() }
    }

    private func feel(_ p: Double) -> String {
        switch p {
        case ..<1: "Nearly flat"
        case ..<2: "Gentle — a little break"
        case ..<3: "Moderate — play a cup or more"
        case ..<4: "Strong slope"
        default: "Severe — be careful above the hole"
        }
    }
}
