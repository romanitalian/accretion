import Foundation

public typealias Vec2 = SIMD2<Double>

/// A circular celestial body. Mass is proportional to area: m = π r².
public struct Body: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case player
        case mote
        /// Steers toward smaller bodies and flees bigger ones, paying for it with its own mass.
        case hunter
        /// Small and skittish: only runs away from bigger bodies.
        case fleer
        /// Fixed in place, pulls everything with gravity, swallows what touches it. Never counts toward winning.
        case attractor
        /// Splits into two halves that scatter when something bigger gets close.
        case splitter
        /// Every few seconds pushes everything around it away.
        case pulsar
        /// Touching it destroys equal mass on both sides. Dangerous at any size.
        case antimatter
        /// Fast, bounces without losing speed, sheds a trail of edible dust.
        case comet
        /// Half of a double star: binaries pull only on each other and circle their common centre.
        case binary
        /// A lost cosmonaut, tumbling slowly. Tiny, harmless, edible. For the sense of scale (and an achievement).
        case astronaut
        /// Solid: never merges, everything bounces off it. Orbits a black hole or hangs still.
        case planet
        /// Solid and unstable: goes off when something much bigger comes close, blasting nearby giants apart.
        case bomb
    }

    public let id: Int
    public var kind: Kind
    public var position: Vec2
    public var velocity: Vec2
    public var mass: Double
    /// World time at which this body explodes as a supernova; `.infinity` = never.
    public var fuse: Double

    public init(id: Int, kind: Kind, position: Vec2, velocity: Vec2 = .zero, mass: Double, fuse: Double = .infinity) {
        self.id = id
        self.kind = kind
        self.position = position
        self.velocity = velocity
        self.mass = mass
        self.fuse = fuse
    }

    public init(id: Int, kind: Kind, position: Vec2, velocity: Vec2 = .zero, radius: Double, fuse: Double = .infinity) {
        self.init(id: id, kind: kind, position: position, velocity: velocity, mass: Body.mass(forRadius: radius), fuse: fuse)
    }

    public var isSupernova: Bool { fuse.isFinite }

    public var radius: Double { Body.radius(forMass: mass) }

    public static func radius(forMass mass: Double) -> Double { (max(mass, 0) / .pi).squareRoot() }
    public static func mass(forRadius radius: Double) -> Double { .pi * radius * radius }
}

extension Vec2 {
    var length: Double { (x * x + y * y).squareRoot() }
}
