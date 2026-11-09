import SwiftUI

@main
struct StrokeLabWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Image(systemName: "flag.fill").font(.title).foregroundStyle(.green)
                Text("StrokeLab").font(.headline)
                Text("Yardages coming in Round 2").font(.footnote).multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
