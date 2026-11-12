import SwiftUI

@main
struct StrokeLabApp: App {
    @State private var store = Store()
    @State private var location = LocationModel()
    @State private var swings = SwingStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .environment(swings)
                .tint(.fairway)
                .task { PhoneSync.shared.activate(store) }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Play", systemImage: "figure.golf") { PlayView() }
            Tab("Stats", systemImage: "chart.bar.xaxis") { StatsView() }
            Tab("Rounds", systemImage: "list.number") { RoundsView() }
            Tab("Swing", systemImage: "video.fill") { SwingListView() }
            Tab("Course", systemImage: "map") { CourseView() }
        }
    }
}
