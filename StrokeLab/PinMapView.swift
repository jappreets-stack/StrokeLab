import SwiftUI
import MapKit

/// Tap the satellite photo to drop front / center / back pins for a green.
struct PinMapView: View {
    @State var hole: Int
    @Environment(Store.self) private var store
    @State private var which: Which = .front
    @State private var camera: MapCameraPosition = .automatic
    @State private var located = false
    @State private var pending: Coordinate?
    @State private var farYards = 0

    enum Which: String, CaseIterable { case front = "Front", center = "Center", back = "Back" }

    var body: some View {
        let pins = store.pins(hole)
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $camera) {
                    marker(pins.front, "F", .yellow)
                    marker(pins.center, "C", .white)
                    marker(pins.back, "B", .red)
                }
                .mapStyle(.imagery)
                .onTapGesture { point in
                    guard let c = proxy.convert(point, from: .local) else { return }
                    set(Coordinate(lat: c.latitude, lon: c.longitude))
                }
            }
            VStack(spacing: 10) {
                Text("Zoom in on hole \(hole)'s green, then tap the \(which.rawValue.lowercased()) edge.")
                    .font(.subheadline).multilineTextAlignment(.center)
                if let check = sanityCheck(pins) {
                    Text(check.text).font(.caption.weight(.semibold)).foregroundStyle(check.ok ? Color.fairway : .orange)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 8) {
                    ForEach(Which.allCases, id: \.self) { w in
                        ChoiceButton(title: w.rawValue + (value(w, pins) != nil ? " ✓" : ""),
                                     selected: which == w, height: 48, font: .headline) { which = w }
                    }
                }
                HStack(spacing: 8) {
                    ChoiceButton(title: "◀︎ Hole \(hole - 1)", selected: false, height: 48, font: .headline) { go(hole - 1) }
                        .disabled(hole == 1).opacity(hole == 1 ? 0.4 : 1)
                    ChoiceButton(title: "Hole \(hole + 1) ▶︎", selected: pins.isComplete, height: 48, font: .headline) { go(hole + 1) }
                        .disabled(hole == 18).opacity(hole == 18 ? 0.4 : 1)
                }
            }
            .padding()
            .background(.bar)
        }
        .confirmationDialog("That's \(farYards) yds from this green's other pins",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Start this green over here") {
                if let c = pending { store.data.pins[hole - 1] = GreenPins(hole: hole); which = .front; apply(c) }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text("A green is only 20–40 yds deep. Zoom in so the green fills the screen, then tap its edges.") }
        .navigationTitle("Hole \(hole) green")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: hole) { await centerCamera() }
    }

    @MapContentBuilder
    private func marker(_ c: Coordinate?, _ label: String, _ color: Color) -> some MapContent {
        if let c {
            Annotation(label, coordinate: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)) {
                Circle().fill(color).stroke(.black, lineWidth: 2).frame(width: 16, height: 16)
            }
        }
    }

    /// Is this the right green? For a par 3 the previous green should be about the hole's length away.
    private func sanityCheck(_ p: GreenPins) -> (text: String, ok: Bool)? {
        guard let c = p.center else { return nil }
        let h = Course.hole(hole)
        var parts: [String] = []
        var ok = true
        if p.isComplete {
            let depth = Int(p.spreadYards)
            parts.append("Green is \(depth) yds deep")
            if depth > 50 { ok = false }
        }
        if hole > 1, let prev = store.pins(hole - 1).center {
            let gap = Int(prev.yards(to: c))
            parts.append("\(gap) yds from hole \(hole - 1)'s green (hole \(hole) is \(h.yards) yds)")
            if gap > h.yards + 200 { ok = false }
        }
        return parts.isEmpty ? nil : ((ok ? "✓ " : "Check this: ") + parts.joined(separator: " · "), ok)
    }

    private func value(_ w: Which, _ p: GreenPins) -> Coordinate? {
        switch w { case .front: p.front; case .center: p.center; case .back: p.back }
    }

    private func set(_ c: Coordinate) {
        let others = [store.pins(hole).front, store.pins(hole).center, store.pins(hole).back]
            .enumerated().filter { $0.offset != Which.allCases.firstIndex(of: which)! }.compactMap(\.element)
        if let far = others.map({ $0.yards(to: c) }).max(), far > 50 {
            pending = c
            farYards = Int(far)
            return
        }
        apply(c)
    }

    private func apply(_ c: Coordinate) {
        switch which {
        case .front: store.data.pins[hole - 1].front = c; which = .center
        case .center: store.data.pins[hole - 1].center = c; which = .back
        case .back: store.data.pins[hole - 1].back = c
        }
    }

    private func go(_ n: Int) {
        hole = n
        which = .front
    }

    /// Start on this green if pinned, else next to the last pinned green, else find the course.
    private func centerCamera() async {
        let nearby = store.pins(hole).center
            ?? store.data.pins.prefix(hole - 1).last(where: { $0.center != nil })?.center
            ?? store.data.pins.first(where: { $0.center != nil })?.center
        if let c = nearby {
            camera = .camera(MapCamera(centerCoordinate: .init(latitude: c.lat, longitude: c.lon), distance: 450))
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Redwood Empire Golf Country Club, Fortuna CA"
        let fortuna = CLLocationCoordinate2D(latitude: 40.5982, longitude: -124.1573)
        request.region = MKCoordinateRegion(center: fortuna, latitudinalMeters: 20000, longitudinalMeters: 20000)
        let found = try? await MKLocalSearch(request: request).start().mapItems.first?.location.coordinate
        camera = .camera(MapCamera(centerCoordinate: found ?? fortuna, distance: found == nil ? 6000 : 1500))
    }
}
