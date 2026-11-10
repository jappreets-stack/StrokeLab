import AVFoundation
import Vision
import CoreGraphics

/// Reads a swing video, tracks the body on every frame, finds the swing phases and measures them.
nonisolated enum PoseAnalyzer {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    static let torsoInches = 19.0   // neck → pelvis for an average adult; used to turn pixels into inches

    static let visionJoints: [Joint: VNHumanBodyPoseObservation.JointName] = [
        .nose: .nose, .neck: .neck, .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow, .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .root: .root, .leftHip: .leftHip, .rightHip: .rightHip, .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    /// - progress: 0…1 callback (called off the main thread).
    static func analyze(url: URL, leftHanded: Bool, progress: @Sendable @escaping (Double) -> Void) async throws -> (SwingAnalysis, fps: Double) {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure("No video in that file.") }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let fps = Double(try await track.load(.nominalFrameRate))
        let duration = try await asset.load(.duration).seconds
        let size = natural.applying(transform)
        let aspect = abs(size.width) / abs(size.height)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        // Pass 1: quick scan at 30 fps to find the swing (fastest hands).
        let scanTimes = stride(from: 0.0, to: duration, by: 1.0 / 30).map { $0 }
        let scan = try await poses(generator, times: scanTimes) { progress(0.3 * $0) }
        guard let fastest = fastestHands(scan) else {
            throw Failure("Couldn't find you in the video. Make sure your whole body is in the frame and the light is good.")
        }

        // Pass 2: detailed look around the swing, up to 120 fps.
        let rate = min(max(fps, 30), 120)
        let start = max(0, fastest - 2.2), end = min(duration, fastest + 1.3)
        let detailTimes = stride(from: start, to: end, by: 1.0 / rate).map { $0 }
        let frames = try await poses(generator, times: detailTimes) { progress(0.3 + 0.7 * $0) }
        guard frames.count > 20 else { throw Failure("The swing was too short to read. Try again with your whole body in frame.") }

        let analysis = try measure(frames: frames, aspect: aspect, leftHanded: leftHanded)
        return (analysis, fps)
    }

    // MARK: Vision

    private static func poses(_ generator: AVAssetImageGenerator, times: [Double],
                              progress: (Double) -> Void) async throws -> [PoseFrame] {
        var out: [PoseFrame] = []
        let cmTimes = times.map { CMTime(seconds: $0, preferredTimescale: 600) }
        var done = 0
        for await result in generator.images(for: cmTimes) {
            done += 1
            if done % 10 == 0 { progress(Double(done) / Double(times.count)) }
            guard let image = try? result.image else { continue }
            if let joints = pose(in: image) {
                out.append(PoseFrame(t: result.requestedTime.seconds, joints: joints))
            }
        }
        return out.sorted { $0.t < $1.t }
    }

    private static func pose(in image: CGImage) -> [Joint: CGPoint]? {
        let request = VNDetectHumanBodyPoseRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        // Biggest person in frame = you.
        guard let obs = request.results?.max(by: { spread($0) < spread($1) }),
              let points = try? obs.recognizedPoints(.all) else { return nil }
        var joints: [Joint: CGPoint] = [:]
        for (joint, name) in visionJoints {
            if let p = points[name], p.confidence > 0.2 {
                joints[joint] = CGPoint(x: p.location.x, y: 1 - p.location.y)   // flip to top-left origin
            }
        }
        return joints[.neck] != nil && joints[.root] != nil ? joints : nil
    }

    private static func spread(_ o: VNHumanBodyPoseObservation) -> CGFloat {
        guard let pts = try? o.recognizedPoints(.all).values.filter({ $0.confidence > 0.2 }), !pts.isEmpty else { return 0 }
        let ys = pts.map(\.location.y)
        return (ys.max()! - ys.min()!)
    }

    private static func fastestHands(_ frames: [PoseFrame]) -> Double? {
        var best: (speed: Double, t: Double)?
        for i in 1..<max(frames.count, 1) {
            guard let a = frames[i - 1].hands, let b = frames[i].hands else { continue }
            let dt = frames[i].t - frames[i - 1].t
            guard dt > 0 else { continue }
            let v = hypot(b.x - a.x, b.y - a.y) / dt
            if v > (best?.speed ?? 0) { best = (v, frames[i].t) }
        }
        return best?.t
    }

    // MARK: Phases + metrics

    static func measure(frames: [PoseFrame], aspect: Double, leftHanded: Bool, ball: CGPoint? = nil,
                        forcedView: CameraView? = nil) throws -> SwingAnalysis {
        // Hands path, lightly smoothed. Work in "pixel-ish" units: x scaled by aspect so distances are true.
        let hands: [CGPoint?] = frames.indices.map { i in
            let window = frames[max(0, i - 1)...min(frames.count - 1, i + 1)].compactMap(\.hands)
            guard !window.isEmpty else { return nil }
            return CGPoint(x: window.map(\.x).reduce(0, +) / Double(window.count),
                           y: window.map(\.y).reduce(0, +) / Double(window.count))
        }
        func speed(_ i: Int) -> Double {
            guard i > 0, let a = hands[i - 1], let b = hands[i] else { return 0 }
            let dt = frames[i].t - frames[i - 1].t
            return dt > 0 ? hypot((b.x - a.x) * aspect, b.y - a.y) / dt : 0
        }
        let speeds = frames.indices.map(speed)
        guard let fastest = speeds.indices.max(by: { speeds[$0] < speeds[$1] }), speeds[fastest] > 0 else {
            throw Failure("Couldn't see your hands clearly enough to find the swing.")
        }
        let maxSpeed = speeds[fastest]
        func idx(near t: Double) -> Int { frames.indices.min { abs(frames[$0].t - t) < abs(frames[$1].t - t) } ?? 0 }

        // Top: highest hands in the 1.5 s before the fastest point.
        let topRange = idx(near: frames[fastest].t - 1.5)...fastest
        guard let top = topRange.filter({ hands[$0] != nil }).min(by: { hands[$0]!.y < hands[$1]!.y }) else {
            throw Failure("Couldn't find the top of your swing.")
        }
        // Impact: lowest hands between the top and just after the fastest point.
        let impactEnd = min(frames.count - 1, idx(near: frames[fastest].t + 0.2))
        guard top < impactEnd,
              let impact = (top + 1...impactEnd).filter({ hands[$0] != nil }).max(by: { hands[$0]!.y < hands[$1]!.y }) else {
            throw Failure("Couldn't find impact.")
        }
        // Takeaway: hands also slow down at the top, so start from the fastest point of the backswing
        // and walk back until the hands are nearly still.
        let backStart = idx(near: frames[top].t - 1.6)
        let midBack = (backStart...top).max { speeds[$0] < speeds[$1] } ?? top
        let stillSpeed = max(speeds[midBack] * 0.12, maxSpeed * 0.02)
        var takeaway = midBack
        while takeaway > 0 && speeds[takeaway] > stillSpeed { takeaway -= 1 }
        let address = max(0, takeaway - 2)
        // Finish: highest hands in the 1.2 s after impact.
        let finishRange = impact...min(frames.count - 1, idx(near: frames[impact].t + 1.2))
        let finish = finishRange.filter({ hands[$0] != nil }).min(by: { hands[$0]!.y < hands[$1]!.y }) ?? finishRange.upperBound

        let phases: [SwingPhase: Int] = [.address: address, .top: top, .impact: impact, .finish: finish]

        // Averaged joints around a frame (±2) to steady the numbers.
        func joint(_ j: Joint, _ i: Int) -> CGPoint? {
            let pts = frames[max(0, i - 2)...min(frames.count - 1, i + 2)].compactMap { $0.joints[j] }
            guard !pts.isEmpty else { return nil }
            return CGPoint(x: pts.map(\.x).reduce(0, +) / Double(pts.count) * aspect,
                           y: pts.map(\.y).reduce(0, +) / Double(pts.count))
        }
        guard let neckA = joint(.neck, address), let rootA = joint(.root, address) else {
            throw Failure("Couldn't see your posture at address.")
        }
        let torso = hypot(neckA.x - rootA.x, neckA.y - rootA.y)
        let inch = torsoInches / max(torso, 0.0001)

        // Face-on vs down-the-line: shoulders look wide face-on, narrow from behind.
        var view = forcedView ?? .downTheLine
        if forcedView == nil, let ls = joint(.leftShoulder, address), let rs = joint(.rightShoulder, address) {
            view = hypot(ls.x - rs.x, ls.y - rs.y) / torso > 0.55 ? .faceOn : .downTheLine
        }
        let handsA = hands[address].map { CGPoint(x: $0.x * aspect, y: $0.y) } ?? rootA
        let ballSide: Double = handsA.x >= rootA.x ? 1 : -1
        // Face-on: the target is on your lead side. Right-handed golfer facing the camera → target is to the right of the frame.
        let toTarget: Double = leftHanded ? -1 : 1

        var m = SwingMetrics()
        m.backswing = frames[top].t - frames[takeaway].t
        m.downswing = frames[impact].t - frames[top].t

        func tilt(_ i: Int) -> Double? {
            guard let n = joint(.neck, i), let r = joint(.root, i) else { return nil }
            return atan2(abs(n.x - r.x), r.y - n.y) * 180 / .pi     // degrees forward of vertical
        }

        switch view {
        case .downTheLine:
            if let rootI = joint(.root, impact) { m.hipsTowardBall = (rootI.x - rootA.x) * ballSide * inch }
            m.spineAngleAddress = tilt(address)
            m.spineAngleImpact = tilt(impact)
            if let hA = joint(.nose, address), let hI = joint(.nose, impact) {
                m.headUp = (hA.y - hI.y) * inch
                m.headTowardBall = (hI.x - hA.x) * ballSide * inch
            }
            if let ball {
                let b = CGPoint(x: ball.x * aspect, y: ball.y)
                var above = 0, below = 0, total = 0
                for i in top...impact {
                    guard let h = hands[i] else { continue }
                    let p = CGPoint(x: h.x * aspect, y: h.y)
                    // Only grade the part of the downswing above the hips (where plane matters most).
                    guard p.y < rootA.y else { continue }
                    total += 1
                    if p.y < lineY(from: b, through: neckA, atX: p.x) { above += 1 }
                    if p.y > lineY(from: b, through: handsA, atX: p.x) { below += 1 }
                }
                if total > 3 {
                    m.overTheTop = Double(above) / Double(total)
                    m.underPlane = Double(below) / Double(total)
                }
            }
        case .faceOn:
            if let rT = joint(.root, top) { m.hipSwayAtTop = -(rT.x - rootA.x) * toTarget * inch }
            if let hA = joint(.nose, address) {
                if let hT = joint(.nose, top) { m.headSwayAtTop = -(hT.x - hA.x) * toTarget * inch }
                if let hI = joint(.nose, impact) { m.headAheadAtImpact = (hI.x - hA.x) * toTarget * inch }
            }
            m.shoulderTurn = turn(.leftShoulder, .rightShoulder, address, top, joint)
            m.hipTurn = turn(.leftHip, .rightHip, address, top, joint)
        }

        return SwingAnalysis(frames: frames, phases: phases, takeaway: takeaway, aspect: aspect, view: view,
                             ballSide: ballSide, ball: ball, metrics: m)
    }

    /// Rough turn from how much a body line shrinks when it rotates away from the camera.
    private static func turn(_ a: Joint, _ b: Joint, _ i0: Int, _ i1: Int,
                             _ joint: (Joint, Int) -> CGPoint?) -> Double? {
        guard let a0 = joint(a, i0), let b0 = joint(b, i0), let a1 = joint(a, i1), let b1 = joint(b, i1) else { return nil }
        let w0 = abs(a0.x - b0.x), w1 = abs(a1.x - b1.x)
        guard w0 > 0 else { return nil }
        return acos(min(1, w1 / w0)) * 180 / .pi
    }

    static func lineY(from a: CGPoint, through b: CGPoint, atX x: Double) -> Double {
        guard abs(b.x - a.x) > 0.0001 else { return a.y }
        return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
    }
}
