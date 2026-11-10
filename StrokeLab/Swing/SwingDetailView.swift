import SwiftUI
import AVFoundation

struct SwingDetailView: View {
    let record: SwingRecord
    @Environment(SwingStore.self) private var swings
    @AppStorage("leftHanded") private var leftHanded = false
    @State private var analysis: SwingAnalysis?
    @State private var player = AVPlayer()
    @State private var time: Double = 0
    @State private var duration: Double = 1
    @State private var slow = true
    @State private var settingBall = false
    @State private var showSkeleton = true
    @State private var observer: Any?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let a = analysis {
                    ZStack {
                        PlayerLayerView(player: player)
                        SwingOverlay(analysis: a, time: time, showSkeleton: showSkeleton)
                            .allowsHitTesting(settingBall)
                            .contentShape(.rect)
                            .gesture(SpatialTapGesture().onEnded { setBall(at: $0.location) }, including: settingBall ? .all : .none)
                            .overlay(alignment: .top) {
                                if settingBall {
                                    Text("Tap the ball").font(.headline).padding(8).background(.yellow, in: .capsule).padding(.top, 8)
                                }
                            }
                    }
                    .aspectRatio(a.aspect, contentMode: .fit)
                    .frame(maxHeight: 520)
                    .background(.black)
                    .clipShape(.rect(cornerRadius: 12))
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { overlaySize = $0 }

                    controls(a)
                    legend(a)
                    VStack(spacing: 10) {
                        ForEach(SwingCoach.tips(for: a)) { TipCard(tip: $0) }
                    }
                    numbers(a)
                } else {
                    ProgressView("Loading…").padding(.top, 80)
                }
            }
            .padding()
        }
        .navigationTitle("\(record.club) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            analysis = swings.analysis(record)
            let item = AVPlayerItem(url: swings.videoURL(record))
            player.replaceCurrentItem(with: item)
            duration = (try? await item.asset.load(.duration).seconds) ?? 1
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 120), queue: .main) { t in
                MainActor.assumeIsolated { time = t.seconds }
            }
            if let a = analysis, let f = a.frame(at: .address) { seek(max(0, f.t - 0.2)) }
        }
        .onDisappear { player.pause(); if let observer { player.removeTimeObserver(observer) } }
    }

    @State private var overlaySize: CGSize = .zero

    // MARK: Controls

    private func controls(_ a: SwingAnalysis) -> some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { time }, set: { seek($0) }), in: 0...max(duration, 0.1))
            HStack(spacing: 8) {
                ForEach(SwingPhase.allCases, id: \.self) { p in
                    ChoiceButton(title: p.rawValue, selected: isAt(p, a), height: 40, font: .subheadline.bold()) {
                        if let f = a.frame(at: p) { player.pause(); seek(f.t) }
                    }
                }
            }
            HStack(spacing: 8) {
                ChoiceButton(title: player.rate == 0 ? "▶︎ Play" : "❚❚ Pause", selected: true, height: 44, font: .headline) { togglePlay(a) }
                ChoiceButton(title: slow ? "¼ speed" : "Full speed", selected: false, height: 44, font: .headline) {
                    slow.toggle(); if player.rate != 0 { player.rate = rate }
                }
                ChoiceButton(title: showSkeleton ? "Body on" : "Body off", selected: false, height: 44, font: .headline) { showSkeleton.toggle() }
            }
            if a.view == .downTheLine {
                ChoiceButton(title: a.ball == nil ? "Set ball (for swing plane)" : "Move ball", selected: settingBall, height: 44, font: .headline) {
                    settingBall.toggle()
                    if settingBall, let f = a.frame(at: .address) { player.pause(); seek(f.t) }
                }
            }
            Picker("View", selection: Binding(get: { a.view }, set: { remeasure(view: $0) })) {
                ForEach(CameraView.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var rate: Float {
        // Slow-motion videos already have many frames per second; ¼ of real time looks smooth.
        slow ? 0.25 : 1
    }

    private func togglePlay(_ a: SwingAnalysis) {
        if player.rate != 0 { player.pause(); return }
        if let finish = a.frame(at: .finish), time >= finish.t - 0.02, let addr = a.frame(at: .address) { seek(max(0, addr.t - 0.2)) }
        player.rate = rate
    }

    private func seek(_ t: Double) {
        time = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func isAt(_ p: SwingPhase, _ a: SwingAnalysis) -> Bool {
        guard let f = a.frame(at: p) else { return false }
        return abs(f.t - time) < 0.02
    }

    private func setBall(at point: CGPoint) {
        guard settingBall, overlaySize.width > 0, let a = analysis else { return }
        let ball = CGPoint(x: point.x / overlaySize.width, y: point.y / overlaySize.height)
        settingBall = false
        remeasure(ball: ball, view: a.view)
    }

    private func remeasure(ball: CGPoint? = nil, view: CameraView) {
        guard let a = analysis else { return }
        if let new = try? PoseAnalyzer.measure(frames: a.frames, aspect: a.aspect, leftHanded: leftHanded,
                                               ball: ball ?? a.ball, forcedView: view) {
            analysis = new
            swings.save(new, for: record)
        }
    }

    // MARK: Info

    private func legend(_ a: SwingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if a.view == .downTheLine {
                key(.green, "Shaft plane: ball → hands at address")
                key(.red, "Shoulder plane: ball → base of neck. Coming down above it = over the top")
                key(.cyan, "Your posture at address. Hips moving past it = early extension")
            } else {
                key(.cyan, "Where your head and hips started")
            }
            key(.yellow, "Hand path: backswing (yellow) · downswing (white)")
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func key(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 16, height: 4); Text(t) }
    }

    private func numbers(_ a: SwingAnalysis) -> some View {
        let m = a.metrics
        func inch(_ v: Double?) -> String { v.map { String(format: "%+.1f\"", $0) } ?? "—" }
        func deg(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))°" } ?? "—" }
        return VStack(alignment: .leading, spacing: 6) {
            Text("The numbers").font(.headline)
            row("Tempo", m.tempo.map { String(format: "%.1f : 1", $0) } ?? "—")
            row("Backswing / downswing", m.backswing.map { b in String(format: "%.2fs / %.2fs", b, m.downswing ?? 0) } ?? "—")
            if a.view == .downTheLine {
                row("Hips toward ball at impact", inch(m.hipsTowardBall))
                row("Spine bend address → impact", "\(deg(m.spineAngleAddress)) → \(deg(m.spineAngleImpact))")
                row("Head up / toward ball", "\(inch(m.headUp)) / \(inch(m.headTowardBall))")
                row("Downswing above shoulder line", m.overTheTop.map { "\(Int($0 * 100))%" } ?? "set ball")
                row("Downswing below shaft line", m.underPlane.map { "\(Int($0 * 100))%" } ?? "set ball")
            } else {
                row("Hip sway at top", inch(m.hipSwayAtTop))
                row("Head back at top", inch(m.headSwayAtTop))
                row("Head toward target at impact", inch(m.headAheadAtImpact))
                row("Shoulder / hip turn (est.)", "\(deg(m.shoulderTurn)) / \(deg(m.hipTurn))")
            }
            Text("Inches are estimates scaled from your body size in the video. Compare swings filmed from the same spot.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 12))
    }

    private func row(_ l: String, _ v: String) -> some View {
        HStack { Text(l).foregroundStyle(.secondary); Spacer(); Text(v).bold().monospacedDigit() }.font(.subheadline)
    }
}

struct TipCard: View {
    let tip: CoachTip
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(tip.title, systemImage: icon).font(.headline).foregroundStyle(color)
            Text(tip.detail).font(.subheadline)
            if let drill = tip.drill {
                Text("Drill: ").bold() + Text(drill)
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.5)))
    }
    private var color: Color { switch tip.level { case .fix: .red; case .watch: .orange; case .good: .fairway } }
    private var icon: String { switch tip.level { case .fix: "exclamationmark.triangle.fill"; case .watch: "eye.fill"; case .good: "checkmark.circle.fill" } }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> V { let v = V(); v.playerLayer.player = player; v.playerLayer.videoGravity = .resize; return v }
    func updateUIView(_ uiView: V, context: Context) {}
    final class V: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Lines drawn over the video. The container is sized to the video's aspect ratio, so normalized points map directly.
struct SwingOverlay: View {
    let analysis: SwingAnalysis
    let time: Double
    let showSkeleton: Bool

    private static let bones: [(Joint, Joint)] = [
        (.neck, .leftShoulder), (.neck, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.neck, .root), (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle), (.neck, .nose),
    ]

    var body: some View {
        Canvas { ctx, size in
            func p(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x * size.width, y: q.y * size.height) }
            let a = analysis
            guard let address = a.frame(at: .address) else { return }

            // Reference lines from address
            if a.view == .downTheLine {
                if let ball = a.ball {
                    if let hands = address.hands { line(ctx, size, from: p(ball), through: p(hands), color: .green) }
                    if let neck = address.joints[.neck] { line(ctx, size, from: p(ball), through: p(neck), color: .red) }
                    ctx.fill(Path(ellipseIn: CGRect(x: p(ball).x - 7, y: p(ball).y - 7, width: 14, height: 14)), with: .color(.white))
                }
                if let n = address.joints[.neck], let r = address.joints[.root] {
                    var spine = Path(); spine.move(to: p(r)); spine.addLine(to: p(n))
                    ctx.stroke(spine, with: .color(.cyan.opacity(0.8)), style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    // Butt line: vertical through the back of the hips at address
                    let back = CGPoint(x: r.x - 0.04 * a.ballSide / a.aspect, y: r.y)
                    var butt = Path(); butt.move(to: CGPoint(x: p(back).x, y: p(back).y - size.height * 0.18)); butt.addLine(to: CGPoint(x: p(back).x, y: p(back).y + size.height * 0.12))
                    ctx.stroke(butt, with: .color(.cyan.opacity(0.8)), style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                }
            } else {
                if let nose = address.joints[.nose], let n = address.joints[.neck] {
                    let r = abs(n.y - nose.y) * size.height * 1.2
                    ctx.stroke(Path(roundedRect: CGRect(x: p(nose).x - r, y: p(nose).y - r * 1.2, width: 2 * r, height: 2.2 * r), cornerRadius: 6),
                               with: .color(.cyan.opacity(0.8)), style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                }
                if let root = address.joints[.root] {
                    for dx in [-0.06, 0.06] {
                        let x = p(CGPoint(x: root.x + dx / a.aspect, y: 0)).x
                        var v = Path(); v.move(to: CGPoint(x: x, y: p(root).y - size.height * 0.12)); v.addLine(to: CGPoint(x: x, y: p(root).y + size.height * 0.25))
                        ctx.stroke(v, with: .color(.cyan.opacity(0.8)), style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    }
                }
            }

            // Hand path up to now
            let top = a.phases[.top] ?? 0
            let end = a.phases[.finish] ?? a.frames.count - 1
            var back = Path(), down = Path()
            for i in a.takeaway...end where a.frames[i].t <= time {
                guard let h = a.frames[i].hands else { continue }
                if i <= top { back.isEmpty ? back.move(to: p(h)) : back.addLine(to: p(h)) }
                else { down.isEmpty ? down.move(to: p(h)) : down.addLine(to: p(h)) }
            }
            ctx.stroke(back, with: .color(.yellow), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            ctx.stroke(down, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            // Body now
            if showSkeleton, let now = a.frames.min(by: { abs($0.t - time) < abs($1.t - time) }), abs(now.t - time) < 0.1 {
                for (j1, j2) in Self.bones {
                    guard let q1 = now.joints[j1], let q2 = now.joints[j2] else { continue }
                    var b = Path(); b.move(to: p(q1)); b.addLine(to: p(q2))
                    ctx.stroke(b, with: .color(.green.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                for q in now.joints.values {
                    ctx.fill(Path(ellipseIn: CGRect(x: p(q).x - 4, y: p(q).y - 4, width: 8, height: 8)), with: .color(.white))
                }
            }
        }
    }

    /// A line from a through b, extended to the edge of the frame.
    private func line(_ ctx: GraphicsContext, _ size: CGSize, from a: CGPoint, through b: CGPoint, color: Color) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(hypot(dx, dy), 1)
        let far = CGPoint(x: a.x + dx / len * size.height * 2, y: a.y + dy / len * size.height * 2)
        var path = Path(); path.move(to: a); path.addLine(to: far)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3))
    }
}
