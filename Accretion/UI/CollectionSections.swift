import SwiftUI

extension MenuView {
    var skinsSection: some View { SkinsSection(scene: scene) }
    var achievementsSection: some View { AchievementsSection() }
}

/// Player star colours, unlocked by total campaign stars.
struct SkinsSection: View {
    let scene: GameScene
    @AppStorage("accretion.skin") private var selected = Skin.gold.rawValue

    var body: some View {
        let stars = Skin.totalStars
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Облик").font(.title3.bold())
                Spacer()
                Label("\(stars)", systemImage: "star.fill")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Skin.allCases) { skin in
                        skinButton(skin, unlocked: stars >= skin.cost)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func skinButton(_ skin: Skin, unlocked: Bool) -> some View {
        let (r, g, b) = skin.rgb
        let color = Color(red: r, green: g, blue: b)
        let isSelected = selected == skin.rawValue
        return Button {
            selected = skin.rawValue
            scene.skin = skin
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [color, color.opacity(0.15)], center: .center, startRadius: 4, endRadius: 26))
                        .frame(width: 52, height: 52)
                        .opacity(unlocked ? 1 : 0.25)
                    if !unlocked {
                        Image(systemName: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .overlay(Circle().stroke(color, lineWidth: isSelected ? 2 : 0).padding(-4))
                Text(unlocked ? skin.title : "\(skin.cost) ★")
                    .font(.caption)
                    .foregroundStyle(unlocked ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(Text(unlocked ? skin.title : "\(skin.title), нужно \(skin.cost) звёзд"))
    }
}

struct AchievementsSection: View {
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let unlocked = AchievementStore.unlocked
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Достижения").font(.title3.bold())
                Spacer()
                Text("\(unlocked.count) из \(Achievement.allCases.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Achievement.allCases) { achievement in
                    let done = unlocked.contains(achievement)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: achievement.icon)
                            .font(.title3)
                            .frame(width: 26)
                            .foregroundStyle(done ? Color(red: 1, green: 0.83, blue: 0.43) : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(achievement.title).font(.subheadline.bold())
                            Text(achievement.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(done ? 0.08 : 0.03)))
                    .opacity(done ? 1 : 0.6)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(Text(done ? "получено" : "не получено"))
                }
            }
        }
    }
}
