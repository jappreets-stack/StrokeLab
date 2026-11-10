import SwiftUI
import MapKit

/// Full-screen hole map (from the Course tab or the map button).
struct HoleMapView: View {
    let hole: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            HoleMapContent(hole: hole)
                .navigationTitle("Hole \(hole) · Par \(Course.hole(hole).par) · \(Course.hole(hole).yards) yds")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Satellite view of one hole. Tap anywhere for yards from you (or a point you pick) to there, and from there to the green.
struct HoleMapContent: View {
    let hole: Int
    var compactFooter = false
    @Environment(Store.self) private var store
    @Environment(LocationModel.self) private var location
    @State private var camera: MapCameraPosition = .automatic
    @State private var start: CLLocationCoordinate2D?   // only used when you're not on this hole
    @State private var target: CLLocationCoordinate2D?
    @State private var framed = false

    private var h: Hole { Course.hole(hole) }
    private var green: CLLocationCoordinate2D? { store.pins(hole).center.map(\.clCoordinate) }

    /// You count as "on the hole" when you're within the hole's length (+100 yds) of the green.
    private var me: CLLocationCoordinate2D? {
        guard let loc = location.location?.coordinate else { return nil }
        guard let green else { return loc }
        return yards(loc, green) <= Double(h.yards + 100) ? loc : nil
    }
    private var from: CLLocationCoordinate2D? { me ?? start }

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    let pins = store.pins(hole)
                    pin(pins.front, .yellow); pin(pins.center, .white); pin(pins.back, .red)
                    if me == nil, let start {
                        Annotation("Start", coordinate: start) { dot(.blue) }
                    }
                    if let target {
                        Annotation("", coordinate: target) {
                            Image(systemName: "scope").font(.title.bold()).foregroundStyle(.yellow)
                                .shadow(color: .black, radius: 2)
                        }
                        if let from {
                            MapPolyline(coordinates: [from, target]).stroke(.white, lineWidth: 3)
                            label(from, target)
                        }
                        if let green {
                            MapPolyline(coordinates: [target, green]).stroke(.yellow, style: .init(lineWidth: 3, dash: [6, 4]))
                            label(target, green)
                        }
                    }
                }
                .mapStyle(.imagery)
                .mapControls { MapUserLocationButton(); MapCompass() }
                .onTapGesture { point in
                    guard let c = proxy.convert(point, from: .local) else { return }
                    if me == nil && start == nil { start = c } else { target = c }
                }
            }
            .overlay(alignment: .topLeading) {
                if target != nil || start != nil {
                    Button("Clear") { target = nil; start = nil }
                        .font(.headline).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: .capsule).foregroundStyle(.white).padding(10)
                }
            }
            if !compactFooter || target != nil || green == nil { footer }
        }
        .onAppear { location.start(); frame() }
        .onDisappear { location.stop() }
        .onChange(of: me != nil) { _, _ in frame() }
    }

    // MARK: Pieces

    private var footer: some View {
        VStack(spacing: 6) {
            if green == nil {
                Text("Set this green's pins in the Course tab to see yards to the green.")
            } else if let from, let target, let green {
                HStack(spacing: 24) {
                    big("\(Int(yards(from, target)))", me != nil ? "to target" : "start → target")
                    big("\(Int(yards(target, green)))", "target → green")
                }
            } else if me == nil && start == nil {
                Text("Not on this hole. Tap where you'd hit from (like the tee), then tap a target.")
            } else {
                Text("Tap a spot to see how far it is, and what's left to the green.")
            }
        }
        .font(.subheadline.weight(.semibold))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding()
        .background(.bar)
    }

    private func big(_ n: String, _ caption: String) -> some View {
        VStack(spacing: 0) {
            Text(n).font(.system(size: 40, weight: .heavy, design: .rounded)).monospacedDigit()
            Text(caption).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    @MapContentBuilder
    private func pin(_ c: Coordinate?, _ color: Color) -> some MapContent {
        if let c { Annotation("", coordinate: c.clCoordinate) { dot(color, size: 12) } }
    }

    @MapContentBuilder
    private func label(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> some MapContent {
        let mid = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
        Annotation("", coordinate: mid) {
            Text("\(Int(yards(a, b)))").font(.headline.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                .background(.black.opacity(0.75), in: .capsule).foregroundStyle(.white)
        }
    }

    private func dot(_ color: Color, size: CGFloat = 16) -> some View {
        Circle().fill(color).stroke(.black, lineWidth: 2).frame(width: size, height: size)
    }

    /// On the hole: look from you toward the green. Otherwise: the whole hole around the green, north up.
    private func frame() {
        guard let green else {
            if let me { camera = .camera(MapCamera(centerCoordinate: me, distance: 800)) }
            return
        }
        if let me {
            let d = yards(me, green) / 1.09361
            let mid = CLLocationCoordinate2D(latitude: (me.latitude + green.latitude) / 2,
                                             longitude: (me.longitude + green.longitude) / 2)
            camera = .camera(MapCamera(centerCoordinate: mid, distance: max(400, d * 4.2),
                                       heading: bearing(me, green)))
        } else {
            camera = .camera(MapCamera(centerCoordinate: green, distance: max(500, Double(h.yards) * 4)))
        }
    }
}

// MARK: - Geometry

func yards(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    CLLocation(latitude: a.latitude, longitude: a.longitude)
        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) * 1.09361
}

func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
    let Δλ = (b.longitude - a.longitude) * .pi / 180
    let y = sin(Δλ) * cos(φ2)
    let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}

extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}
