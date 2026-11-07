import SpriteKit
import UIKit

/// Renders a `World` and turns touches into thrust. Owns no game rules.
final class GameScene: SKScene {
    private enum Palette {
        static let food = UIColor(red: 0.43, green: 0.78, blue: 1.00, alpha: 1)    // #6EC6FF
        static let threat = UIColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 1)  // #FF6B6B
        static let neutral = UIColor(red: 0.91, green: 0.91, blue: 0.94, alpha: 1) // #E8E8F0
        static let player = UIColor(red: 1.00, green: 0.83, blue: 0.43, alpha: 1)  // #FFD36E
        static let attractor = UIColor(red: 0.69, green: 0.49, blue: 1.00, alpha: 1) // #B07CFF
        static let target = UIColor(red: 0.45, green: 1.00, blue: 0.78, alpha: 1)    // #73FFC7, distinct from food/threat/player
        static let bomb = UIColor(red: 1.00, green: 0.45, blue: 0.15, alpha: 1)
        static let antimatter = UIColor(red: 1.00, green: 0.24, blue: 0.67, alpha: 1) // #FF3DAA
        static let comet = UIColor(red: 0.81, green: 0.97, blue: 1.00, alpha: 1)     // icy
        static let pulsar = UIColor(red: 0.62, green: 0.96, blue: 1.00, alpha: 1)
        static let nebula = UIColor(red: 0.85, green: 0.45, blue: 0.85, alpha: 1)
        static let wormholeA = UIColor(red: 0.45, green: 1.00, blue: 0.85, alpha: 1)
        static let wormholeB = UIColor(red: 1.00, green: 0.80, blue: 0.45, alpha: 1)
        static let background = UIColor(red: 0.02, green: 0.03, blue: 0.09, alpha: 1)
    }

    /// Sprite size relative to the body's diameter (the texture has a glow halo around the core).
    private static let glowScale = 1.7
    private static let puffInterval = 0.08

    var onPuff: (() -> Void)?
    var onAbsorb: (() -> Void)?
    /// The player swallowed a body completely.
    var onSwallow: (() -> Void)?

    /// Centre-to-centre distance of the SwiftUI top-left buttons (menu, restart).
    static let topButtonSpacing: CGFloat = 56
    /// Speeds offered by the speed chips. Low for careful manoeuvres, high for quick runs.
    static let speedOptions: [Double] = [0.5, 1, 2, 3, 5]
    private(set) var warpSpeed = 1.0
    private let warpButton = SKShapeNode(circleOfRadius: 24)
    private let warpLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var lastSwallowCount = 0
    private var lastSwallowFeedback: Double = -1

    /// 0…1, how close the nearest bigger body is. Drives the music's danger layer.
    var onDanger: ((Double) -> Void)?
    /// A rating star popped in on the result overlay.
    var onStar: (() -> Void)?

    private static let maxArrows = 4
    private let massRingTrack = SKShapeNode()
    private let massRing = SKShapeNode()
    private var arrows: [SKShapeNode] = []
    private let resultLayer = SKNode()
    private var awaitingContinue = false
    private var frameCounter = 0
    /// Largest mass each body ever had, so a swallow flash reflects the meal, not its last crumb.
    private var peakMass: [Int: Double] = [:]

    /// The player is losing mass to someone (heartbeat haptic).
    var onBeingEaten: (() -> Void)?
    /// A supernova went off.
    var onExplosion: (() -> Void)?
    private var beingEatenUntil: Double = -1
    private var lastHeartbeat: Double = -1
    private let targetMarker = SKShapeNode()
    private let goalLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var lastGoalText = ""
    private var lastGoalUpdate: Double = -1
    private let screenFlash = SKSpriteNode(color: .white, size: .zero)

    /// One-line explanation of a mechanic that appears for the first time on this level.
    private var levelIntro: String?
    /// Nebulae and wormhole mouths: static scenery under the bodies.
    private let terrainLayer = SKNode()
    private lazy var softTexture = GameScene.makeSoftTexture()

    /// Pinch zoom on top of the automatic zoom: >1 shows more of the world. Remembered between launches.
    private static let zoomKey = "accretion.zoom"
    private static let zoomRange: ClosedRange<CGFloat> = 0.5...3
    private var userZoom: CGFloat = {
        let saved = CGFloat(UserDefaults.standard.double(forKey: GameScene.zoomKey))
        return saved > 0 ? min(max(saved, GameScene.zoomRange.lowerBound), GameScene.zoomRange.upperBound) : 1
    }()
    private var pinchStartZoom: CGFloat = 1
    private var isPinching = false

    /// Something went through a wormhole near the player.
    var onTeleport: (() -> Void)?
    /// Every 5 levels is a new "world" with its own harmony.
    var onWorldChange: ((Int) -> Void)?
    /// Nearest objects as sound voices, every frame.
    var onSoundscape: (([SoundscapeVoice]) -> Void)?

    /// Faint tether between the two halves of a double star.
    private let binaryLink = SKShapeNode()
    /// Dead end: "nothing left to eat" restart pill.
    private let stuckPrompt = SKShapeNode(rectOf: CGSize(width: 290, height: 46), cornerRadius: 23)
    private var stuckSince: Double?
    private var stuckPromptFrame: CGRect?

    private var world: World!
    private(set) var mode: GameMode = .campaign(level: GameProgress.currentLevel)
    /// Osmos-style control, from settings.
    var controlAwayFromTouch = false
    private var nodes: [Int: SKSpriteNode] = [:]
    private let bodyLayer = SKNode()
    private let backdrop = SKNode()
    private let border = SKShapeNode()
    private let cam = SKCameraNode()
    private let hint = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let banner = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private lazy var glowTexture = GameScene.makeGlowTexture()

    private var lastUpdate: TimeInterval?
    private var touchPoint: CGPoint?
    private var lastPuff: TimeInterval = 0
    private var hasMoved = false
    private var lastPlayerMass: Double = 0
    private var lastAbsorbFeedback: Double = -1
    private var restartScheduled = false

    // MARK: - Lifecycle

    override init() {
        super.init(size: CGSize(width: 400, height: 800))
        // Must be set before SpriteView presents the scene, otherwise circles are stretched.
        scaleMode = .resizeFill
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        backgroundColor = Palette.background
        StarSurface.setAnimated(!reduceMotion)
        // Two fingers = pinch zoom; one finger = thrust.
        view.isMultipleTouchEnabled = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        let doubleTapTwoFingers = UITapGestureRecognizer(target: self, action: #selector(resetZoom))
        doubleTapTwoFingers.numberOfTouchesRequired = 2
        view.addGestureRecognizer(doubleTapTwoFingers)

        addChild(backdrop)
        terrainLayer.zPosition = -1
        addChild(terrainLayer)
        addChild(bodyLayer)
        border.strokeColor = UIColor(white: 1, alpha: 0.08)
        border.lineWidth = 3
        addChild(border)

        addChild(cam)
        camera = cam
        hint.text = String(localized: "Коснись — лети")
        hint.fontSize = 22
        hint.fontColor = UIColor(white: 1, alpha: 0.75)
        cam.addChild(hint)
        banner.fontSize = 28
        banner.numberOfLines = 2
        banner.horizontalAlignmentMode = .center
        banner.verticalAlignmentMode = .center
        banner.fontColor = .white
        banner.alpha = 0
        cam.addChild(banner)

        warpButton.fillColor = UIColor(white: 1, alpha: 0.08)
        warpButton.strokeColor = UIColor(white: 1, alpha: 0.25)
        warpButton.lineWidth = 1
        warpButton.zPosition = 10
        warpLabel.fontSize = 17
        warpLabel.verticalAlignmentMode = .center
        warpLabel.fontColor = UIColor(white: 1, alpha: 0.8)
        warpButton.addChild(warpLabel)
        cam.addChild(warpButton)
        updateWarpLabel()
        setupOverlays()

        #if DEBUG
        // `-AccretionLevel N`: open campaign level N (0-based) directly.
        if UserDefaults.standard.object(forKey: "AccretionLevel") != nil {
            mode = .campaign(level: UserDefaults.standard.integer(forKey: "AccretionLevel"))
        }
        #endif
        loadLevel()
        layoutOverlay()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutOverlay()
    }

    private func layoutOverlay() {
        hint.position = CGPoint(x: 0, y: -size.height * 0.28)
        banner.position = CGPoint(x: 0, y: size.height * 0.22)
        let insets = view?.safeAreaInsets ?? .zero
        warpButton.position = CGPoint(
            x: size.width / 2 - insets.right - 24 - 16,
            y: size.height / 2 - insets.top - 24 - 8
        )
        // Caption sits in the gap between the restart button (left) and the warp button (right).
        let restartRight = -warpButton.position.x + GameScene.topButtonSpacing + 24
        let warpLeft = warpButton.position.x - 24
        goalLabel.position = CGPoint(x: (restartRight + warpLeft) / 2, y: warpButton.position.y)
        goalLabelMaxWidth = max(warpLeft - restartRight - 16, 60)
        fitGoalLabel()
        screenFlash.size = CGSize(width: size.width * 2, height: size.height * 2)
    }

    /// One tap moves to the next speed in `speedOptions` (×0.5 → ×1 → ×2 → ×3 → ×5 → ×0.5).
    private func tapSpeedButton() {
        warpButton.run(.sequence([.scale(to: 1.15, duration: 0.08), .scale(to: 1, duration: 0.12)]))
        let options = GameScene.speedOptions
        let current = options.firstIndex(where: { $0 == warpSpeed }) ?? 1
        setSpeed(options[(current + 1) % options.count])
    }

    /// Set from the speed chips (one tap picks a value).
    func setSpeed(_ speed: Double) {
        warpSpeed = speed
        updateWarpLabel()
    }

    private func updateWarpLabel() {
        let speed = warpSpeed
        warpLabel.text = "×" + (speed == speed.rounded() ? "\(Int(speed))" : "\(speed)")
        warpButton.strokeColor = UIColor(white: 1, alpha: speed > 1 ? 0.7 : 0.25)
    }

    private func loadLevel() {
        nodes.values.forEach { $0.removeFromParent() }
        nodes.removeAll()
        let spec = GameProgress.spec(for: mode)
        world = spec.makeWorld()
        levelIntro = spec.intro
        switch mode {
        case .campaign(let level): onWorldChange?(level / 5)
        case .daily(let day): onWorldChange?(day)
        case .sandbox(let config): onWorldChange?(Int(config.seed % 4))
        }
        #if DEBUG
        // `-AccretionQuickWin YES`: a level that is won in about a second, to check the result screen.
        if UserDefaults.standard.bool(forKey: "AccretionQuickWin") {
            world = World(size: Vec2(800, 800), bodies: [
                Body(id: 0, kind: .player, position: Vec2(400, 400), radius: 22),
                Body(id: 1, kind: .mote, position: Vec2(428, 400), radius: 10),
                Body(id: 2, kind: .mote, position: Vec2(100, 100), radius: 23),
            ], playerID: 0)
        }
        // `-AccretionShowcase YES`: every advanced object in one level.
        if UserDefaults.standard.bool(forKey: "AccretionShowcase") {
            world = LevelGenerator.makeWorld(seed: 9, difficulty: 0.8, splitters: true, pulsar: true, nebula: true,
                                             antimatter: true, comets: true, wormholes: true, binaries: true)
        }
        // `-AccretionBlackHoleDemo YES`: black hole with orbiting planets, the player on an orbit nearby.
        if UserDefaults.standard.bool(forKey: "AccretionBlackHoleDemo") {
            world = LevelGenerator.makeWorld(seed: 3, difficulty: 0.3, attractor: true, planets: true)
        }
        // `-AccretionAstronautDemo YES`: a cosmonaut floating next to the player, among stars of all sizes.
        if UserDefaults.standard.bool(forKey: "AccretionAstronautDemo") {
            world = World(size: Vec2(1600, 1600), bodies: [
                Body(id: 0, kind: .player, position: Vec2(800, 800), radius: 22),
                Body(id: 1, kind: .astronaut, position: Vec2(880, 840), velocity: Vec2(-2, 0), radius: 5),
                Body(id: 2, kind: .mote, position: Vec2(700, 930), radius: 12),
                Body(id: 3, kind: .mote, position: Vec2(930, 700), radius: 35),
                Body(id: 4, kind: .mote, position: Vec2(650, 680), radius: 6),
                Body(id: 5, kind: .mote, position: Vec2(150, 150), radius: 50),
            ], playerID: 0)
        }
        // `-AccretionSupernovaDemo YES`: a supernova goes off on screen after 2 s.
        if UserDefaults.standard.bool(forKey: "AccretionSupernovaDemo") {
            world = World(size: Vec2(1600, 1600), bodies: [
                Body(id: 0, kind: .player, position: Vec2(800, 650), radius: 22),
                Body(id: 1, kind: .mote, position: Vec2(800, 900), radius: 40, fuse: 2),
                Body(id: 2, kind: .mote, position: Vec2(150, 150), radius: 50),
            ], playerID: 0)
        }
        #endif
        lastPlayerMass = world.player?.mass ?? 0
        lastSwallowCount = 0
        lastSwallowFeedback = -1
        restartScheduled = false
        awaitingContinue = false
        shareButtonFrame = nil
        replayButtonFrame = nil
        countedSwallows = 0
        lastBounces = 0
        recorded = []
        stuckSince = nil
        stuckPrompt.isHidden = true
        stuckPromptFrame = nil
        playback = nil
        peakMass.removeAll()
        particleLayer.removeAllChildren()
        resultLayer.removeAllChildren()
        resultLayer.isHidden = true
        banner.removeAllActions()
        setBanner(title: levelTitle, subtitle: [goalTitle, levelIntro].compactMap { $0 }.joined(separator: "\n"))
        buildTerrain()
        banner.alpha = 1
        // A new mechanic gets more time, so the extra line can be read.
        banner.run(.sequence([.wait(forDuration: levelIntro == nil ? 2.2 : 3.8), .fadeOut(withDuration: 0.8)]))
        beingEatenUntil = -1
        lastHeartbeat = -1
        targetMarker.isHidden = true
        updateGoalLabel(force: true)
        border.path = CGPath(rect: CGRect(x: 0, y: 0, width: world.size.x, height: world.size.y), transform: nil)
        buildBackdrop()
        if let player = world.player {
            cam.position = CGPoint(x: player.position.x, y: player.position.y)
            cam.setScale(targetScale(for: player))
        }
        sync()
    }

    // MARK: - Frame

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate.map { currentTime - $0 } ?? 0
        lastUpdate = currentTime

        if let touchPoint, currentTime - lastPuff >= GameScene.puffInterval {
            lastPuff = currentTime
            puff(at: touchPoint)
        }

        if playback != nil {
            stepPlayback(dt: dt)
        } else {
            world.advance(by: dt * warpSpeed)
        }
        sync()
        followPlayer(dt: dt)
        frameCounter += 1
        handleEvents(world.drainEvents())
        handleExplosions(world.drainExplosions())
        handlePulses(world.drainPulses())
        handleTeleports(world.drainTeleports())
        animateWormholes()
        if let onSoundscape, playback == nil {
            let halfWidth = Double(size.width) / 2 * Double(cam.xScale)
            onSoundscape(Soundscape.voices(world: world, cameraCenter: Vec2(Double(cam.position.x), Double(cam.position.y)), halfWidth: halfWidth))
        }
        updateBinaryLink()
        updateTrajectory()
        updateStuckPrompt()
        updateMassRing()
        updateTargetMarker()
        updateThreatsAndDanger()
        updateGoalLabel(force: false)
        handleState()
    }

    private func puff(at viewPoint: CGPoint) {
        guard world.state == .playing, playback == nil else { return }
        let target = convertPoint(fromView: viewPoint)
        let step = world.stepCount
        if world.thrust(toward: Vec2(target.x, target.y), awayFromTarget: controlAwayFromTouch) {
            recorded.append(Replay.Input(step: step, x: Double(target.x), y: Double(target.y), away: controlAwayFromTouch))
            onPuff?()
            dismissHint()
        }
    }

    /// Clears the time base so a long pause does not turn into one big step.
    func resetClock() { lastUpdate = nil }

    private func sync() {
        let playerMass = world.player?.mass ?? 0
        if playerMass > lastPlayerMass + 1, world.time - lastAbsorbFeedback > 0.15 {
            lastAbsorbFeedback = world.time
            onAbsorb?()
        }
        lastPlayerMass = playerMass
        // At most ~3 chimes a second, so sweeping through dust doesn't turn into noise.
        if world.playerSwallowCount > lastSwallowCount, world.time - lastSwallowFeedback > 0.3 {
            lastSwallowCount = world.playerSwallowCount
            lastSwallowFeedback = world.time
            onSwallow?()
        }

        checkSwallowAchievements()
        if world.playerBounces > lastBounces {
            lastBounces = world.playerBounces
            onBounce?()
            award(.billiards)
        }

        var alive = Set<Int>()
        for body in world.bodies {
            alive.insert(body.id)
            if body.mass > peakMass[body.id] ?? 0 { peakMass[body.id] = body.mass }
            let node = nodes[body.id] ?? makeNode(for: body)
            node.position = CGPoint(x: body.position.x, y: body.position.y)
            let diameter = body.radius * 2 * GameScene.glowScale
            node.size = CGSize(width: diameter, height: diameter)
            node.color = color(for: body, playerMass: playerMass)
            if body.isSupernova {
                // Last 10 s: pulses faster and faster, and burns whiter.
                let remaining = body.fuse - world.time
                let heat = min(max(1 - remaining / 10, 0), 1)
                node.color = node.color.mixed(with: .white, amount: heat * 0.7)
                if !reduceMotion {
                    let frequency = 0.6 + heat * 4
                    node.setScale(CGFloat(1 + 0.07 * heat * sin(2 * .pi * frequency * world.time)))
                }
            }
            if body.id == world.playerID, world.time < beingEatenUntil {
                // Being drained: tint red and tremble.
                node.color = node.color.mixed(with: threatColor, amount: 0.55)
                if !reduceMotion {
                    let jitter = body.radius * 0.08
                    node.position.x += CGFloat(Double.random(in: -jitter...jitter))
                    node.position.y += CGFloat(Double.random(in: -jitter...jitter))
                }
            }
            if body.kind == .comet {
                node.color = Palette.comet.mixed(with: node.color, amount: 0.25)
            }
            if let seam = node.childNode(withName: "seam") {
                seam.xScale = CGFloat(body.radius) * 0.9
                seam.yScale = CGFloat(body.radius) * 0.9
            }
            if body.kind == .astronaut {
                // Drawn bigger than its collision circle so the figure reads; the aura carries the food colour.
                let side = body.radius * 2 * 2.8
                node.size = CGSize(width: side, height: side)
                if let aura = node.childNode(withName: "aura") as? SKSpriteNode {
                    aura.size = CGSize(width: side * 1.3, height: side * 1.3)
                    aura.color = node.color
                }
                // Beacon on top of the helmet (children aren't scaled by the sprite's size).
                node.childNode(withName: "beacon")?.position = CGPoint(x: side * 0.1, y: side * 0.4)
            }
            if let corona = node.childNode(withName: "corona") as? SKSpriteNode {
                let side = body.radius * 2 * 2.2
                corona.size = CGSize(width: side, height: side)
                corona.color = node.color
            }
            if let core = node.childNode(withName: "core") as? SKSpriteNode {
                core.size = CGSize(width: body.radius * 1.1, height: body.radius * 1.1)
            }
            if body.kind == .attractor {
                // Black hole: the black disc is exactly the swallowing radius; the disk and glow sit outside it.
                let core = body.radius * 2 / 0.8
                node.size = CGSize(width: core, height: core)
                node.childNode(withName: "halo").map { ($0 as? SKSpriteNode)?.size = CGSize(width: body.radius * 7, height: body.radius * 7) }
                node.childNode(withName: "disk").map { ($0 as? SKSpriteNode)?.size = CGSize(width: body.radius * 6, height: body.radius * 6) }
            }
            if body.kind == .planet {
                // Solid body: drawn at its true size, no glow.
                node.size = CGSize(width: body.radius * 2, height: body.radius * 2)
                node.childNode(withName: "ring").map { ($0 as? SKSpriteNode)?.size = CGSize(width: body.radius * 4.4, height: body.radius * 1.5) }
            }
        }
        for (id, node) in nodes where !alive.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
        if peakMass.count > world.bodies.count * 2 + 64 {
            peakMass = peakMass.filter { alive.contains($0.key) }
        }
    }

    private func makeNode(for body: Body) -> SKSpriteNode {
        let node = SKSpriteNode(texture: glowTexture)
        node.colorBlendFactor = 1
        node.blendMode = .add
        node.zPosition = body.kind == .player ? 2 : 1
        if body.kind == .attractor {
            node.texture = blackHoleTexture
            node.colorBlendFactor = 0
            node.blendMode = .alpha
            node.zPosition = 1.2
            // Accretion disk: hot gas spiralling in, turning slowly behind the black disc.
            let disk = SKSpriteNode(texture: accretionDiskTexture)
            disk.name = "disk"
            disk.blendMode = .add
            disk.zPosition = -0.3
            node.addChild(disk)
            if !reduceMotion { disk.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 18))) }
            let halo = SKSpriteNode(texture: glowTexture)
            halo.name = "halo"
            halo.color = Palette.attractor
            halo.colorBlendFactor = 1
            halo.blendMode = .add
            halo.alpha = 0.18
            halo.zPosition = -0.5
            node.addChild(halo)
            if !reduceMotion {
                let swell = SKAction.sequence([.fadeAlpha(to: 0.28, duration: 2), .fadeAlpha(to: 0.14, duration: 2)])
                swell.timingMode = .easeInEaseOut
                halo.run(.repeatForever(swell))
            }
        }
        // Living plasma surface on everything big enough to see it (not comets: they stay icy and plain).
        if body.radius >= StarSurface.minRadius || body.kind == .player,
           ![.comet, .attractor, .planet].contains(body.kind) {
            StarSurface.apply(to: node, seed: body.id)
        }
        if body.kind == .bomb {
            // Ticking: quick pulse, and a dashed ring showing how close a giant must come to set it off.
            let reach = CGFloat(body.radius + World.bombTriggerGap)
            let circle = CGPath(ellipseIn: CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2), transform: nil)
            let ring = SKShapeNode(path: circle.copy(dashingWithPhase: 0, lengths: [10, 8]))
            ring.strokeColor = Palette.bomb.withAlphaComponent(0.55)
            ring.lineWidth = 2
            ring.zPosition = -0.2
            node.addChild(ring)
            if !reduceMotion {
                let tick = SKAction.sequence([.scale(to: 1.12, duration: 0.25), .scale(to: 1, duration: 0.25)])
                node.run(.repeatForever(tick))
                ring.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 8)))
            }
        }
        if body.kind == .planet {
            node.texture = planetTextures[body.id % planetTextures.count]
            node.colorBlendFactor = 0
            node.blendMode = .alpha
            node.zRotation = CGFloat(Double(body.id % 7) * 0.4 - 1.2)
            if body.id % 3 == 0 {
                // Every third planet gets a Saturn ring.
                let ring = SKSpriteNode(texture: ringTexture)
                ring.name = "ring"
                ring.zPosition = 0.1
                ring.alpha = 0.85
                node.addChild(ring)
            }
        }
        if body.kind == .astronaut {
            node.texture = astronautTexture
            node.colorBlendFactor = 0
            node.blendMode = .alpha
            node.zRotation = CGFloat(Double(body.id % 628) / 100)
            let aura = SKSpriteNode(texture: softTexture)
            aura.name = "aura"
            aura.colorBlendFactor = 1
            aura.blendMode = .add
            aura.alpha = 0.45
            aura.zPosition = -0.1
            node.addChild(aura)
            // Helmet beacon: a tiny red light blinking once a second.
            let beacon = SKSpriteNode(color: UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 1), size: CGSize(width: 2.2, height: 2.2))
            beacon.position = CGPoint(x: 0, y: 0)
            beacon.name = "beacon"
            beacon.zPosition = 0.2
            node.addChild(beacon)
            beacon.run(.repeatForever(.sequence([.fadeIn(withDuration: 0.05), .wait(forDuration: 0.15), .fadeOut(withDuration: 0.2), .wait(forDuration: 0.6)])))
            if !reduceMotion {
                // Lazy tumble, direction depends on the id.
                let turn = SKAction.rotate(byAngle: body.id % 2 == 0 ? .pi * 2 : -.pi * 2, duration: 11)
                node.run(.repeatForever(turn))
            }
        }
        if body.kind == .player {
            // Corona: soft rays slowly turning behind the player star.
            let corona = SKSpriteNode(texture: coronaTexture)
            corona.name = "corona"
            corona.colorBlendFactor = 1
            corona.blendMode = .add
            corona.alpha = 0.4
            corona.zPosition = -0.2
            node.addChild(corona)
            if !reduceMotion {
                corona.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 40)))
                let breathe = SKAction.sequence([.fadeAlpha(to: 0.25, duration: 2.5), .fadeAlpha(to: 0.45, duration: 2.5)])
                breathe.timingMode = .easeInEaseOut
                corona.run(.repeatForever(breathe))
            }
        }
        switch body.kind {
        case .splitter:
            // A seam across the star: it will crack in two.
            let seam = SKShapeNode(rectOf: CGSize(width: 2, height: 0.08))
            seam.name = "seam"
            seam.fillColor = UIColor(white: 0, alpha: 0.55)
            seam.strokeColor = .clear
            seam.zPosition = 0.1
            node.addChild(seam)
            if !reduceMotion { seam.run(.repeatForever(.rotate(byAngle: .pi, duration: 6))) }
        case .pulsar:
            let core = SKSpriteNode(texture: glowTexture)
            core.name = "core"
            core.color = Palette.pulsar
            core.colorBlendFactor = 1
            core.blendMode = .add
            core.zPosition = 0.1
            node.addChild(core)
        case .antimatter:
            // Dark core + fast flicker: reads as "wrong", not as food.
            let core = SKSpriteNode(texture: glowTexture)
            core.name = "core"
            core.color = .black
            core.colorBlendFactor = 1
            core.blendMode = .alpha
            core.alpha = 0.75
            core.zPosition = 0.1
            node.addChild(core)
            if !reduceMotion {
                let flicker = SKAction.sequence([.fadeAlpha(to: 0.7, duration: 0.12), .fadeAlpha(to: 1, duration: 0.18)])
                node.run(.repeatForever(flicker))
            }
        default:
            break
        }
        if body.kind == .hunter {
            // Hunters "breathe" so they read as alive, independent of their food/threat colour.
            let pulse = SKAction.sequence([.fadeAlpha(to: 0.5, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)])
            pulse.timingMode = .easeInEaseOut
            node.run(.repeatForever(pulse))
        }
        bodyLayer.addChild(node)
        nodes[body.id] = node
        return node
    }

    private func color(for body: Body, playerMass: Double) -> UIColor {
        if body.kind == .player { return playerColor }
        if body.kind == .attractor { return Palette.attractor }
        if body.kind == .bomb { return Palette.bomb }
        // Antimatter is dangerous at any size, so it never wears the "food" colour.
        if body.kind == .antimatter { return Palette.antimatter }
        guard playerMass > 0 else { return threatColor }
        let ratio = body.mass / playerMass
        if ratio < 1 {
            return Palette.neutral.mixed(with: foodColor, amount: min((1 - ratio) / 0.15, 1))
        }
        return Palette.neutral.mixed(with: threatColor, amount: min((ratio - 1) / 0.15, 1))
    }

    // MARK: - Accessibility

    /// Blue/orange instead of blue/red, white player: readable with red-green colour blindness.
    var contrastColors = false
    private var foodColor: UIColor { contrastColors ? UIColor(red: 0.24, green: 0.61, blue: 1, alpha: 1) : Palette.food }
    private var threatColor: UIColor { contrastColors ? UIColor(red: 1, green: 0.54, blue: 0, alpha: 1) : Palette.threat }
    /// Chosen in the menu; contrast mode overrides it with white.
    var skin = Skin.selected
    private var playerColor: UIColor {
        if contrastColors { return .white }
        let (r, g, b) = skin.rgb
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    // MARK: - Camera

    private func targetScale(for player: Body) -> CGFloat {
        // Keep the player around 1/16 of the short screen side; never zoom in past 1:1.
        let shortSide = max(min(size.width, size.height), 1)
        let visible = max(player.radius * 32, 520)
        return CGFloat(visible) / shortSide * userZoom
    }

    @objc private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .began:
            isPinching = true
            touchPoint = nil
            pinchStartZoom = userZoom
        case .changed:
            // Fingers apart (scale > 1) = zoom in = see less.
            userZoom = min(max(pinchStartZoom / pinch.scale, GameScene.zoomRange.lowerBound), GameScene.zoomRange.upperBound)
            if let player = world.player { cam.setScale(targetScale(for: player)) }
        default:
            isPinching = false
            UserDefaults.standard.set(Double(userZoom), forKey: GameScene.zoomKey)
        }
    }

    /// Two-finger tap: back to the automatic zoom.
    @objc private func resetZoom() {
        userZoom = 1
        UserDefaults.standard.set(1.0, forKey: GameScene.zoomKey)
    }

    private func followPlayer(dt: Double) {
        guard let player = world.player else { return }
        let follow = CGFloat(1 - exp(-dt * 6))
        let target = CGPoint(x: player.position.x, y: player.position.y)
        cam.position.x += (target.x - cam.position.x) * follow
        cam.position.y += (target.y - cam.position.y) * follow
        let zoom = CGFloat(1 - exp(-dt * 1.5))
        cam.setScale(cam.xScale + (targetScale(for: player) - cam.xScale) * zoom)
    }

    // MARK: - Win / lose

    private func handleState() {
        // During a replay, stepPlayback decides what happens at the end.
        guard playback == nil else { return }
        switch world.state {
        case .playing:
            break
        case .won:
            guard !restartScheduled else { return }
            restartScheduled = true
            touchPoint = nil
            showResult()
        case .lost:
            guard !restartScheduled else { return }
            restartScheduled = true
            touchPoint = nil
            switch world.lossReason {
            case .targetLost:
                if case .trap = world.goal {
                    showBanner(String(localized: "Ловушка сорвалась. Ещё раз"))
                } else {
                    showBanner(String(localized: "Цель досталась другому. Ещё раз"))
                }
            default: showBanner(String(localized: "Поглощена. Ещё раз"))
            }
            run(.wait(forDuration: 1.4)) { [weak self] in self?.loadLevel() }
        }
    }

    /// Big title plus a smaller line under it, wrapped to the screen width.
    private func setBanner(title: String, subtitle: String? = nil) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 6
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: UIFont(name: "AvenirNext-DemiBold", size: 28) ?? .boldSystemFont(ofSize: 28),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ])
        if let subtitle {
            text.append(NSAttributedString(string: "\n" + subtitle, attributes: [
                .font: UIFont(name: "AvenirNext-Medium", size: 18) ?? .systemFont(ofSize: 18),
                .foregroundColor: UIColor(white: 1, alpha: 0.8),
                .paragraphStyle: paragraph,
            ]))
        }
        banner.numberOfLines = 0
        banner.preferredMaxLayoutWidth = max(size.width - 48, 200)
        banner.attributedText = text
    }

    private func showBanner(_ text: String) {
        setBanner(title: text)
        banner.removeAllActions()
        banner.run(.fadeIn(withDuration: 0.4))
    }

    private func dismissHint() {
        guard !hasMoved else { return }
        hasMoved = true
        hint.run(.sequence([.wait(forDuration: 1.5), .fadeOut(withDuration: 1.0), .removeFromParent()]))
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let view else { return }
        if playback != nil {
            finishPlayback()
            return
        }
        if awaitingContinue {
            let point = touch.location(in: view)
            if let share = shareButtonFrame, share.contains(point) {
                requestShare()
            } else if let replay = replayButtonFrame, replay.contains(point), let run = lastRun {
                awaitingContinue = false
                play(run, returnToResult: true)
            } else {
                nextLevel()
            }
            return
        }
        if let stuck = stuckPromptFrame, !stuckPrompt.isHidden, stuck.contains(touch.location(in: view)) {
            restartLevel()
            return
        }
        // A second finger means a pinch, not a thrust.
        if isPinching || (event?.allTouches?.count ?? 1) > 1 {
            touchPoint = nil
            return
        }
        let point = touch.location(in: view)
        // Camera children ignore camera scale, so hit-test in view points (view y grows downward).
        let buttonInView = CGPoint(x: size.width / 2 + warpButton.position.x, y: size.height / 2 - warpButton.position.y)
        if (point - buttonInView).length < 34 {
            tapSpeedButton()
            return
        }
        touchPoint = point
        // A quick tap can end before the next frame, so puff right away instead of waiting for update().
        lastPuff = CACurrentMediaTime()
        puff(at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let view else { return }
        if isPinching || (event?.allTouches?.count ?? 1) > 1 {
            touchPoint = nil
            return
        }
        touchPoint = touch.location(in: view)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touchPoint = nil }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchPoint = nil }

    // MARK: - Overlays: mass ring, threat arrows

    private let particleLayer = SKNode()

    private func setupOverlays() {
        for ring in [massRingTrack, massRing] {
            ring.fillColor = .clear
            ring.lineCap = .round
            ring.zPosition = 3
            bodyLayer.addChild(ring)
        }
        massRingTrack.strokeColor = UIColor(white: 1, alpha: 0.12)
        massRing.strokeColor = Palette.player.withAlphaComponent(0.9)

        particleLayer.zPosition = 1.5
        bodyLayer.addChild(particleLayer)

        let triangle = CGMutablePath()
        triangle.move(to: CGPoint(x: 11, y: 0))
        triangle.addLine(to: CGPoint(x: -7, y: 8))
        triangle.addLine(to: CGPoint(x: -7, y: -8))
        triangle.closeSubpath()
        for _ in 0..<GameScene.maxArrows {
            let arrow = SKShapeNode(path: triangle)
            arrow.fillColor = Palette.threat
            arrow.strokeColor = .clear
            arrow.zPosition = 9
            arrow.isHidden = true
            cam.addChild(arrow)
            arrows.append(arrow)
        }

        resultLayer.zPosition = 20
        resultLayer.isHidden = true
        cam.addChild(resultLayer)

        targetMarker.fillColor = .clear
        targetMarker.strokeColor = Palette.target
        targetMarker.zPosition = 3
        targetMarker.isHidden = true
        bodyLayer.addChild(targetMarker)

        goalLabel.fontSize = 15
        goalLabel.fontColor = UIColor(white: 1, alpha: 0.75)
        goalLabel.verticalAlignmentMode = .center
        goalLabel.zPosition = 9
        cam.addChild(goalLabel)

        screenFlash.alpha = 0
        screenFlash.zPosition = 15
        screenFlash.blendMode = .add
        cam.addChild(screenFlash)

        binaryLink.strokeColor = UIColor(white: 1, alpha: 0.12)
        binaryLink.zPosition = 0.5
        binaryLink.isHidden = true
        bodyLayer.addChild(binaryLink)

        stuckPrompt.fillColor = UIColor(white: 1, alpha: 0.12)
        stuckPrompt.strokeColor = UIColor(white: 1, alpha: 0.4)
        stuckPrompt.zPosition = 12
        stuckPrompt.isHidden = true
        let stuckLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        stuckLabel.text = String(localized: "Еды не осталось · начать заново")
        stuckLabel.fontSize = 16
        stuckLabel.verticalAlignmentMode = .center
        stuckPrompt.addChild(stuckLabel)
        cam.addChild(stuckPrompt)
    }

    // MARK: - Trajectory: where the ship will go if untouched

    /// Predicted path drawn as a thin line of short segments that get thinner and dimmer with distance from the ship.
    var showTrajectory = true
    private static let trajectorySegmentCount = 60
    /// Distance (world units) at which the ribbon has fully faded.
    private static let trajectoryFadeDistance = 700.0
    private var trajectoryCore: [SKShapeNode] = []

    private func updateTrajectory() {
        if trajectoryCore.isEmpty {
            for _ in 0..<GameScene.trajectorySegmentCount {
                let core = SKShapeNode()
                core.fillColor = .clear
                core.lineCap = .round
                core.zPosition = 1.9
                core.isHidden = true
                bodyLayer.addChild(core)
                trajectoryCore.append(core)
            }
        }
        let path = (showTrajectory && playback == nil && world.state == .playing) ? world.predictPlayerPath() : []
        guard path.count >= 2 else {
            for index in trajectoryCore.indices {
                trajectoryCore[index].isHidden = true
            }
            return
        }
        let origin = path[0]
        // Pale blue and mostly see-through: a hint, not a highlight.
        let color = foodColor
        let scale = cam.xScale
        for index in trajectoryCore.indices {
            guard index + 1 < path.count else {
                trajectoryCore[index].isHidden = true
                continue
            }
            let a = path[index]
            let b = path[index + 1]
            // Fade by how far the segment is from the ship, so the tail thins out as it recedes.
            let distance = (b - origin).length
            let fade = pow(max(0, 1 - distance / GameScene.trajectoryFadeDistance), 1.3)
            guard fade > 0.03 else {
                trajectoryCore[index].isHidden = true
                continue
            }
            let line = CGMutablePath()
            line.move(to: CGPoint(x: a.x, y: a.y))
            line.addLine(to: CGPoint(x: b.x, y: b.y))

            let core = trajectoryCore[index]
            core.path = line
            core.strokeColor = color.withAlphaComponent(CGFloat(0.3 * fade))
            core.lineWidth = CGFloat(0.6 + 1.6 * fade) * scale
            core.isHidden = false

        }
    }

    private func updateBinaryLink() {
        let pair = world.bodies.filter { $0.kind == .binary }
        guard pair.count == 2 else {
            binaryLink.isHidden = true
            return
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: pair[0].position.x, y: pair[0].position.y))
        path.addLine(to: CGPoint(x: pair[1].position.x, y: pair[1].position.y))
        binaryLink.path = path.copy(dashingWithPhase: 0, lengths: [10 * cam.xScale, 8 * cam.xScale])
        binaryLink.lineWidth = 1.5 * cam.xScale
        binaryLink.isHidden = false
    }

    /// After 2 s with nothing left to eat, offer a restart instead of leaving the player drifting.
    private func updateStuckPrompt() {
        guard playback == nil, world.isStuck else {
            stuckSince = nil
            stuckPrompt.isHidden = true
            stuckPromptFrame = nil
            return
        }
        let since = stuckSince ?? world.time
        stuckSince = since
        guard world.time - since > 2, stuckPrompt.isHidden else { return }
        let insets = view?.safeAreaInsets ?? .zero
        stuckPrompt.position = CGPoint(x: 0, y: -size.height / 2 + insets.bottom + 60)
        stuckPrompt.isHidden = false
        stuckPrompt.alpha = 0
        stuckPrompt.run(.fadeIn(withDuration: 0.4))
        stuckPromptFrame = CGRect(
            x: size.width / 2 - 145, y: size.height / 2 - stuckPrompt.position.y - 23, width: 290, height: 46
        ).insetBy(dx: -8, dy: -8)
    }

    // MARK: - Goal HUD

    /// The body the goal is about (eat it, or lure it onto the bomb): gets the marker and the arrow.
    private var goalTargetID: Int? {
        switch world.goal {
        case .eatTarget(let id): id
        case .trap(let id): id
        default: nil
        }
    }

    private var goalTitle: String {
        switch world.goal {
        case .becomeBiggest: String(localized: "Стань самой большой звездой")
        case .reachMass(let multiple): String(localized: "Вырасти в \(multiple.formatted(.number.precision(.fractionLength(0...1)))) раза")
        case .survive(let seconds): String(localized: "Продержись \(Int(seconds)) секунд")
        case .eatTarget: String(localized: "Поглоти отмеченную звезду")
        case .eatAllHunters: String(localized: "Съешь всех охотников")
        case .travel(let times): String(localized: "Пройди через червоточину \(times) раза")
        case .trap: String(localized: "Заведи гиганта на бомбу")
        }
    }

    /// Short live status between the two top buttons, refreshed 4× a second.
    private func updateGoalLabel(force: Bool) {
        guard force || world.time - lastGoalUpdate >= 0.25 else { return }
        lastGoalUpdate = world.time
        var text: String
        switch world.goal {
        case .becomeBiggest:
            text = String(localized: "Стань самой большой")
        case .reachMass(let multiple):
            let now = (world.player?.mass ?? 0) / max(world.initialPlayerMass, 1)
            text = String(localized: "Масса ×\(Self.format(now)) из ×\(Self.format(multiple))")
        case .survive(let seconds):
            let left = max(Int((seconds - world.time).rounded(.up)), 0)
            text = String(localized: "Продержись \(left / 60):\(String(format: "%02d", left % 60))")
        case .eatTarget:
            text = String(localized: "Поглоти цель")
        case .eatAllHunters:
            let left = world.bodies.filter { $0.kind == .hunter }.count
            text = String(localized: "Охотников осталось: \(left)")
        case .travel(let times):
            text = String(localized: "Червоточины: \(world.playerTeleports) из \(times)")
        case .trap(let id):
            // Distance from the giant to the bomb, so you can tell whether the lure is working.
            if let giant = world.bodies.first(where: { $0.id == id }),
               let gap = world.bodies.filter({ $0.kind == .bomb })
                .map({ ($0.position - giant.position).length - $0.radius - giant.radius }).min() {
                text = String(localized: "Гигант до бомбы: \(max(Int(gap), 0))")
            } else {
                text = String(localized: "Заведи гиганта на бомбу")
            }
        }
        if playback != nil { text = "▶︎ " + String(localized: "Повтор") + " · " + text }
        if text != lastGoalText {
            lastGoalText = text
            goalLabel.text = text
            fitGoalLabel()
        }
        goalLabel.isHidden = world.state != .playing
    }

    private var goalLabelMaxWidth: CGFloat = 200

    /// Shrinks the caption if it would run into the buttons (long goals, narrow phones).
    private func fitGoalLabel() {
        goalLabel.setScale(1)
        let width = goalLabel.frame.width
        if width > goalLabelMaxWidth { goalLabel.setScale(goalLabelMaxWidth / width) }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// Dashed rotating ring around the `eatTarget` body.
    private func updateTargetMarker() {
        guard let id = goalTargetID,
              let target = world.bodies.first(where: { $0.id == id }),
              world.state == .playing else {
            targetMarker.isHidden = true
            return
        }
        let scale = cam.xScale
        let radius = CGFloat(target.radius) + 10 * scale
        let circle = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        targetMarker.path = circle.copy(dashingWithPhase: 0, lengths: [8 * scale, 6 * scale])
        targetMarker.lineWidth = 2 * scale
        targetMarker.position = CGPoint(x: target.position.x, y: target.position.y)
        if !reduceMotion { targetMarker.zRotation = CGFloat(world.time * 0.4) }
        targetMarker.isHidden = false
    }

    // MARK: - Terrain: nebulae, wormholes

    private var wormholeNodes: [SKNode] = []

    private func buildTerrain() {
        terrainLayer.removeAllChildren()
        wormholeNodes.removeAll()
        for nebula in world.nebulae {
            // Two offset soft blobs read as a cloud rather than a disc.
            for (offset, tint, alpha) in [(Vec2(0, 0), Palette.nebula, 0.22), (Vec2(0.25, -0.2), Palette.attractor, 0.14)] {
                let cloud = SKSpriteNode(texture: softTexture)
                let side = nebula.radius * 2.3
                cloud.size = CGSize(width: side, height: side * 0.9)
                let c = nebula.center + offset * nebula.radius
                cloud.position = CGPoint(x: c.x, y: c.y)
                cloud.color = tint
                cloud.colorBlendFactor = 1
                cloud.blendMode = .add
                cloud.alpha = CGFloat(alpha)
                terrainLayer.addChild(cloud)
            }
        }
        for hole in world.wormholes {
            for (point, color) in [(hole.a, Palette.wormholeA), (hole.b, Palette.wormholeB)] {
                let mouth = SKNode()
                mouth.position = CGPoint(x: point.x, y: point.y)
                // Glow, then two dashed rings spinning in opposite directions.
                let glow = SKSpriteNode(texture: softTexture)
                glow.size = CGSize(width: hole.radius * 3.2, height: hole.radius * 3.2)
                glow.color = color
                glow.colorBlendFactor = 1
                glow.blendMode = .add
                glow.alpha = 0.35
                mouth.addChild(glow)
                for (index, scale) in [1.0, 0.65].enumerated() {
                    let r = CGFloat(hole.radius * scale)
                    let circle = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
                    let ring = SKShapeNode(path: circle.copy(dashingWithPhase: 0, lengths: [r * 0.5, r * 0.25]))
                    ring.strokeColor = color
                    ring.lineWidth = 3
                    ring.name = index == 0 ? "outer" : "inner"
                    mouth.addChild(ring)
                }
                terrainLayer.addChild(mouth)
                wormholeNodes.append(mouth)
            }
        }
    }

    private func animateWormholes() {
        guard !reduceMotion else { return }
        let angle = CGFloat(world.time)
        for mouth in wormholeNodes {
            mouth.childNode(withName: "outer")?.zRotation = angle * 1.2
            mouth.childNode(withName: "inner")?.zRotation = -angle * 2
        }
    }

    private func handleTeleports(_ teleports: [World.Teleport]) {
        for teleport in teleports {
            for point in [teleport.from, teleport.to] {
                let flash = SKSpriteNode(texture: softTexture)
                flash.size = CGSize(width: 140, height: 140)
                flash.position = CGPoint(x: point.x, y: point.y)
                flash.blendMode = .add
                flash.zPosition = 4
                terrainLayer.addChild(flash)
                flash.run(.sequence([.group([.scale(to: 1.8, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
            }
            if teleport.bodyID == world.playerID {
                if playback == nil { award(.traveler) }
                onTeleport?()
                // Jump the camera instead of sweeping across the whole map.
                if let player = world.player { cam.position = CGPoint(x: player.position.x, y: player.position.y) }
            }
        }
    }

    // MARK: - Pulsar

    private func handlePulses(_ pulses: [World.Pulse]) {
        for pulse in pulses {
            let ring = SKShapeNode(circleOfRadius: CGFloat(pulse.reach))
            ring.strokeColor = Palette.pulsar
            ring.fillColor = Palette.pulsar.withAlphaComponent(0.05)
            ring.lineWidth = 3 * cam.xScale
            ring.position = CGPoint(x: pulse.position.x, y: pulse.position.y)
            ring.zPosition = 3.5
            ring.setScale(0.1)
            bodyLayer.addChild(ring)
            let grow = SKAction.scale(to: 1, duration: 0.6)
            grow.timingMode = .easeOut
            ring.run(.sequence([.group([grow, .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        }
    }

    // MARK: - Share

    /// Shares a picture of the result screen. GameView shows the system share sheet.
    var onShare: ((UIImage, String) -> Void)?
    private var shareButtonFrame: CGRect?

    private func requestShare() {
        guard let view, let texture = view.texture(from: self) else { return }
        let image = UIImage(cgImage: texture.cgImage())
        let stars = LevelRating.stars(ejectedMass: world.playerEjectedMass, initialMass: world.initialPlayerMass)
        let what: String = switch mode {
        case .campaign(let level): String(localized: "уровень \(level + 1)")
        case .daily: String(localized: "ежедневный уровень")
        case .sandbox: String(localized: "песочница")
        }
        let text = String(localized: "Accretion: \(what) — \(String(repeating: "★", count: stars))\(String(repeating: "☆", count: 3 - stars))")
        onShare?(image, text)
    }

    // MARK: - Supernova

    private func handleExplosions(_ explosions: [World.Explosion]) {
        for explosion in explosions {
            onExplosion?()
            if playback == nil, let player = world.player, (player.position - explosion.position).length < 500 {
                award(.supernovaSurvivor)
            }
            let center = CGPoint(x: explosion.position.x, y: explosion.position.y)
            for (color, delay, growth) in [(UIColor.white, 0.0, 6.0), (UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1), 0.08, 4.0)] {
                let ring = SKShapeNode(circleOfRadius: CGFloat(explosion.radius))
                ring.strokeColor = color
                ring.fillColor = color.withAlphaComponent(0.15)
                ring.lineWidth = 4 * cam.xScale
                ring.position = center
                ring.zPosition = 4
                ring.alpha = 0
                bodyLayer.addChild(ring)
                let grow = SKAction.scale(to: reduceMotion ? 1 : CGFloat(growth), duration: 0.9)
                grow.timingMode = .easeOut
                ring.run(.sequence([
                    .wait(forDuration: delay),
                    .fadeIn(withDuration: 0.05),
                    .group([grow, .fadeOut(withDuration: 0.9)]),
                    .removeFromParent(),
                ]))
            }
            // Flash the whole screen only if the blast is on screen.
            let rel = CGPoint(x: (center.x - cam.position.x) / cam.xScale, y: (center.y - cam.position.y) / cam.xScale)
            if !reduceMotion, abs(rel.x) < size.width, abs(rel.y) < size.height {
                screenFlash.removeAllActions()
                screenFlash.alpha = 0.35
                screenFlash.run(.fadeOut(withDuration: 0.5))
            }
        }
    }

    /// Ring around the player: how far it is from outweighing the biggest other body (the win condition).
    private func updateMassRing() {
        guard let player = world.player, world.state == .playing else {
            massRing.isHidden = true
            massRingTrack.isHidden = true
            return
        }
        let progress = world.goalProgress
        massRing.strokeColor = playerColor.withAlphaComponent(0.9)
        let scale = cam.xScale
        let radius = CGFloat(player.radius) + 7 * scale
        let position = CGPoint(x: player.position.x, y: player.position.y)

        massRingTrack.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        let arc = CGMutablePath()
        arc.addArc(center: .zero, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * CGFloat(progress), clockwise: true)
        massRing.path = arc
        for ring in [massRingTrack, massRing] {
            ring.lineWidth = 2.5 * scale
            ring.position = position
            ring.isHidden = false
        }
    }

    /// Red arrows at the screen edge for bigger bodies out of view, plus the danger level for the music.
    private func updateThreatsAndDanger() {
        guard let player = world.player, world.state == .playing else {
            arrows.forEach { $0.isHidden = true }
            onDanger?(0)
            return
        }
        let scale = Double(cam.xScale)
        let halfW = Double(size.width) / 2 * scale
        let halfH = Double(size.height) / 2 * scale
        let camPos = Vec2(Double(cam.position.x), Double(cam.position.y))
        let range = max(halfW, halfH) * 2.5

        var danger = 0.0
        var offscreen: [(gap: Double, body: Body)] = []
        for body in world.bodies where body.id != player.id && ((body.mass > player.mass * 1.05 && body.kind != .planet) || body.kind == .antimatter) {
            let gap = (body.position - player.position).length - body.radius - player.radius
            danger = max(danger, min(max(1 - gap / (player.radius * 6 + 120), 0), 1))
            let rel = body.position - camPos
            let outOfView = abs(rel.x) > halfW + body.radius || abs(rel.y) > halfH + body.radius
            if outOfView, gap < range { offscreen.append((gap, body)) }
        }
        onDanger?(danger)

        offscreen.sort { $0.gap < $1.gap }
        // The goal target always gets the first arrow when it's out of view, whatever its size.
        if let id = goalTargetID, let target = world.bodies.first(where: { $0.id == id }) {
            offscreen.removeAll { $0.body.id == id }
            let rel = target.position - camPos
            if abs(rel.x) > halfW + target.radius || abs(rel.y) > halfH + target.radius {
                offscreen.insert((0, target), at: 0)
            }
        }
        let insets = view?.safeAreaInsets ?? .zero
        let edgeX = Double(size.width) / 2 - 26 - Double(max(insets.left, insets.right))
        let edgeY = Double(size.height) / 2 - 26 - Double(max(insets.top, insets.bottom))
        for (index, arrow) in arrows.enumerated() {
            guard index < offscreen.count else {
                arrow.isHidden = true
                continue
            }
            let (gap, body) = offscreen[index]
            if let id = goalTargetID, body.id == id {
                arrow.fillColor = Palette.target
            } else {
                arrow.fillColor = switch body.kind {
                case .attractor: Palette.attractor
                case .antimatter: Palette.antimatter
                default: threatColor
                }
            }
            let v = (body.position - camPos) / scale // in screen points
            let t = min(edgeX / max(abs(v.x), 1e-6), edgeY / max(abs(v.y), 1e-6))
            var position = CGPoint(x: v.x * t, y: v.y * t)
            // Slide along the edge so the arrow never covers the time-warp button or the menu button
            // (SwiftUI, mirrored at top-left).
            let menuButton = CGPoint(x: -warpButton.position.x, y: warpButton.position.y)
            let restartButton = CGPoint(x: menuButton.x + GameScene.topButtonSpacing, y: menuButton.y)
            for button in [warpButton.position, menuButton, restartButton] where (position - button).length < 48 {
                if abs(position.x) >= CGFloat(edgeX) - 1 {
                    position.y = button.y - 48
                } else {
                    position.x = button.x - 48 * (button.x > 0 ? 1 : -1)
                }
            }
            // Same for the goal caption between the buttons.
            if !goalLabel.isHidden, position.y > goalLabel.position.y - 30,
               abs(position.x) < goalLabel.frame.width / 2 + 24 {
                position.y = goalLabel.position.y - 36
            }
            arrow.position = position
            arrow.zRotation = CGFloat(atan2(v.y, v.x))
            arrow.alpha = CGFloat(0.35 + 0.65 * (1 - gap / range))
            arrow.isHidden = false
        }
    }

    // MARK: - Overlays: particles and flash

    private func handleEvents(_ events: [World.ContactEvent]) {
        guard !events.isEmpty else { return }
        let playerID = world.playerID
        let playerMass = world.player?.mass ?? 0

        if events.contains(where: { $0.smallID == playerID || ($0.annihilation && $0.bigID == playerID) }) {
            beingEatenUntil = world.time + 0.2
            // Heartbeat-like haptic while being drained, not on every frame.
            if world.time - lastHeartbeat > 0.45 {
                lastHeartbeat = world.time
                onBeingEaten?()
            }
        }

        // A flash when the player swallows something meaningful (12%+ of its own mass at its peak).
        if events.contains(where: { $0.swallowed && $0.bigID == playerID && (peakMass[$0.smallID] ?? 0) > playerMass * 0.12 }) {
            flashPlayer()
        }

        // Particles every other frame, strongest few contacts only.
        guard !reduceMotion, frameCounter % 2 == 0, particleLayer.children.count < 160 else { return }
        var strongest: [Int: World.ContactEvent] = [:]
        for event in events where event.mass > (strongest[event.smallID]?.mass ?? 0) {
            strongest[event.smallID] = event
        }
        for event in strongest.values.sorted(by: { $0.mass > $1.mass }).prefix(6) {
            spawnParticle(for: event)
        }
    }

    private func spawnParticle(for event: World.ContactEvent) {
        guard let big = world.bodies.first(where: { $0.id == event.bigID }) else { return }
        let toBig = big.position - event.smallPosition
        let distance = toBig.length
        guard distance > 1e-6 else { return }
        let dir = toBig / distance
        let perp = Vec2(-dir.y, dir.x)
        let start = event.smallPosition + dir * event.smallRadius * 0.6 + perp * event.smallRadius * Double.random(in: -0.5...0.5)

        let particle = SKSpriteNode(texture: glowTexture)
        let side = CGFloat(min(max(event.smallRadius * 0.55, 2.5), 12)) * CGFloat(GameScene.glowScale)
        particle.size = CGSize(width: side, height: side)
        particle.color = nodes[event.smallID]?.color ?? Palette.neutral
        particle.colorBlendFactor = 1
        particle.blendMode = .add
        particle.alpha = 0.9
        particle.position = CGPoint(x: start.x, y: start.y)
        particleLayer.addChild(particle)

        let move = SKAction.move(to: CGPoint(x: big.position.x, y: big.position.y), duration: 0.35)
        move.timingMode = .easeIn
        particle.run(.sequence([
            .group([move, .scale(to: 0.3, duration: 0.35), .fadeAlpha(to: 0, duration: 0.35)]),
            .removeFromParent(),
        ]))
    }

    private func flashPlayer() {
        guard let player = world.player else { return }
        let wave = SKShapeNode(circleOfRadius: CGFloat(player.radius))
        wave.strokeColor = playerColor
        wave.fillColor = .clear
        wave.lineWidth = 3 * cam.xScale
        wave.position = CGPoint(x: player.position.x, y: player.position.y)
        wave.zPosition = 4
        bodyLayer.addChild(wave)
        let grow = SKAction.scale(to: reduceMotion ? 1.2 : 2.6, duration: 0.55)
        grow.timingMode = .easeOut
        wave.run(.sequence([.group([grow, .fadeOut(withDuration: 0.55)]), .removeFromParent()]))

        if !reduceMotion, let node = nodes[player.id] {
            node.run(.sequence([.scale(to: 1.12, duration: 0.08), .scale(to: 1, duration: 0.25)]))
        }
    }

    // MARK: - Result overlay

    /// Numbers on the result screen; kept so the screen can be shown again after watching the replay.
    private struct ResultStats {
        var stars: Int
        var seconds: Int
        var spentPercent: Int
    }
    private var lastStats: ResultStats?

    /// `recording`: a real finish (save stars, unlock, keep the replay). False when coming back from a replay.
    private func showResult(recording: Bool = true) {
        let stats = (recording ? nil : lastStats) ?? ResultStats(
            stars: LevelRating.stars(ejectedMass: world.playerEjectedMass, initialMass: world.initialPlayerMass),
            seconds: Int(world.time),
            spentPercent: Int((world.playerEjectedMass / max(world.initialPlayerMass, 1) * 100).rounded())
        )
        let stars = stats.stars
        if recording {
            lastStats = stats
            awardForWin(stats)
            GameProgress.record(stars: stars, for: mode)
            if case .campaign(let level) = mode { GameProgress.unlock(upTo: level + 1) }
            let run = Replay(stars: stars, time: world.time, inputs: recorded)
            lastRun = run
            ReplayStore.saveIfBetter(run, for: mode)
        }

        goalLabel.isHidden = true
        banner.removeAllActions()
        banner.alpha = 0
        // Whoever won a level no longer needs the "touch to fly" hint.
        hasMoved = true
        hint.removeAllActions()
        hint.removeFromParent()
        resultLayer.removeAllChildren()
        resultLayer.isHidden = false
        resultLayer.alpha = 0
        resultLayer.run(.fadeIn(withDuration: 0.4))

        let dim = SKSpriteNode(color: .black, size: CGSize(width: size.width * 2, height: size.height * 2))
        dim.alpha = 0.55
        resultLayer.addChild(dim)

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        switch mode {
        case .campaign(let level): title.text = String(localized: "Уровень \(level + 1) пройден")
        case .daily: title.text = String(localized: "Ежедневный уровень пройден")
        case .sandbox: title.text = String(localized: "Песочница пройдена")
        }
        title.fontSize = 30
        title.position = CGPoint(x: 0, y: 90)
        resultLayer.addChild(title)

        for index in 0..<3 {
            let star = SKShapeNode(path: GameScene.starPath(radius: 26))
            star.position = CGPoint(x: CGFloat(index - 1) * 72, y: 20)
            star.lineWidth = 2
            if index < stars {
                star.fillColor = Palette.player
                star.strokeColor = Palette.player
                star.setScale(0)
                let pop = SKAction.sequence([.scale(to: 1.25, duration: 0.15), .scale(to: 1, duration: 0.1)])
                star.run(.sequence([.wait(forDuration: 0.5 + Double(index) * 0.35), .run { [weak self] in self?.onStar?() }, pop]))
            } else {
                star.fillColor = .clear
                star.strokeColor = UIColor(white: 1, alpha: 0.3)
            }
            resultLayer.addChild(star)
        }

        let seconds = stats.seconds
        let spent = stats.spentPercent
        let statsLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
        statsLabel.text = String(localized: "Время \(seconds / 60):\(String(format: "%02d", seconds % 60)) · потрачено \(spent)% массы")
        statsLabel.fontSize = 17
        statsLabel.fontColor = UIColor(white: 1, alpha: 0.75)
        statsLabel.position = CGPoint(x: 0, y: -50)
        resultLayer.addChild(statsLabel)

        // Two pills under the stats: replay and share. Tapping anywhere else continues.
        let pillSize = CGSize(width: 150, height: 44)
        func pill(_ text: String, x: CGFloat) -> CGRect {
            let center = CGPoint(x: x, y: -115)
            let node = SKShapeNode(rectOf: pillSize, cornerRadius: 22)
            node.position = center
            node.fillColor = UIColor(white: 1, alpha: 0.1)
            node.strokeColor = UIColor(white: 1, alpha: 0.35)
            let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            label.text = text
            label.fontSize = 17
            label.verticalAlignmentMode = .center
            node.addChild(label)
            resultLayer.addChild(node)
            // Hit area in view points (view y grows downward), a little larger than the pill.
            return CGRect(
                x: size.width / 2 + center.x - pillSize.width / 2,
                y: size.height / 2 - center.y - pillSize.height / 2,
                width: pillSize.width, height: pillSize.height
            ).insetBy(dx: -6, dy: -8)
        }
        replayButtonFrame = lastRun == nil ? nil : pill(String(localized: "Повтор"), x: -82)
        shareButtonFrame = pill(String(localized: "Поделиться"), x: lastRun == nil ? 0 : 82)

        let next = SKLabelNode(fontNamed: "AvenirNext-Medium")
        next.text = String(localized: "Коснись, чтобы продолжить")
        next.fontSize = 18
        next.fontColor = .white
        next.alpha = 0
        next.position = CGPoint(x: 0, y: -size.height * 0.3)
        resultLayer.addChild(next)
        let breathe = SKAction.sequence([.fadeAlpha(to: 0.35, duration: 0.9), .fadeAlpha(to: 0.9, duration: 0.9)])
        next.run(.sequence([.wait(forDuration: 1.2), .fadeAlpha(to: 0.9, duration: 0.4), .repeatForever(breathe)]))

        // A finger still held from the last puff must not skip the result instantly.
        run(.wait(forDuration: 0.8)) { [weak self] in self?.awaitingContinue = true }
    }

    private func nextLevel() {
        awaitingContinue = false
        switch mode {
        case .campaign(let level):
            startCampaign(level: level + 1)
        case .daily:
            // Back to where the campaign left off.
            startCampaign(level: GameProgress.currentLevel)
        case .sandbox(let config):
            startSandbox(config.reshuffled())
        }
    }

    // MARK: - Replay

    /// Thrusts of the current run, for saving as a replay.
    private var recorded: [Replay.Input] = []
    /// The run that just ended, for "watch replay" on the result screen.
    private var lastRun: Replay?
    private struct Playback {
        var inputs: [Replay.Input]
        var cursor = 0
        /// Came from the result screen: show it again afterwards. Otherwise go back to the campaign.
        var returnToResult: Bool
        var finishing = false
    }
    private var playback: Playback?
    private var playbackAccumulator = 0.0
    private static let playbackSpeed = 2.0
    private var replayButtonFrame: CGRect?

    var isPlayingBack: Bool { playback != nil }

    /// Re-runs the level from scratch, feeding the recorded thrusts on the same steps.
    private func play(_ replay: Replay, returnToResult: Bool) {
        loadLevel()
        hint.removeFromParent()
        hasMoved = true
        playback = Playback(inputs: replay.inputs, returnToResult: returnToResult)
        playbackAccumulator = 0
        setBanner(title: String(localized: "Повтор"), subtitle: String(localized: "Коснись, чтобы выйти"))
        banner.removeAllActions()
        banner.alpha = 1
        banner.run(.sequence([.wait(forDuration: 1.5), .fadeOut(withDuration: 0.6)]))
        updateGoalLabel(force: true)
    }

    /// Menu: watch the best run of a campaign level, then return to the campaign.
    func playBestReplay(level: Int) {
        guard let replay = ReplayStore.best(for: .campaign(level: level)) else { return }
        mode = .campaign(level: level)
        play(replay, returnToResult: false)
    }

    private func stepPlayback(dt: Double) {
        guard var current = playback else { return }
        playbackAccumulator += min(dt, 0.1) * GameScene.playbackSpeed * warpSpeed
        while playbackAccumulator >= World.fixedStep, world.state == .playing {
            while current.cursor < current.inputs.count, current.inputs[current.cursor].step <= world.stepCount {
                let input = current.inputs[current.cursor]
                world.thrust(toward: Vec2(input.x, input.y), awayFromTarget: input.away)
                current.cursor += 1
            }
            world.step(World.fixedStep)
            playbackAccumulator -= World.fixedStep
        }
        playback = current
        if world.state != .playing, !current.finishing {
            playback?.finishing = true
            run(.wait(forDuration: 1.2)) { [weak self] in self?.finishPlayback() }
        }
    }

    private func finishPlayback() {
        guard let finished = playback else { return }
        playback = nil
        removeAllActions()
        if finished.returnToResult, world.state == .won {
            restartScheduled = true
            showResult(recording: false)
        } else if finished.returnToResult {
            nextLevel()
        } else {
            startCampaign(level: GameProgress.currentLevel)
        }
    }

    // MARK: - Achievements

    /// Newly unlocked achievement (sound + haptic in GameView).
    var onAchievement: ((Achievement) -> Void)?
    private var countedSwallows = 0
    private var toastQueue: [Achievement] = []
    private var toastShowing = false

    private func award(_ achievement: Achievement) {
        guard playback == nil, AchievementStore.unlock(achievement) else { return }
        onAchievement?(achievement)
        toastQueue.append(achievement)
        showNextToast()
    }

    /// Swallow-based achievements, checked whenever the player's swallow count grows.
    private func checkSwallowAchievements() {
        guard playback == nil, world.playerSwallowCount > countedSwallows else { return }
        AchievementStore.addSwallowed(world.playerSwallowCount - countedSwallows)
        countedSwallows = world.playerSwallowCount
        if AchievementStore.totalSwallowed >= 100 { award(.hundredSwallowed) }
        let kinds = world.playerSwallowsByKind
        if kinds[.hunter, default: 0] > 0 { award(.hunterHunter) }
        if kinds[.comet, default: 0] > 0 { award(.cometCatcher) }
        if kinds[.binary, default: 0] > 0 { award(.binaryBreaker) }
        if kinds[.astronaut, default: 0] > 0 { award(.astronaut) }
    }

    private func awardForWin(_ stats: ResultStats) {
        award(.firstWin)
        if stats.stars == 3 { award(.threeStars) }
        if case .trap = world.goal { award(.bomber) }
        if stats.spentPercent == 0 { award(.zen) }
        if GameProgress.maxUnlockedLevel >= 9 { award(.tenLevels) }
        if GameProgress.maxUnlockedLevel >= 19 { award(.twentyLevels) }
        switch mode {
        case .daily: award(.daily)
        case .sandbox: award(.sandbox)
        case .campaign: break
        }
    }

    /// One toast at a time, sliding in under the top buttons.
    private func showNextToast() {
        guard !toastShowing, !toastQueue.isEmpty else { return }
        toastShowing = true
        let achievement = toastQueue.removeFirst()

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = "★ " + achievement.title
        label.fontSize = 16
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        let width = max(label.frame.width + 40, 200)
        let toast = SKShapeNode(rectOf: CGSize(width: width, height: 40), cornerRadius: 20)
        toast.fillColor = Palette.player
        toast.strokeColor = .clear
        toast.zPosition = 30
        toast.addChild(label)
        let restY = warpButton.position.y - 64
        toast.position = CGPoint(x: 0, y: restY + 30)
        toast.alpha = 0
        cam.addChild(toast)

        let slideIn = SKAction.group([.fadeIn(withDuration: 0.25), .moveTo(y: restY, duration: 0.25)])
        slideIn.timingMode = .easeOut
        toast.run(.sequence([
            slideIn,
            .wait(forDuration: 2.2),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
        ])) { [weak self] in
            self?.toastShowing = false
            self?.showNextToast()
        }
    }

    // MARK: - Mode switching (called from the menu)

    func startSandbox(_ config: SandboxConfig) {
        SandboxConfig.saved = config
        mode = .sandbox(config)
        if world != nil { loadLevel() }
    }

    func startCampaign(level: Int) {
        GameProgress.currentLevel = level
        mode = .campaign(level: level)
        if world != nil { loadLevel() }
    }

    func startDaily() {
        mode = .daily(day: GameProgress.today)
        if world != nil { loadLevel() }
    }

    func restartLevel() {
        if world != nil { loadLevel() }
    }

    private var levelTitle: String {
        switch mode {
        case .campaign(let level): String(localized: "Уровень \(level + 1)")
        case .daily: String(localized: "Ежедневный уровень")
        case .sandbox: String(localized: "Песочница")
        }
    }

    private static func starPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? radius : radius * 0.45
            let angle = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let point = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Art

    private func buildBackdrop() {
        backdrop.removeAllChildren()
        var rng = SplitMix64(seed: 42)
        let dot = SKTexture(image: GameScene.makeDotImage())
        for _ in 0..<Int(world.size.x * world.size.y / 9000) {
            let star = SKSpriteNode(texture: dot)
            let s = CGFloat(Double.random(in: 1...3, using: &rng))
            star.size = CGSize(width: s, height: s)
            star.alpha = CGFloat(Double.random(in: 0.15...0.5, using: &rng))
            star.position = CGPoint(
                x: Double.random(in: 0...world.size.x, using: &rng),
                y: Double.random(in: 0...world.size.y, using: &rng)
            )
            backdrop.addChild(star)
        }
    }

    private static func makeGlowTexture() -> SKTexture {
        let side: CGFloat = 256
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: side / 2, y: side / 2)
            let core = side / 2 / CGFloat(glowScale)
            let colors = [
                UIColor(white: 1, alpha: 1).cgColor,
                UIColor(white: 1, alpha: 0.95).cgColor,
                UIColor(white: 1, alpha: 0.25).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray
            let coreStop = core / (side / 2)
            let locations: [CGFloat] = [0, coreStop * 0.85, coreStop, 1]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)!
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side / 2, options: [])
        }
        return SKTexture(image: image)
    }

    /// Smooth radial falloff with no hard core: clouds, flashes, portal glow.
    private lazy var coronaTexture = GameScene.makeCoronaTexture()
    private lazy var astronautTexture = GameScene.makeAstronautTexture()
    private lazy var blackHoleTexture = GameScene.makeBlackHoleTexture()
    private lazy var accretionDiskTexture = GameScene.makeAccretionDiskTexture()
    private lazy var planetTextures = (0..<4).map { GameScene.makePlanetTexture(variant: $0) }
    private lazy var ringTexture = GameScene.makeRingTexture()
    private var lastBounces = 0
    /// The player bounced off a planet.
    var onBounce: (() -> Void)?

    /// Black disc (exactly the swallowing radius at 80% of the texture) with a thin bright photon ring.
    private static func makeBlackHoleTexture() -> SKTexture {
        let side: CGFloat = 256
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let cg = ctx.cgContext
            let c = side / 2
            let r = c * 0.8
            // Soft photon glow, then the sharp ring, then the shadow.
            cg.setStrokeColor(UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 0.25).cgColor)
            cg.setLineWidth(14)
            cg.strokeEllipse(in: CGRect(x: c - r * 1.03, y: c - r * 1.03, width: r * 2.06, height: r * 2.06))
            cg.setStrokeColor(UIColor(red: 1, green: 0.9, blue: 0.75, alpha: 0.95).cgColor)
            cg.setLineWidth(3)
            cg.strokeEllipse(in: CGRect(x: c - r * 1.03, y: c - r * 1.03, width: r * 2.06, height: r * 2.06))
            UIColor.black.setFill()
            cg.fillEllipse(in: CGRect(x: c - r, y: c - r, width: r * 2, height: r * 2))
        }
        return SKTexture(image: image)
    }

    /// Hot gas disk: white-yellow at the inner edge, through orange to deep red, with spiral streaks.
    private static func makeAccretionDiskTexture() -> SKTexture {
        let side: CGFloat = 512
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let cg = ctx.cgContext
            let c = CGPoint(x: side / 2, y: side / 2)
            let inner = side / 2 * 0.36
            let colors = [
                UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 0.95).cgColor,
                UIColor(red: 1, green: 0.62, blue: 0.25, alpha: 0.7).cgColor,
                UIColor(red: 0.75, green: 0.2, blue: 0.35, alpha: 0.35).cgColor,
                UIColor(red: 0.35, green: 0.1, blue: 0.5, alpha: 0).cgColor,
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 0.6, 1])!
            cg.drawRadialGradient(gradient, startCenter: c, startRadius: inner, endCenter: c, endRadius: side / 2, options: [])
            // Spiral streaks so the rotation is visible.
            var rng = SplitMix64(seed: 3)
            for _ in 0..<70 {
                let start = CGFloat(Double.random(in: 0..<(2 * .pi), using: &rng))
                let radius = inner + CGFloat(Double.random(in: 0.02...0.55, using: &rng)) * side / 2
                let sweep = CGFloat(Double.random(in: 0.3...1.2, using: &rng))
                let path = UIBezierPath(arcCenter: c, radius: radius, startAngle: start, endAngle: start + sweep, clockwise: true)
                path.lineWidth = CGFloat(Double.random(in: 1...3.5, using: &rng))
                UIColor(red: 1, green: 0.85, blue: 0.6, alpha: CGFloat(Double.random(in: 0.08...0.35, using: &rng))).setStroke()
                path.stroke()
            }
            // Clear the middle so the black hole sits in a hole.
            cg.setBlendMode(.clear)
            cg.fillEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
        }
        return SKTexture(image: image)
    }

    /// Four planet looks: banded gas giant, ice giant, rusty rock, lavender. Lit from the top-left.
    private static func makePlanetTexture(variant: Int) -> SKTexture {
        let palettes: [(UIColor, UIColor)] = [
            (UIColor(red: 0.85, green: 0.7, blue: 0.5, alpha: 1), UIColor(red: 0.6, green: 0.42, blue: 0.28, alpha: 1)),
            (UIColor(red: 0.45, green: 0.75, blue: 0.85, alpha: 1), UIColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)),
            (UIColor(red: 0.78, green: 0.42, blue: 0.3, alpha: 1), UIColor(red: 0.55, green: 0.28, blue: 0.2, alpha: 1)),
            (UIColor(red: 0.72, green: 0.62, blue: 0.85, alpha: 1), UIColor(red: 0.5, green: 0.42, blue: 0.68, alpha: 1)),
        ]
        let (base, band) = palettes[variant % palettes.count]
        let side: CGFloat = 256
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let cg = ctx.cgContext
            let disc = CGRect(x: 2, y: 2, width: side - 4, height: side - 4)
            cg.addEllipse(in: disc)
            cg.clip()
            base.setFill()
            cg.fill(disc)
            var rng = SplitMix64(seed: UInt64(variant + 11))
            if variant == 2 {
                // Rocky: craters instead of bands.
                for _ in 0..<14 {
                    let r = CGFloat(Double.random(in: 6...26, using: &rng))
                    let x = CGFloat(Double.random(in: 20...236, using: &rng))
                    let y = CGFloat(Double.random(in: 20...236, using: &rng))
                    band.withAlphaComponent(0.6).setFill()
                    cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
            } else {
                // Gas bands with a slight wave.
                var y: CGFloat = 0
                while y < side {
                    let height = CGFloat(Double.random(in: 8...28, using: &rng))
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: 0, y: y))
                    for x in stride(from: 0, through: side, by: 16) {
                        path.addLine(to: CGPoint(x: x, y: y + sin(x / 30 + y) * 3))
                    }
                    path.addLine(to: CGPoint(x: side, y: y + height))
                    path.addLine(to: CGPoint(x: 0, y: y + height))
                    path.close()
                    band.withAlphaComponent(CGFloat(Double.random(in: 0.2...0.6, using: &rng))).setFill()
                    path.fill()
                    y += height + CGFloat(Double.random(in: 6...22, using: &rng))
                }
            }
            // Day side and night side.
            let light = CGPoint(x: side * 0.32, y: side * 0.3)
            let shade = [UIColor(white: 1, alpha: 0.3).cgColor, UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.7).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: shade, locations: [0, 0.45, 1])!
            cg.drawRadialGradient(gradient, startCenter: light, startRadius: 0, endCenter: CGPoint(x: side / 2, y: side / 2), endRadius: side * 0.62, options: [.drawsAfterEndLocation])
        }
        return SKTexture(image: image)
    }

    /// A thin tilted ring (drawn flat; the sprite squashes it).
    private static func makeRingTexture() -> SKTexture {
        let size = CGSize(width: 512, height: 512)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            for (inset, alpha, width) in [(40.0, 0.5, 18.0), (70.0, 0.3, 10.0), (20.0, 0.25, 6.0)] {
                cg.setStrokeColor(UIColor(red: 0.95, green: 0.88, blue: 0.75, alpha: alpha).cgColor)
                cg.setLineWidth(width)
                cg.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset))
            }
            // Hide the part of the ring behind the planet (upper half near the middle).
            cg.setBlendMode(.clear)
            cg.fill(CGRect(x: 150, y: 0, width: 212, height: 256))
        }
        return SKTexture(image: image)
    }

    /// A tiny cosmonaut in a white suit with a gold visor and a backpack, drawn once.
    private static func makeAstronautTexture() -> SKTexture {
        let side: CGFloat = 128
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let cg = ctx.cgContext
            let suit = UIColor(white: 0.96, alpha: 1)
            let shade = UIColor(white: 0.72, alpha: 1)
            // Backpack behind the body.
            shade.setFill()
            UIBezierPath(roundedRect: CGRect(x: 40, y: 50, width: 48, height: 44), cornerRadius: 8).fill()
            // Arms and legs.
            suit.setFill()
            UIBezierPath(roundedRect: CGRect(x: 26, y: 60, width: 16, height: 30), cornerRadius: 8).fill()
            UIBezierPath(roundedRect: CGRect(x: 86, y: 60, width: 16, height: 30), cornerRadius: 8).fill()
            UIBezierPath(roundedRect: CGRect(x: 46, y: 92, width: 15, height: 26), cornerRadius: 7).fill()
            UIBezierPath(roundedRect: CGRect(x: 67, y: 92, width: 15, height: 26), cornerRadius: 7).fill()
            // Torso.
            UIBezierPath(roundedRect: CGRect(x: 42, y: 56, width: 44, height: 44), cornerRadius: 12).fill()
            // Chest panel.
            UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 56, y: 70, width: 16, height: 10), cornerRadius: 2).fill()
            // Helmet and gold visor with a highlight.
            suit.setFill()
            cg.fillEllipse(in: CGRect(x: 36, y: 10, width: 56, height: 56))
            UIColor(red: 1, green: 0.78, blue: 0.35, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 46, y: 22, width: 36, height: 28))
            UIColor(white: 1, alpha: 0.7).setFill()
            cg.fillEllipse(in: CGRect(x: 52, y: 26, width: 10, height: 7))
        }
        return SKTexture(image: image)
    }

    /// Irregular soft rays around a hole: a stylised solar corona.
    private static func makeCoronaTexture() -> SKTexture {
        let side: CGFloat = 256
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let cg = ctx.cgContext
            let c = CGPoint(x: side / 2, y: side / 2)
            var rng = SplitMix64(seed: 7)
            for i in 0..<18 {
                let angle = CGFloat(i) / 18 * .pi * 2 + CGFloat(Double.random(in: -0.1...0.1, using: &rng))
                let length = side / 2 * CGFloat(Double.random(in: 0.65...1, using: &rng))
                let width = CGFloat(Double.random(in: 0.05...0.11, using: &rng))
                let ray = CGMutablePath()
                ray.move(to: CGPoint(x: c.x + cos(angle - width) * side * 0.2, y: c.y + sin(angle - width) * side * 0.2))
                ray.addLine(to: CGPoint(x: c.x + cos(angle) * length, y: c.y + sin(angle) * length))
                ray.addLine(to: CGPoint(x: c.x + cos(angle + width) * side * 0.2, y: c.y + sin(angle + width) * side * 0.2))
                ray.closeSubpath()
                cg.saveGState()
                cg.addPath(ray)
                cg.clip()
                let colors = [UIColor(white: 1, alpha: 0.9).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                cg.drawRadialGradient(gradient, startCenter: c, startRadius: side * 0.2, endCenter: c, endRadius: length, options: [])
                cg.restoreGState()
            }
        }
        return SKTexture(image: image)
    }

    private static func makeSoftTexture() -> SKTexture {
        let side: CGFloat = 256
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let center = CGPoint(x: side / 2, y: side / 2)
            let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.45).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            ctx.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side / 2, options: [])
        }
        return SKTexture(image: image)
    }

    private static func makeDotImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}

private extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    var length: CGFloat { (x * x + y * y).squareRoot() }
}

private extension UIColor {
    func mixed(with other: UIColor, amount: Double) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}
