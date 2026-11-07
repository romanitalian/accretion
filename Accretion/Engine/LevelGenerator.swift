import Foundation

/// Deterministic PRNG (SplitMix64): same seed → same level on every device.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public enum LevelGenerator {
    public static let playerID = 0
    public static let playerRadius = 22.0

    public static let attractorRadius = 55.0

    /// Goal without body ids; the generator picks the target itself.
    public enum GoalKind: Sendable, Equatable {
        case becomeBiggest
        case reachMass(multiple: Double)
        case survive(seconds: Double)
        case eatTarget
        case eatAllHunters
        case travel(times: Int)
        /// A bomb and a giant hunter: lure the giant onto the bomb.
        case trap
    }

    /// Builds a solvable level. `difficulty` in 0...1 adds more and faster bodies.
    /// `attractor`: a fixed gravity well in the centre, everything starts on a circular orbit around it.
    /// `supernova`: the biggest rival explodes after 18–32 s.
    /// `splitters`: some mid-sized stars burst in two when threatened.
    /// `pulsar`: one pulsar pushes everything away every few seconds.
    /// `nebula`: 1–2 drag clouds full of dust.
    public static func makeWorld(
        seed: UInt64, difficulty: Double = 0, attractor: Bool = false,
        supernova: Bool = false, splitters: Bool = false, pulsar: Bool = false, nebula: Bool = false,
        antimatter: Bool = false, comets: Bool = false, wormholes: Bool = false, binaries: Bool = false, astronaut: Bool = false, planets: Bool = false,
        space: Double = 1, goal: GoalKind = .becomeBiggest
    ) -> World {
        let features = Features(attractor: attractor, supernova: supernova, splitters: splitters, pulsar: pulsar,
                                nebula: nebula, antimatter: antimatter, comets: comets, wormholes: wormholes,
                                binaries: binaries, astronaut: astronaut, planets: planets)
        var attempt: UInt64 = 0
        while true {
            let world = candidate(seed: seed &+ attempt &* 0x1000_0000_01, difficulty: difficulty,
                                  features: features, space: space, goal: goal)
            // A trap level is won by luring, not by outgrowing, so the size check doesn't apply.
            if case .trap = world.goal { return world }
            if isSolvable(world) || attempt >= 50 { return world }
            attempt += 1
        }
    }

    /// Rough solvability check: everything smaller than the player plus the player itself
    /// must outweigh the biggest rival with a 20% margin. Attractors are terrain, not rivals.
    public static func isSolvable(_ world: World) -> Bool {
        guard let player = world.player else { return false }
        let others = world.bodies.filter { $0.id != player.id && World.isRival($0) }
        guard let biggest = others.map(\.mass).max(), biggest > player.mass else { return false }
        let edible = others.filter { $0.mass < player.mass }.reduce(0) { $0 + $1.mass }
        return player.mass + edible > biggest * 1.2
    }

    private struct Features {
        var attractor: Bool
        var supernova: Bool
        var splitters: Bool
        var pulsar: Bool
        var nebula: Bool
        var antimatter: Bool
        var comets: Bool
        var wormholes: Bool
        var binaries: Bool
        var astronaut: Bool
        var planets: Bool
    }

    public static let pulsarRadius = 26.0

    /// `space` scales the playfield's side; object counts scale with its area, so density stays the same.
    private static func candidate(seed: UInt64, difficulty: Double, features: Features, space: Double, goal: GoalKind) -> World {
        let attractor = features.attractor
        let supernova = features.supernova
        var rng = SplitMix64(seed: seed)
        let d = min(max(difficulty, 0), 1)
        let size = Vec2(2000 + 800 * d, 2000 + 800 * d) * space
        let area = space * space
        /// A count for the normal field, scaled to this field's area (never below 1).
        func scaled(_ count: Int) -> Int { max(1, Int((Double(count) * area).rounded())) }
        let center = size / 2
        var bodies: [Body] = []
        var nextID = 1

        // Orbit setup: counter-clockwise circular speed around the well, slightly randomised.
        let wellMass = Body.mass(forRadius: attractorRadius)
        func orbitVelocity(at p: Vec2, jitter: Double) -> Vec2 {
            let r = p - center
            let distance = r.length
            guard distance > 1 else { return .zero }
            let tangent = Vec2(-r.y, r.x) / distance
            return tangent * World.orbitalSpeed(attractorMass: wellMass, distance: distance) * jitter
        }

        let playerStart: Vec2
        if attractor {
            bodies.append(Body(id: nextID, kind: .attractor, position: center, radius: attractorRadius))
            nextID += 1
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            playerStart = center + Vec2(cos(angle), sin(angle)) * 420
            bodies.append(Body(id: playerID, kind: .player, position: playerStart,
                               velocity: orbitVelocity(at: playerStart, jitter: 1), radius: playerRadius))
        } else {
            playerStart = center
            bodies.append(Body(id: playerID, kind: .player, position: center, radius: playerRadius))
        }

        let count = scaled(110 + Int(60 * d))
        let maxSpeed = 12 + 30 * d

        /// Places a mote at a random free spot (optionally inside a circle). Returns its index.
        @discardableResult
        func place(radius: Double, minPlayerGap: Double, within zone: World.Nebula? = nil) -> Int? {
            for _ in 0..<40 {
                var p = Vec2(
                    Double.random(in: radius...(size.x - radius), using: &rng),
                    Double.random(in: radius...(size.y - radius), using: &rng)
                )
                if let zone {
                    let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                    let r = zone.radius * Double.random(in: 0...1, using: &rng).squareRoot() * 0.9
                    p = zone.center + Vec2(cos(angle), sin(angle)) * r
                    p.x = min(max(p.x, radius), size.x - radius)
                    p.y = min(max(p.y, radius), size.y - radius)
                }
                if (p - playerStart).length < playerRadius + radius + minPlayerGap { continue }
                if bodies.contains(where: {
                    let margin = $0.kind == .attractor ? 140.0 : 2.0
                    return ($0.position - p).length < $0.radius + radius + margin
                }) { continue }
                let velocity: Vec2
                if attractor {
                    velocity = orbitVelocity(at: p, jitter: Double.random(in: 0.85...1.1, using: &rng))
                } else {
                    let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                    velocity = Vec2(cos(angle), sin(angle)) * Double.random(in: 0...maxSpeed, using: &rng)
                }
                bodies.append(Body(id: nextID, kind: .mote, position: p, velocity: velocity, radius: radius))
                nextID += 1
                return bodies.count - 1
            }
            return nil
        }

        // Nebulae: drag clouds away from the start, filled with dust later.
        var nebulae: [World.Nebula] = []
        if features.nebula {
            for _ in 0..<scaled(d > 0.5 ? 2 : 1) {
                for _ in 0..<30 {
                    let radius = Double.random(in: 280...380, using: &rng)
                    let c = Vec2(
                        Double.random(in: radius...(size.x - radius), using: &rng),
                        Double.random(in: radius...(size.y - radius), using: &rng)
                    )
                    let farFromStart = (c - playerStart).length > radius + 250
                    let apart = nebulae.allSatisfy { ($0.center - c).length > $0.radius + radius }
                    if farFromStart, apart {
                        nebulae.append(World.Nebula(center: c, radius: radius))
                        break
                    }
                }
            }
        }

        // A double star: two big halves circling their common centre, away from the start and the well.
        if features.binaries {
            let halfRadius = 30.0
            let separation = 240.0
            let speed = World.binarySpeed(mass: Body.mass(forRadius: halfRadius), separation: separation)
            let span = separation / 2 + halfRadius + 20
            for _ in 0..<60 {
                let c = Vec2(
                    Double.random(in: span...(size.x - span), using: &rng),
                    Double.random(in: span...(size.y - span), using: &rng)
                )
                guard (c - playerStart).length > span + playerRadius + 260 else { continue }
                if attractor, (c - center).length < attractorRadius + span + 200 { continue }
                let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                let axis = Vec2(cos(angle), sin(angle))
                let tangent = Vec2(-axis.y, axis.x)
                for sign in [-1.0, 1.0] {
                    bodies.append(Body(id: nextID, kind: .binary, position: c + axis * (separation / 2) * sign,
                                       velocity: tangent * speed * sign, radius: halfRadius))
                    nextID += 1
                }
                break
            }
        }

        // A few giants the player has to outgrow.
        let giants = scaled(2 + Int(2 * d))
        for _ in 0..<giants {
            place(radius: Double.random(in: 32...(44 + 10 * d), using: &rng), minPlayerGap: 260)
        }
        // Power-law sizes: many small motes, few large ones.
        for _ in 0..<count {
            let u = Double.random(in: 0..<1, using: &rng)
            let radius = min(4 * pow(1 - u, -1 / 1.8), 30)
            place(radius: radius, minPlayerGap: radius > playerRadius ? 200 : 30)
        }
        // Dust inside nebulae: lots of easy food, but slow going.
        for zone in nebulae {
            for _ in 0..<30 {
                place(radius: Double.random(in: 3...5.5, using: &rng), minPlayerGap: 30, within: zone)
            }
        }
        // One pulsar, a bit bigger than the player, not too close to the start.
        if features.pulsar, let index = place(radius: pulsarRadius, minPlayerGap: 380) {
            bodies[index].kind = .pulsar
        }
        if features.antimatter {
            for _ in 0..<scaled(2 + Int(2 * d)) {
                if let index = place(radius: Double.random(in: 14...24, using: &rng), minPlayerGap: 260) {
                    bodies[index].kind = .antimatter
                }
            }
        }
        // Planets: solid bumpers. Around a black hole they orbit; elsewhere they hang still.
        if features.planets {
            for _ in 0..<scaled(2 + Int(2 * d)) {
                if let index = place(radius: Double.random(in: 20...34, using: &rng), minPlayerGap: 160) {
                    bodies[index].kind = .planet
                    if !attractor { bodies[index].velocity = .zero }
                }
            }
        }
        if features.astronaut, let index = place(radius: 5, minPlayerGap: 220) {
            bodies[index].kind = .astronaut
            bodies[index].velocity = bodies[index].velocity * 0.3 // drifting, not racing
        }
        if features.comets {
            for _ in 0..<scaled(d > 0.6 ? 2 : 1) {
                if let index = place(radius: 12, minPlayerGap: 300) {
                    let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                    bodies[index].kind = .comet
                    bodies[index].velocity = Vec2(cos(angle), sin(angle)) * 240
                }
            }
        }

        // Wormholes: mouths far apart, clear of the start, nebulae and the gravity well.
        var wormholes: [World.Wormhole] = []
        if features.wormholes {
            let mouth = 46.0
            func freeSpot() -> Vec2? {
                for _ in 0..<60 {
                    let p = Vec2(
                        Double.random(in: 120...(size.x - 120), using: &rng),
                        Double.random(in: 120...(size.y - 120), using: &rng)
                    )
                    let clearOfStart = (p - playerStart).length > 260
                    let clearOfWell = !attractor || (p - center).length > attractorRadius + 220
                    let clearOfNebula = nebulae.allSatisfy { ($0.center - p).length > $0.radius + mouth + 40 }
                    let clearOfHoles = wormholes.allSatisfy { ($0.a - p).length > 300 && ($0.b - p).length > 300 }
                    if clearOfStart, clearOfWell, clearOfNebula, clearOfHoles { return p }
                }
                return nil
            }
            for _ in 0..<scaled(d > 0.7 ? 2 : 1) {
                guard let a = freeSpot() else { break }
                var b: Vec2?
                for _ in 0..<20 {
                    if let candidate = freeSpot(), (candidate - a).length > min(size.x, size.y) * 0.45 {
                        b = candidate
                        break
                    }
                }
                if let b { wormholes.append(World.Wormhole(a: a, b: b, radius: mouth)) }
            }
        }

        // From the second level on, some mid-sized motes become hunters (never the giants: they'd eat everything at once).
        if d >= 0.05 {
            let hunterCount = scaled(1 + Int(4 * d))
            let candidates = bodies.indices.filter { bodies[$0].kind == .mote && (9...20).contains(bodies[$0].radius) }
            for index in candidates.prefix(hunterCount) { bodies[index].kind = .hunter }
        }
        // Skittish small fry from level 3: easy food that makes the player chase.
        if d >= 0.1 {
            let fleerCount = scaled(3 + Int(6 * d))
            let candidates = bodies.indices.filter { bodies[$0].kind == .mote && (4...8).contains(bodies[$0].radius) }
            for index in candidates.prefix(fleerCount) { bodies[index].kind = .fleer }
        }
        if features.splitters {
            let splitterCount = scaled(2 + Int(3 * d))
            let candidates = bodies.indices.filter { bodies[$0].kind == .mote && (12...20).contains(bodies[$0].radius) }
            for index in candidates.prefix(splitterCount) { bodies[index].kind = .splitter }
        }

        let playerMass = Body.mass(forRadius: playerRadius)
        if supernova, let index = bodies.indices
            .filter({ bodies[$0].kind == .mote })
            .max(by: { bodies[$0].mass < bodies[$1].mass }) {
            bodies[index].fuse = 18 + Double.random(in: 0...14, using: &rng)
        }

        let resolvedGoal: Goal
        switch goal {
        case .becomeBiggest: resolvedGoal = .becomeBiggest
        case .reachMass(let multiple): resolvedGoal = .reachMass(multiple: multiple)
        case .survive(let seconds): resolvedGoal = .survive(seconds: seconds)
        case .eatTarget:
            // The smallest body that's clearly bigger than the player: you must grow first, but it's reachable.
            let target = bodies
                .filter { $0.kind == .mote && !$0.isSupernova && $0.mass > playerMass * 1.3 }
                .min { $0.mass < $1.mass }
            resolvedGoal = target.map { .eatTarget(id: $0.id) } ?? .becomeBiggest
        case .eatAllHunters:
            resolvedGoal = bodies.contains { $0.kind == .hunter } ? .eatAllHunters : .becomeBiggest
        case .travel(let times):
            resolvedGoal = wormholes.isEmpty ? .becomeBiggest : .travel(times: times)
        case .trap:
            // The giant hunts the player; the bomb sits between them. Lead the giant onto it.
            let giantIndex = place(radius: 62, minPlayerGap: 650)
            let bombIndex = place(radius: 16, minPlayerGap: 260)
            if let giantIndex, let bombIndex {
                bodies[giantIndex].kind = .hunter
                bodies[giantIndex].velocity = .zero
                bodies[bombIndex].kind = .bomb
                bodies[bombIndex].velocity = bodies[bombIndex].velocity * 0.2
                resolvedGoal = .trap(target: bodies[giantIndex].id)
            } else {
                resolvedGoal = .becomeBiggest
            }
        }

        return World(size: size, bodies: bodies, playerID: playerID, goal: resolvedGoal, nebulae: nebulae, wormholes: wormholes)
    }
}
