import Foundation

/// Local achievements: no account, no network. Unlocked once, forever.
enum Achievement: String, CaseIterable, Identifiable {
    case firstWin
    case threeStars
    case zen
    case tenLevels
    case twentyLevels
    case hundredSwallowed
    case hunterHunter
    case cometCatcher
    case binaryBreaker
    case astronaut
    case billiards
    case bomber
    case traveler
    case supernovaSurvivor
    case daily
    case sandbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstWin: String(localized: "Первая победа")
        case .threeStars: String(localized: "Три звезды")
        case .zen: String(localized: "Дзен")
        case .tenLevels: String(localized: "Созвездие")
        case .twentyLevels: String(localized: "Галактика")
        case .hundredSwallowed: String(localized: "Ненасытная")
        case .hunterHunter: String(localized: "Охотник на охотников")
        case .cometCatcher: String(localized: "Ловец комет")
        case .binaryBreaker: String(localized: "Разлучница")
        case .astronaut: String(localized: "Космонавт на борту")
        case .billiards: String(localized: "Бильярд")
        case .bomber: String(localized: "Бомбардир")
        case .traveler: String(localized: "Путешественница")
        case .supernovaSurvivor: String(localized: "В эпицентре")
        case .daily: String(localized: "Каждый день")
        case .sandbox: String(localized: "Творец")
        }
    }

    var detail: String {
        switch self {
        case .firstWin: String(localized: "Пройди любой уровень")
        case .threeStars: String(localized: "Получи три звезды")
        case .zen: String(localized: "Пройди уровень, не потратив массы")
        case .tenLevels: String(localized: "Открой 10 уровней")
        case .twentyLevels: String(localized: "Открой 20 уровней")
        case .hundredSwallowed: String(localized: "Поглоти 100 звёзд")
        case .hunterHunter: String(localized: "Поглоти охотника")
        case .cometCatcher: String(localized: "Поглоти комету")
        case .binaryBreaker: String(localized: "Поглоти половинку двойной звезды")
        case .astronaut: String(localized: "Подбери потерявшегося космонавта")
        case .billiards: String(localized: "Отскочи от планеты")
        case .bomber: String(localized: "Заведи гиганта на бомбу")
        case .traveler: String(localized: "Пройди через червоточину")
        case .supernovaSurvivor: String(localized: "Переживи сверхновую совсем рядом")
        case .daily: String(localized: "Пройди ежедневный уровень")
        case .sandbox: String(localized: "Выиграй в песочнице")
        }
    }

    /// SF Symbol for the menu.
    var icon: String {
        switch self {
        case .firstWin: "flag.checkered"
        case .threeStars: "star.fill"
        case .zen: "leaf"
        case .tenLevels: "sparkles"
        case .twentyLevels: "hurricane"
        case .hundredSwallowed: "circle.hexagongrid.fill"
        case .hunterHunter: "figure.run"
        case .cometCatcher: "wind"
        case .binaryBreaker: "circle.grid.2x1"
        case .astronaut: "person.crop.circle"
        case .billiards: "globe.europe.africa"
        case .bomber: "flame"
        case .traveler: "arrow.triangle.swap"
        case .supernovaSurvivor: "burst"
        case .daily: "sun.max"
        case .sandbox: "wand.and.stars"
        }
    }
}

enum AchievementStore {
    private static var defaults: UserDefaults { .standard }
    private static let unlockedKey = "accretion.achievements"
    private static let swallowedKey = "accretion.totalSwallowed"

    static var unlocked: Set<Achievement> {
        Set((defaults.stringArray(forKey: unlockedKey) ?? []).compactMap(Achievement.init(rawValue:)))
    }

    static func isUnlocked(_ achievement: Achievement) -> Bool { unlocked.contains(achievement) }

    /// Returns true only the first time, so the caller can celebrate once.
    @discardableResult
    static func unlock(_ achievement: Achievement) -> Bool {
        var set = unlocked
        guard set.insert(achievement).inserted else { return false }
        defaults.set(set.map(\.rawValue).sorted(), forKey: unlockedKey)
        return true
    }

    static var totalSwallowed: Int { defaults.integer(forKey: swallowedKey) }

    static func addSwallowed(_ count: Int) {
        defaults.set(totalSwallowed + count, forKey: swallowedKey)
    }
}

/// Player star looks, unlocked by total campaign stars.
enum Skin: String, CaseIterable, Identifiable {
    case gold, ice, rose, emerald, violet, nova

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gold: String(localized: "Золото")
        case .ice: String(localized: "Лёд")
        case .rose: String(localized: "Роза")
        case .emerald: String(localized: "Изумруд")
        case .violet: String(localized: "Фиалка")
        case .nova: String(localized: "Сверхновая")
        }
    }

    /// Stars needed to unlock.
    var cost: Int {
        switch self {
        case .gold: 0
        case .ice: 6
        case .rose: 12
        case .emerald: 20
        case .violet: 30
        case .nova: 42
        }
    }

    /// sRGB components, shared by SwiftUI and SpriteKit.
    var rgb: (Double, Double, Double) {
        switch self {
        case .gold: (1.00, 0.83, 0.43)
        case .ice: (0.75, 0.95, 1.00)
        case .rose: (1.00, 0.62, 0.78)
        case .emerald: (0.45, 0.95, 0.62)
        case .violet: (0.80, 0.62, 1.00)
        case .nova: (1.00, 1.00, 0.92)
        }
    }

    private static let key = "accretion.skin"

    static var selected: Skin {
        get { Skin(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .gold }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static var totalStars: Int {
        (0...GameProgress.maxUnlockedLevel).reduce(0) { $0 + GameProgress.bestStars(level: $1) }
    }

    var isUnlocked: Bool { Skin.totalStars >= cost }
}
