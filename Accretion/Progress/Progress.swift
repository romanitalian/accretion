import Foundation

/// What is being played right now.
enum GameMode: Equatable {
    case campaign(level: Int)
    /// One shared level per calendar day; `day` is yyyymmdd.
    case daily(day: Int)
    /// Player-assembled level: no stars, no unlocks, just play.
    case sandbox(SandboxConfig)
}

/// What the player switched on in the sandbox. Persisted as JSON in UserDefaults.
struct SandboxConfig: Codable, Equatable {
    var seed: UInt64 = 1
    var difficulty = 0.4
    var attractor = false
    var supernova = false
    var splitters = true
    var pulsar = false
    var nebula = false
    var antimatter = false
    var comets = true
    var wormholes = false
    var binaries = false
    var astronaut = true
    var planets = false

    private static let key = "accretion.sandbox"

    static var saved: SandboxConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let config = try? JSONDecoder().decode(SandboxConfig.self, from: data) else { return SandboxConfig() }
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: key) }
        }
    }

    /// Same switches, a different layout.
    func reshuffled() -> SandboxConfig {
        var copy = self
        copy.seed = UInt64.random(in: 1...UInt64(UInt32.max))
        return copy
    }
}

/// Saved progress in UserDefaults. Small, local, offline: no account needed.
enum GameProgress {
    private static var defaults: UserDefaults { .standard }
    private static let levelKey = "accretion.level"
    private static let maxLevelKey = "accretion.maxLevel"

    /// Level the campaign resumes at (0-based).
    static var currentLevel: Int {
        get { defaults.integer(forKey: levelKey) }
        set { defaults.set(newValue, forKey: levelKey) }
    }

    /// Highest level the player may pick in the menu (0-based, inclusive).
    static var maxUnlockedLevel: Int {
        max(defaults.integer(forKey: maxLevelKey), currentLevel)
    }

    static func unlock(upTo level: Int) {
        if level > defaults.integer(forKey: maxLevelKey) { defaults.set(level, forKey: maxLevelKey) }
    }

    /// Stars are kept per playfield size: a level on a huge field plays differently from a compact one.
    static func stars(level: Int, size: WorldSize = .current) -> Int {
        defaults.integer(forKey: "accretion.stars.\(level)\(size.keySuffix)")
    }
    static func dailyStars(day: Int, size: WorldSize = .current) -> Int {
        defaults.integer(forKey: "accretion.daily.\(day)\(size.keySuffix)")
    }
    /// Best result on any size (for things that shouldn't depend on the current setting, like skins).
    static func bestStars(level: Int) -> Int {
        WorldSize.allCases.map { stars(level: level, size: $0) }.max() ?? 0
    }

    /// Keeps the best result.
    static func record(stars: Int, for mode: GameMode) {
        let key: String
        switch mode {
        case .campaign(let level): key = "accretion.stars.\(level)\(WorldSize.current.keySuffix)"
        case .daily(let day): key = "accretion.daily.\(day)\(WorldSize.current.keySuffix)"
        case .sandbox: return
        }
        defaults.set(max(defaults.integer(forKey: key), stars), forKey: key)
    }

    static var today: Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return (c.year ?? 2026) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    /// Every third level from the 4th on has a gravity well.
    static func hasAttractor(level: Int) -> Bool { level >= 3 && level % 3 == 0 }

    /// Levels 6, 9, 12…: the biggest rival will explode.
    static func hasSupernova(level: Int) -> Bool { level >= 5 && level % 3 == 2 }

    /// First two levels teach the basics; after that goals rotate.
    static func goal(level: Int) -> LevelGenerator.GoalKind {
        guard level >= 2 else { return .becomeBiggest }
        // Special goals for levels whose objects make them interesting.
        if hasTrap(level: level) { return .trap }
        if hasWormholes(level: level) { return .travel(times: 3) }
        if level >= 9, level % 5 == 4 { return .eatAllHunters }
        switch level % 4 {
        case 1: return .reachMass(multiple: 3)
        case 2: return .survive(seconds: 60)
        case 3: return .eatTarget
        default: return .becomeBiggest
        }
    }

    static func dailyGoal(day: Int) -> LevelGenerator.GoalKind { goal(level: 4 + day % 4) }

    static func hasSplitters(level: Int) -> Bool { level >= 6 }
    /// Bomb-and-giant levels 15, 20, 25… (never with a black hole: the giant would just fall in).
    static func hasTrap(level: Int) -> Bool { level >= 14 && level % 5 == 4 && !hasAttractor(level: level) }
    static func hasPulsar(level: Int) -> Bool { level >= 7 && level % 2 == 1 }
    static func hasNebula(level: Int) -> Bool { level >= 9 && level % 3 == 1 }
    static func hasComets(level: Int) -> Bool { level >= 8 && level % 4 == 0 }
    static func hasAntimatter(level: Int) -> Bool { level >= 11 && level % 4 == 3 }
    static func hasWormholes(level: Int) -> Bool { level >= 12 && level % 3 == 0 }
    static func hasBinaries(level: Int) -> Bool { level >= 13 && level % 4 == 1 }
    /// A lost cosmonaut drifts through levels 2, 5, 8…
    static func hasAstronaut(level: Int) -> Bool { level >= 1 && level % 3 == 1 }
    /// Planets circle every black hole from level 7 on, and hang in some open levels.
    static func hasPlanets(level: Int) -> Bool { (hasAttractor(level: level) && level >= 6) || (level >= 8 && level % 5 == 3) }

    /// Everything that makes one level different from another.
    struct LevelSpec {
        var seed: UInt64
        var difficulty: Double
        /// Playfield scale from the size setting.
        var space = 1.0
        var attractor = false
        var supernova = false
        var splitters = false
        var pulsar = false
        var nebula = false
        var antimatter = false
        var comets = false
        var wormholes = false
        var binaries = false
        var astronaut = false
        var planets = false
        var goal: LevelGenerator.GoalKind = .becomeBiggest
        /// One line shown the first time a mechanic appears.
        var intro: String?

        func makeWorld() -> World {
            LevelGenerator.makeWorld(
                seed: seed, difficulty: difficulty, attractor: attractor, supernova: supernova,
                splitters: splitters, pulsar: pulsar, nebula: nebula,
                antimatter: antimatter, comets: comets, wormholes: wormholes,
                binaries: binaries, astronaut: astronaut, planets: planets, space: space, goal: goal
            )
        }
    }

    static func spec(for mode: GameMode) -> LevelSpec {
        switch mode {
        case .campaign(let level):
            return LevelSpec(
                seed: UInt64(level) &+ 1,
                difficulty: min(Double(level) / 20, 1),
                space: WorldSize.current.scale,
                attractor: hasAttractor(level: level),
                supernova: hasSupernova(level: level),
                splitters: hasSplitters(level: level),
                pulsar: hasPulsar(level: level),
                nebula: hasNebula(level: level),
                antimatter: hasAntimatter(level: level),
                comets: hasComets(level: level),
                wormholes: hasWormholes(level: level),
                binaries: hasBinaries(level: level),
                astronaut: hasAstronaut(level: level),
                planets: hasPlanets(level: level),
                goal: goal(level: level),
                intro: intro(level: level)
            )
        case .daily(let day):
            // Same day → same level on every device.
            return LevelSpec(
                seed: UInt64(day) &* 0x9E37_79B9 &+ 17,
                difficulty: 0.5,
                space: WorldSize.current.scale,
                attractor: day % 2 == 0,
                supernova: day % 2 == 1,
                splitters: true,
                pulsar: day % 3 == 0,
                nebula: day % 3 == 1,
                antimatter: day % 4 == 2,
                comets: day % 2 == 0,
                wormholes: day % 3 == 2,
                binaries: day % 5 == 1,
                astronaut: day % 2 == 1,
                planets: day % 2 == 0,
                goal: dailyGoal(day: day)
            )
        case .sandbox(let c):
            return LevelSpec(
                seed: c.seed, difficulty: c.difficulty, space: WorldSize.current.scale,
                attractor: c.attractor, supernova: c.supernova, splitters: c.splitters,
                pulsar: c.pulsar, nebula: c.nebula, antimatter: c.antimatter,
                comets: c.comets, wormholes: c.wormholes, binaries: c.binaries, astronaut: c.astronaut, planets: c.planets
            )
        }
    }

    /// First appearance of each mechanic gets a one-line explanation under the goal.
    private static func intro(level: Int) -> String? {
        switch level {
        case 1: String(localized: "Новое: охотники гонятся за теми, кто меньше")
        case 2: String(localized: "Новое: мелкие беглецы удирают от тебя")
        case 3: String(localized: "Новое: чёрная дыра. Не подлетай к горизонту")
        case 5: String(localized: "Новое: сверхновая скоро взорвётся")
        case 6: String(localized: "Новое: планеты — от них можно отскочить, но съесть нельзя")
        case 7: String(localized: "Новое: пульсар отталкивает всё вокруг")
        case 8: String(localized: "Новое: комета оставляет хвост из еды")
        case 9: String(localized: "Новое: делящиеся звёзды распадаются надвое")
        case 10: String(localized: "Новое: туманность тормозит, но в ней много пыли")
        case 11: String(localized: "Новое: антиматерия уничтожает массу. Не трогай!")
        case 12: String(localized: "Новое: червоточины. Нырни в одну — вынырнешь из другой")
        case 13: String(localized: "Новое: двойная звезда. Две гигантские звезды кружат друг вокруг друга")
        case 14: String(localized: "Новое: бомба. Гигант гонится за тобой — заведи его на неё")
        default: nil
        }
    }
}

/// Player settings, shared by SwiftUI (@AppStorage) and the scene.
enum SettingsKey {
    static let music = "settings.music"
    static let sounds = "settings.sounds"
    static let musicVolume = "settings.musicVolume"
    static let soundsVolume = "settings.soundsVolume"
    static let haptics = "settings.haptics"
    /// Osmos-style: the blob flies to the touch, the player moves away from it.
    static let controlAway = "settings.controlAway"
    /// Blue/orange palette for red-green colour blindness.
    static let contrastColors = "settings.contrastColors"
    /// Playfield size: "compact", "normal" or "huge" (see WorldSize).
    static let worldSize = "settings.worldSize"
    /// Predicted path of the ship as fading dots.
    static let trajectory = "settings.trajectory"
}

/// Playfield size from settings. Object counts follow the area, so density (and difficulty) stays the same.
enum WorldSize: String, CaseIterable, Identifiable {
    case compact, normal, huge

    var id: String { rawValue }

    /// Side length relative to the normal field.
    var scale: Double {
        switch self {
        case .compact: 0.7
        case .normal: 1
        case .huge: 1.5
        }
    }

    var title: String {
        switch self {
        case .compact: String(localized: "Компактное")
        case .normal: String(localized: "Обычное")
        case .huge: String(localized: "Огромное")
        }
    }

    /// Storage-key suffix for per-size stars and replays. Normal keeps the old keys, so earlier progress stays.
    var keySuffix: String { self == .normal ? "" : ".\(rawValue)" }

    static var current: WorldSize {
        WorldSize(rawValue: UserDefaults.standard.string(forKey: SettingsKey.worldSize) ?? "") ?? .normal
    }
}
