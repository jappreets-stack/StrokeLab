import Foundation
import Observation

/// Saved swings: a small list file, plus each swing's video and pose data in Documents/Swings.
@Observable
final class SwingStore {
    var swings: [SwingRecord] = [] { didSet { saveList() } }

    static let folder: URL = {
        let url = URL.documentsDirectory.appending(path: "Swings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private static let listURL = folder.appending(path: "swings.json")

    init() {
        if let raw = try? Data(contentsOf: Self.listURL),
           let list = try? JSONDecoder.app.decode([SwingRecord].self, from: raw) { swings = list }
    }

    private func saveList() {
        if let raw = try? JSONEncoder.app.encode(swings) { try? raw.write(to: Self.listURL, options: .atomic) }
    }

    func videoURL(_ r: SwingRecord) -> URL { Self.folder.appending(path: r.videoFile) }

    func analysis(_ r: SwingRecord) -> SwingAnalysis? {
        guard let raw = try? Data(contentsOf: Self.folder.appending(path: r.poseFile)) else { return nil }
        return try? JSONDecoder.app.decode(SwingAnalysis.self, from: raw)
    }

    func save(_ a: SwingAnalysis, for r: SwingRecord) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let raw = try? enc.encode(a) { try? raw.write(to: Self.folder.appending(path: r.poseFile), options: .atomic) }
        if let i = swings.firstIndex(where: { $0.id == r.id }) {
            swings[i].tempo = a.metrics.tempo
            swings[i].view = a.view
            swings[i].headline = SwingCoach.headline(for: a)
        }
    }

    /// Moves a recorded/imported video in and analyzes it.
    func add(videoAt source: URL, club: String, leftHanded: Bool, progress: @Sendable @escaping (Double) -> Void) async throws -> SwingRecord {
        var record = SwingRecord(club: club, view: .downTheLine, fps: 30)
        let dest = videoURL(record)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: source, to: dest)
        do {
            let (analysis, fps) = try await Task.detached(priority: .userInitiated) {
                try await PoseAnalyzer.analyze(url: dest, leftHanded: leftHanded, progress: progress)
            }.value
            record.fps = fps
            swings.insert(record, at: 0)
            save(analysis, for: record)
            return swings[0]
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
    }

    func delete(_ r: SwingRecord) {
        try? FileManager.default.removeItem(at: videoURL(r))
        try? FileManager.default.removeItem(at: Self.folder.appending(path: r.poseFile))
        swings.removeAll { $0.id == r.id }
    }
}
