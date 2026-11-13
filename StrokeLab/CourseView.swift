import SwiftUI

struct CourseView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { ClubYardsView() } label: {
                        Label("My club distances", systemImage: "ruler")
                    }
                } footer: { Text("Used with the wind to pick a club for the yardage.") }
                section("Front nine", 1...9)
                section("Back nine", 10...18)
            }
            .navigationTitle("Course")
            .navigationDestination(for: Int.self) { HolePlanEditor(hole: $0) }
            .toolbar {
                NavigationLink { GreenLevelView() } label: { Label("Green level", systemImage: "level") }
            }
        }
    }

    private func section(_ title: String, _ range: ClosedRange<Int>) -> some View {
        Section {
            ForEach(range, id: \.self) { n in
                let h = Course.hole(n), plan = store.plan(n), pins = store.pins(n)
                NavigationLink(value: n) {
                    HStack(spacing: 12) {
                        Text("\(n)").font(.title2.bold()).frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Par \(h.par) · \(h.yards) yds · SI \(h.strokeIndex)").font(.headline)
                            Text("\(plan.teeClub.rawValue) · target \(plan.target) · \(plan.troubleText)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: pins.isComplete ? "mappin.circle.fill" : "mappin.slash")
                            .foregroundStyle(pins.isComplete ? Color.fairway : .secondary)
                    }
                }
            }
        } header: {
            Text("\(title) · par \(Course.par(of: Array(range)))")
        }
    }
}

struct HolePlanEditor: View {
    let hole: Int
    @Environment(Store.self) private var store
    @State private var showMap = false

    var body: some View {
        @Bindable var store = store
        let plan = $store.data.plans[hole - 1]
        let h = Course.hole(hole)
        Form {
            Section { PlanCard(plan: plan.wrappedValue) }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Trouble") {
                Picker("Side", selection: plan.troubleSide) {
                    ForEach(TroubleSide.allCases, id: \.self) { Text($0.rawValue) }
                }
                ForEach(Hazard.allCases, id: \.self) { hz in
                    Toggle(hz.rawValue, isOn: Binding(
                        get: { plan.wrappedValue.hazards.contains(hz) },
                        set: { on in
                            plan.wrappedValue.hazards.removeAll { $0 == hz }
                            if on { plan.wrappedValue.hazards.append(hz) }
                        }))
                }
            }
            Section("Plan") {
                Picker("Tee club", selection: plan.teeClub) {
                    ForEach(Club.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("Target score: \(plan.wrappedValue.target)", value: plan.target, in: h.par - 1...h.par + 3)
                TextField("Note to self", text: plan.note, axis: .vertical).lineLimit(2...5)
            }
            Section("Map") {
                Button("View hole map", systemImage: "map") { showMap = true }
            }
            Section("Green") {
                TextField("How the green breaks (e.g. everything toward the clubhouse)",
                          text: Binding(get: { plan.wrappedValue.greenRead ?? "" }, set: { plan.wrappedValue.greenRead = $0 }),
                          axis: .vertical).lineLimit(1...4)
                NavigationLink {
                    PinMapView(hole: hole)
                } label: {
                    LabeledContent("Front · center · back pins",
                                   value: store.pins(hole).isComplete ? "Set" : "Not set")
                }
            }
        }
        .navigationTitle("Hole \(hole) · Par \(h.par) · \(h.yards) yds")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showMap) { HoleMapView(hole: hole) }
    }
}

/// Carry yards per club. The watch and phone use these with the wind to suggest a club.
struct ClubYardsView: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(Club.allCases) { c in
                    let y = store.clubYards[c.rawValue] ?? 0
                    Stepper(value: Binding(get: { y }, set: { v in
                        var t = store.clubYards; t[c.rawValue] = v; store.data.clubYards = t
                    }), in: 30...320, step: 1) {
                        HStack {
                            Text(c.rawValue).font(.headline).frame(width: 60, alignment: .leading)
                            Text("\(y) yds").monospacedDigit()
                        }
                    }
                }
            } footer: {
                Text("Your normal carry, not your best one. Into the wind adds about 1% per mph; a helping wind takes off about half that.")
            }
            Section { Button("Reset to defaults", role: .destructive) { store.data.clubYards = nil } }
        }
        .navigationTitle("Club distances")
    }
}
