import AVFoundation

/// Prototype background music: a slow generative pad (4-chord loop, two crossfading layers) through a large reverb.
/// Placeholder until real tracks are licensed; it never interrupts the user's own music.
@MainActor
final class AmbientMusic {
    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var source: AVAudioSourceNode?
    private let synth = PadSynth()

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback: heard through the speaker even with the Ring/Silent switch on (with .ambient the
            // speaker went silent and only headphones played). .mixWithOthers keeps Spotify etc. playing.
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            log("session setup failed: \(error)")
        }
        // Earlier builds returned here when other audio was playing and never retried, so the
        // pad stayed silent until the next app switch. Mixing means we can play alongside it.
        log("session: category=\(session.category.rawValue) otherAudio=\(session.isOtherAudioPlaying) "
            + "shouldSilenceHint=\(session.secondaryAudioShouldBeSilencedHint) outputVolume=\(session.outputVolume) "
            + "route=\(session.currentRoute.outputs.map(\.portType.rawValue))")
        guard source == nil else {
            startEngine()
            return
        }

        // Use the hardware output rate (48 kHz on some devices). A mono source at a different rate than the
        // output chain fails to start the engine with -10868.
        let hardware = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = hardware.sampleRate > 0 ? hardware.sampleRate : 48_000
        let outFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let synth = self.synth
        synth.sampleRate = sampleRate

        let node = Self.makeSourceNode(synth: synth, format: outFormat)
        source = node

        reverb.loadFactoryPreset(.cathedral)
        reverb.wetDryMix = 55
        engine.attach(node)
        engine.attach(reverb)
        // Let the engine pick the formats between nodes: explicit mono -> stereo links fail on some devices.
        engine.connect(node, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        // The pad measures about -22 dBFS; this brings it to a clearly audible level on speakers.
        engine.mainMixerNode.outputVolume = 0.85
        observeRouteChanges()
        startEngine()
    }

    private var routeObserver: NSObjectProtocol?

    /// Output device changed (Bluetooth connected or dropped, headphones plugged in): iOS stops the engine.
    /// Restart it, or the music stays silent until the app is reopened.
    private func observeRouteChanges() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log("route changed, restarting engine")
                self?.startEngine()
            }
        }
    }

    /// The render block runs on the real-time audio thread. It must NOT inherit the main-actor isolation of
    /// the enclosing class: Swift would insert a main-thread check there and trap (SIGTRAP) on launch.
    private nonisolated static func makeSourceNode(synth: PadSynth, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.renderStereo(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
    }

    private var startAttempts = 0

    /// Starts the engine, retrying a few times. A failed start used to be silently ignored.
    private func startEngine() {
        do {
            try engine.start()
            log("engine running=\(engine.isRunning) sampleRate=\(engine.outputNode.outputFormat(forBus: 0).sampleRate)")
            startAttempts = 0
        } catch {
            log("engine start failed (attempt \(startAttempts + 1)): \(error)")
            guard startAttempts < 5 else { return }
            startAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, !self.engine.isRunning else { return }
                self.startEngine()
            }
        }
    }

    func pause() { engine.pause() }

    private func log(_ message: String) {
        print("[audio] " + message)
    }

    /// Soft bell on top of the pad, e.g. when the player swallows a star.
    /// Pad + danger layer. Fades rather than cuts.
    /// 0…1 from the settings slider. Squared, because loudness feels logarithmic: half the slider ≈ half as loud.
    var musicVolume = 1.0 {
        didSet { synth.musicTarget = musicVolume * musicVolume }
    }
    /// Chimes (swallows, rating stars).
    /// 0…1 for chimes, booms and proximity beeps.
    var soundsVolume = 1.0 {
        didSet { synth.sfxGain = soundsVolume * soundsVolume }
    }
    var soundsEnabled: Bool { soundsVolume > 0.001 }

    func chime() {
        guard soundsEnabled else { return }
        synth.requestChime()
    }

    /// Supernova: falling tone plus a burst of noise.
    func boom() {
        guard soundsEnabled else { return }
        synth.requestBoom()
    }

    /// Positional sound of the nearest objects (see Soundscape). Called every frame from the scene.
    func setVoices(_ voices: [SoundscapeVoice]) { synth.setVoices(voices) }

    /// 0 = calm, 1 = a bigger body is right next to the player. Smoothed on the audio side.
    /// Drives the low drone (music) and the proximity beeps (sounds).
    func setDanger(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        synth.dangerTarget = clamped
        synth.proximityTarget = soundsEnabled ? clamped : 0
    }

    /// World index → chord progression; changes on the next chord boundary.
    func setWorld(_ index: Int) { synth.progressionIndex = ((index % 4) + 4) % 4 }

    /// Short rising chime for going through a wormhole.
    func whoosh() { chime() }
}

/// Real-time render state. Only touched from the audio thread after setup.
final class PadSynth: @unchecked Sendable {
    var sampleRate: Double = 44_100

    /// One progression per world, all in C major / A minor so the pentatonic chime fits every one.
    private let progressions: [[[Double]]] = [
        // 0 — Am(add9) · Fmaj7 · Cadd9 · G6: open, calm.
        [[110.00, 164.81, 246.94, 261.63], [87.31, 130.81, 196.00, 220.00],
         [130.81, 196.00, 293.66, 329.63], [98.00, 146.83, 220.00, 246.94]],
        // 1 — Dm9 · Am7 · Em7 · Fmaj7: wistful.
        [[73.42, 110.00, 174.61, 329.63], [110.00, 164.81, 196.00, 261.63],
         [82.41, 123.47, 146.83, 196.00], [87.31, 130.81, 164.81, 220.00]],
        // 2 — Csus2 · Gsus4 · Fadd9 · Em7: suspended, spacious.
        [[65.41, 98.00, 146.83, 196.00], [98.00, 146.83, 196.00, 261.63],
         [87.31, 130.81, 196.00, 220.00], [82.41, 123.47, 146.83, 196.00]],
        // 3 — Am · Em/G · Dm/F · Esus4: darker, for late levels.
        [[110.00, 164.81, 220.00, 261.63], [98.00, 164.81, 196.00, 246.94],
         [87.31, 146.83, 174.61, 220.00], [82.41, 123.47, 164.81, 220.00]],
    ]
    /// Chosen from the main thread; each layer picks it up at its next silent chord change.
    var progressionIndex = 0
    private var layerChord: [[Double]] = [[], []]
    private var layerChordStep = [-1, -1]

    // Proximity beeps: soft "parking sensor" in the mid range, so a phone speaker plays it clearly.
    var proximityTarget = 0.0
    private var proximity = 0.0
    private var beepClock = 0.0
    private var beepAge = 10.0
    private var beepPhase = 0.0

    private func proximitySample(dt: Double) -> Double {
        proximity += (proximityTarget - proximity) * min(dt * 6, 1)
        if proximity > 0.12 {
            // 1.2 beeps/s far away … ~8/s when touching.
            beepClock += dt * (1.2 + 7 * proximity)
            if beepClock >= 1 {
                beepClock -= 1
                beepAge = 0
            }
        } else {
            beepClock = 0.9 // first beep comes quickly once danger appears
        }
        guard beepAge < 0.15 else { return 0 }
        let freq = 660 + 440 * proximity
        beepPhase += 2 * .pi * freq * dt
        if beepPhase > 2 * .pi { beepPhase -= 2 * .pi }
        let envelope = min(beepAge / 0.003, 1) * exp(-beepAge * 35)
        beepAge += dt
        return sin(beepPhase) * envelope * 0.05 * (0.4 + 0.6 * proximity)
    }
    private let chordSeconds = 9.0
    private let detune = 1.003
    private var time: Double = 0
    /// [layer][voice][osc]
    private var phases = Array(repeating: Array(repeating: [0.0, 0.0], count: 4), count: 2)

    // Chime: A-minor pentatonic, two octaves up, so it fits every chord of the loop.
    private let chimeNotes = [440.00, 523.25, 587.33, 659.25, 783.99, 880.00]
    /// Set from the main thread, consumed by the audio thread. A missed or doubled chime is harmless.
    private var chimeRequests = 0
    private var chimesHandled = 0
    private var chimeIndex = 0
    private var chimeFreq = 0.0
    private var chimeAge = 10.0
    private var chimePhase = (0.0, 0.0)

    func requestChime() { chimeRequests &+= 1 }

    private var boomRequests = 0
    private var boomsHandled = 0
    private var boomAge = 10.0
    private var boomPhase = 0.0
    private var noiseState: UInt32 = 22_222
    private var noiseLowpass = 0.0

    func requestBoom() { boomRequests &+= 1 }

    private func boomSample(dt: Double) -> Double {
        guard boomAge < 3 else { return 0 }
        // Pitch falls from ~300 Hz to ~50 Hz: big, but still audible on a phone speaker at the start.
        let freq = 50 + 250 * exp(-boomAge * 4)
        boomPhase += 2 * .pi * freq * dt
        if boomPhase > 2 * .pi { boomPhase -= 2 * .pi }
        noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
        let white = Double(noiseState) / Double(UInt32.max) * 2 - 1
        noiseLowpass += (white - noiseLowpass) * 0.08
        let tone = (sin(boomPhase) + 0.5 * sin(boomPhase * 2)) * exp(-boomAge * 2.2)
        let rumble = noiseLowpass * exp(-boomAge * 3.5) * 2.5
        boomAge += dt
        return (tone + rumble) * min(boomAge / 0.005, 1) * 0.09
    }

    /// 1 = music on, 0 = off; `musicGain` follows it over ~1 s.
    var musicTarget = 1.0
    /// Sound-effects gain, set from the main thread.
    var sfxGain = 1.0
    private var musicGain = 1.0

    // Danger layer: two close low notes (A2 + B♭2) beating against each other, pulsing like a heartbeat.
    // Built from harmonics so it is audible on a phone speaker, which can't play the fundamentals well.
    var dangerTarget = 0.0
    private var dangerLevel = 0.0
    private var dangerPhase = (0.0, 0.0)

    private func dangerSample(dt: Double) -> Double {
        // ~0.7 s to swell in, ~2 s to fade out.
        let rate = dangerTarget > dangerLevel ? 1.5 : 0.5
        dangerLevel += (dangerTarget - dangerLevel) * min(rate * dt, 1)
        guard dangerLevel > 0.001 else { return 0 }
        dangerPhase.0 += 2 * .pi * 110.00 * dt
        dangerPhase.1 += 2 * .pi * 116.54 * dt
        if dangerPhase.0 > 2 * .pi { dangerPhase.0 -= 2 * .pi }
        if dangerPhase.1 > 2 * .pi { dangerPhase.1 -= 2 * .pi }
        var tone = 0.0
        for k in 1...4 {
            let weight = 1 / Double(k)
            tone += (sin(dangerPhase.0 * Double(k)) + sin(dangerPhase.1 * Double(k))) * weight
        }
        // Heartbeat speeds up with danger: 1.0 → 2.2 beats per second.
        let beat = pow((1 + sin(2 * .pi * time * (1 + 1.2 * dangerLevel))) / 2, 3)
        return tone * (0.4 + 0.6 * beat) * dangerLevel * 0.045
    }

    private var dt: Double { 1 / sampleRate }

    /// Per-block bookkeeping: handle chime and boom requests from the main thread.
    private func beginBlock() {
        if chimeRequests != chimesHandled {
            chimesHandled = chimeRequests
            // Walk the scale with small steps so successive chimes form a little melody.
            chimeIndex = (chimeIndex + [1, 2, 4][chimesHandled % 3]) % chimeNotes.count
            chimeFreq = chimeNotes[chimeIndex]
            chimeAge = 0
            chimePhase = (0, 0)
        }
        if boomRequests != boomsHandled {
            boomsHandled = boomRequests
            boomAge = 0
            boomPhase = 0
        }
    }

    /// One mono sample of the mix: pad, bells, danger tone and effects.
    private func nextMono() -> Double {
        let dt = self.dt
        var bell = 0.0
        if chimeAge < 3 {
            // Bell = fundamental + inharmonic partial, short attack, long exponential tail.
            chimePhase.0 += 2 * .pi * chimeFreq * dt
            chimePhase.1 += 2 * .pi * chimeFreq * 2.76 * dt
            let attack = min(chimeAge / 0.01, 1)
            bell = (sin(chimePhase.0) + 0.3 * sin(chimePhase.1) * exp(-chimeAge * 3)) * attack * exp(-chimeAge * 1.8) * 0.05
            chimeAge += dt
        }
        // Fade in over the first 4 seconds so launch is never abrupt.
        let master = min(time / 4, 1) * 0.06
        var sample = 0.0
        for layer in 0..<2 {
            let shifted = time / chordSeconds + Double(layer) * 0.5
            let step = Int(shifted)
            if step != layerChordStep[layer] {
                // Envelope is at zero here, so switching progression can't click.
                layerChordStep[layer] = step
                let progression = progressions[min(max(progressionIndex, 0), progressions.count - 1)]
                layerChord[layer] = progression[step % progression.count]
            }
            let chord = layerChord[layer]
            // sin² and cos² envelopes: the two layers sum to constant loudness, and each
            // layer changes chord exactly when its envelope is silent, so no clicks.
            let envelope = pow(sin(.pi * shifted.truncatingRemainder(dividingBy: 1)), 2)
            for voice in 0..<chord.count {
                let base = chord[voice]
                for osc in 0..<2 {
                    let freq = osc == 0 ? base : base * detune
                    phases[layer][voice][osc] += 2 * .pi * freq * dt
                    if phases[layer][voice][osc] > 2 * .pi { phases[layer][voice][osc] -= 2 * .pi }
                    sample += sin(phases[layer][voice][osc]) * envelope
                }
            }
        }
        let breathing = 0.85 + 0.15 * sin(2 * .pi * time / 13)
        musicGain += (musicTarget - musicGain) * min(dt * 2, 1)
        let music = (sample * master * breathing + dangerSample(dt: dt)) * musicGain
        let effects = (bell + boomSample(dt: dt) + proximitySample(dt: dt)) * sfxGain
        time += dt
        return music + effects
    }

    /// Mono test/offline path.
    func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        beginBlock()
        for frame in 0..<frames { out[frame] = Float(nextMono()) }
    }

    /// Stereo output: the mix in both ears, plus the soundscape voices panned to where they are on screen.
    func renderStereo(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        beginBlock()
        refreshVoices()
        let dt = self.dt
        for frame in 0..<frames {
            let mono = nextMono()
            let (voiceLeft, voiceRight) = voicesSample(dt: dt)
            left[frame] = Float(mono + voiceLeft)
            right[frame] = Float(mono + voiceRight)
        }
    }

    // MARK: - Soundscape voices

    private let voiceLock = NSLock()
    private var pendingVoices: [SoundscapeVoice] = []
    private var activeVoices: [SoundscapeVoice] = []
    /// One slot per audible voice. A slot keeps its last voice while it fades out, so sounds don't click off.
    private var slotVoice = [SoundscapeVoice?](repeating: nil, count: 8)
    private var slotPhase = [Double](repeating: 0, count: 8)
    private var slotLevel = [Double](repeating: 0, count: 8)

    /// Called from the main thread every frame; the audio thread picks it up at the next block.
    func setVoices(_ voices: [SoundscapeVoice]) {
        voiceLock.lock()
        pendingVoices = Array(voices.prefix(slotVoice.count))
        voiceLock.unlock()
    }

    private func refreshVoices() {
        voiceLock.lock()
        activeVoices = pendingVoices
        voiceLock.unlock()
    }

    private func voicesSample(dt: Double) -> (Double, Double) {
        var left = 0.0
        var right = 0.0
        for slot in 0..<slotVoice.count {
            if slot < activeVoices.count { slotVoice[slot] = activeVoices[slot] }
            guard let voice = slotVoice[slot] else { continue }
            let active = slot < activeVoices.count
            let target = active ? voice.gain * sfxGain : 0
            // Fade toward the target so voices appear and leave smoothly.
            slotLevel[slot] += (target - slotLevel[slot]) * min(dt * 8, 1)
            if !active, slotLevel[slot] < 1e-5 {
                slotVoice[slot] = nil
                slotLevel[slot] = 0
                continue
            }
            slotPhase[slot] += 2 * .pi * voice.frequency * dt
            if slotPhase[slot] > 2 * .pi { slotPhase[slot] -= 2 * .pi }
            let p = slotPhase[slot]
            let wave: Double
            switch voice.timbre {
            case .sine: wave = sin(p)
            case .hollow: wave = sin(p) + 0.35 * sin(3 * p)
            case .rumble: wave = sin(p) * (0.7 + 0.3 * sin(2 * .pi * 0.3 * time))
            case .chirp: wave = sin(p) * (0.5 + 0.5 * sin(2 * .pi * 4 * time))
            case .threat: wave = sin(p) * (0.6 + 0.4 * sin(2 * .pi * 3 * time)) + 0.2 * sin(2 * p)
            }
            let sample = wave * slotLevel[slot] * 0.12
            // Equal-power pan: -1 = left ear only, +1 = right ear only.
            let angle = (voice.pan + 1) * .pi / 4
            left += sample * cos(angle)
            right += sample * sin(angle)
        }
        return (left, right)
    }
}
