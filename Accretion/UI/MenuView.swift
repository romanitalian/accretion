import SwiftUI

/// Pause menu: continue, today's level, level select with stars, settings. Everything is one tap.
struct MenuView: View {
    let scene: GameScene
    @Binding var isPresented: Bool

    @AppStorage(SettingsKey.musicVolume) private var musicVolume = 1.0
    @AppStorage(SettingsKey.soundsVolume) private var soundsVolume = 1.0
    @AppStorage(SettingsKey.haptics) private var hapticsOn = true
    @AppStorage(SettingsKey.controlAway) private var controlAway = false
    @AppStorage(SettingsKey.contrastColors) private var contrastColors = false
    @AppStorage(SettingsKey.trajectory) private var trajectoryOn = true
    @AppStorage(SettingsKey.worldSize) private var worldSize = WorldSize.normal.rawValue

    private let gold = Color(red: 1.0, green: 0.83, blue: 0.43)
    private let violet = Color(red: 0.69, green: 0.49, blue: 1.0)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    continueButton
                    dailyCard
                    levels
                    skinsSection
                    achievementsSection
                    sandboxSection
                    settings
                }
                .padding(20)
            }
            .background(Color(red: 0.02, green: 0.03, blue: 0.09).ignoresSafeArea())
            .navigationTitle("Accretion")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresented = false } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Закрыть"))
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var continueButton: some View {
        Button { isPresented = false } label: {
            Label("Продолжить", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(gold)
        .foregroundStyle(.black)
    }

    private var dailyCard: some View {
        let today = GameProgress.today
        let stars = GameProgress.dailyStars(day: today)
        return Button {
            scene.startDaily()
            isPresented = false
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(gold)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ежедневный уровень").font(.headline)
                    Text(stars > 0 ? "Пройден сегодня. Можно улучшить результат" : "Новый уровень каждый день, одинаковый для всех")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                StarsView(count: stars, color: gold)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var levels: some View {
        let unlocked = GameProgress.maxUnlockedLevel
        let current: Int? = if case .campaign(let level) = scene.mode { level } else { nil }
        // Show the unlocked ones plus a few locked ones, so there's always something ahead.
        let shown = ((unlocked + 1 + 4) / 5) * 5 + 5
        return VStack(alignment: .leading, spacing: 12) {
            Text("Уровни").font(.title3.bold())
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<shown, id: \.self) { level in
                    levelCell(level, locked: level > unlocked, isCurrent: level == current)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                legend(Circle().fill(violet).frame(width: 8, height: 8), "чёрная дыра")
                legend(Circle().fill(Color.orange).frame(width: 8, height: 8), "сверхновая")
                legend(goalIcon(.reachMass(multiple: 2)), "вырасти в N раз")
                legend(goalIcon(.survive(seconds: 1)), "продержись")
                legend(goalIcon(.eatTarget), "поглоти цель")
                legend(goalIcon(.eatAllHunters), "съешь всех охотников")
                legend(goalIcon(.travel(times: 1)), "пройди через червоточины")
                legend(goalIcon(.trap), "заведи гиганта на бомбу")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func levelCell(_ level: Int, locked: Bool, isCurrent: Bool) -> some View {
        Button {
            scene.startCampaign(level: level)
            isPresented = false
        } label: {
            VStack(spacing: 4) {
                if locked {
                    Image(systemName: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("\(level + 1)").font(.headline.monospacedDigit())
                }
                StarsView(count: GameProgress.stars(level: level), color: gold, size: 7)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(locked ? 0.03 : 0.07)))
            .overlay(alignment: .topTrailing) {
                if GameProgress.hasAttractor(level: level) {
                    Circle().fill(violet).frame(width: 6, height: 6).padding(6)
                } else if GameProgress.hasSupernova(level: level) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6).padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                goalIcon(GameProgress.goal(level: level))
                    .padding(5)
                    .opacity(locked ? 0.4 : 0.8)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold, lineWidth: isCurrent ? 1.5 : 0))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .contextMenu {
            if !locked, ReplayStore.best(for: .campaign(level: level)) != nil {
                Button {
                    scene.playBestReplay(level: level)
                    isPresented = false
                } label: {
                    Label("Смотреть лучший повтор", systemImage: "play.circle")
                }
            }
        }
        .accessibilityLabel(Text(locked ? "Уровень \(level + 1), закрыт" : "Уровень \(level + 1), звёзд: \(GameProgress.stars(level: level))"))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Настройки").font(.title3.bold())
            VStack(spacing: 0) {
                volumeRow("Музыка", value: $musicVolume)
                Divider()
                volumeRow("Звуки", value: $soundsVolume)
                Divider()
                Toggle("Вибрация", isOn: $hapticsOn).padding(14)
                Divider()
                Toggle(isOn: $contrastColors) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Контрастные цвета")
                        Text("Синий / оранжевый — для дальтонизма")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                Divider()
                Toggle("Траектория", isOn: $trajectoryOn)
                    .padding(14)
            }
            .tint(gold)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))

            VStack(alignment: .leading, spacing: 8) {
                Text("Размер пространства").font(.subheadline).foregroundStyle(.secondary)
                Picker("Размер пространства", selection: $worldSize) {
                    ForEach(WorldSize.allCases) { size in
                        Text(size.title).tag(size.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("Плотность звёзд та же: на большом поле просто больше места и объектов. Звёзды за уровни считаются отдельно для каждого размера.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Управление").font(.subheadline).foregroundStyle(.secondary)
                Picker("Как лететь", selection: $controlAway) {
                    Text("К пальцу").tag(false)
                    Text("От пальца").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Button(role: .none) {
                scene.restartLevel()
                isPresented = false
            } label: {
                Label("Начать уровень заново", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }
}

private extension MenuView {
    /// Small icon for a level goal; the classic "become biggest" goal has none.
    @ViewBuilder
    func goalIcon(_ goal: LevelGenerator.GoalKind) -> some View {
        let name: String? = switch goal {
        case .becomeBiggest: nil
        case .reachMass: "arrow.up.circle"
        case .survive: "timer"
        case .eatTarget: "scope"
        case .eatAllHunters: "figure.run"
        case .travel: "arrow.triangle.swap"
        case .trap: "flame"
        }
        if let name {
            Image(systemName: name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    func legend(_ icon: some View, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            icon.frame(width: 12)
            Text(text)
        }
    }
}

private struct StarsView: View {
    let count: Int
    let color: Color
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < count ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(index < count ? color : .white.opacity(0.25))
            }
        }
        .accessibilityHidden(true)
    }
}
