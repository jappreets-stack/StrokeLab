import SwiftUI
import AVFoundation

/// Slow-motion recorder: highest frame rate the camera offers (up to 240 fps), countdown so you can walk to the ball.
final class SwingCamera: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "swing.camera")
    private(set) var fps: Double = 30
    var onFinish: ((URL?) -> Void)?

    func start(_ ready: @escaping @Sendable (Double) -> Void) {
        queue.async { [self] in
            if session.inputs.isEmpty { configure() }
            session.startRunning()
            let f = fps
            DispatchQueue.main.async { ready(f) }
        }
    }

    func stop() { queue.async { [self] in session.stopRunning() } }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration(); return
        }
        session.addInput(input)
        if session.canAddOutput(output) { session.addOutput(output) }

        // Pick the fastest format that is at least 720p (prefer 1080p).
        let candidates = device.formats.compactMap { f -> (AVCaptureDevice.Format, Double, Int32)? in
            let dims = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard dims.width >= 1280, dims.width <= 1920 else { return nil }
            let maxFPS = f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return (f, min(maxFPS, 240), dims.width)
        }
        if let best = candidates.max(by: { ($0.1, $0.2) < ($1.1, $1.2) }), (try? device.lockForConfiguration()) != nil {
            device.activeFormat = best.0
            let d = CMTime(value: 1, timescale: CMTimeScale(best.1))
            device.activeVideoMinFrameDuration = d
            device.activeVideoMaxFrameDuration = d
            device.unlockForConfiguration()
            fps = best.1
        }
        if let c = output.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        session.commitConfiguration()
    }

    func record() {
        queue.async { [self] in
            let url = URL.temporaryDirectory.appending(path: "swing-\(UUID().uuidString).mov")
            output.startRecording(to: url, recordingDelegate: self)
        }
    }

    func finish() { queue.async { [self] in if output.isRecording { output.stopRecording() } } }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        let ok = (error == nil) || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        DispatchQueue.main.async { self.onFinish?(ok ? url : nil) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.layer_.session = session
        v.layer_.videoGravity = .resizeAspect
        if let c = v.layer_.connection, c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layer_: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

struct SwingCaptureView: View {
    let onVideo: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera = SwingCamera()
    @State private var fps: Double = 0
    @State private var state: Stage = .ready
    @State private var countdown = 5
    @State private var seconds = 0
    @State private var denied = false
    enum Stage { case ready, counting, recording }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            guide
            VStack {
                HStack {
                    Button("Cancel") { camera.finish(); camera.onFinish = nil; dismiss() }
                        .font(.headline).padding(10).background(.black.opacity(0.5), in: .capsule).foregroundStyle(.white)
                    Spacer()
                    if fps > 0 { Pill(text: "\(Int(fps)) fps", color: .black.opacity(0.5)).foregroundStyle(.white) }
                }
                Spacer()
                switch state {
                case .ready:
                    Text("Whole body + club in frame. Tap record, walk to the ball, swing.")
                        .font(.subheadline.bold()).multilineTextAlignment(.center).padding(10)
                        .background(.black.opacity(0.55), in: .rect(cornerRadius: 10)).foregroundStyle(.white)
                case .counting:
                    Text("\(countdown)").font(.system(size: 120, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .shadow(radius: 8)
                case .recording:
                    Text("● REC \(seconds)s · swing now").font(.title2.bold()).padding(10)
                        .background(.red, in: .capsule).foregroundStyle(.white)
                }
                Spacer().frame(height: 20)
                Button(action: tapRecord) {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 5).frame(width: 84, height: 84)
                        if state == .ready { Circle().fill(.red).frame(width: 68, height: 68) }
                        else { RoundedRectangle(cornerRadius: 8).fill(.red).frame(width: 36, height: 36) }
                    }
                }
                .padding(.bottom, 20)
            }
            .padding()
        }
        .task {
            if await AVCaptureDevice.requestAccess(for: .video) {
                camera.onFinish = { url in if let url { onVideo(url) } ; dismiss() }
                camera.start { fps = $0 }
            } else { denied = true }
        }
        .onDisappear { camera.stop() }
        .alert("Camera access is off", isPresented: $denied) {
            Button("OK") { dismiss() }
        } message: { Text("Turn on Camera for StrokeLab in Settings → Privacy & Security → Camera.") }
    }

    /// Faint frame showing where you should stand: centered, head near the top, feet near the bottom.
    private var guide: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            RoundedRectangle(cornerRadius: 20)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: w * 0.62, height: h * 0.62)
                .position(x: w / 2, y: h / 2)
        }
        .allowsHitTesting(false)
    }

    private func tapRecord() {
        switch state {
        case .ready:
            state = .counting; countdown = 5
            Task {
                while countdown > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    guard state == .counting else { return }
                    countdown -= 1
                }
                state = .recording; seconds = 0
                camera.record()
                while state == .recording && seconds < 12 {
                    try? await Task.sleep(for: .seconds(1))
                    seconds += 1
                }
                if state == .recording { camera.finish() }
            }
        case .counting:
            state = .ready
        case .recording:
            state = .ready
            camera.finish()
        }
    }
}
