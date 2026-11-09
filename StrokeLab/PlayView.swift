import SwiftUI

struct PlayView: View {
    @Environment(Store.self) private var store
    @State private var showStart = false
    @State private var playing: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "flag.fill").font(.system(size: 56)).foregroundStyle(Color.fairway)
                Text(Course.name).font(.title2.bold())
                Text("\(Course.tees) tees · Par \(Course.par) · \(String(format: "%.1f", Course.rating)) / \(Course.slope)")
                    .foregroundStyle(.secondary)
                Spacer()
                if let round = store.currentRound {
                    let next = round.holes.first { !$0.isEntered }?.hole ?? round.holes.last!.hole
                    ChoiceButton(title: "Continue round · Hole \(next)", selected: true, height: 72) {
                        playing = round.id
                    }
                    Text("\(round.type.rawValue) · \(round.total) (\(toParText(round.toPar))) thru \(round.entered.count)")
                        .foregroundStyle(.secondary)
                } else {
                    ChoiceButton(title: "Start a round", selected: true, height: 72) { showStart = true }
                }
            }
            .padding()
            .navigationTitle("Play")
            .sheet(isPresented: $showStart) {
                StartRoundView { type, warmUp in
                    playing = store.startRound(type, warmUp: warmUp)
                    showStart = false
                }
            }
            .fullScreenCover(item: $playing) { id in
                HoleEntryView(roundID: id)
            }
        }
    }
}

extension UUID: @retroactive Identifiable { public var id: UUID { self } }
