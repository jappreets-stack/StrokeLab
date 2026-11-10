import Foundation
import CoreGraphics

/// The body points we track. Positions are normalized to the upright video frame, origin top-left.
nonisolated enum Joint: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case nose, neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
}

nonisolated struct PoseFrame: Codable, Sendable {
    var t: Double                       // seconds into the video (real time)
    var joints: [Joint: CGPoint]

    var hands: CGPoint? {
        switch (joints[.leftWrist], joints[.rightWrist]) {
        case let (l?, r?): CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
        case let (l?, nil): l
        case let (nil, r?): r
        default: nil
        }
    }
}

nonisolated enum CameraView: String, Codable, Sendable, CaseIterable {
    case downTheLine = "Down the line", faceOn = "Face on"
}

nonisolated enum SwingPhase: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
    case address = "Address", top = "Top", impact = "Impact", finish = "Finish"
}

/// Everything measured from one swing. Inches are estimates scaled from your torso length.
nonisolated struct SwingMetrics: Codable, Sendable {
    var backswing: Double?        // seconds, takeaway → top
    var downswing: Double?        // seconds, top → impact
    var tempo: Double? { guard let b = backswing, let d = downswing, d > 0 else { return nil }; return b / d }

    // Down the line
    var hipsTowardBall: Double?   // inches at impact vs address (+ = toward ball = early extension)
    var spineAngleAddress: Double?
    var spineAngleImpact: Double?
    var spineLoss: Double? { guard let a = spineAngleAddress, let i = spineAngleImpact else { return nil }; return a - i }
    var headUp: Double?           // inches at impact (+ = rose)
    var headTowardBall: Double?   // inches at impact
    var overTheTop: Double?       // share of downswing with hands above the shoulder plane (0–1)
    var underPlane: Double?       // share of downswing with hands below the shaft plane (0–1)

    // Face on
    var hipSwayAtTop: Double?     // inches away from target at the top
    var headSwayAtTop: Double?    // inches away from target at the top
    var headAheadAtImpact: Double? // inches toward target at impact
    var shoulderTurn: Double?     // degrees at top (estimate)
    var hipTurn: Double?          // degrees at top (estimate)
}

nonisolated struct SwingAnalysis: Codable, Sendable {
    var frames: [PoseFrame]
    var phases: [SwingPhase: Int]       // index into frames
    var takeaway: Int
    var aspect: Double                  // video width / height
    var view: CameraView
    var ballSide: Double                // DTL: +1 ball is to the right of the golfer in the frame
    var ball: CGPoint?                  // tapped by you (DTL)
    var metrics: SwingMetrics

    func frame(at phase: SwingPhase) -> PoseFrame? { phases[phase].map { frames[$0] } }
}

/// One saved swing (list summary; the pose data lives in its own file).
nonisolated struct SwingRecord: Codable, Sendable, Identifiable {
    var id = UUID()
    var date = Date()
    var club: String = "7i"
    var view: CameraView
    var fps: Double
    var tempo: Double?
    var headline: String = ""
    var videoFile: String { "\(id.uuidString).mov" }
    var poseFile: String { "\(id.uuidString).pose.json" }
}
