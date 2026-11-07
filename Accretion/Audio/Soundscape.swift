import Foundation

/// One audible object: a tone the player can place by ear.
struct SoundscapeVoice: Sendable, Equatable {
    enum Timbre: Sendable, Equatable {
        /// Food: a plain, friendly tone.
        case sine
        /// Planet: hollow, two partials.
        case hollow
        /// Black hole: slow, deep, breathing.
        case rumble
        /// Comet, astronaut, pulsar: light tremolo.
        case chirp
        /// Bigger than you (or antimatter): fast tremolo, reads as danger.
        case threat
    }

    var frequency: Double
    /// -1 = left ear, 0 = centre, +1 = right ear. Matches where the object is on screen.
    var pan: Double
    /// 0…1 before the sound-effects volume is applied.
    var gain: Double
    var timbre: Timbre
}

/// Turns the nearest objects into voices. Pure function of the world, so it is testable.
///
/// Mapping (what you hear → what you see):
/// - pitch: size. Small objects sing high (880 Hz), big ones growl low (60 Hz).
/// - pan: left/right position on screen.
/// - loudness: closeness to you, and how big the object is.
/// - timbre: what the object is (food, threat, planet, black hole, light objects).
enum Soundscape {
    static let maxVoices = 6
    /// Objects farther than this (world units) are silent. Black holes are heard from further away.
    static let reach = 900.0
    static let blackHoleReach = 1500.0

    static func voices(world: World, cameraCenter: Vec2, halfWidth: Double) -> [SoundscapeVoice] {
        guard world.state == .playing, let player = world.player, halfWidth > 1 else { return [] }
        var candidates: [(distance: Double, voice: SoundscapeVoice)] = []
        for body in world.bodies where body.id != player.id {
            let distance = (body.position - player.position).length
            let limit = body.kind == .attractor ? blackHoleReach : reach
            guard distance < limit else { continue }
            let onScreen = (body.position.x - cameraCenter.x) / halfWidth
            candidates.append((distance, voice(for: body, player: player, distance: distance, screenX: onScreen, reach: limit)))
        }
        return candidates
            .sorted { $0.distance < $1.distance }
            .prefix(maxVoices)
            .map(\.voice)
    }

    static func voice(for body: Body, player: Body, distance: Double, screenX: Double, reach: Double) -> SoundscapeVoice {
        let pan = min(max(screenX, -1), 1)
        // Radius 3 → 880 Hz, radius 50 → 60 Hz, on a log scale (how pitch is heard).
        let t = min(max((body.radius - 3) / 47, 0), 1)
        let pitch = 880 * pow(60.0 / 880.0, t)
        // Closer is louder; the falloff reaches zero at `reach`.
        let falloff = max(0, 1 - distance / reach) * (1 / (1 + distance / 300))

        switch body.kind {
        case .attractor:
            return SoundscapeVoice(frequency: 48, pan: pan, gain: min(0.9, 0.9 * max(0, 1 - distance / reach) + 0.1), timbre: .rumble)
        case .planet:
            return SoundscapeVoice(frequency: pitch, pan: pan, gain: min(1, 0.4 + 0.6 * falloff), timbre: .hollow)
        case .astronaut, .comet, .pulsar:
            return SoundscapeVoice(frequency: pitch, pan: pan, gain: min(1, 0.3 + 0.7 * falloff), timbre: .chirp)
        case .antimatter:
            return SoundscapeVoice(frequency: pitch, pan: pan, gain: min(1, 0.4 + 0.6 * falloff), timbre: .threat)
        default:
            let bigger = body.mass > player.mass * 1.05
            let base = 0.35 + 0.65 * min(body.radius / 25, 1)
            return SoundscapeVoice(
                frequency: pitch, pan: pan, gain: min(1, base * falloff),
                timbre: bigger ? .threat : .sine
            )
        }
    }
}
