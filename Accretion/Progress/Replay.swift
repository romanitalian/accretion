import Foundation

/// A finished run, stored as the player's inputs only. The simulation is deterministic, so replaying
/// the same thrusts on the same fixed steps reproduces the run exactly.
struct Replay: Codable, Equatable {
    struct Input: Codable, Equatable {
        /// `World.stepCount` at the moment of the thrust (applied before that step).
        var step: Int
        /// Thrust target in world coordinates.
        var x: Double
        var y: Double
        var away: Bool
    }

    var stars: Int
    var time: Double
    var inputs: [Input]

    /// More stars wins; with equal stars the faster run wins.
    func isBetter(than other: Replay?) -> Bool {
        guard let other else { return true }
        if stars != other.stars { return stars > other.stars }
        return time < other.time
    }
}

/// Best replay per level, as small JSON files in Application Support. Sandbox runs aren't kept.
enum ReplayStore {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("replays", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(for mode: GameMode) -> URL? {
        switch mode {
        case .campaign(let level): directory?.appendingPathComponent("level-\(level)\(WorldSize.current.keySuffix).json")
        case .daily(let day): directory?.appendingPathComponent("daily-\(day)\(WorldSize.current.keySuffix).json")
        case .sandbox: nil
        }
    }

    static func best(for mode: GameMode) -> Replay? {
        guard let url = url(for: mode), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Replay.self, from: data)
    }

    /// Saves `replay` if it beats the stored one.
    static func saveIfBetter(_ replay: Replay, for mode: GameMode) {
        guard let url = url(for: mode), replay.isBetter(than: best(for: mode)),
              let data = try? JSONEncoder().encode(replay) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
