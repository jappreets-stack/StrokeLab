import SwiftUI

@main
struct StrokeLabApp: App {
    @State private var store = Store()
    @State private var location = LocationModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .tint(.fairway)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Play", systemImage: "figure.golf") { PlayView() }
            Tab("Rounds", systemImage: "list.number") { RoundsView() }
            Tab("Course", systemImage: "map") { CourseView() }
        }
    }
}
