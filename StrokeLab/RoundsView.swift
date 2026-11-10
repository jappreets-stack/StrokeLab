import SwiftUI
import UniformTypeIdentifiers

struct RoundsView: View {
    @Environment(Store.self) private var store
    @State private var addPast = false
    @State private var importing = false
    @State private var pendingImport: URL?
    @State private var importError: String?
    @State private var toDelete: Round?

    var body: some View {
        NavigationStack {
            List {
                if store.data.rounds.isEmpty {
                    ContentUnavailableView("No rounds yet", systemImage: "figure.golf",
                                           description: Text("Start one on the Play tab, or add a past round."))
                }
                ForEach(store.data.rounds) { round in
                    NavigationLink(value: round.id) { RoundRow(round: round) }
                        .swipeActions {
                            Button("Delete", role: .destructive) { toDelete = round }
                        }
                }
            }
            .navigationTitle("Rounds")
            .navigationDestination(for: UUID.self) { RoundDetailView(roundID: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add past round", systemImage: "plus") { addPast = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Backup", systemImage: "externaldrive") {
                        ShareLink("Export backup file", item: store.exportFile())
                        Button("Restore from backup…", systemImage: "square.and.arrow.down") { importing = true }
                    }
                }
            }
            .sheet(isPresented: $addPast) { ScoresOnlyView() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { pendingImport = url }
            }
            .confirmationDialog("Replace everything in StrokeLab with this backup?",
                                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                                titleVisibility: .visible) {
                Button("Replace with backup", role: .destructive) {
                    if let url = pendingImport {
                        do { try store.importBackup(from: url) } catch { importError = error.localizedDescription }
                    }
                    pendingImport = nil
                }
            } message: { Text("Your current rounds, plans and pins will be overwritten. Export a backup first if unsure.") }
            .confirmationDialog("Delete this round?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible, presenting: toDelete) { round in
                Button("Delete round", role: .destructive) { store.delete(round.id) }
            } message: { round in
                Text("\(round.date.formatted(date: .abbreviated, time: .omitted)) · \(round.type.rawValue) · \(round.total). This can't be undone.")
            }
            .alert("Couldn't read that backup", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK") {}
            } message: { Text(importError ?? "") }
        }
    }
}

struct RoundRow: View {
    let round: Round
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(round.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                HStack(spacing: 6) {
                    Text(round.type.rawValue)
                    if round.scoresOnly { Text("· scores only") }
                    if !round.finished { Text("· in progress").foregroundStyle(Color.fairway) }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(round.total)").font(.title2.bold()).monospacedDigit()
                Text(toParText(round.toPar)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct RoundDetailView: View {
    let roundID: UUID
    @Environment(Store.self) private var store
    @State private var editing = false

    var body: some View {
        if let ri = store.index(of: roundID) {
            let r = store.data.rounds[ri]
            List {
                Section {
                    Scorecard(round: r)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                Section("This round") {
                    stat("Score", "\(r.total) (\(toParText(r.toPar)))")
                    stat("Putts", r.entered.contains { $0.putts != nil } ? "\(r.putts)" : "—")
                    if !r.scoresOnly {
                        let pens = r.entered.map(\.penalties).reduce(0, +)
                        let lost = r.entered.filter(\.lostBall).count
                        stat("Penalty strokes", "\(pens)")
                        stat("Lost balls", lost == 0 ? "0 · one-ball round 🎯" : "\(lost)")
                        let gir = r.entered.filter { $0.greenHit == true }.count
                        stat("Greens hit", "\(gir) of \(r.entered.count)")
                        let tries = r.entered.filter { $0.upDown != .notAttempted }
                        stat("Up & downs", "\(tries.filter { $0.upDown == .made }.count) of \(tries.count)")
                        let firsts = r.entered.compactMap { h in h.firstPuttResult ?? (h.putts == 1 ? .made : nil) }
                        if !firsts.isEmpty {
                            let counts = PuttResult.allCases.compactMap { res -> String? in
                                let n = firsts.filter { $0 == res }.count
                                return n > 0 ? "\(n) \(res.rawValue.lowercased())" : nil
                            }
                            stat("First putts", counts.joined(separator: " · "))
                        }
                        if let w = r.warmUp { stat("Warm-up", w.rawValue) }
                    }
                    stat("Blow-ups (7+)", "\(r.entered.filter { ($0.score ?? 0) >= 7 }.count)")
                }
            }
            .navigationTitle(r.date.formatted(date: .abbreviated, time: .omitted))
            .toolbar { Button("Edit") { editing = true } }
            .fullScreenCover(isPresented: $editing) {
                if r.scoresOnly { ScoresOnlyView(editing: r) } else { HoleEntryView(roundID: r.id) }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).font(.body.weight(.semibold)).foregroundStyle(.primary) }
    }
}

/// Classic scorecard grid: hole, par, score (colored), putts.
struct Scorecard: View {
    let round: Round
    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 6) {
            row("Hole", round.holes.map { "\($0.hole)" }, bold: true)
            row("Par", round.holes.map { "\($0.par)" })
            GridRow {
                Text("Score").font(.caption.bold()).gridColumnAlignment(.leading)
                ForEach(round.holes) { h in
                    Text(h.score.map(String.init) ?? "–")
                        .font(.callout.bold()).monospacedDigit()
                        .foregroundStyle(h.score.map { scoreColor($0, par: h.par) } ?? .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            row("Putts", round.holes.map { $0.putts.map(String.init) ?? "–" })
        }
    }

    private func row(_ label: String, _ values: [String], bold: Bool = false) -> some View {
        GridRow {
            Text(label).font(.caption.bold()).gridColumnAlignment(.leading)
            ForEach(values.indices, id: \.self) { i in
                Text(values[i]).font(bold ? .caption.bold() : .caption).monospacedDigit()
                    .foregroundStyle(bold ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
