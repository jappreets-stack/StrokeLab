import SwiftUI

/// Fast entry for old rounds: score and putts only.
struct ScoresOnlyView: View {
    var editing: Round? = nil
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var round = Round(type: .front, scoresOnly: true)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Date", selection: $round.date, in: ...Date(), displayedComponents: .date)
                    if editing == nil {
                        Picker("Holes", selection: Binding(get: { round.type }, set: { changeType($0) })) {
                            ForEach(RoundType.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    ForEach($round.holes) { $h in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading) {
                                Text("\(h.hole)").font(.title3.bold())
                                Text("Par \(h.par)").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(width: 48, alignment: .leading)
                            Counter(value: $h.score, start: h.par, color: h.score.map { scoreColor($0, par: h.par) })
                            Spacer()
                            Counter(value: $h.putts, start: 2, label: "putts")
                        }
                    }
                } footer: {
                    Text("Tap + or − once to start at par (score) or 2 (putts). Putts are optional.")
                }
            }
            .navigationTitle(editing == nil ? "Add past round" : "Edit round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!round.isComplete).bold()
                }
            }
            .onAppear { if let editing { round = editing } }
        }
    }

    private func changeType(_ t: RoundType) {
        let old = Dictionary(uniqueKeysWithValues: round.holes.map { ($0.hole, $0) })
        round.type = t
        round.holes = t.holeNumbers.map { old[$0] ?? HoleScore(hole: $0) }
    }

    private func save() {
        if let editing, let i = store.index(of: editing.id) {
            store.data.rounds[i] = round
        } else {
            store.addPastRound(round)
        }
        dismiss()
    }
}

struct Counter: View {
    @Binding var value: Int?
    let start: Int
    var label: String? = nil
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            step("minus") { value = value.map { max(0, $0 - 1) } ?? start }
            VStack(spacing: 0) {
                Text(value.map(String.init) ?? "–").font(.title2.bold()).monospacedDigit()
                    .foregroundStyle(color ?? .primary)
                if let label { Text(label).font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(minWidth: 40)
            step("plus") { value = value.map { $0 + 1 } ?? start }
        }
    }

    private func step(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.headline)
                .frame(width: 40, height: 40)
                .background(Color.card, in: .circle)
        }
        .buttonStyle(.borderless)
    }
}
