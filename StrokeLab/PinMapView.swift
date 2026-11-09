import SwiftUI
import MapKit

/// Tap the satellite photo to drop front / center / back pins for a green.
struct PinMapView: View {
    @State var hole: Int
    @Environment(Store.self) private var store
    @State private var which: Which = .front
    @State private var camera: MapCameraPosition = .automatic
    @State private var located = false

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

    private func value(_ w: Which, _ p: GreenPins) -> Coordinate? {
        switch w { case .front: p.front; case .center: p.center; case .back: p.back }
    }

    private func set(_ c: Coordinate) {
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
