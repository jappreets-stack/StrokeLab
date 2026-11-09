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
                TabView(selection: $index) {
                    ForEach(round.holes.indices, id: \.self) { hi in
                        HoleForm(roundIndex: ri, holeIndex: hi)
                            .tag(hi)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
                index = round.holes.firstIndex { !$0.isEntered } ?? 0
                location.start()
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

    var body: some View {
        @Bindable var store = store
        let s = $store.data.rounds[roundIndex].holes[holeIndex]
        let entry = s.wrappedValue
        let hole = Course.hole(entry.hole)
        let plan = store.plan(entry.hole)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(hole)
                YardageStrip(pins: store.pins(hole.number))
                PlanCard(plan: plan)

                ChoiceRow(label: "Score", options: Array(max(1, hole.par - 1)...(hole.par + 6)),
                          title: { "\($0)" }, value: s.score, columns: 4, height: 60)
                ChoiceRow(label: "Putts", options: [0, 1, 2, 3, 4], title: { "\($0)" },
                          value: s.putts, columns: 5)
                ChoiceRow(label: "Tee shot", options: TeeResult.options(par: hole.par), title: \.rawValue,
                          value: s.teeResult, columns: hole.par == 3 ? 5 : 4)
                ChoiceRow(label: "Tee club", hint: entry.teeClub == plan.teeClub ? "(the plan)" : "(off plan)",
                          options: Club.allCases, title: \.rawValue, value: s.teeClub, columns: 6, height: 44)
                ChoiceRow(label: "Penalty strokes", options: [0, 1, 2, 3], title: { "\($0)" },
                          value: Binding(get: { entry.penalties }, set: { s.wrappedValue.penalties = $0 ?? 0 }))
                ChoiceRow(label: "Lost ball", options: [false, true], title: { $0 ? "Yes" : "No" },
                          value: Binding(get: { entry.lostBall }, set: { s.wrappedValue.lostBall = $0 ?? false }),
                          columns: 2)
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
            HStack(spacing: 0) {
                cell("Front", location.yards(to: pins.front))
                cell("Center", location.yards(to: pins.center), big: true)
                cell("Back", location.yards(to: pins.back))
            }
            .padding(.vertical, 6)
            .background(Color.card, in: .rect(cornerRadius: 14))
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
