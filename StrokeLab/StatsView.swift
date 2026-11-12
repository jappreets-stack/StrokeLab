import SwiftUI
import Charts

/// The dashboard: where your strokes go, in plain English. Tap the charts for details.
struct StatsView: View {
    @Environment(Store.self) private var store
    @State private var range: RangeFilter = .ten
    @State private var nine: NineFilter = .front
    @State private var pickedNine: Int?
    @State private var pickedHole: String?

    enum RangeFilter: String, CaseIterable {
        case five = "Last 5", ten = "Last 10", all = "All"
        var limit: Int? { switch self { case .five: 5; case .ten: 10; case .all: nil } }
    }
    enum NineFilter: String, CaseIterable {
        case front = "Front 9", back = "Back 9", both = "All holes"
        func has(_ h: Int) -> Bool { switch self { case .front: h <= 9; case .back: h >= 10; case .both: true } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    filters
                    let s = StatsModel(rounds: store.data.rounds, nine: nine, limit: range.limit)
                    if s.holes.isEmpty {
                        ContentUnavailableView("No scores yet", systemImage: "chart.bar",
                                               description: Text("Play a round (or add a past one in Rounds) and your stats show up here."))
                            .padding(.top, 40)
                    } else {
                        takeaways(s)
                        scoring(s)
                        holesCard(s)
                        teeCard(s)
                        par3Card(s)
                        puttingCard(s)
                        shortGameCard(s)
                        if s.warmCompare != nil { warmCard(s) }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stats")
        }
    }

    // MARK: Filters

    private var filters: some View {
        VStack(spacing: 8) {
            Picker("Holes", selection: $nine) {
                ForEach(NineFilter.allCases, id: \.self) { Text($0.rawValue) }
            }
            Picker("Rounds", selection: $range) {
                ForEach(RangeFilter.allCases, id: \.self) { Text($0.rawValue) }
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Takeaways

    private func takeaways(_ s: StatsModel) -> some View {
        Card(title: "What the numbers say", icon: "lightbulb.fill") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(s.takeaways, id: \.self) { t in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Color.fairway).frame(width: 7, height: 7).padding(.top, 7)
                        Text(LocalizedStringKey(t)).font(.callout)
                    }
                }
                if s.roundCount < 5 {
                    Text("Only \(s.roundCount) round\(s.roundCount == 1 ? "" : "s") so far. Patterns get trustworthy around 5–10.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Scoring

    private func scoring(_ s: StatsModel) -> some View {
        Card(title: "9-hole scores", icon: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Tile(value: s.avgNine.map { String(format: "%.1f", $0) } ?? "—", label: "Average")
                    Tile(value: s.bestNine.map { "\($0)" } ?? "—", label: "Best")
                    Tile(value: String(format: "%.1f", s.blowUpsPerNine), label: "Blow-ups / 9",
                         color: s.blowUpsPerNine >= 1 ? .red : .fairway)
                }
                if s.nines.count >= 2 {
                    Chart {
                        RuleMark(y: .value("Break 90", 45))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Break-90 pace: 45").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                            }
                        ForEach(s.nines) { n in
                            LineMark(x: .value("Round", n.index), y: .value("Score", n.score))
                                .foregroundStyle(Color.fairway)
                            PointMark(x: .value("Round", n.index), y: .value("Score", n.score))
                                .foregroundStyle(n.score <= 45 ? Color.fairway : Color.primary)
                                .symbolSize(pickedNine == n.index ? 140 : 50)
                        }
                        if let p = pickedNine, let n = s.nines.first(where: { $0.index == p }) {
                            RuleMark(x: .value("Round", p))
                                .foregroundStyle(.secondary.opacity(0.3))
                                .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                    VStack(spacing: 0) {
                                        Text("\(n.score)").font(.headline)
                                        Text("\(n.date.formatted(.dateTime.month().day())) · \(n.side)").font(.caption2)
                                    }
                                    .padding(6).background(.background, in: .rect(cornerRadius: 8))
                                }
                        }
                    }
                    .chartXSelection(value: $pickedNine)
                    .chartXAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 170)
                    Text("Oldest → newest. Drag across to see each round.").font(.caption).foregroundStyle(.secondary)
                }
                mixBar(s)
            }
        }
    }

    /// Pars, bogeys, doubles, blow-ups as one bar.
    private func mixBar(_ s: StatsModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Every hole you've played").font(.subheadline.weight(.semibold))
            Chart(s.mix) { m in
                BarMark(x: .value("Holes", m.count), y: .value("", "mix"))
                    .foregroundStyle(by: .value("Result", m.name))
            }
            .chartForegroundStyleScale(domain: StatsModel.mixNames, range: [Color.blue, Color.fairway, Color.gray, Color.orange, Color.red])
            .chartYAxis(.hidden).chartXAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 26)
            HStack(spacing: 10) {
                ForEach(Array(zip(StatsModel.mixNames, [Color.blue, Color.fairway, Color.gray, Color.orange, Color.red])), id: \.0) { name, color in
                    let n = s.mix.first { $0.name == name }?.count ?? 0
                    if n > 0 {
                        HStack(spacing: 3) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text("\(name) \(n)").font(.caption)
                        }
                    }
                }
            }
        }
    }

    // MARK: Holes

    private func holesCard(_ s: StatsModel) -> some View {
        Card(title: "Where the strokes go", icon: "flag.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Average over par on each hole. Tap a bar.").font(.caption).foregroundStyle(.secondary)
                Chart(s.holes) { h in
                    BarMark(x: .value("Hole", "\(h.hole)"), y: .value("Over par", h.avgOver))
                        .foregroundStyle(h.avgOver >= 2 ? Color.red : h.avgOver >= 1 ? Color.orange : Color.fairway)
                        .opacity(pickedHole == nil || pickedHole == "\(h.hole)" ? 1 : 0.35)
                        .annotation(position: .top) {
                            Text(String(format: "%+.1f", h.avgOver)).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        }
                }
                .chartXSelection(value: $pickedHole)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)
                if let p = pickedHole, let h = s.holes.first(where: { "\($0.hole)" == p }) {
                    holeDetail(h)
                } else if let worst = s.holes.max(by: { $0.avgOver < $1.avgOver }) {
                    Text("Costliest: **Hole \(worst.hole)** (par \(worst.par), \(String(format: "%+.1f", worst.avgOver)) on average).")
                        .font(.callout)
                }
            }
        }
    }

    private func holeDetail(_ h: StatsModel.HoleRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hole \(h.hole) · Par \(h.par) · \(Course.hole(h.hole).yards) yds").font(.headline)
            Text("Played \(h.played)× · average \(String(format: "%.1f", h.avg)) · best \(h.best)").font(.callout)
            if !h.teeText.isEmpty { Text("Tee: \(h.teeText)").font(.callout).foregroundStyle(.secondary) }
            if let p = h.avgPutts { Text("Putts: \(String(format: "%.1f", p)) a hole").font(.callout).foregroundStyle(.secondary) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 10))
    }

    // MARK: Tee shots

    private func teeCard(_ s: StatsModel) -> some View {
        Card(title: "Off the tee (par 4s and 5s)", icon: "figure.golf") {
            if s.tee.total == 0 {
                Text("Tap the tee shot result on each hole to see this.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Tile(value: "\(s.tee.left)", label: "Left", color: .orange)
                        Tile(value: "\(s.tee.fairway)", label: "Fairway", color: .fairway)
                        Tile(value: "\(s.tee.right)", label: "Right", color: .orange)
                        if s.tee.short > 0 { Tile(value: "\(s.tee.short)", label: "Short", color: .gray) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What the miss cost you (avg vs par)").font(.subheadline.weight(.semibold))
                        costRow("Fairway", s.tee.costFairway, .fairway)
                        costRow("Just off", s.tee.costJustOff, .orange)
                        costRow("In trouble", s.tee.costTrouble, .red)
                        if s.tee.unsized > 0 {
                            Text("\(s.tee.unsized) miss\(s.tee.unsized == 1 ? "" : "es") not marked “just off” or “in trouble” yet. Mark them in the round to sharpen this.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func costRow(_ label: String, _ v: (avg: Double, n: Int)?, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
            Spacer()
            if let v {
                Text(String(format: "%+.1f", v.avg)).font(.headline.monospacedDigit())
                Text("(\(v.n))").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    // MARK: Par 3s

    private func par3Card(_ s: StatsModel) -> some View {
        Card(title: "Par 3s", icon: "target") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Tile(value: s.par3.avgOver.map { String(format: "%+.1f", $0) } ?? "—", label: "Avg vs par")
                    Tile(value: "\(s.par3.green)/\(s.par3.played)", label: "Greens hit", color: .fairway)
                }
                if !s.par3.misses.isEmpty {
                    Text("Missed: " + s.par3.misses.map { "\($0.0.lowercased()) \($0.1)" }.joined(separator: " · "))
                        .font(.callout)
                }
            }
        }
    }

    // MARK: Putting

    private func puttingCard(_ s: StatsModel) -> some View {
        Card(title: "Putting", icon: "circle.circle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Tile(value: s.puttsPerNine.map { String(format: "%.1f", $0) } ?? "—", label: "Putts / 9")
                    Tile(value: String(format: "%.1f", s.threePuttsPerNine), label: "3-putts / 9",
                         color: s.threePuttsPerNine >= 1 ? .red : .fairway)
                    Tile(value: "\(s.onePutts)", label: "1-putts", color: .fairway)
                }
                if !s.firstPutts.isEmpty {
                    Text("First putts by length").font(.subheadline.weight(.semibold))
                    let lengths = s.firstPutts.map(\.length).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                    VStack(spacing: 8) {
                        ForEach(lengths, id: \.self) { len in
                            let rows = s.firstPutts.filter { $0.length == len }
                            let total = rows.map(\.count).reduce(0, +)
                            let made = rows.first { $0.result == "Made" }?.count ?? 0
                            HStack(spacing: 8) {
                                Text(len).font(.callout.monospacedDigit()).frame(width: 74, alignment: .leading)
                                HStack(spacing: 3) {
                                    ForEach(rows) { r in
                                        ForEach(0..<r.count, id: \.self) { _ in
                                            RoundedRectangle(cornerRadius: 3).fill(Self.puttColor[r.result] ?? .gray)
                                                .frame(width: 16, height: 16)
                                        }
                                    }
                                }
                                Spacer()
                                Text("\(made)/\(total) made").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 10) {
                            ForEach(["Made", "Short", "Long", "Left", "Right"], id: \.self) { k in
                                HStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2).fill(Self.puttColor[k]!).frame(width: 9, height: 9)
                                    Text(k).font(.caption2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let t = s.puttTendency { Text(LocalizedStringKey(t)).font(.callout) }
                }
            }
        }
    }

    static let puttColor: [String: Color] = ["Made": .fairway, "Short": .blue, "Long": .red, "Left": .purple, "Right": .orange]

    // MARK: Short game

    private func shortGameCard(_ s: StatsModel) -> some View {
        Card(title: "Greens, chips & trouble", icon: "leaf.fill") {
            HStack(spacing: 10) {
                Tile(value: s.girPct.map { "\($0)%" } ?? "—", label: "Greens in reg")
                Tile(value: s.upDown.map { "\($0.made)/\($0.tries)" } ?? "—", label: "Up & downs")
                Tile(value: String(format: "%.1f", s.penaltiesPerNine), label: "Penalties / 9",
                     color: s.penaltiesPerNine > 0.5 ? .red : .fairway)
            }
        }
    }

    // MARK: Warm-up

    private func warmCard(_ s: StatsModel) -> some View {
        Card(title: "Warm-up vs none", icon: "flame.fill") {
            if let w = s.warmCompare {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Tile(value: w.warm.map { String(format: "%.1f", $0) } ?? "—", label: "Warmed up", color: .fairway)
                        Tile(value: w.cold.map { String(format: "%.1f", $0) } ?? "—", label: "No warm-up", color: .orange)
                    }
                    Text("Average 9-hole score. First 3 holes: \(w.firstThreeText)").font(.callout)
                }
            }
        }
    }
}

// MARK: - Small views

private struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(Color.fairway)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

private struct Tile: View {
    let value: String
    let label: String
    var color: Color = .primary
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(color)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.card, in: .rect(cornerRadius: 12))
    }
}

// MARK: - The math

struct StatsModel {
    struct Nine: Identifiable { var id: Int { index }; let index: Int; let date: Date; let side: String; let score: Int; let warm: Bool?; let firstThree: Int }
    struct HoleRow: Identifiable {
        var id: Int { hole }
        let hole: Int, par: Int, played: Int, avg: Double, best: Int, avgPutts: Double?, teeText: String
        var avgOver: Double { avg - Double(par) }
    }
    struct Mix: Identifiable { var id: String { name }; let name: String; let count: Int }
    struct PuttRow: Identifiable { let id = UUID(); let length: String; let result: String; let count: Int }
    struct Tee {
        var left = 0, right = 0, fairway = 0, short = 0, unsized = 0
        var total: Int { left + right + fairway + short }
        var costFairway: (avg: Double, n: Int)?
        var costJustOff: (avg: Double, n: Int)?
        var costTrouble: (avg: Double, n: Int)?
    }
    struct Par3 { var played = 0, green = 0; var avgOver: Double?; var misses: [(String, Int)] = [] }

    static let mixNames = ["Birdie+", "Par", "Bogey", "Double", "Blow-up 7+"]

    var roundCount = 0
    var nines: [Nine] = []
    var holes: [HoleRow] = []
    var mix: [Mix] = []
    var tee = Tee()
    var par3 = Par3()
    var firstPutts: [PuttRow] = []
    var puttTendency: String?
    var onePutts = 0
    var threePuttsPerNine = 0.0
    var puttsPerNine: Double?
    var girPct: Int?
    var upDown: (made: Int, tries: Int)?
    var penaltiesPerNine = 0.0
    var blowUpsPerNine = 0.0
    var warmCompare: (warm: Double?, cold: Double?, firstThreeText: String)?
    var takeaways: [String] = []

    var avgNine: Double? { nines.isEmpty ? nil : Double(nines.map(\.score).reduce(0, +)) / Double(nines.count) }
    var bestNine: Int? { nines.map(\.score).min() }

    init(rounds all: [Round], nine: StatsView.NineFilter, limit: Int?) {
        var rounds = all.filter { r in r.holes.contains { nine.has($0.hole) && $0.isEntered } }
            .sorted { $0.date > $1.date }
        if let limit { rounds = Array(rounds.prefix(limit)) }
        roundCount = rounds.count
        let played = rounds.flatMap { r in r.holes.filter { nine.has($0.hole) && $0.isEntered }.map { (r, $0) } }
        guard !played.isEmpty else { return }
        let entries = played.map(\.1)
        let ninesPlayed = Double(entries.count) / 9

        // 9-hole scores, oldest first.
        var list: [(Date, String, Int, Bool?, Int)] = []
        for r in rounds {
            for (side, range) in [("Front", 1...9), ("Back", 10...18)] where nine.has(range.lowerBound) {
                let hs = r.holes.filter { range.contains($0.hole) }
                guard hs.count == 9, hs.allSatisfy(\.isEntered) else { continue }
                let warm: Bool? = r.warmUp.map { $0 != .none }
                let first3 = hs.prefix(3).map { ($0.score ?? 0) - $0.par }.reduce(0, +)
                list.append((r.date, side, hs.compactMap(\.score).reduce(0, +), warm, first3))
            }
        }
        nines = list.sorted { $0.0 < $1.0 }.enumerated().map {
            Nine(index: $0.offset, date: $0.element.0, side: $0.element.1, score: $0.element.2, warm: $0.element.3, firstThree: $0.element.4)
        }

        // Holes.
        let byHole = Dictionary(grouping: entries, by: \.hole)
        holes = byHole.keys.sorted().map { n in
            let hs = byHole[n]!
            let scores = hs.compactMap(\.score)
            let putts = hs.compactMap(\.putts)
            let tees = Dictionary(grouping: hs.compactMap(\.teeResult), by: { $0 }).map { "\($0.key.rawValue.lowercased()) \($0.value.count)" }.sorted()
            return HoleRow(hole: n, par: Course.hole(n).par, played: hs.count,
                           avg: Double(scores.reduce(0, +)) / Double(scores.count), best: scores.min() ?? 0,
                           avgPutts: putts.isEmpty ? nil : Double(putts.reduce(0, +)) / Double(putts.count),
                           teeText: tees.joined(separator: ", "))
        }

        // Scoring mix.
        func bucket(_ h: HoleScore) -> String {
            let s = h.score ?? 0, d = s - h.par
            if s >= 7 { return "Blow-up 7+" }
            return d < 0 ? "Birdie+" : d == 0 ? "Par" : d == 1 ? "Bogey" : "Double"
        }
        let buckets = Dictionary(grouping: entries, by: bucket)
        mix = Self.mixNames.map { Mix(name: $0, count: buckets[$0]?.count ?? 0) }
        let blowUps = buckets["Blow-up 7+"]?.count ?? 0
        blowUpsPerNine = Double(blowUps) / ninesPlayed

        // Tee shots on par 4s and 5s, and what each outcome cost.
        func avgOver(_ hs: [HoleScore]) -> (Double, Int)? {
            hs.isEmpty ? nil : (Double(hs.map { ($0.score ?? 0) - $0.par }.reduce(0, +)) / Double(hs.count), hs.count)
        }
        let long = entries.filter { $0.par >= 4 && $0.teeResult != nil }
        tee.left = long.filter { $0.teeResult == .left }.count
        tee.right = long.filter { $0.teeResult == .right }.count
        tee.fairway = long.filter { $0.teeResult == .fairway }.count
        tee.short = long.filter { $0.teeResult == .short }.count
        tee.unsized = long.filter { $0.teeMissed && $0.missSize == nil }.count
        tee.costFairway = avgOver(long.filter { $0.teeResult == .fairway })
        tee.costJustOff = avgOver(long.filter { $0.teeMissed && $0.missSize == .justOff })
        tee.costTrouble = avgOver(long.filter { $0.teeMissed && $0.missSize == .trouble })

        // Par 3s.
        let p3 = entries.filter { $0.par == 3 }
        par3.played = p3.count
        par3.green = p3.filter { $0.teeResult == .green }.count
        par3.avgOver = avgOver(p3)?.0
        let p3miss = Dictionary(grouping: p3.compactMap(\.teeResult).filter { $0 != .green }, by: { $0 })
        par3.misses = p3miss.map { ($0.key.rawValue, $0.value.count) }.sorted { $0.1 > $1.1 }

        // Putting.
        let putts = entries.compactMap(\.putts)
        if !putts.isEmpty { puttsPerNine = Double(putts.reduce(0, +)) / (Double(putts.count) / 9) }
        onePutts = putts.filter { $0 == 1 }.count
        threePuttsPerNine = Double(putts.filter { $0 >= 3 }.count) / ninesPlayed
        var rows: [PuttRow] = []
        for len in PuttLength.allCases {
            let hs = entries.filter { $0.firstPutt == len }
            let byResult = Dictionary(grouping: hs, by: { $0.firstPuttResult ?? ($0.putts == 1 ? .made : nil) })
            for res in PuttResult.allCases {
                if let n = byResult[res]?.count, n > 0 { rows.append(PuttRow(length: len.rawValue + " ft", result: res.rawValue, count: n)) }
            }
        }
        firstPutts = rows
        let misses = entries.filter { $0.firstPuttResult != nil && $0.firstPuttResult != .made }
        let longN = misses.filter { $0.firstPuttResult == .long }.count
        let shortN = misses.filter { $0.firstPuttResult == .short }.count
        // A clear pattern at one length beats the overall mix.
        for len in PuttLength.allCases {
            let m = misses.filter { $0.firstPutt == len }
            guard m.count >= 3 else { continue }
            for res in [PuttResult.long, .short, .left, .right] {
                let n = m.filter { $0.firstPuttResult == res }.count
                if Double(n) / Double(m.count) >= 0.75 {
                    puttTendency = "From **\(len.rawValue) ft**, \(n) of \(m.count) misses finish **\(res.rawValue.lowercased())**."
                        + (res == .long ? " Die those at the hole." : res == .short ? " Get them to the hole." : "")
                }
            }
            if puttTendency != nil { break }
        }
        if puttTendency == nil, misses.count >= 3 {
            if longN > shortN * 2 { puttTendency = "Misses finish **long** (\(longN) of \(misses.count)). Speed is the fix: die it at the hole." }
            else if shortN > longN * 2 { puttTendency = "Misses finish **short** (\(shortN) of \(misses.count)). Get it to the hole." }
            else { puttTendency = "Misses are mixed: \(longN) long, \(shortN) short. Speed is about right." }
        }

        // Greens, up & downs, penalties.
        let gir = entries.compactMap(\.greenHit)
        if !gir.isEmpty { girPct = Int((Double(gir.filter { $0 }.count) / Double(gir.count) * 100).rounded()) }
        let ud = entries.map(\.upDown).filter { $0 != .notAttempted }
        if !ud.isEmpty { upDown = (ud.filter { $0 == .made }.count, ud.count) }
        penaltiesPerNine = Double(entries.map(\.penalties).reduce(0, +)) / ninesPlayed

        // Warm-up.
        let warm = nines.filter { $0.warm == true }, cold = nines.filter { $0.warm == false }
        if !warm.isEmpty && !cold.isEmpty {
            func avg(_ n: [Nine]) -> Double { Double(n.map(\.score).reduce(0, +)) / Double(n.count) }
            func f3(_ n: [Nine]) -> String { String(format: "%+.1f", Double(n.map(\.firstThree).reduce(0, +)) / Double(n.count)) }
            warmCompare = (avg(warm), avg(cold), "\(f3(warm)) warmed up vs \(f3(cold)) cold")
        }

        // Plain-English takeaways, biggest first.
        var t: [String] = []
        if blowUps > 0 {
            let where_ = played.filter { ($0.1.score ?? 0) >= 7 }.map { "hole \($0.1.hole)" }
            t.append("**\(blowUps) blow-up\(blowUps == 1 ? "" : "s")** (7+): \(Array(Set(where_)).sorted().joined(separator: ", ")). That's the first stroke saver.")
        } else {
            t.append("**Zero blow-ups.** That's the system working.")
        }
        if let f = tee.costFairway, let j = tee.costJustOff, j.0 - f.0 < 0.75 {
            t.append("Tee misses that are just off cost you little (\(String(format: "%+.1f", j.0)) vs \(String(format: "%+.1f", f.0)) from the fairway). Only the big misses hurt.")
        }
        if let tr = tee.costTrouble {
            t.append("Tee shots **in trouble** average \(String(format: "%+.1f", tr.0)) on the hole.")
        }
        if tee.left + tee.right >= 3 {
            if tee.right >= tee.left * 2 { t.append("Tee misses go **right** (\(tee.right) of \(tee.left + tee.right)).") }
            else if tee.left >= tee.right * 2 { t.append("Tee misses go **left** (\(tee.left) of \(tee.left + tee.right)).") }
        }
        if let p = par3.avgOver, par3.played >= 2, let others = avgOver(entries.filter { $0.par > 3 })?.0, p > others + 0.4 {
            t.append("Par 3s cost the most: \(String(format: "%+.1f", p)) each vs \(String(format: "%+.1f", others)) on the rest.")
        }
        if let pt = puttTendency { t.append(pt) }
        takeaways = t
    }
}
