import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

struct SwingListView: View {
    @Environment(SwingStore.self) private var swings
    @AppStorage("leftHanded") private var leftHanded = false
    @AppStorage("swingClub") private var club = "7i"
    @State private var recording = false
    @State private var pick: PhotosPickerItem?
    @State private var progress: Double?
    @State private var error: String?
    @State private var open: SwingRecord?
    @State private var toDelete: SwingRecord?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ChoiceButton(title: "Record a swing", selected: true, height: 60) { recording = true }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    PhotosPicker(selection: $pick, matching: .videos) {
                        Label("Use a video from Photos", systemImage: "photo.on.rectangle")
                    }
                    Picker("Club", selection: $club) {
                        ForEach(Club.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Toggle("Left-handed", isOn: $leftHanded)
                }
                Section("How to film (no tripod)") { FilmingGuide() }
                Section("Your swings") {
                    if swings.swings.isEmpty {
                        Text("No swings yet.").foregroundStyle(.secondary)
                    }
                    ForEach(swings.swings) { s in
                        Button { open = s } label: { SwingRow(record: s) }
                            .buttonStyle(.plain)
                            .swipeActions { Button("Delete", role: .destructive) { toDelete = s } }
                    }
                }
            }
            .navigationTitle("Swing")
            .fullScreenCover(isPresented: $recording) {
                SwingCaptureView { url in Task { await analyze(url) } }
            }
            .navigationDestination(item: $open) { SwingDetailView(record: $0) }
            .onChange(of: pick) { _, item in
                guard let item else { return }
                Task {
                    if let movie = try? await item.loadTransferable(type: Movie.self) { await analyze(movie.url) }
                    else { error = "Couldn't load that video." }
                    pick = nil
                }
            }
            .overlay { if let progress { AnalyzingCard(progress: progress) } }
            .alert("Couldn't analyze the swing", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
            .confirmationDialog("Delete this swing?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible, presenting: toDelete) { s in
                Button("Delete swing and video", role: .destructive) { swings.delete(s) }
            } message: { _ in Text("The video and its analysis are removed from this phone.") }
        }
    }

    private func analyze(_ url: URL) async {
        progress = 0
        defer { progress = nil }
        do {
            let record = try await swings.add(videoAt: url, club: club, leftHanded: leftHanded) { p in
                Task { @MainActor in progress = p }
            }
            open = record
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension SwingRecord: Hashable {
    static func == (a: SwingRecord, b: SwingRecord) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// A video file from Photos, copied into a temporary file we can read.
struct Movie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let copy = URL.temporaryDirectory.appending(path: "import-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Movie(url: copy)
        }
    }
}

struct SwingRow: View {
    let record: SwingRecord
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.view == .faceOn ? "person.fill" : "figure.golf")
                .font(.title2).frame(width: 36).foregroundStyle(Color.fairway)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.headline.isEmpty ? "Swing" : record.headline).font(.headline).lineLimit(2)
                Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(record.club) · \(record.view.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let t = record.tempo { Text(String(format: "%.1f:1", t)).font(.subheadline.bold()).monospacedDigit() }
        }
        .contentShape(.rect)
    }
}

struct AnalyzingCard: View {
    let progress: Double
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView(value: progress).tint(.fairway).frame(width: 200)
                Text("Tracking your swing…").font(.headline)
                Text("Finding your body in every frame").font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }
}

struct FilmingGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("1", "Prop the phone at about hip height: lean it on a bucket, golf bag, chair or shelf. Upright (portrait).")
            row("2", "Down the line (for plane & early extension): stand behind your hands, 10–12 ft back, camera pointing at your target.")
            row("3", "Face on (for sway, head, turn): straight across from your chest, 10–12 ft away.")
            row("4", "Whole body and the club at the top must fit inside the dashed box. Turn on all the garage lights.")
            row("5", "Tap record, walk to the ball during the 5-second count, swing. It stops by itself after 12 seconds.")
        }
        .font(.subheadline)
    }
    private func row(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.subheadline.bold()).frame(width: 22, height: 22).background(Color.fairway.opacity(0.2), in: .circle)
            Text(t)
        }
    }
}
