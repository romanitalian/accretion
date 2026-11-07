import XCTest

final class EngineTests: XCTestCase {
    func testContactPreservesAreaAndLeavesBodiesTouching() {
        let (big, small) = MassTransfer.radiiAfterContact(big: 10, small: 5, distance: 12)
        XCTAssertEqual(big * big + small * small, 125, accuracy: 1e-9)
        XCTAssertEqual(big + small, 12, accuracy: 1e-9)
        XCTAssertLessThan(small, 5)
    }

    func testDeepOverlapSwallowsSmallBody() {
        let (big, small) = MassTransfer.radiiAfterContact(big: 10, small: 3, distance: 2)
        XCTAssertEqual(small, 0)
        XCTAssertEqual(big * big, 109, accuracy: 1e-9)
    }

    func testNoTransferWithoutContact() {
        let (big, small) = MassTransfer.radiiAfterContact(big: 10, small: 5, distance: 15)
        XCTAssertEqual(big, 10)
        XCTAssertEqual(small, 5)
    }

    func testCollisionConservesMassAndMomentum() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), velocity: Vec2(5, 0), radius: 20),
            Body(id: 1, kind: .mote, position: Vec2(525, 500), velocity: Vec2(-3, 2), radius: 10),
            // A distant giant keeps the level running (otherwise the player wins on step one).
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 40),
        ], playerID: 0)
        let mass = world.totalMass
        let momentum = world.totalMomentum
        for _ in 0..<240 { world.step(World.fixedStep) }
        XCTAssertEqual(world.totalMass, mass, accuracy: mass * 1e-9)
        XCTAssertEqual(world.totalMomentum.x, momentum.x, accuracy: 1e-6)
        XCTAssertEqual(world.totalMomentum.y, momentum.y, accuracy: 1e-6)
        XCTAssertEqual(world.bodies.count, 2, "small body should be fully absorbed")
        XCTAssertEqual(world.state, .playing)
    }

    func testThrustConservesMassAndMomentumAndShrinksPlayer() throws {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20),
            Body(id: 1, kind: .mote, position: Vec2(100, 100), radius: 30),
        ], playerID: 0)
        let massBefore = try XCTUnwrap(world.player).mass
        XCTAssertTrue(world.thrust(toward: Vec2(600, 500)))
        let player = try XCTUnwrap(world.player)
        XCTAssertLessThan(player.mass, massBefore)
        XCTAssertGreaterThan(player.velocity.x, 0, "player moves toward the touch")
        XCTAssertEqual(world.totalMomentum.x, 0, accuracy: 1e-9)
        XCTAssertEqual(world.totalMass, massBefore + Body.mass(forRadius: 30), accuracy: 1e-6)
        // Ejecta must not be re-absorbed instantly.
        world.step(World.fixedStep)
        XCTAssertEqual(world.bodies.count, 3)
    }

    func testBiggerBodyEatsPlayer() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 10),
            Body(id: 1, kind: .mote, position: Vec2(530, 500), velocity: Vec2(-40, 0), radius: 25),
        ], playerID: 0)
        for _ in 0..<600 { world.step(World.fixedStep) }
        XCTAssertNil(world.player)
        XCTAssertEqual(world.state, .lost)
    }

    func testHunterChasesAndEatsSmallerBody() {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1800, 1800), radius: 5),
            Body(id: 1, kind: .hunter, position: Vec2(500, 500), radius: 20),
            Body(id: 2, kind: .mote, position: Vec2(800, 650), radius: 8),
            Body(id: 3, kind: .mote, position: Vec2(100, 1900), radius: 40),
        ], playerID: 0)
        for _ in 0..<(120 * 20) { world.step(World.fixedStep) }
        XCTAssertFalse(world.bodies.contains { $0.id == 2 }, "hunter should have caught its prey within 20 s")
        XCTAssertEqual(world.state, .playing)
    }

    func testHunterFleesBiggerBody() throws {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1000, 1100), radius: 40),
            Body(id: 1, kind: .hunter, position: Vec2(1000, 1000), radius: 15),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 50),
        ], playerID: 0)
        world.step(World.fixedStep)
        let hunter = try XCTUnwrap(world.bodies.first { $0.id == 1 })
        XCTAssertLessThan(hunter.velocity.y, 0, "hunter should push away from the bigger player")
    }

    func testPlayerSwallowsAreCounted() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20),
            Body(id: 1, kind: .mote, position: Vec2(505, 500), radius: 3),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 40),
        ], playerID: 0)
        world.step(World.fixedStep)
        XCTAssertEqual(world.playerSwallowCount, 1)
    }

    func testRatingStars() {
        XCTAssertEqual(LevelRating.stars(ejectedMass: 0, initialMass: 100), 3)
        XCTAssertEqual(LevelRating.stars(ejectedMass: 60, initialMass: 100), 3)
        XCTAssertEqual(LevelRating.stars(ejectedMass: 100, initialMass: 100), 2)
        XCTAssertEqual(LevelRating.stars(ejectedMass: 200, initialMass: 100), 1)
        XCTAssertEqual(LevelRating.stars(ejectedMass: 5, initialMass: 0), 1)
    }

    func testEjectedMassIsTracked() throws {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20),
            Body(id: 1, kind: .mote, position: Vec2(100, 100), radius: 30),
        ], playerID: 0)
        let start = world.initialPlayerMass
        world.thrust(toward: Vec2(600, 500))
        world.thrust(toward: Vec2(600, 500))
        let player = try XCTUnwrap(world.player)
        XCTAssertEqual(world.playerEjectedMass, start - player.mass, accuracy: 1e-9)
        XCTAssertGreaterThan(world.playerEjectedMass, 0)
    }

    func testContactEventsReportTransferAndSwallow() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20),
            Body(id: 1, kind: .mote, position: Vec2(505, 500), radius: 3),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 40),
        ], playerID: 0)
        world.step(World.fixedStep)
        let events = world.drainEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.bigID, 0)
        XCTAssertEqual(events.first?.smallID, 1)
        XCTAssertEqual(events.first?.swallowed, true)
        XCTAssertEqual(events.first?.mass ?? 0, Body.mass(forRadius: 3), accuracy: 1e-9)
        XCTAssertTrue(world.drainEvents().isEmpty, "drain empties the buffer")
    }

    func testCircularOrbitStaysStable() throws {
        let wellMass = Body.mass(forRadius: 55)
        let distance = 420.0
        let speed = World.orbitalSpeed(attractorMass: wellMass, distance: distance)
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1500 + distance, 1500), velocity: Vec2(0, speed), radius: 10),
            Body(id: 1, kind: .attractor, position: Vec2(1500, 1500), radius: 55),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 30),
        ], playerID: 0)
        for _ in 0..<(120 * 30) { world.step(World.fixedStep) } // more than half an orbit
        let player = try XCTUnwrap(world.player)
        XCTAssertEqual((player.position - Vec2(1500, 1500)).length, distance, accuracy: distance * 0.03)
        XCTAssertGreaterThan(world.time, 29)
    }

    func testAttractorStaysPutAndSwallowsPlayer() throws {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1000, 1200), radius: 15),
            Body(id: 1, kind: .attractor, position: Vec2(1000, 1000), radius: 55),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 30),
        ], playerID: 0)
        for _ in 0..<(120 * 15) { world.step(World.fixedStep) }
        XCTAssertEqual(world.state, .lost, "player falls in without thrust")
        let well = try XCTUnwrap(world.bodies.first { $0.kind == .attractor })
        XCTAssertEqual(well.position, Vec2(1000, 1000))
    }

    func testAttractorDoesNotBlockWinning() {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1000, 1700), radius: 30),
            Body(id: 1, kind: .attractor, position: Vec2(1000, 1000), radius: 55),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 20),
        ], playerID: 0)
        world.step(World.fixedStep)
        XCTAssertEqual(world.state, .won)
    }

    func testFleerRunsFromBiggerBody() throws {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1100, 1000), radius: 30),
            Body(id: 1, kind: .fleer, position: Vec2(1000, 1000), radius: 6),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 50),
        ], playerID: 0)
        world.step(World.fixedStep)
        let fleer = try XCTUnwrap(world.bodies.first { $0.id == 1 })
        XCTAssertLessThan(fleer.velocity.x, 0)
    }

    func testAttractorLevelsAreSolvableAndOrbiting() throws {
        for seed in 1...100 as ClosedRange<UInt64> {
            let world = LevelGenerator.makeWorld(seed: seed, difficulty: 0.3, attractor: true)
            XCTAssertTrue(LevelGenerator.isSolvable(world), "seed \(seed)")
            XCTAssertEqual(world.bodies.filter { $0.kind == .attractor }.count, 1)
            let player = try XCTUnwrap(world.player)
            XCTAssertGreaterThan(player.velocity.length, 10, "player starts on an orbit")
        }
    }

    // MARK: - Supernova

    func testSupernovaExplodesIntoFragmentsConservingMass() {
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(200, 200), radius: 10),
            Body(id: 1, kind: .mote, position: Vec2(1500, 1500), radius: 40, fuse: 1.0),
            Body(id: 2, kind: .mote, position: Vec2(2800, 2800), radius: 45),
        ], playerID: 0)
        let mass = world.totalMass
        for _ in 0..<(120 * 1 + 2) { world.step(World.fixedStep) }
        XCTAssertFalse(world.bodies.contains { $0.id == 1 })
        XCTAssertEqual(world.bodies.count, 2 + World.supernovaFragments)
        XCTAssertEqual(world.totalMass, mass, accuracy: mass * 1e-9)
        XCTAssertEqual(world.drainExplosions().count, 1)
        // Fragments fly apart instead of instantly re-merging.
        for _ in 0..<60 { world.step(World.fixedStep) }
        XCTAssertEqual(world.bodies.count, 2 + World.supernovaFragments)
    }

    func testGeneratorArmsOneSupernova() {
        let world = LevelGenerator.makeWorld(seed: 3, difficulty: 0.3, supernova: true)
        let armed = world.bodies.filter(\.isSupernova)
        XCTAssertEqual(armed.count, 1)
        XCTAssertTrue((18...32).contains(armed[0].fuse))
    }

    // MARK: - Goals

    func testReachMassGoal() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20),
            Body(id: 1, kind: .mote, position: Vec2(530, 500), velocity: Vec2(-20, 0), radius: 15),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 60),
        ], playerID: 0, goal: .reachMass(multiple: 1.5))
        for _ in 0..<240 { world.step(World.fixedStep) }
        XCTAssertEqual(world.state, .won)
    }

    func testSurviveGoal() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20),
            Body(id: 1, kind: .mote, position: Vec2(100, 100), radius: 60),
        ], playerID: 0, goal: .survive(seconds: 2))
        for _ in 0..<(120 * 2 - 10) { world.step(World.fixedStep) }
        XCTAssertEqual(world.state, .playing)
        XCTAssertGreaterThan(world.goalProgress, 0.9)
        for _ in 0..<20 { world.step(World.fixedStep) }
        XCTAssertEqual(world.state, .won)
    }

    func testEatTargetWonWhenPlayerSwallowsIt() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20),
            Body(id: 1, kind: .mote, position: Vec2(528, 500), velocity: Vec2(-20, 0), radius: 10),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 60),
        ], playerID: 0, goal: .eatTarget(id: 1))
        for _ in 0..<240 { world.step(World.fixedStep) }
        XCTAssertEqual(world.state, .won)
    }

    func testEatTargetLostWhenSomeoneElseSwallowsIt() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(100, 900), radius: 20),
            Body(id: 1, kind: .mote, position: Vec2(528, 500), velocity: Vec2(-20, 0), radius: 10),
            Body(id: 2, kind: .mote, position: Vec2(500, 500), radius: 25),
        ], playerID: 0, goal: .eatTarget(id: 1))
        for _ in 0..<240 { world.step(World.fixedStep) }
        XCTAssertEqual(world.state, .lost)
        XCTAssertEqual(world.lossReason, .targetLost)
    }

    func testEatenPlayerReportsReason() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 10),
            Body(id: 1, kind: .mote, position: Vec2(515, 500), radius: 30),
        ], playerID: 0)
        for _ in 0..<240 { world.step(World.fixedStep) }
        XCTAssertEqual(world.lossReason, .eaten)
    }

    func testEatTargetLevelsPickAReachableTarget() throws {
        for seed in 1...100 as ClosedRange<UInt64> {
            let world = LevelGenerator.makeWorld(seed: seed, difficulty: 0.4, goal: .eatTarget)
            guard case .eatTarget(let id) = world.goal else { return XCTFail("seed \(seed): no target") }
            let target = try XCTUnwrap(world.bodies.first { $0.id == id })
            let player = try XCTUnwrap(world.player)
            XCTAssertGreaterThan(target.mass, player.mass)
            XCTAssertFalse(target.isSupernova)
        }
    }

    // MARK: - Advanced objects

    /// A far, big rival keeps levels from ending on step one.
    private let anchor = Body(id: 99, kind: .mote, position: Vec2(60, 60), radius: 50)

    func testSplitterSplitsWhenThreatenedConservingMassAndMomentum() {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1000, 1060), radius: 30),
            Body(id: 1, kind: .splitter, position: Vec2(1000, 1000), velocity: Vec2(5, 0), radius: 16),
            anchor,
        ], playerID: 0)
        let mass = world.totalMass
        let momentum = world.totalMomentum
        world.step(World.fixedStep)
        XCTAssertFalse(world.bodies.contains { $0.id == 1 })
        XCTAssertEqual(world.bodies.count, 4)
        XCTAssertEqual(world.totalMass, mass, accuracy: 1e-6)
        XCTAssertEqual(world.totalMomentum.x, momentum.x, accuracy: 1e-6)
        XCTAssertEqual(world.totalMomentum.y, momentum.y, accuracy: 1e-6)
    }

    func testPulsarPushesNeighboursAway() throws {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1150, 1000), radius: 10),
            Body(id: 1, kind: .pulsar, position: Vec2(1000, 1000), radius: 26),
            anchor,
        ], playerID: 0)
        for _ in 0..<Int(World.pulseInterval * 120 + 2) { world.step(World.fixedStep) }
        let player = try XCTUnwrap(world.player)
        XCTAssertGreaterThan(player.velocity.x, 50)
        XCTAssertEqual(world.drainPulses().count, 1)
    }

    func testNebulaSlowsBodiesDown() throws {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1000, 1000), velocity: Vec2(100, 0), radius: 10),
            anchor,
        ], playerID: 0, nebulae: [World.Nebula(center: Vec2(1000, 1000), radius: 400)])
        for _ in 0..<120 { world.step(World.fixedStep) }
        let player = try XCTUnwrap(world.player)
        XCTAssertLessThan(player.velocity.x, 50)
        XCTAssertGreaterThan(player.velocity.x, 20)
    }

    func testAntimatterDestroysMassOnBothSides() throws {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1000, 1000), radius: 30),
            Body(id: 1, kind: .antimatter, position: Vec2(1035, 1000), velocity: Vec2(-30, 0), radius: 10),
            anchor,
        ], playerID: 0)
        let playerMass = try XCTUnwrap(world.player).mass
        let total = world.totalMass
        for _ in 0..<240 { world.step(World.fixedStep) }
        XCTAssertFalse(world.bodies.contains { $0.id == 1 }, "antimatter annihilated")
        let player = try XCTUnwrap(world.player)
        XCTAssertEqual(player.mass, playerMass - Body.mass(forRadius: 10), accuracy: 1)
        XCTAssertEqual(world.totalMass, total - 2 * Body.mass(forRadius: 10), accuracy: 1)
        XCTAssertFalse(World.isRival(Body(id: 5, kind: .antimatter, position: .zero, radius: 5)))
    }

    func testWormholeTeleportsSmallBodiesOnly() throws {
        let hole = World.Wormhole(a: Vec2(500, 500), b: Vec2(1500, 1500), radius: 46)
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(470, 500), velocity: Vec2(100, 0), radius: 10),
            Body(id: 1, kind: .mote, position: Vec2(500, 700), velocity: Vec2(0, -100), radius: 60),
            anchor,
        ], playerID: 0, wormholes: [hole])
        for _ in 0..<60 { world.step(World.fixedStep) }
        let player = try XCTUnwrap(world.player)
        XCTAssertGreaterThan(player.position.x, 1400, "player came out of the far mouth")
        XCTAssertGreaterThan(player.velocity.x, 90, "velocity kept")
        XCTAssertEqual(world.drainTeleports().count, 1)
        let big = try XCTUnwrap(world.bodies.first { $0.id == 1 })
        XCTAssertLessThan(big.position.x, 600, "too big to fit")
    }

    func testCometShedsDustAndKeepsSpeedOffWalls() throws {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(100, 900), radius: 10),
            Body(id: 1, kind: .comet, position: Vec2(500, 500), velocity: Vec2(240, 0), radius: 12),
            anchor,
        ], playerID: 0)
        let total = world.totalMass
        for _ in 0..<(120 * 3) { world.step(World.fixedStep) }
        XCTAssertEqual(world.totalMass, total, accuracy: total * 1e-9)
        XCTAssertGreaterThan(world.bodies.count, 10, "dust trail")
        let comet = try XCTUnwrap(world.bodies.first { $0.id == 1 })
        // It bounced off the right wall without losing speed there; re-eating its own trail slows it a little.
        XCTAssertLessThan(comet.velocity.x, 0, "bounced")
        XCTAssertGreaterThan(comet.velocity.length, 150, "still fast")
    }

    func testAdvancedLevelsContainTheirObjects() {
        let world = LevelGenerator.makeWorld(seed: 9, difficulty: 0.8, splitters: true, pulsar: true, nebula: true,
                                             antimatter: true, comets: true, wormholes: true)
        let kinds = Set(world.bodies.map(\.kind))
        for kind: Body.Kind in [.splitter, .pulsar, .antimatter, .comet] {
            XCTAssertTrue(kinds.contains(kind), "\(kind)")
        }
        XCTAssertFalse(world.nebulae.isEmpty)
        XCTAssertFalse(world.wormholes.isEmpty)
        XCTAssertTrue(LevelGenerator.isSolvable(world))
    }

    // MARK: - Double star, dead end, replay

    func testDoubleStarStaysInOrbit() throws {
        let m = Body.mass(forRadius: 30)
        let speed = World.binarySpeed(mass: m, separation: 240)
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(100, 100), radius: 10),
            Body(id: 1, kind: .binary, position: Vec2(1380, 1500), velocity: Vec2(0, -speed), radius: 30),
            Body(id: 2, kind: .binary, position: Vec2(1620, 1500), velocity: Vec2(0, speed), radius: 30),
        ], playerID: 0)
        let momentum = world.totalMomentum
        for _ in 0..<(120 * 20) { world.step(World.fixedStep) }
        let a = try XCTUnwrap(world.bodies.first { $0.id == 1 })
        let b = try XCTUnwrap(world.bodies.first { $0.id == 2 })
        XCTAssertEqual((a.position - b.position).length, 240, accuracy: 12, "separation holds")
        XCTAssertEqual(((a.position + b.position) / 2 - Vec2(1500, 1500)).length, 0, accuracy: 1, "centre stays")
        XCTAssertEqual(world.totalMomentum.x, momentum.x, accuracy: 1e-6)
    }

    func testGeneratorBuildsOneDoubleStar() {
        let world = LevelGenerator.makeWorld(seed: 4, difficulty: 0.6, binaries: true)
        XCTAssertEqual(world.bodies.filter { $0.kind == .binary }.count, 2)
    }

    func testStuckWhenNothingSmallerIsLeft() {
        let stuck = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 10),
            Body(id: 1, kind: .mote, position: Vec2(100, 100), radius: 30),
            Body(id: 2, kind: .antimatter, position: Vec2(900, 900), radius: 3),
        ], playerID: 0)
        XCTAssertTrue(stuck.isStuck, "antimatter doesn't count as food")

        let fine = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 10),
            Body(id: 1, kind: .mote, position: Vec2(100, 100), radius: 30),
            Body(id: 2, kind: .mote, position: Vec2(900, 900), radius: 3),
        ], playerID: 0)
        XCTAssertFalse(fine.isStuck)

        let survive = World(size: Vec2(1000, 1000), bodies: stuck.bodies, playerID: 0, goal: .survive(seconds: 30))
        XCTAssertFalse(survive.isStuck, "survive levels never dead-end")
    }

    /// The replay contract: the same thrusts on the same step numbers reproduce the run exactly.
    func testReplayReproducesRun() {
        let spec = GameProgress.spec(for: .campaign(level: 7))
        let live = spec.makeWorld()
        var inputs: [Replay.Input] = []
        for i in 0..<1_500 {
            if i % 37 == 0 {
                let target = Vec2(Double(i % 900) + 100, Double((i * 7) % 900) + 100)
                if live.thrust(toward: target) {
                    inputs.append(Replay.Input(step: live.stepCount, x: target.x, y: target.y, away: false))
                }
            }
            live.step(World.fixedStep)
        }

        let replayed = spec.makeWorld()
        var cursor = 0
        // A finished world stops counting steps, so loop a fixed number of times (like the live run did).
        for _ in 0..<1_500 {
            while cursor < inputs.count, inputs[cursor].step <= replayed.stepCount {
                replayed.thrust(toward: Vec2(inputs[cursor].x, inputs[cursor].y))
                cursor += 1
            }
            replayed.step(World.fixedStep)
        }
        XCTAssertEqual(replayed.bodies, live.bodies)
        XCTAssertEqual(replayed.state, live.state)
    }

    func testBestReplayPrefersStarsThenTime() throws {
        let slow3 = Replay(stars: 3, time: 90, inputs: [])
        let fast3 = Replay(stars: 3, time: 60, inputs: [])
        let fast2 = Replay(stars: 2, time: 30, inputs: [])
        XCTAssertTrue(fast3.isBetter(than: slow3))
        XCTAssertFalse(fast2.isBetter(than: slow3))
        XCTAssertTrue(fast2.isBetter(than: nil))
        let data = try JSONEncoder().encode(Replay(stars: 1, time: 5, inputs: [.init(step: 3, x: 1, y: 2, away: true)]))
        XCTAssertEqual(try JSONDecoder().decode(Replay.self, from: data).inputs.first?.step, 3)
    }

    // MARK: - New goals, stats, achievements

    func testEatAllHuntersGoal() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20),
            Body(id: 1, kind: .hunter, position: Vec2(526, 500), velocity: Vec2(-20, 0), radius: 8),
            Body(id: 2, kind: .mote, position: Vec2(60, 60), radius: 50),
        ], playerID: 0, goal: .eatAllHunters)
        XCTAssertEqual(world.initialHunters, 1)
        for _ in 0..<240 { world.step(World.fixedStep) }
        XCTAssertEqual(world.state, .won)
        XCTAssertEqual(world.playerSwallowsByKind[.hunter], 1)
    }

    func testTravelGoalCountsPlayerTeleports() {
        let hole = World.Wormhole(a: Vec2(500, 500), b: Vec2(1500, 1500), radius: 46)
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(470, 500), velocity: Vec2(100, 0), radius: 10),
            Body(id: 2, kind: .mote, position: Vec2(60, 60), radius: 50),
        ], playerID: 0, goal: .travel(times: 1), wormholes: [hole])
        XCTAssertFalse(world.isStuck, "travel levels don't need growth")
        for _ in 0..<60 { world.step(World.fixedStep) }
        XCTAssertEqual(world.playerTeleports, 1)
        XCTAssertEqual(world.state, .won)
    }

    func testWormholeLevelsGetTravelGoal() {
        let spec = GameProgress.spec(for: .campaign(level: 12))
        XCTAssertTrue(spec.wormholes)
        guard case .travel = spec.makeWorld().goal else { return XCTFail("expected a travel goal") }
    }

    func testAchievementUnlocksOnlyOnce() {
        let key = "accretion.achievements"
        let saved = UserDefaults.standard.stringArray(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(AchievementStore.unlock(.firstWin))
        XCTAssertFalse(AchievementStore.unlock(.firstWin))
        XCTAssertTrue(AchievementStore.isUnlocked(.firstWin))
        XCTAssertFalse(AchievementStore.isUnlocked(.zen))
    }

    func testSkinsCostMoreAsTheyGo() {
        let costs = Skin.allCases.map(\.cost)
        XCTAssertEqual(costs.first, 0, "default skin is free")
        XCTAssertEqual(costs, costs.sorted())
    }

    // MARK: - Planets

    func testPlayerBouncesOffPlanetWithoutMerging() throws {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(900, 1000), velocity: Vec2(80, 0), radius: 15),
            Body(id: 1, kind: .planet, position: Vec2(1000, 1000), radius: 30),
            Body(id: 2, kind: .mote, position: Vec2(60, 60), radius: 50),
        ], playerID: 0)
        let playerMass = try XCTUnwrap(world.player).mass
        let planetMass = try XCTUnwrap(world.bodies.first { $0.id == 1 }).mass
        for _ in 0..<240 { world.step(World.fixedStep) }
        let player = try XCTUnwrap(world.player)
        let planet = try XCTUnwrap(world.bodies.first { $0.id == 1 })
        XCTAssertEqual(player.mass, playerMass, "no mass changes hands")
        XCTAssertEqual(planet.mass, planetMass)
        XCTAssertLessThan(player.velocity.x, -50, "bounced back")
        XCTAssertLessThan(planet.velocity.length, 10, "planet barely moves")
        XCTAssertEqual(world.playerBounces, 1)
        XCTAssertGreaterThanOrEqual((player.position - planet.position).length, player.radius + planet.radius - 0.5)
    }

    func testBlackHoleStillSwallowsPlanets() {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(100, 100), radius: 10),
            Body(id: 1, kind: .attractor, position: Vec2(1000, 1000), radius: 55),
            Body(id: 2, kind: .planet, position: Vec2(1000, 1200), radius: 25),
            Body(id: 3, kind: .mote, position: Vec2(1900, 1900), radius: 50),
        ], playerID: 0)
        for _ in 0..<(120 * 15) { world.step(World.fixedStep) }
        XCTAssertFalse(world.bodies.contains { $0.id == 2 })
    }

    func testPlanetsAreNotFoodOrRivals() {
        let planet = Body(id: 5, kind: .planet, position: .zero, radius: 30)
        XCTAssertFalse(World.isRival(planet))
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 40),
            Body(id: 1, kind: .planet, position: Vec2(100, 100), radius: 20),
            Body(id: 2, kind: .mote, position: Vec2(900, 900), radius: 45),
        ], playerID: 0)
        XCTAssertTrue(world.isStuck, "a smaller planet is not something you can eat")
        let level = LevelGenerator.makeWorld(seed: 5, difficulty: 0.4, attractor: true, planets: true)
        XCTAssertGreaterThanOrEqual(level.bodies.filter { $0.kind == .planet }.count, 2)
        XCTAssertTrue(LevelGenerator.isSolvable(level))
    }

    func testSimulationIsDeterministic() {
        func run() -> [Body] {
            let world = LevelGenerator.makeWorld(seed: 7, difficulty: 0.5)
            for i in 0..<2_000 {
                if i % 10 == 0 { world.thrust(toward: Vec2(0, 0)) }
                world.step(World.fixedStep)
            }
            return world.bodies
        }
        XCTAssertEqual(run(), run())
    }

    func testGeneratedLevelsAreSolvable() {
        for seed in 1...300 as ClosedRange<UInt64> {
            let world = LevelGenerator.makeWorld(seed: seed, difficulty: Double(seed % 10) / 10)
            XCTAssertTrue(LevelGenerator.isSolvable(world), "seed \(seed)")
            XCTAssertEqual(world.state, .playing)
        }
    }
}

// MARK: - Audio output (checked offline: no device needed)

final class AudioOutputTests: XCTestCase {
    /// The pad must produce real signal, not silence, and never NaN/inf.
    func testPadRendersAudibleSignal() {
        let synth = PadSynth()
        synth.sampleRate = 44_100
        synth.musicTarget = 1
        var buffer = [Float](repeating: 0, count: 44_100 * 6)
        buffer.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, frames: $0.count) }
        let tail = buffer.suffix(44_100 * 4)
        let rms = (tail.reduce(0) { $0 + Double($1) * Double($1) } / Double(tail.count)).squareRoot()
        XCTAssertTrue(buffer.allSatisfy { $0.isFinite })
        XCTAssertGreaterThan(rms, 0.001, "pad should be audible, RMS=\(rms)")
    }

    /// Swallow chime and supernova boom must also produce sound when triggered.
    func testEffectsRenderSound() {
        let synth = PadSynth()
        synth.sampleRate = 44_100
        synth.musicTarget = 0
        synth.requestChime()
        var buffer = [Float](repeating: 0, count: 44_100)
        buffer.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, frames: $0.count) }
        let peak = buffer.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.001, "chime should be audible, peak=\(peak)")
    }

    /// Volume 0 must mute the pad completely.
    func testMuteSilencesPad() {
        let synth = PadSynth()
        synth.sampleRate = 44_100
        synth.musicTarget = 0
        // Gain fades out over about a second, so check the last second of an 8-second render.
        var buffer = [Float](repeating: 0, count: 44_100 * 8)
        buffer.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, frames: $0.count) }
        XCTAssertLessThan(buffer.suffix(44_100).map { abs($0) }.max() ?? 1, 1e-4)
    }
}

// MARK: - Soundscape: sound that carries the picture

final class SoundscapeTests: XCTestCase {
    private func render(_ synth: PadSynth, seconds: Double) -> (left: [Float], right: [Float]) {
        let frames = Int(44_100 * seconds)
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                synth.renderStereo(left: l.baseAddress!, right: r.baseAddress!, frames: frames)
            }
        }
        return (left, right)
    }

    private func soloSynth(_ voice: SoundscapeVoice) -> PadSynth {
        let synth = PadSynth()
        synth.sampleRate = 44_100
        synth.musicTarget = 0
        synth.sfxGain = 1
        synth.setVoices([voice])
        return synth
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        (samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(samples.count, 1))).squareRoot()
    }

    /// Frequency measured by counting zero crossings over the last second (music has faded out by then).
    private func measuredFrequency(_ samples: [Float]) -> Double {
        let tail = samples.suffix(44_100)
        var crossings = 0
        var previous = tail.first ?? 0
        for sample in tail.dropFirst() {
            if (sample >= 0) != (previous >= 0) { crossings += 1 }
            previous = sample
        }
        return Double(crossings) / 2
    }

    func testLeftVoiceIsHeardInLeftEarOnly() {
        let synth = soloSynth(SoundscapeVoice(frequency: 440, pan: -1, gain: 1, timbre: .sine))
        let out = render(synth, seconds: 6)
        XCTAssertGreaterThan(rms(out.left.suffix(44_100)), 0.02, "voice should be audible on the left")
        XCTAssertLessThan(rms(out.right.suffix(44_100)), 1e-4, "and silent on the right")
    }

    func testCentreVoiceIsInBothEars() {
        let synth = soloSynth(SoundscapeVoice(frequency: 440, pan: 0, gain: 1, timbre: .sine))
        let out = render(synth, seconds: 6)
        let left = rms(out.left.suffix(44_100))
        let right = rms(out.right.suffix(44_100))
        XCTAssertGreaterThan(left, 0.02)
        XCTAssertEqual(left, right, accuracy: left * 0.05)
    }

    func testRenderedPitchMatchesVoiceFrequency() {
        for target in [220.0, 880.0] {
            let synth = soloSynth(SoundscapeVoice(frequency: target, pan: 0, gain: 1, timbre: .sine))
            let out = render(synth, seconds: 6)
            XCTAssertEqual(measuredFrequency(out.left), target, accuracy: target * 0.03, "target \(target) Hz")
        }
    }

    func testSmallObjectsSingHigherThanBigOnes() throws {
        let player = Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20)
        let small = Soundscape.voice(for: Body(id: 1, kind: .mote, position: Vec2(600, 500), radius: 4), player: player,
                                     distance: 100, screenX: 0, reach: 900)
        let big = Soundscape.voice(for: Body(id: 2, kind: .mote, position: Vec2(600, 500), radius: 45), player: player,
                                   distance: 100, screenX: 0, reach: 900)
        XCTAssertGreaterThan(small.frequency, big.frequency * 4, "small ≫ big in pitch")
        XCTAssertEqual(big.timbre, .threat, "a body bigger than you sounds like danger")
        let hole = Soundscape.voice(for: Body(id: 3, kind: .attractor, position: Vec2(600, 500), radius: 55), player: player,
                                    distance: 300, screenX: 0, reach: 1500)
        XCTAssertLessThan(hole.frequency, 100, "black hole growls")
        XCTAssertEqual(hole.timbre, .rumble)
    }

    func testBiggerThanPlayerSoundsLikeThreat() {
        let player = Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20)
        let giant = Soundscape.voice(for: Body(id: 1, kind: .mote, position: Vec2(600, 500), radius: 40), player: player,
                                     distance: 100, screenX: 0, reach: 900)
        XCTAssertEqual(giant.timbre, .threat)
    }

    func testCloserIsLouderAndFarIsSilent() {
        let player = Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 20)
        let body = Body(id: 1, kind: .mote, position: Vec2(0, 0), radius: 20)
        let near = Soundscape.voice(for: body, player: player, distance: 100, screenX: 0, reach: 900)
        let far = Soundscape.voice(for: body, player: player, distance: 700, screenX: 0, reach: 900)
        XCTAssertGreaterThan(near.gain, far.gain)
        let beyond = Soundscape.voices(
            world: World(size: Vec2(3000, 3000), bodies: [player, Body(id: 2, kind: .mote, position: Vec2(2500, 500), radius: 20)], playerID: 0),
            cameraCenter: Vec2(500, 500), halfWidth: 200)
        XCTAssertTrue(beyond.isEmpty, "nothing within reach, nothing sounds")
    }

    func testPanFollowsScreenPosition() {
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1500, 1500), radius: 20),
            Body(id: 1, kind: .mote, position: Vec2(1500 + 150, 1500), radius: 15),
            Body(id: 2, kind: .mote, position: Vec2(1500 - 150, 1500), radius: 15),
        ], playerID: 0)
        let voices = Soundscape.voices(world: world, cameraCenter: Vec2(1500, 1500), halfWidth: 300)
        XCTAssertEqual(voices.count, 2)
        XCTAssertEqual(voices.filter { $0.pan > 0.4 }.count, 1, "one object is on the right")
        XCTAssertEqual(voices.filter { $0.pan < -0.4 }.count, 1, "one object is on the left")
    }

    func testNoMoreThanSixVoicesNearestFirst() {
        var bodies = [Body(id: 0, kind: .player, position: Vec2(1500, 1500), radius: 20)]
        for i in 1...12 {
            bodies.append(Body(id: i, kind: .mote, position: Vec2(1500 + Double(i) * 40, 1500), radius: 8))
        }
        let world = World(size: Vec2(3000, 3000), bodies: bodies, playerID: 0)
        let voices = Soundscape.voices(world: world, cameraCenter: Vec2(1500, 1500), halfWidth: 1000)
        XCTAssertEqual(voices.count, Soundscape.maxVoices)
        XCTAssertGreaterThanOrEqual(voices.first?.gain ?? 0, voices.last?.gain ?? 1, "nearest is loudest")
    }
}

// MARK: - Trajectory prediction

final class TrajectoryTests: XCTestCase {
    func testFreeFlightIsAStraightLine() {
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(100, 500), velocity: Vec2(100, 0), radius: 10),
            Body(id: 1, kind: .mote, position: Vec2(2900, 2900), radius: 20),
        ], playerID: 0)
        let path = world.predictPlayerPath()
        XCTAssertEqual(path.count, 61, "start + one point per 0.1 s for 6 s")
        XCTAssertEqual(path.first?.x ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(path.last?.x ?? 0, 100 + 100 * 6, accuracy: 1e-6)
        XCTAssertTrue(path.allSatisfy { abs($0.y - 500) < 1e-9 }, "no sideways drift")
    }

    func testPathDoesNotMoveTheRealWorld() {
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(100, 500), velocity: Vec2(100, 0), radius: 10),
            Body(id: 1, kind: .mote, position: Vec2(2900, 2900), radius: 20),
        ], playerID: 0)
        _ = world.predictPlayerPath()
        XCTAssertEqual(world.player?.position, Vec2(100, 500), "prediction is read-only")
        XCTAssertEqual(world.stepCount, 0)
    }

    func testFallingIntoBlackHoleEndsThePath() throws {
        let world = World(size: Vec2(2000, 2000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1000, 1200), radius: 10),
            Body(id: 1, kind: .attractor, position: Vec2(1000, 1000), radius: 55),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 30),
        ], playerID: 0)
        let path = world.predictPlayerPath()
        XCTAssertLessThan(path.count, 61, "stops early")
        let last = try XCTUnwrap(path.last)
        XCTAssertLessThan((last - Vec2(1000, 1000)).length, 55 + 1, "ends at the black hole")
    }

    func testOrbitPathStaysOnACircle() {
        let distance = 420.0
        let speed = World.orbitalSpeed(attractorMass: Body.mass(forRadius: 55), distance: distance)
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1500 + distance, 1500), velocity: Vec2(0, speed), radius: 10),
            Body(id: 1, kind: .attractor, position: Vec2(1500, 1500), radius: 55),
            Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 30),
        ], playerID: 0)
        let path = world.predictPlayerPath(seconds: 6)
        XCTAssertEqual(path.count, 61, "an orbit never falls in")
        for point in path {
            XCTAssertEqual((point - Vec2(1500, 1500)).length, distance, accuracy: distance * 0.03)
        }
    }

    func testNoPredictionWhenNotPlaying() {
        let world = World(size: Vec2(1000, 1000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(500, 500), radius: 10),
        ], playerID: 0)
        world.step(World.fixedStep)
        XCTAssertNotEqual(world.state, .playing, "the level is over (here: the player is alone, so it is won)")
        XCTAssertTrue(world.predictPlayerPath().isEmpty)
    }
}

// MARK: - Bomb and trap

final class TrapTests: XCTestCase {
    private func trapWorld(giantAt giant: Vec2, giantVelocity: Vec2 = .zero) -> World {
        World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(200, 200), radius: 20),
            Body(id: 1, kind: .hunter, position: giant, velocity: giantVelocity, radius: 60),
            Body(id: 2, kind: .bomb, position: Vec2(1500, 1500), radius: 16),
        ], playerID: 0, goal: .trap(target: 1))
    }

    func testGiantNearBombBlowsUpAndWins() {
        // Giant drifting into the bomb's trigger range.
        let world = trapWorld(giantAt: Vec2(1500 + 16 + 60 + 50, 1500), giantVelocity: Vec2(-40, 0))
        for _ in 0..<240 where world.state == .playing { world.step(World.fixedStep) }
        XCTAssertTrue(world.targetExploded)
        XCTAssertEqual(world.state, .won)
        XCTAssertFalse(world.bodies.contains { $0.id == 1 }, "giant is now fragments")
        XCTAssertFalse(world.bodies.contains { $0.kind == .bomb }, "bomb went off")
    }

    func testBlastConservesMassAndPushesNeighboursAway() throws {
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1500, 1700), radius: 20),
            Body(id: 1, kind: .hunter, position: Vec2(1500 + 16 + 60 + 40, 1500), radius: 60),
            Body(id: 2, kind: .bomb, position: Vec2(1500, 1500), radius: 16),
            Body(id: 3, kind: .mote, position: Vec2(100, 2900), radius: 70),
        ], playerID: 0, goal: .trap(target: 1))
        let mass = world.totalMass
        world.step(World.fixedStep)
        XCTAssertEqual(world.totalMass, mass, accuracy: mass * 1e-9, "bomb and giant become fragments, nothing vanishes")
        let player = try XCTUnwrap(world.player)
        XCTAssertGreaterThan(player.velocity.y, 50, "player inside the blast is thrown away from it")
    }

    func testSmallBodiesAndPlayerDoNotSetItOff() {
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1500 + 16 + 22 + 10, 1500), radius: 22),
            Body(id: 1, kind: .hunter, position: Vec2(200, 200), radius: 60),
            Body(id: 2, kind: .bomb, position: Vec2(1500, 1500), radius: 16),
            Body(id: 3, kind: .mote, position: Vec2(1500, 1500 + 40), radius: 8),
        ], playerID: 0, goal: .trap(target: 1))
        for _ in 0..<60 { world.step(World.fixedStep) }
        XCTAssertTrue(world.bodies.contains { $0.kind == .bomb }, "player and small motes are safe near it")
        XCTAssertFalse(world.targetExploded)
    }

    func testBombIsSolid() throws {
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1400, 1500), velocity: Vec2(80, 0), radius: 20),
            Body(id: 2, kind: .bomb, position: Vec2(1500, 1500), radius: 16),
            Body(id: 3, kind: .mote, position: Vec2(100, 2900), radius: 70),
        ], playerID: 0)
        let mass = try XCTUnwrap(world.player).mass
        for _ in 0..<180 { world.step(World.fixedStep) }
        let player = try XCTUnwrap(world.player)
        XCTAssertEqual(player.mass, mass, "you can't eat the bomb")
        XCTAssertLessThan(player.velocity.x, 0, "you bounce off it")
        XCTAssertFalse(World.isRival(Body(id: 9, kind: .bomb, position: .zero, radius: 16)))
    }

    func testTrapLostWhenBombIsGone() {
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(200, 200), radius: 20),
            Body(id: 1, kind: .hunter, position: Vec2(2500, 2500), radius: 60),
        ], playerID: 0, goal: .trap(target: 1))
        world.step(World.fixedStep)
        XCTAssertEqual(world.state, .lost)
        XCTAssertEqual(world.lossReason, .targetLost)
    }

    func testGiantHuntsThePlayer() throws {
        let world = World(size: Vec2(3000, 3000), bodies: [
            Body(id: 0, kind: .player, position: Vec2(1000, 1500), radius: 20),
            Body(id: 1, kind: .hunter, position: Vec2(1400, 1500), radius: 60),
            Body(id: 2, kind: .bomb, position: Vec2(2800, 2800), radius: 16),
        ], playerID: 0, goal: .trap(target: 1))
        for _ in 0..<(120 * 3) { world.step(World.fixedStep) }
        let giant = try XCTUnwrap(world.bodies.first { $0.id == 1 })
        XCTAssertLessThan(giant.velocity.x, -5, "the giant comes for you: that is the lure")
    }

    func testTrapLevelsAreBuilt() throws {
        let spec = GameProgress.spec(for: .campaign(level: 14))
        XCTAssertFalse(spec.attractor, "no black hole to swallow the giant")
        let world = spec.makeWorld()
        guard case .trap(let id) = world.goal else { return XCTFail("expected a trap goal") }
        let giant = try XCTUnwrap(world.bodies.first { $0.id == id })
        XCTAssertEqual(giant.kind, .hunter)
        XCTAssertGreaterThan(giant.mass, try XCTUnwrap(world.player).mass * 3)
        XCTAssertEqual(world.bodies.filter { $0.kind == .bomb }.count, 1)
    }
}

// MARK: - Playfield size

final class WorldSizeTests: XCTestCase {
    private func setSize(_ size: WorldSize) {
        UserDefaults.standard.set(size.rawValue, forKey: SettingsKey.worldSize)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.worldSize)
        super.tearDown()
    }

    func testFieldScalesAndDensityStaysTheSame() {
        let normal = LevelGenerator.makeWorld(seed: 11, difficulty: 0.4, space: 1)
        let huge = LevelGenerator.makeWorld(seed: 11, difficulty: 0.4, space: 1.5)
        let compact = LevelGenerator.makeWorld(seed: 11, difficulty: 0.4, space: 0.7)
        XCTAssertEqual(huge.size.x, normal.size.x * 1.5, accuracy: 1e-9)
        XCTAssertEqual(compact.size.x, normal.size.x * 0.7, accuracy: 1e-9)

        func density(_ w: World) -> Double { Double(w.bodies.count) / (w.size.x * w.size.y) }
        XCTAssertEqual(density(huge), density(normal), accuracy: density(normal) * 0.25)
        XCTAssertEqual(density(compact), density(normal), accuracy: density(normal) * 0.25)
        XCTAssertGreaterThan(huge.bodies.count, normal.bodies.count * 2)
    }

    func testEverySizeStillMakesSolvableLevels() {
        for space in [0.7, 1.5] {
            for seed in 1...40 as ClosedRange<UInt64> {
                let world = LevelGenerator.makeWorld(seed: seed, difficulty: Double(seed % 10) / 10, space: space)
                XCTAssertTrue(LevelGenerator.isSolvable(world), "seed \(seed), space \(space)")
            }
        }
    }

    func testSettingDrivesTheLevelSpec() {
        setSize(.huge)
        XCTAssertEqual(GameProgress.spec(for: .campaign(level: 3)).space, 1.5)
        setSize(.compact)
        XCTAssertEqual(GameProgress.spec(for: .daily(day: 20261105)).space, 0.7)
    }

    func testStarsAreKeptPerSize() {
        let level = 987_654
        let keys = WorldSize.allCases.map { "accretion.stars.\(level)\($0.keySuffix)" }
        defer { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        setSize(.huge)
        GameProgress.record(stars: 3, for: .campaign(level: level))
        XCTAssertEqual(GameProgress.stars(level: level, size: .huge), 3)
        XCTAssertEqual(GameProgress.stars(level: level, size: .normal), 0, "huge doesn't count as normal")
        XCTAssertEqual(GameProgress.bestStars(level: level), 3, "skins use the best of any size")
    }

    func testTrapFitsOnCompactField() {
        setSize(.compact)
        let world = GameProgress.spec(for: .campaign(level: 14)).makeWorld()
        guard case .trap = world.goal else { return XCTFail("trap should still fit on a compact field") }
    }
}
