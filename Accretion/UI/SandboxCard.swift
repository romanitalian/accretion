import SwiftUI

extension MenuView {
    var sandboxSection: some View {
        SandboxCard(scene: scene, isPresented: $isPresented)
    }

    /// Title, speaker icons on both ends, slider in between. Dragging to zero mutes.
    func volumeRow(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue < 0.01 ? "выкл." : "\(Int(value.wrappedValue * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { value.wrappedValue = 0 } label: {
                    Image(systemName: value.wrappedValue < 0.01 ? "speaker.slash.fill" : "speaker.fill")
                        .frame(width: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Выключить"))
                Slider(value: value, in: 0...1)
                    .accessibilityLabel(Text(title))
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
    }
}

/// Sandbox: switch on any objects, pick a difficulty, play. No stars, no progress, just fun.
struct SandboxCard: View {
    let scene: GameScene
    @Binding var isPresented: Bool
    @State private var config = SandboxConfig.saved
    @State private var expanded = false

    private let gold = Color(red: 1.0, green: 0.83, blue: 0.43)

    private var toggles: [(String, String, WritableKeyPath<SandboxConfig, Bool>)] {
        [
            ("Чёрная дыра", "circle.circle", \.attractor),
            ("Планеты", "globe.europe.africa", \.planets),
            ("Сверхновая", "sparkle", \.supernova),
            ("Делящиеся звёзды", "circle.lefthalf.filled", \.splitters),
            ("Пульсар", "dot.radiowaves.left.and.right", \.pulsar),
            ("Туманность", "cloud", \.nebula),
            ("Антиматерия", "exclamationmark.octagon", \.antimatter),
            ("Кометы", "wind", \.comets),
            ("Червоточины", "arrow.triangle.swap", \.wormholes),
            ("Двойная звезда", "circle.grid.2x1", \.binaries),
            ("Космонавт", "person.crop.circle", \.astronaut),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Песочница").font(.title3.bold())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Собери свой уровень из любых объектов")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(toggles, id: \.0) { title, icon, key in
                        Toggle(isOn: Binding(get: { config[keyPath: key] }, set: { config[keyPath: key] = $0 })) {
                            Label(LocalizedStringKey(title), systemImage: icon)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Сложность: \(Int(config.difficulty * 100))%")
                        Slider(value: $config.difficulty, in: 0...1)
                    }
                    .padding(14)
                }
                .tint(gold)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
            }

            Button {
                scene.startSandbox(config.reshuffled())
                isPresented = false
            } label: {
                Label("Играть в песочнице", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(gold)
        }
    }
}
