import SpriteKit
import SwiftUI
import UIKit

@main
struct AccretionApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
        }
    }
}

/// The whole app: launch goes straight into a level. The menu is optional and one tap away.
struct GameView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = GameScene()
    @State private var music = AmbientMusic()
    @State private var puffHaptic = UIImpactFeedbackGenerator(style: .soft)
    @State private var absorbHaptic = UIImpactFeedbackGenerator(style: .light)
    @State private var heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    @AppStorage(SettingsKey.contrastColors) private var contrastColors = false
    @AppStorage(SettingsKey.trajectory) private var trajectoryOn = true
    @AppStorage(SettingsKey.worldSize) private var worldSize = WorldSize.normal.rawValue
    @State private var showMenu = false
    @State private var sharePayload: SharePayload?

    @AppStorage(SettingsKey.musicVolume) private var musicVolume = 1.0
    @AppStorage(SettingsKey.soundsVolume) private var soundsVolume = 1.0
    @AppStorage(SettingsKey.controlAway) private var controlAway = false

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) { menuButton }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .sheet(isPresented: $showMenu, onDismiss: resume) {
                MenuView(scene: scene, isPresented: $showMenu)
            }
            .sheet(item: $sharePayload) { payload in
                ActivityView(items: [payload.image, payload.text])
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                scene.onPuff = { if hapticsOn { puffHaptic.impactOccurred(intensity: 0.35) } }
                scene.onAbsorb = { if hapticsOn { absorbHaptic.impactOccurred(intensity: 0.5) } }
                scene.onSwallow = { music.chime() }
                scene.onStar = {
                    music.chime()
                    if hapticsOn { absorbHaptic.impactOccurred(intensity: 0.8) }
                }
                scene.onDanger = { music.setDanger($0) }
                scene.onBeingEaten = { if hapticsOn { heavyHaptic.impactOccurred(intensity: 0.7) } }
                scene.onTeleport = { music.whoosh() }
                scene.onBounce = { if hapticsOn { absorbHaptic.impactOccurred(intensity: 0.9) } }
                scene.onAchievement = { _ in
                    music.chime()
                    if hapticsOn { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
                scene.onWorldChange = { music.setWorld($0) }
                scene.onSoundscape = { music.setVoices($0) }
                scene.onShare = { image, text in sharePayload = SharePayload(image: image, text: text) }
                scene.onExplosion = {
                    music.boom()
                    if hapticsOn { heavyHaptic.impactOccurred(intensity: 1) }
                }
                applySettings()
                music.start()
            }
            .onChange(of: musicVolume) { applySettings() }
            .onChange(of: soundsVolume) { applySettings() }
            .onChange(of: controlAway) { applySettings() }
            .onChange(of: contrastColors) { applySettings() }
            .onChange(of: trajectoryOn) { applySettings() }
            // A new field size only makes sense from a fresh start of the level.
            .onChange(of: worldSize) { scene.restartLevel() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    if !showMenu { resume() }
                    music.start()
                default:
                    scene.isPaused = true
                    music.pause()
                }
            }
    }

    /// Menu + restart, matching the time-warp button on the right: same size, same distance from the safe area.
    private var menuButton: some View {
        HStack(spacing: GameScene.topButtonSpacing - 48) {
            roundButton("line.3.horizontal", label: "Меню") {
                scene.isPaused = true
                showMenu = true
            }
            .accessibilityIdentifier("menuButton")
            roundButton("arrow.counterclockwise", label: "Начать уровень заново") {
                if hapticsOn { absorbHaptic.impactOccurred(intensity: 0.6) }
                scene.restartLevel()
            }
        }
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    private func roundButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 48, height: 48)
                .background(Circle().fill(.white.opacity(0.08)))
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .accessibilityLabel(Text(label))
    }

    /// Read at call time so toggling in the menu applies immediately.
    private var hapticsOn: Bool { UserDefaults.standard.object(forKey: SettingsKey.haptics) as? Bool ?? true }

    private func applySettings() {
        music.musicVolume = musicVolume
        music.soundsVolume = soundsVolume
        scene.controlAwayFromTouch = controlAway
        scene.contrastColors = contrastColors
        scene.showTrajectory = trajectoryOn
    }

    private func resume() {
        scene.resetClock()
        scene.isPaused = false
    }
}

/// What the result screen hands to the system share sheet.
struct SharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let text: String
}

/// System share sheet (Messages, Telegram, Photos, …).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
