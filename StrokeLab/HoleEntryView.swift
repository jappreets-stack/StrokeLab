import SwiftUI

/// One screen per hole: plan card on top, big buttons below. Swipe or tap Next to move on.
struct HoleEntryView: View {
    let roundID: UUID
    @Environment(Store.self) private var store
    @Environment(LocationModel.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var confirmFinish = false

    var body: some View {
        if let ri = store.index(of: roundID) {
            let round = store.data.rounds[ri]
            NavigationStack {
                // One hole at a time (no swiping, so dragging the map never flips the hole). Back/Next below.
                HoleForm(roundIndex: ri, holeIndex: min(index, round.holes.count - 1))
                    .id(index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaInset(edge: .bottom) { bottomBar(round) }
                .navigationTitle("Hole \(round.holes[index].hole)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text("Hole \(round.holes[index].hole)").font(.headline)
                            if !round.entered.isEmpty {
                                Text("\(round.total) · \(toParText(round.toPar)) thru \(round.entered.count)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onAppear {
                index = round.currentHole.flatMap { h in round.holes.firstIndex { $0.hole == h } }
                    ?? round.holes.firstIndex { !$0.isEntered } ?? 0
                location.start()
            }
            .onChange(of: index) { _, i in
                // Remember where you are, so reopening the round lands on the same hole.
                if store.data.rounds.indices.contains(ri), store.data.rounds[ri].holes.indices.contains(i) {
                    store.data.rounds[ri].currentHole = store.data.rounds[ri].holes[i].hole
                }
            }
            .onChange(of: store.data.rounds.first { $0.id == roundID }?.currentHole) { _, h in
                // Follow the hole you picked on the watch.
                guard let h, let r = store.data.rounds.first(where: { $0.id == roundID }),
                      let i = r.holes.firstIndex(where: { $0.hole == h }), i != index else { return }
                index = i
            }
            .onDisappear { location.stop() }
            .confirmationDialog("Finish this round?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish round") {
                    if store.data.currentRoundID == roundID { store.finishCurrentRound() }
                    else { store.data.rounds[ri].finished = true }
                    dismiss()
                }
            } message: {
                let missing = round.holes.count - round.entered.count
                Text(missing == 0 ? "\(round.total) (\(toParText(round.toPar)))"
                                  : "\(missing) hole(s) have no score yet. They won't count.")
            }
        } else {
            Text("Round not found").onAppear { dismiss() }
        }
    }

    private func bottomBar(_ round: Round) -> some View {
        HStack(spacing: 10) {
            ChoiceButton(title: "◀︎ Back", selected: false, height: 56) {
                withAnimation { index = max(0, index - 1) }
            }
            .disabled(index == 0).opacity(index == 0 ? 0.4 : 1)
            .frame(width: 110)
            if index == round.holes.count - 1 {
                ChoiceButton(title: "Finish round", selected: true, height: 56) { confirmFinish = true }
            } else {
                ChoiceButton(title: "Next · Hole \(round.holes[index + 1].hole) ▶︎", selected: true, height: 56) {
                    withAnimation { index += 1 }
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }
}

/// The stats buttons for a single hole.
private struct HoleForm: View {
    let roundIndex: Int
    let holeIndex: Int
    @Environment(Store.self) private var store
    @Environment(LocationModel.self) private var location
    @State private var showMap = false
    @State private var showMore = false
    @State private var mode: Mode = .map
    enum Mode: String, CaseIterable { case map = "Map", score = "Score" }

    private func moreSummary(_ e: HoleScore, _ plan: HolePlan) -> String {
        var parts = ["\(e.teeClub?.rawValue ?? plan.teeClub.rawValue) off the tee"]
        parts.append(e.penalties == 0 ? "no penalties" : "\(e.penalties) penalty")
        if e.lostBall { parts.append("lost ball") }
        if let r = e.firstPuttResult { parts.append("first putt \(r.rawValue.lowercased())") }
        return parts.joined(separator: " · ") + " — tap for penalties, lost ball, putts"
    }

    var body: some View {
        @Bindable var store = store
        let s = $store.data.rounds[roundIndex].holes[holeIndex]
        let entry = s.wrappedValue
        let hole = Course.hole(entry.hole)
        let plan = store.plan(entry.hole)

        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 6).padding(.bottom, 8)

            if mode == .map {
                mapMode(hole, plan)
            } else {
                scoreMode(s, entry, hole, plan)
            }
        }
        .fullScreenCover(isPresented: $showMap) { HoleMapView(hole: hole.number) }
    }

    /// SwingU-style: the hole on satellite with big yardages, plan underneath, one button to enter the score.
    private func mapMode(_ hole: Hole, _ plan: HolePlan) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HoleMapContent(hole: hole.number, compactFooter: true)
                YardageStrip(pins: store.pins(hole.number))
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 10).padding(.top, 8)
                    .allowsHitTesting(false)
            }
            VStack(spacing: 8) {
                HStack {
                    Text("Par \(hole.par) · \(hole.yards) yds").font(.headline)
                    Spacer()
                    Text("\(plan.teeClub.rawValue) · target \(plan.target)").font(.headline).foregroundStyle(Color.fairway)
                }
                if plan.troubleSide != .none || !plan.hazards.isEmpty {
                    Label(plan.troubleText, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ChoiceButton(title: "Enter score", selected: false, height: 50, font: .headline) {
                    withAnimation { mode = .score }
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private func scoreMode(_ s: Binding<HoleScore>, _ entry: HoleScore, _ hole: Hole, _ plan: HolePlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(hole)
                YardageStrip(pins: store.pins(hole.number))
                    .contentShape(.rect)
                    .onTapGesture { showMap = true }
                PlanCard(plan: plan)

                ChoiceRow(label: "Score", options: Array(max(1, hole.par - 1)...(hole.par + 6)),
                          title: { "\($0)" }, value: s.score, columns: 4, height: 60)
                ChoiceRow(label: "Putts", options: [0, 1, 2, 3, 4], title: { "\($0)" },
                          value: s.putts, columns: 5)
                ChoiceRow(label: "Tee shot", options: TeeResult.options(par: hole.par), title: \.rawValue,
                          value: s.teeResult, columns: hole.par == 3 ? 5 : 4)
                if entry.teeMissed {
                    ChoiceRow(label: "How far off?", options: MissSize.allCases, title: \.label,
                              value: s.missSize, columns: 3, height: 48)
                }

                Button { withAnimation { showMore.toggle() } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(showMore ? "Less" : "More").font(.headline)
                            if !showMore { Text(moreSummary(entry, plan)).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Image(systemName: showMore ? "chevron.up" : "chevron.down").font(.headline)
                    }
                    .padding()
                    .background(Color.card, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if showMore {
                    ChoiceRow(label: "Penalty strokes", options: [0, 1, 2, 3], title: { "\($0)" },
                              value: Binding(get: { entry.penalties }, set: { s.wrappedValue.penalties = $0 ?? 0 }))
                    ChoiceRow(label: "Greenside bunker", options: [false, true], title: { $0 ? "Yes" : "No" },
                              value: s.sand, columns: 2)
                    ChoiceRow(label: "Lost ball", options: [false, true], title: { $0 ? "Yes" : "No" },
                              value: Binding(get: { entry.lostBall }, set: { s.wrappedValue.lostBall = $0 ?? false }),
                              columns: 2)
                    ChoiceRow(label: "Tee club", hint: entry.teeClub == plan.teeClub ? "(the plan)" : "(off plan)",
                              options: Club.allCases, title: \.rawValue, value: s.teeClub, columns: 6, height: 44)
                    if (entry.putts ?? 0) > 0 {
                        ChoiceRow(label: "First putt length", hint: "(feet)", options: PuttLength.allCases, title: \.rawValue,
                                  value: s.firstPutt, columns: 3, height: 48)
                        ChoiceRow(label: "First putt", options: PuttResult.allCases, title: \.rawValue,
                                  value: Binding(get: { entry.firstPuttResult ?? (entry.putts == 1 ? .made : nil) },
                                                 set: { s.wrappedValue.firstPuttResult = $0 }),
                                  columns: 5, height: 48)
                        if let r = entry.firstPuttResult, r != .made {
                            ChoiceRow(label: "Finished", hint: "(from the hole)", options: PuttMiss.allCases, title: \.rawValue,
                                      value: s.puttMiss, columns: 3, height: 48)
                        }
                    }
                    ChoiceRow(label: "Green in regulation",
                              hint: entry.greenOverride == nil && entry.autoGreen != nil ? "(worked out from score + putts)" : nil,
                              options: [true, false], title: { $0 ? "Hit" : "Missed" },
                              value: Binding(get: { entry.greenHit },
                                             set: { s.wrappedValue.greenOverride = ($0 == entry.autoGreen) ? nil : $0 }),
                              columns: 2)
                    if entry.greenHit == false {
                        ChoiceRow(label: "Up & down", hint: entry.upDownOverride == nil ? "(auto: par or better = made)" : nil,
                                  options: [UpDown.made, .missed, .notAttempted],
                                  title: { switch $0 { case .made: "Made"; case .missed: "Missed"; case .notAttempted: "No chance" } },
                                  value: Binding(get: { entry.upDown },
                                                 set: { s.wrappedValue.upDownOverride = ($0 == entry.autoUpDown) ? nil : $0 }),
                                  columns: 3)
                    }
                }
            }
            .padding()
            .padding(.bottom, 20)
        }
    }

    private func header(_ hole: Hole) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Par \(hole.par)").font(.largeTitle.bold())
            Text("\(hole.yards) yds").font(.title2.weight(.semibold))
            Spacer()
            Pill(text: "SI \(hole.strokeIndex)")
            Button { showMap = true } label: {
                Image(systemName: "map.fill").font(.title3.bold())
                    .frame(width: 48, height: 40)
                    .background(Color.fairway, in: .rect(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Hole map")
        }
    }
}

struct PlanCard: View {
    let plan: HolePlan
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(plan.teeClub.rawValue, systemImage: "figure.golf").font(.title3.bold())
                Spacer()
                Text("Target \(plan.target)").font(.title3.bold())
            }
            HStack(spacing: 6) {
                Image(systemName: plan.troubleSide == .none && plan.hazards.isEmpty ? "checkmark.shield" : "exclamationmark.triangle.fill")
                    .foregroundStyle(plan.hazards.contains(.ob) || plan.hazards.contains(.water) ? .red : .orange)
                Text(plan.troubleText).font(.headline)
            }
            if !plan.note.isEmpty { Text(plan.note).font(.callout).foregroundStyle(.secondary) }
            if let read = plan.greenRead, !read.isEmpty {
                Label(read, systemImage: "arrow.down.right.circle.fill").font(.callout.weight(.semibold))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fairway.opacity(0.15), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.fairway, lineWidth: 2))
    }
}

struct YardageStrip: View {
    let pins: GreenPins
    @Environment(LocationModel.self) private var location

    var body: some View {
        if pins.center != nil {
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    cell("Front", location.yards(to: pins.front))
                    cell("Center", location.yards(to: pins.center), big: true)
                    cell("Back", location.yards(to: pins.back))
                }
                advice
            }
            .padding(.vertical, 6)
            .overlay(alignment: .bottomTrailing) {
                if let a = location.accuracyYards {
                    Text("GPS ±\(a)").font(.caption2.weight(.semibold)).foregroundStyle(a > 10 ? .orange : .secondary).padding(6)
                }
            }
            .background(Color.card, in: .rect(cornerRadius: 14))
            .task { await WindModel.shared.refresh() }
        }
    }

    @Environment(Store.self) private var store
    @ViewBuilder private var advice: some View {
        if let a = ShotAdvice.make(from: location.location, to: pins.center, wind: WindModel.shared.wind, clubs: store.clubYards) {
            HStack(spacing: 4) {
                if let deg = a.arrow, a.windText != "Calm" {
                    Image(systemName: "location.north.fill").rotationEffect(.degrees(deg))
                }
                Text([a.windText, "plays \(a.playsLike)", a.club?.rawValue].compactMap { $0 }.joined(separator: " · "))
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Color.fairway)
            .padding(.bottom, 10)
        }
    }

    private func cell(_ label: String, _ yards: Int?, big: Bool = false) -> some View {
        VStack(spacing: 0) {
            Text(yards.map { $0 > 999 ? "—" : "\($0)" } ?? "…")
                .font(.system(size: big ? 44 : 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
