import Foundation

/// Turns measurements into plain-English coaching. All on the phone; rules, not AI.
nonisolated struct CoachTip: Identifiable, Sendable {
    enum Level: Int, Sendable { case good = 0, watch = 1, fix = 2 }
    let id = UUID()
    let level: Level
    let title: String
    let detail: String
    var drill: String? = nil
}

nonisolated enum SwingCoach {
    static func tips(for a: SwingAnalysis) -> [CoachTip] {
        let m = a.metrics
        var out: [CoachTip] = []
        func f(_ x: Double) -> String { String(format: "%.1f", abs(x)) }
        func d(_ x: Double) -> String { "\(Int(abs(x).rounded()))°" }

        // Tempo (both views)
        if let t = m.tempo, let b = m.backswing, let ds = m.downswing {
            let ratio = String(format: "%.1f:1", t)
            let times = String(format: "back %.2fs · down %.2fs", b, ds)
            if t < 2.4 {
                out.append(.init(level: .fix, title: "Quick from the top (\(ratio))",
                    detail: "Your backswing is short in time compared with your downswing (\(times)). Good players are near 3:1. Rushing the top is a classic cause of thin and topped shots.",
                    drill: "Hum your tempo song, or count “one-two-three” going back and “four” coming down. Hit 10 balls at 70% feeling the pause at the top."))
            } else if t > 3.8 {
                out.append(.init(level: .watch, title: "Slow, long backswing (\(ratio))",
                    detail: "Your backswing takes a long time compared with the downswing (\(times)). That can make the transition jerky.",
                    drill: "Same count, but keep it flowing: “one-two-three-four” with no hold at the top."))
            } else {
                out.append(.init(level: .good, title: "Tempo \(ratio)", detail: "Right in the tour range (about 3:1). \(times)."))
            }
        }

        switch a.view {
        case .downTheLine:
            if let e = m.hipsTowardBall {
                if e > 4 {
                    out.append(.init(level: .fix, title: "Early extension: hips moved \(f(e))\" toward the ball",
                        detail: "Your hips thrust toward the ball through impact, which stands you up and makes the club hit thin or fat. This is the “over-squat, then stand up” pattern.",
                        drill: "Butt-to-wall drill: set up with your backside touching a wall, bag or chair. Swing slowly and keep it touching through impact. Feel: stand tall at address, then turn."))
                } else if e > 2 {
                    out.append(.init(level: .watch, title: "Hips drift \(f(e))\" toward the ball",
                        detail: "A little early extension. Not a disaster, but it gets worse when you’re tired or rushing.",
                        drill: "Feel your trail back pocket turn behind you on the downswing, not toward the ball."))
                } else {
                    out.append(.init(level: .good, title: "Hips held their depth", detail: "Your hips stayed back through impact (\(String(format: "%+.1f", e))\"). That’s what stops thin shots."))
                }
            }
            if let loss = m.spineLoss, let sa = m.spineAngleAddress {
                if loss > 8 {
                    out.append(.init(level: .fix, title: "Stood up \(d(loss)) through impact",
                        detail: "Your forward bend went from \(d(sa)) at address to \(d(sa - loss)) at impact. Standing up pulls the low point up: thin and topped shots.",
                        drill: "Chest-over-ball feel: hit half shots keeping your chest pointing at the ball until after impact. Start taller at address so there’s less to give back."))
                } else if loss > 4 {
                    out.append(.init(level: .watch, title: "Lost \(d(loss)) of posture", detail: "Slight rise through impact. Keep an eye on it."))
                } else {
                    out.append(.init(level: .good, title: "Posture held", detail: "Your forward bend stayed within \(d(loss)) from address to impact."))
                }
            }
            if let up = m.headUp, up > 3 {
                out.append(.init(level: .watch, title: "Head rose \(f(up))\" by impact",
                    detail: "Your head came up before the ball was gone, usually from standing up.",
                    drill: "Keep your eyes on the back of the ball until you see the grass where it was."))
            }
            if let ott = m.overTheTop, let under = m.underPlane {
                if ott > 0.4 {
                    out.append(.init(level: .fix, title: "Over the top",
                        detail: "On the way down your hands went above the shoulder line (red) for \(Int(ott * 100))% of the downswing. That’s an out-to-in path: pulls and slices.",
                        drill: "Pump drill: swing to the top, pump halfway down twice letting your trail elbow drop to your hip, then hit. Hands should come down inside the red line."))
                } else if under > 0.4 {
                    out.append(.init(level: .watch, title: "Under the plane",
                        detail: "Your hands dropped below the shaft line (green) for \(Int(under * 100))% of the downswing. Too flat/stuck: blocks and hooks.",
                        drill: "Feel your hands stay in front of your chest as you turn through, not behind you."))
                } else {
                    out.append(.init(level: .good, title: "On plane", detail: "Your hands came down between the green and red lines. That’s the slot."))
                }
            } else {
                out.append(.init(level: .watch, title: "Tap the ball to check your swing plane",
                    detail: "Tap “Set ball” and then the ball in the video. I’ll draw the shaft line (green) and shoulder line (red) and grade your downswing."))
            }

        case .faceOn:
            if let s = m.hipSwayAtTop {
                if s > 3 {
                    out.append(.init(level: .fix, title: "Hips swayed \(f(s))\" off the ball",
                        detail: "On the backswing your hips slid away from the target instead of turning. You then have to slide back to hit it, which costs contact.",
                        drill: "Turn, don’t slide: feel your trail hip pocket go behind you. Keep your trail knee flexed and inside your trail foot at the top."))
                } else {
                    out.append(.init(level: .good, title: "Hips turned, didn’t slide", detail: "Only \(f(s))\" of sway at the top."))
                }
            }
            if let h = m.headSwayAtTop, h > 4 {
                out.append(.init(level: .watch, title: "Head moved \(f(h))\" back", detail: "Some head movement back is fine; this is a lot.",
                    drill: "Feel your head stays inside your trail foot at the top."))
            }
            if let h = m.headAheadAtImpact, h > 3 {
                out.append(.init(level: .watch, title: "Head \(f(h))\" toward the target at impact",
                    detail: "Your head got ahead of the ball. That usually adds loft problems and weak contact.",
                    drill: "Keep your head behind the ball until it’s gone."))
            }
            if let st = m.shoulderTurn {
                if st < 55 {
                    out.append(.init(level: .watch, title: "Short shoulder turn (≈\(d(st)))",
                        detail: "Your shoulders turned less than usual. Don’t force it with your shoulder injury.",
                        drill: "Let your lead heel come up a little and your hips turn more, so the shoulders get there without strain."))
                } else {
                    out.append(.init(level: .good, title: "Shoulder turn ≈\(d(st))", detail: "A full, comfortable turn (camera estimate)."))
                }
            }
            if let ht = m.hipTurn {
                out.append(.init(level: .good, title: "Hip turn ≈\(d(ht))", detail: "Camera estimate at the top. Most amateurs are 35–50°."))
            }
        }
        return out.sorted { $0.level.rawValue > $1.level.rawValue }
    }

    /// One line for the list: the biggest thing to fix, or the best news.
    static func headline(for a: SwingAnalysis) -> String {
        let t = tips(for: a)
        if let fix = t.first(where: { $0.level == .fix }) { return fix.title }
        if let watch = t.first(where: { $0.level == .watch }) { return watch.title }
        return t.first?.title ?? "Analyzed"
    }
}
