import Foundation

public enum GameState: Sendable, Equatable {
    case playing
    case won
    case lost
}

/// What the player must do to win a level.
public enum Goal: Sendable, Equatable {
    /// Outweigh every rival (the classic Osmos goal).
    case becomeBiggest
    /// Grow to `multiple` × starting mass.
    case reachMass(multiple: Double)
    /// Stay alive for this many seconds of world time.
    case survive(seconds: Double)
    /// Swallow this particular body yourself.
    case eatTarget(id: Int)
    /// Lure this giant to a bomb: won when it is blown apart.
    case trap(target: Int)
    /// No hunters left in the level (eaten by anyone, but usually by you).
    case eatAllHunters
    /// Go through wormholes this many times.
    case travel(times: Int)
}

public enum LossReason: Sendable, Equatable {
    case eaten
    /// Someone else swallowed the target.
    case targetLost
}

/// Pure simulation: no rendering, no UIKit. Deterministic for a given initial state and input sequence.
public final class World {
    public static let fixedStep = 1.0 / 120.0
    /// Bodies whose radius drops below this are removed (fully absorbed).
    public static let minRadius = 0.6

    public struct Tuning: Sendable {
        /// Fraction of player mass ejected per puff.
        public var ejectFraction = 0.02
        /// Ejecta speed relative to the player, world units per second.
        public var ejectSpeed = 320.0
        /// Speed kept after bouncing off the border.
        public var wallRestitution = 0.9
        /// Gravity constant for attractors. Circular orbit speed at distance d: √(G·M·d / (d² + soft²)).
        public var gravity = 120.0
        /// Softening length, keeps acceleration finite near an attractor's centre.
        public var gravitySoftening = 50.0
        public init() {}
    }

    /// Bodies that never win or lose the game for the player: they're terrain, not rivals.
    /// Antimatter can't be outgrown by eating, so it doesn't count either.
    public static func isRival(_ body: Body) -> Bool {
        body.kind != .attractor && body.kind != .antimatter && !World.isSolid(body.kind)
    }

    /// Solid bodies never merge: others bounce off them.
    public static func isSolid(_ kind: Body.Kind) -> Bool { kind == .planet || kind == .bomb }

    /// A bomb goes off when a body this many times its mass gets within `bombTriggerGap`.
    public static let bombTriggerRatio = 2.0
    public static let bombTriggerGap = 60.0
    /// Bodies within this distance of the blast get pushed away; big rivals in it are blown apart.
    public static let blastRadius = 320.0
    public static let blastStrength = 260.0
    /// Set when the trap target was blown apart.
    public private(set) var targetExploded = false

    /// Circular orbit speed around an attractor of `mass` at `distance`, for setting up levels.
    public static func orbitalSpeed(attractorMass mass: Double, distance d: Double, tuning: Tuning = Tuning()) -> Double {
        (tuning.gravity * mass * d / (d * d + tuning.gravitySoftening * tuning.gravitySoftening)).squareRoot()
    }

    public let size: Vec2
    public let playerID: Int
    public let goal: Goal
    public private(set) var lossReason: LossReason?
    /// Who swallowed the `eatTarget` body, once it's gone.
    private var targetEatenBy: Int?

    /// A supernova that just blew up (for the flash and the boom).
    public struct Explosion: Sendable, Equatable {
        public let position: Vec2
        public let radius: Double
    }

    private var explosions: [Explosion] = []
    public static let supernovaFragments = 12

    public func drainExplosions() -> [Explosion] {
        defer { explosions.removeAll() }
        return explosions
    }
    public var tuning = Tuning()
    public private(set) var bodies: [Body]
    public private(set) var state: GameState = .playing
    /// Total simulated time, seconds.
    public private(set) var time: Double = 0
    /// How many bodies the player has swallowed completely (drives the chime sound).
    public private(set) var playerSwallowCount = 0
    /// What the player swallowed, by kind (for achievements).
    public private(set) var playerSwallowsByKind: [Body.Kind: Int] = [:]
    /// How many times the player went through a wormhole.
    public private(set) var playerTeleports = 0
    /// How many times the player bounced off a planet.
    public private(set) var playerBounces = 0
    /// Planets are this much "heavier" in collisions than their size says: they barely budge, like bumpers.
    public static let planetInertia = 25.0
    /// Bounciness of planet collisions.
    public static let planetRestitution = 0.9
    /// Hunters at the start, for the "eat all hunters" goal and its progress.
    public let initialHunters: Int
    /// Player mass at level start and the mass it has thrown away since: basis for the level rating.
    public let initialPlayerMass: Double
    public private(set) var playerEjectedMass = 0.0

    /// Mass flowing from one body into another during one step. Rendering turns these into particles.
    public struct ContactEvent: Sendable, Equatable {
        public let smallID: Int
        public let bigID: Int
        public let smallPosition: Vec2
        public let smallRadius: Double
        public let mass: Double
        /// The small body vanished in this step.
        public let swallowed: Bool
        /// Matter–antimatter contact: mass destroyed on both sides.
        public var annihilation = false
    }

    private var events: [ContactEvent] = []

    /// Returns contact events since the last call. Bounded so an undrained world (tests) can't grow forever.
    public func drainEvents() -> [ContactEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    private var nextID: Int
    private var accumulator: Double = 0

    /// A gas cloud: slows everything inside it down.
    public struct Nebula: Sendable, Equatable {
        public let center: Vec2
        public let radius: Double
        public init(center: Vec2, radius: Double) {
            self.center = center
            self.radius = radius
        }
        func contains(_ p: Vec2) -> Bool { (p - center).length < radius }
    }

    public let nebulae: [Nebula]
    /// Fraction of speed lost per second inside a nebula.
    public static let nebulaDrag = 0.8

    /// Pulsar shockwave (for the expanding ring).
    public struct Pulse: Sendable, Equatable {
        public let position: Vec2
        public let reach: Double
    }

    public static let pulseInterval = 4.0
    public static let pulseReach = 360.0
    /// Speed kick at the pulsar's surface, fading to 0 at `pulseReach`.
    public static let pulseStrength = 150.0
    private var nextPulseTime = World.pulseInterval
    private var pulses: [Pulse] = []

    public func drainPulses() -> [Pulse] {
        defer { pulses.removeAll() }
        return pulses
    }

    /// Two linked portals. Bodies smaller than the mouth that fall in come out of the other end, same velocity.
    public struct Wormhole: Sendable, Equatable {
        public let a: Vec2
        public let b: Vec2
        public let radius: Double
        public init(a: Vec2, b: Vec2, radius: Double) {
            self.a = a
            self.b = b
            self.radius = radius
        }
    }

    public let wormholes: [Wormhole]

    /// A body went through a wormhole (for the flash).
    public struct Teleport: Sendable, Equatable {
        public let bodyID: Int
        public let from: Vec2
        public let to: Vec2
    }

    private var teleports: [Teleport] = []

    public func drainTeleports() -> [Teleport] {
        defer { teleports.removeAll() }
        return teleports
    }

    /// Comets drop a dust grain this often (world seconds).
    public static let cometShedInterval = 0.12
    private var nextShedTime = World.cometShedInterval

    public init(size: Vec2, bodies: [Body], playerID: Int, goal: Goal = .becomeBiggest,
                nebulae: [Nebula] = [], wormholes: [Wormhole] = []) {
        self.size = size
        self.bodies = bodies
        self.playerID = playerID
        self.goal = goal
        self.nebulae = nebulae
        self.wormholes = wormholes
        self.nextID = (bodies.map(\.id).max() ?? 0) + 1
        self.initialPlayerMass = bodies.first { $0.id == playerID }?.mass ?? 0
        self.initialHunters = bodies.filter { $0.kind == .hunter }.count
    }

    public var player: Body? { bodies.first { $0.id == playerID } }

    public var totalMass: Double { bodies.reduce(0) { $0 + $1.mass } }

    public var totalMomentum: Vec2 { bodies.reduce(.zero) { $0 + $1.velocity * $1.mass } }

    // MARK: - Time

    /// Advances by real elapsed time using a fixed step. Large gaps (app resume) are clamped.
    public func advance(by dt: Double) {
        accumulator += min(max(dt, 0), 0.25)
        while accumulator >= World.fixedStep {
            step(World.fixedStep)
            accumulator -= World.fixedStep
        }
    }

    public func step(_ dt: Double) {
        guard state == .playing else { return }
        time += dt
        stepCount += 1
        if time >= nextAITime {
            nextAITime = time + World.aiInterval
            runAI()
        }
        if time >= nextPulseTime {
            nextPulseTime += World.pulseInterval
            firePulsars()
        }
        if time >= nextShedTime {
            nextShedTime += World.cometShedInterval
            shedCometDust()
        }
        applyGravity(dt)
        integrate(dt)
        passWormholes()
        resolveContacts()
        bodies.removeAll { $0.radius < World.minRadius }
        triggerBombs()
        detonateSupernovas()
        updateState()
    }

    /// A supernova whose fuse ran out bursts into a ring of fragments flying outward. Mass is conserved.
    /// A bomb goes off when something much bigger than it comes close. The blast pushes everything
    /// nearby outward and blows apart every big rival inside it (the bomb itself becomes fragments too).
    /// Explosions are handled by `detonateSupernovas`, which runs right after this in the same step.
    private func triggerBombs() {
        for i in bodies.indices where bodies[i].kind == .bomb && !bodies[i].isSupernova {
            let bomb = bodies[i]
            let triggered = bodies.contains { other in
                other.id != bomb.id && World.isRival(other) && other.mass > bomb.mass * World.bombTriggerRatio
                    && (other.position - bomb.position).length - other.radius - bomb.radius < World.bombTriggerGap
            }
            guard triggered else { continue }
            bodies[i].fuse = time
            for j in bodies.indices where j != i && bodies[j].kind != .attractor {
                let d = bodies[j].position - bomb.position
                let distance = d.length
                guard distance > 1e-6, distance < World.blastRadius else { continue }
                let falloff = 1 - distance / World.blastRadius
                bodies[j].velocity += d / distance * (World.blastStrength * falloff)
                if World.isRival(bodies[j]), bodies[j].mass > bomb.mass * World.bombTriggerRatio {
                    bodies[j].fuse = min(bodies[j].fuse, time)
                }
            }
            explosions.append(Explosion(position: bomb.position, radius: World.blastRadius / 3))
        }
    }

    private func detonateSupernovas() {
        guard bodies.contains(where: { $0.fuse <= time }) else { return }
        let due = bodies.filter { $0.fuse <= time }
        bodies.removeAll { $0.fuse <= time }
        let count = World.supernovaFragments
        for star in due {
            if case .trap(let id) = goal, star.id == id { targetExploded = true }
            let fragmentMass = star.mass / Double(count)
            let fragmentRadius = Body.radius(forMass: fragmentMass)
            // Ring big enough that fragments don't touch each other at birth.
            let ring = max(star.radius * 1.25, fragmentRadius * Double(count) / .pi + 1)
            let offset = Double(star.id % 7) * 0.4
            for k in 0..<count {
                let angle = offset + 2 * .pi * Double(k) / Double(count)
                let dir = Vec2(cos(angle), sin(angle))
                bodies.append(Body(
                    id: nextID, kind: .mote,
                    position: star.position + dir * ring,
                    velocity: star.velocity + dir * 170,
                    mass: fragmentMass
                ))
                nextID += 1
            }
            explosions.append(Explosion(position: star.position, radius: star.radius))
        }
    }

    /// Where the player goes if nothing is touched: the player alone, under its current velocity,
    /// black-hole gravity, nebula drag and the walls. Other bodies are ignored (they drift, and a
    /// prediction that tracks them would jitter). Points are sampled every `sampleEvery` fixed steps.
    /// The path ends early where the player would fall into a black hole.
    public func predictPlayerPath(seconds: Double = 6, sampleEvery: Int = 12) -> [Vec2] {
        guard state == .playing, let player else { return [] }
        var p = player.position
        var v = player.velocity
        let radius = player.radius
        let wells = bodies.filter { $0.kind == .attractor }
        let soft2 = tuning.gravitySoftening * tuning.gravitySoftening
        let dt = World.fixedStep
        let steps = Int(seconds / dt)
        var points: [Vec2] = [p]
        for step in 1...max(steps, 1) {
            for well in wells {
                let d = well.position - p
                let r2 = d.x * d.x + d.y * d.y
                guard r2 > 1e-9 else { continue }
                let acceleration = tuning.gravity * well.mass / (r2 + soft2)
                v += d / r2.squareRoot() * (acceleration * dt)
            }
            if nebulae.contains(where: { $0.contains(p) }) {
                v *= max(1 - World.nebulaDrag * dt, 0)
            }
            p += v * dt
            if p.x < radius { p.x = radius; v.x = abs(v.x) * tuning.wallRestitution }
            if p.x > size.x - radius { p.x = size.x - radius; v.x = -abs(v.x) * tuning.wallRestitution }
            if p.y < radius { p.y = radius; v.y = abs(v.y) * tuning.wallRestitution }
            if p.y > size.y - radius { p.y = size.y - radius; v.y = -abs(v.y) * tuning.wallRestitution }
            if wells.contains(where: { ($0.position - p).length < $0.radius }) {
                points.append(p)
                break
            }
            if step % sampleEvery == 0 { points.append(p) }
        }
        return points
    }

    /// Number of fixed steps simulated so far. Replays key their inputs to it.
    public private(set) var stepCount = 0

    /// Orbital speed of each half of a double star with equal `mass` halves `separation` apart.
    public static func binarySpeed(mass: Double, separation d: Double, tuning: Tuning = Tuning()) -> Double {
        // Each half circles the centre at d/2 under the other's pull: v² / (d/2) = G·m / (d² + soft²).
        (d / 2 * tuning.gravity * mass / (d * d + tuning.gravitySoftening * tuning.gravitySoftening)).squareRoot()
    }

    /// Nothing smaller than the player is left, so it can't grow any more: suggest a restart.
    /// Not for "survive" levels, where growing isn't needed.
    public var isStuck: Bool {
        guard state == .playing, let player else { return false }
        switch goal {
        case .survive, .travel, .trap: return false // growing is not the point there
        default: break
        }
        // Comets keep shedding food, so a level with a comet is never a dead end.
        if bodies.contains(where: { $0.kind == .comet && $0.radius > 5 }) { return false }
        return !bodies.contains { body in
            body.id != playerID && body.kind != .antimatter && body.kind != .attractor && !World.isSolid(body.kind)
                && body.mass < player.mass
        }
    }

    /// 0…1 toward the goal; drives the ring around the player.
    public var goalProgress: Double {
        guard let player else { return 0 }
        switch goal {
        case .becomeBiggest:
            let biggest = bodies.lazy.filter { $0.id != self.playerID && World.isRival($0) }.map(\.mass).max() ?? 0
            return biggest > 0 ? min(player.mass / biggest, 1) : 1
        case .reachMass(let multiple):
            return min(player.mass / (initialPlayerMass * multiple), 1)
        case .survive(let seconds):
            return min(time / seconds, 1)
        case .eatTarget(let id):
            guard let target = bodies.first(where: { $0.id == id }) else { return 1 }
            return min(player.mass / target.mass, 1)
        case .eatAllHunters:
            let left = bodies.filter { $0.kind == .hunter }.count
            return initialHunters > 0 ? 1 - Double(left) / Double(initialHunters) : 1
        case .trap(let id):
            // How close the giant is to the nearest bomb: the ring fills as you lure it in.
            if targetExploded { return 1 }
            guard let target = bodies.first(where: { $0.id == id }) else { return 0 }
            let gaps = bodies.filter { $0.kind == .bomb }.map { ($0.position - target.position).length - $0.radius - target.radius }
            guard let nearest = gaps.min() else { return 0 }
            return min(max(1 - nearest / 1500, 0), 1)
        case .travel(let times):
            return min(Double(playerTeleports) / Double(max(times, 1)), 1)
        }
    }

    // MARK: - Input

    /// Ejects a small blob of the player's mass so the player accelerates toward `target`.
    /// - Parameter awayFromTarget: Osmos-style control (blob flies to the touch, player away from it).
    /// - Returns: false when there was nothing to do (no player, game over, zero direction).
    @discardableResult
    public func thrust(toward target: Vec2, awayFromTarget: Bool = false) -> Bool {
        guard state == .playing, let index = bodies.firstIndex(where: { $0.id == playerID }) else { return false }
        var direction = target - bodies[index].position
        if awayFromTarget { direction = -direction }
        let before = bodies[index].mass
        guard eject(from: index, accelerating: direction, fraction: tuning.ejectFraction) else { return false }
        playerEjectedMass += before - bodies[index].mass
        return true
    }

    /// Throws `fraction` of the body's mass backwards so the body accelerates along `direction`.
    private func eject(from index: Int, accelerating direction: Vec2, fraction: Double) -> Bool {
        let length = direction.length
        guard length > 1e-6 else { return false }
        let direction = direction / length
        var body = bodies[index]

        let ejectMass = body.mass * fraction
        let remaining = body.mass - ejectMass
        guard Body.radius(forMass: remaining) > World.minRadius * 4 else { return false }

        // Momentum conservation: m·v = (m − dm)·v' + dm·(v − dir·ve)
        body.velocity += direction * (ejectMass * tuning.ejectSpeed / remaining)
        body.mass = remaining

        let ejectRadius = Body.radius(forMass: ejectMass)
        let ejecta = Body(
            id: nextID,
            kind: .mote,
            position: body.position - direction * (body.radius + ejectRadius + 0.5),
            velocity: body.velocity - direction * tuning.ejectSpeed * (1 + ejectMass / remaining),
            mass: ejectMass
        )
        nextID += 1
        bodies[index] = body
        bodies.append(ejecta)
        return true
    }

    // MARK: - AI

    private static let aiInterval = 0.25
    private var nextAITime = 0.0

    /// Hunters re-plan 4 times a second. Pure function of world state, so replays stay deterministic.
    private func runAI() {
        // Splitters: when something bigger closes in, burst into two halves (decided first, applied after,
        // because splitting reorders the array).
        var splits: [(id: Int, threat: Vec2)] = []
        for me in bodies where me.kind == .splitter {
            for other in bodies where other.id != me.id && other.mass > me.mass && !World.isSolid(other.kind) {
                let gap = (other.position - me.position).length - other.radius - me.radius
                if gap < 70 {
                    splits.append((me.id, me.position - other.position))
                    break
                }
            }
        }
        for (id, threat) in splits {
            if let index = bodies.firstIndex(where: { $0.id == id }) { split(at: index, awayFrom: threat) }
        }

        // Fleers: dart away from the closest bigger body that gets near.
        for i in bodies.indices where bodies[i].kind == .fleer {
            let me = bodies[i]
            var closest: (gap: Double, body: Body)?
            for other in bodies where other.id != me.id && other.mass > me.mass && !World.isSolid(other.kind) {
                let gap = (other.position - me.position).length - other.radius - me.radius
                if gap < 140, gap < (closest?.gap ?? .infinity) { closest = (gap, other) }
            }
            if let threat = closest?.body {
                _ = eject(from: i, accelerating: me.position - threat.position, fraction: 0.015)
            }
        }

        let hunters = bodies.indices.filter { bodies[$0].kind == .hunter }
        for i in hunters {
            let hunter = bodies[i]
            var threat: Body?
            var prey: Body?
            var bestScore = 0.0
            for other in bodies where other.id != hunter.id {
                let distance = (other.position - hunter.position).length
                let gap = distance - other.radius - hunter.radius
                if (other.mass > hunter.mass && !World.isSolid(other.kind)) || other.kind == .antimatter {
                    if gap < 120, threat.map({ (($0.position - hunter.position).length) > distance }) ?? true { threat = other }
                } else if other.mass < hunter.mass * 0.85, other.kind != .antimatter, !World.isSolid(other.kind), gap < 600 {
                    // Prefer big, close meals.
                    let score = other.mass / max(gap, 20)
                    if score > bestScore { bestScore = score; prey = other }
                }
            }

            if let threat {
                _ = eject(from: i, accelerating: hunter.position - threat.position, fraction: 0.012)
            } else if let prey {
                let toPrey = prey.position - hunter.position
                let lead = toPrey.length / 150
                let aim = toPrey + (prey.velocity - hunter.velocity) * lead
                let desired = aim / max(aim.length, 1e-6) * 70
                let correction = desired - hunter.velocity
                if correction.length > 12 {
                    _ = eject(from: i, accelerating: correction, fraction: 0.006)
                }
            }
        }
    }

    // MARK: - Simulation

    /// Comets leave a grain behind them (2% of their mass), drifting slowly: a trail of food. Mass is conserved.
    private func shedCometDust() {
        for i in bodies.indices where bodies[i].kind == .comet && bodies[i].radius > 5 {
            let comet = bodies[i]
            let speed = comet.velocity.length
            guard speed > 1 else { continue }
            let back = -comet.velocity / speed
            let grainMass = comet.mass * 0.02
            let grainRadius = Body.radius(forMass: grainMass)
            bodies[i].mass -= grainMass
            bodies.append(Body(
                id: nextID, kind: .mote,
                position: comet.position + back * (bodies[i].radius + grainRadius + 1),
                velocity: comet.velocity * 0.08,
                mass: grainMass
            ))
            nextID += 1
        }
    }

    /// Moves bodies that fall into a wormhole mouth to just outside the other mouth, along their velocity.
    private func passWormholes() {
        guard !wormholes.isEmpty else { return }
        for i in bodies.indices where bodies[i].kind != .attractor && !World.isSolid(bodies[i].kind) {
            let body = bodies[i]
            for hole in wormholes where body.radius < hole.radius {
                let (entry, exit): (Vec2, Vec2)
                if (body.position - hole.a).length < hole.radius - body.radius {
                    (entry, exit) = (hole.a, hole.b)
                } else if (body.position - hole.b).length < hole.radius - body.radius {
                    (entry, exit) = (hole.b, hole.a)
                } else {
                    continue
                }
                let speed = body.velocity.length
                let dir = speed > 1e-6 ? body.velocity / speed : Vec2(1, 0)
                // Pop out beyond the far mouth so it doesn't fall straight back in.
                var out = exit + dir * (hole.radius + body.radius + 2)
                out.x = min(max(out.x, body.radius), size.x - body.radius)
                out.y = min(max(out.y, body.radius), size.y - body.radius)
                bodies[i].position = out
                teleports.append(Teleport(bodyID: body.id, from: entry, to: exit))
                if body.id == playerID { playerTeleports += 1 }
                break
            }
        }
    }

    /// Each pulsar kicks every other non-anchored body within reach straight away from itself.
    private func firePulsars() {
        let pulsars = bodies.filter { $0.kind == .pulsar }
        for pulsar in pulsars {
            for i in bodies.indices where bodies[i].id != pulsar.id && bodies[i].kind != .attractor && bodies[i].kind != .planet {
                let d = bodies[i].position - pulsar.position
                let distance = d.length
                let gap = distance - pulsar.radius
                guard distance > 1e-6, gap < World.pulseReach else { continue }
                let falloff = 1 - max(gap, 0) / World.pulseReach
                bodies[i].velocity += d / distance * (World.pulseStrength * falloff)
            }
            pulses.append(Pulse(position: pulsar.position, reach: World.pulseReach + pulsar.radius))
        }
    }

    /// Splits a body into two equal halves flying apart sideways to `threatDirection`. Mass and momentum are conserved.
    private func split(at index: Int, awayFrom threatDirection: Vec2) {
        let body = bodies[index]
        let halfMass = body.mass / 2
        let halfRadius = Body.radius(forMass: halfMass)
        let len = max(threatDirection.length, 1e-6)
        let side = Vec2(-threatDirection.y, threatDirection.x) / len
        bodies.remove(at: index)
        for sign in [-1.0, 1.0] {
            bodies.append(Body(
                id: nextID, kind: .mote,
                position: body.position + side * (halfRadius + 1) * sign,
                velocity: body.velocity + side * 90 * sign,
                mass: halfMass
            ))
            nextID += 1
        }
    }

    private func applyGravity(_ dt: Double) {
        let soft2 = tuning.gravitySoftening * tuning.gravitySoftening
        // Double stars: each binary pulls on the other binaries only (velocities from a snapshot,
        // so the pair stays symmetric and momentum is conserved).
        let binaries = bodies.indices.filter { bodies[$0].kind == .binary }
        if binaries.count > 1 {
            let snapshot = binaries.map { bodies[$0] }
            for (k, i) in binaries.enumerated() {
                for (m, other) in snapshot.enumerated() where m != k {
                    let d = other.position - snapshot[k].position
                    let r2 = d.x * d.x + d.y * d.y
                    guard r2 > 1e-9 else { continue }
                    let acceleration = tuning.gravity * other.mass / (r2 + soft2)
                    bodies[i].velocity += d / r2.squareRoot() * (acceleration * dt)
                }
            }
        }

        let attractors = bodies.filter { $0.kind == .attractor }
        guard !attractors.isEmpty else { return }
        for i in bodies.indices where bodies[i].kind != .attractor {
            for a in attractors {
                let d = a.position - bodies[i].position
                let r2 = d.x * d.x + d.y * d.y
                guard r2 > 1e-9 else { continue }
                let acceleration = tuning.gravity * a.mass / (r2 + soft2)
                bodies[i].velocity += d / r2.squareRoot() * (acceleration * dt)
            }
        }
    }

    private func integrate(_ dt: Double) {
        let wallRestitution = tuning.wallRestitution
        for i in bodies.indices {
            var b = bodies[i]
            // Comets keep their speed off the walls, so they stay comets.
            let restitution = b.kind == .comet ? 1.0 : wallRestitution
            if b.kind == .attractor {
                // Anchored: absorbing momentum must not drift it.
                b.velocity = .zero
                bodies[i] = b
                continue
            }
            if !nebulae.isEmpty, nebulae.contains(where: { $0.contains(b.position) }) {
                b.velocity *= max(1 - World.nebulaDrag * dt, 0)
            }
            b.position += b.velocity * dt
            let r = b.radius
            if b.position.x < r { b.position.x = r; b.velocity.x = abs(b.velocity.x) * restitution }
            if b.position.x > size.x - r { b.position.x = size.x - r; b.velocity.x = -abs(b.velocity.x) * restitution }
            if b.position.y < r { b.position.y = r; b.velocity.y = abs(b.velocity.y) * restitution }
            if b.position.y > size.y - r { b.position.y = size.y - r; b.velocity.y = -abs(b.velocity.y) * restitution }
            bodies[i] = b
        }
    }

    /// Sweep-and-prune on x, then mass transfer for every overlapping pair.
    private func resolveContacts() {
        let order = bodies.indices.sorted { bodies[$0].position.x - bodies[$0].radius < bodies[$1].position.x - bodies[$1].radius }
        for a in 0..<order.count {
            let i = order[a]
            for bIndex in (a + 1)..<order.count {
                let j = order[bIndex]
                let ri = bodies[i].radius
                guard ri > 0 else { break }
                if bodies[j].position.x - bodies[j].radius > bodies[i].position.x + ri { break }
                transferMass(i, j)
            }
        }
    }

    /// Planet contact: push apart and bounce instead of merging. A black hole still swallows planets.
    private func bounce(_ i: Int, _ j: Int) {
        var a = bodies[i]
        var b = bodies[j]
        let delta = b.position - a.position
        let distance = delta.length
        let overlap = a.radius + b.radius - distance
        guard overlap > 0, distance > 1e-9 else { return }
        let n = delta / distance
        func inertia(_ body: Body) -> Double { World.isSolid(body.kind) ? body.mass * World.planetInertia : body.mass }
        let invA = 1 / inertia(a)
        let invB = 1 / inertia(b)
        let share = invA / (invA + invB)
        // Separate in proportion to how easily each one moves.
        a.position -= n * (overlap * share)
        b.position += n * (overlap * (1 - share))
        let closing = (b.velocity - a.velocity).x * n.x + (b.velocity - a.velocity).y * n.y
        if closing < 0 {
            let impulse = -(1 + World.planetRestitution) * closing / (invA + invB)
            a.velocity -= n * (impulse * invA)
            b.velocity += n * (impulse * invB)
            if a.id == playerID || b.id == playerID { playerBounces += 1 }
        }
        bodies[i] = a
        bodies[j] = b
    }

    private func transferMass(_ i: Int, _ j: Int) {
        let planetContact = World.isSolid(bodies[i].kind) || World.isSolid(bodies[j].kind)
        let blackHoleContact = bodies[i].kind == .attractor || bodies[j].kind == .attractor
        if planetContact, !blackHoleContact {
            bounce(i, j)
            return
        }
        let iBigger = bodies[i].mass > bodies[j].mass || (bodies[i].mass == bodies[j].mass && bodies[i].id < bodies[j].id)
        let (bigIndex, smallIndex) = iBigger ? (i, j) : (j, i)
        var big = bodies[bigIndex]
        var small = bodies[smallIndex]
        guard small.mass > 0 else { return }

        let d = (big.position - small.position).length
        let (_, newSmallRadius) = MassTransfer.radiiAfterContact(big: big.radius, small: small.radius, distance: d)
        let newSmallMass = newSmallRadius < World.minRadius ? 0 : Body.mass(forRadius: newSmallRadius)
        let delta = small.mass - newSmallMass
        guard delta > 0 else { return }

        if (big.kind == .antimatter) != (small.kind == .antimatter) {
            // Matter meets antimatter: the same mass vanishes from both. Nobody grows.
            small.mass = newSmallMass
            big.mass = max(big.mass - delta, 0)
            if Body.radius(forMass: big.mass) < World.minRadius { big.mass = 0 }
            if small.mass == 0, case .eatTarget(let id) = goal, small.id == id { targetEatenBy = -1 }
            if big.mass == 0, case .eatTarget(let id) = goal, big.id == id { targetEatenBy = -1 }
            bodies[bigIndex] = big
            bodies[smallIndex] = small
            if events.count >= 2_000 { events.removeFirst(1_000) }
            events.append(ContactEvent(
                smallID: small.id, bigID: big.id, smallPosition: small.position,
                smallRadius: small.radius, mass: delta, swallowed: newSmallMass == 0, annihilation: true
            ))
            return
        }

        // Absorbed matter carries its momentum into the bigger body.
        big.velocity = (big.velocity * big.mass + small.velocity * delta) / (big.mass + delta)
        big.mass += delta
        small.mass = newSmallMass
        if newSmallMass == 0, big.id == playerID {
            playerSwallowCount += 1
            playerSwallowsByKind[small.kind, default: 0] += 1
        }
        if newSmallMass == 0, case .eatTarget(let id) = goal, small.id == id { targetEatenBy = big.id }
        if events.count >= 2_000 { events.removeFirst(1_000) }
        events.append(ContactEvent(
            smallID: small.id, bigID: big.id, smallPosition: small.position,
            smallRadius: small.radius, mass: delta, swallowed: newSmallMass == 0
        ))
        bodies[bigIndex] = big
        bodies[smallIndex] = small
    }

    private func updateState() {
        guard let player else {
            state = .lost
            lossReason = .eaten
            return
        }
        switch goal {
        case .becomeBiggest:
            let biggestOther = bodies.lazy.filter { $0.id != self.playerID && World.isRival($0) }.map(\.mass).max() ?? 0
            if player.mass > biggestOther { state = .won }
        case .reachMass(let multiple):
            if player.mass >= initialPlayerMass * multiple { state = .won }
        case .survive(let seconds):
            if time >= seconds { state = .won }
        case .trap(let id):
            if targetExploded {
                state = .won
            } else if !bodies.contains(where: { $0.id == id }) || !bodies.contains(where: { $0.kind == .bomb }) {
                // The giant was eaten, or the bomb is gone: the trap can't be sprung any more.
                state = .lost
                lossReason = .targetLost
            }
        case .eatTarget(let id):
            guard !bodies.contains(where: { $0.id == id }) else { return }
            if targetEatenBy == playerID {
                state = .won
            } else {
                // Swallowed by someone else, or blew up.
                state = .lost
                lossReason = .targetLost
            }
        case .eatAllHunters:
            if !bodies.contains(where: { $0.kind == .hunter }) { state = .won }
        case .travel(let times):
            if playerTeleports >= times { state = .won }
        }
    }
}

public enum MassTransfer {
    /// Radii after resolving an overlap: total area is preserved and the bodies end up just touching.
    ///
    /// Solves  R + r = d  and  R² + r² = R₀² + r₀²  for the smaller root r.
    /// Returns (big, small); `small` is 0 when the small body is swallowed completely.
    public static func radiiAfterContact(big: Double, small: Double, distance d: Double) -> (Double, Double) {
        guard d < big + small else { return (big, small) }
        let areaSum = big * big + small * small
        let smallRadius = (d - (max(2 * areaSum - d * d, 0)).squareRoot()) / 2
        if smallRadius <= 0 { return (areaSum.squareRoot(), 0) }
        return (d - smallRadius, smallRadius)
    }
}
