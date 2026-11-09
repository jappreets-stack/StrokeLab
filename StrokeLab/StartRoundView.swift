import SwiftUI

struct StartRoundView: View {
    let onStart: (RoundType, WarmUp) -> Void
    @State private var type: RoundType? = .front
    @State private var showRoutine = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ChoiceRow(label: "Which holes?", options: RoundType.allCases, title: \.rawValue,
                              value: $type, columns: 3)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Did you warm up?").font(.headline)
                        ChoiceButton(title: "Yes, I warmed up", selected: false) { start(.full) }
                        ChoiceButton(title: "Do the 5-minute routine now", selected: false) { showRoutine = true }
                        ChoiceButton(title: "No, straight to the tee", selected: false) { start(.none) }
                        Text("Your dashboard will compare scores on warm-up days with no-warm-up days.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("New round")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showRoutine) {
                RoutineView { start(.routine) }
            }
        }
    }

    private func start(_ w: WarmUp) { onStart(type ?? .front, w) }
}

/// Five minutes in the parking lot / by the first tee.
struct RoutineView: View {
    let onDone: () -> Void
    @State private var done: Set<Int> = []

    private let steps = [
        ("10 easy swings, 7-iron", "Slow first, then full. Stand tall, then turn."),
        ("5 hybrid swings at ¾ speed", "Feel the tempo you'll use off every tee."),
        ("5 chips, 9-iron bump-and-run", "Land it on the fringe, let it roll."),
        ("5 putts from 3 feet", "Make them all. Hear the ball drop."),
        ("3 lag putts from 30 feet", "Finish inside 3 feet. Speed, not line."),
        ("Read hole 1's plan", "Club, target, where the trouble is."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(steps.indices, id: \.self) { i in
                    Button {
                        if done.contains(i) { done.remove(i) } else { done.insert(i) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: done.contains(i) ? "checkmark.circle.fill" : "circle")
                                .font(.title).foregroundStyle(done.contains(i) ? Color.fairway : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(steps[i].0).font(.headline)
                                Text(steps[i].1).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.card, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                ChoiceButton(title: "Done · tee off", selected: true, height: 64, action: onDone)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("5-minute warm-up")
    }
}
