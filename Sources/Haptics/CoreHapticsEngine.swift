import CoreGraphics
import CoreHaptics
import Foundation

/// El motor de verdad. Es un `actor` porque `CHHapticEngine` invoca
/// `resetHandler` y `stoppedHandler` fuera del hilo principal: el aislamiento
/// tiene que ser explícito, no confiado (docs/arquitectura.md §7).
///
/// El audio vive dentro del mismo actor porque comparten ciclo de vida,
/// interrupciones y `AVAudioSession`. Dos actores gestionando la misma sesión de
/// audio es una carrera esperando a ocurrir.
actor CoreHapticsEngine: HapticsEngine {

    private var engine: CHHapticEngine?
    private var eventPlayers: [HapticSignal: CHHapticPatternPlayer] = [:]
    private var alignmentPlayer: CHHapticAdvancedPatternPlayer?
    private var proximityPlayer: CHHapticAdvancedPatternPlayer?

    private var alignmentActive = false
    private var currentCue: ProximityCue?
    private var proximityLoop: Task<Void, Never>?

    private let audio = AudioCueEngine()
    private(set) var resetCount = 0
    private(set) var isRunning = false

    var capabilities: HapticsCapabilities {
        HapticsCapabilities(
            supportsHaptics: CHHapticEngine.capabilitiesForHardware().supportsHaptics,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    /// Diagnóstico para la pantalla de debug de S3.
    var diagnostics: (supportsHaptics: Bool, running: Bool, resets: Int, lowPower: Bool) {
        (CHHapticEngine.capabilitiesForHardware().supportsHaptics,
         isRunning,
         resetCount,
         ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    // MARK: - Ciclo de vida

    func prepare() async {
        let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        await audio.prepare(substituting: !supported)
        guard supported else { return }

        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true

            engine.resetHandler = { [weak self] in
                Task { await self?.handleReset() }
            }
            engine.stoppedHandler = { [weak self] reason in
                Task { await self?.handleStopped(reason) }
            }

            try await engine.start()
            self.engine = engine
            try loadPlayers(on: engine)
            isRunning = true
        } catch {
            // Un fallo de arranque no es fatal: el juego cae al audio sustitutivo y
            // sigue siendo jugable. Perder los hápticos no puede perder la partida.
            engine = nil
            isRunning = false
            await audio.enableSubstitution()
        }
    }

    private func handleReset() async {
        resetCount += 1
        alignmentActive = false
        guard let engine else { return }
        do {
            try await engine.start()
            try loadPlayers(on: engine)
            isRunning = true
            // Si el jugador estaba dentro de una zona a ciegas, el mapa vuelve solo:
            // `currentCue` sigue en pie y el bucle lo retoma.
            if currentCue != nil { startProximityLoop() }
        } catch {
            isRunning = false
        }
    }

    private func handleStopped(_ reason: CHHapticEngine.StoppedReason) async {
        isRunning = false
        alignmentActive = false
        proximityLoop?.cancel()
        proximityLoop = nil

        switch reason {
        case .audioSessionInterrupt, .applicationSuspended:
            // No se rearranca aquí: se espera a volver a primer plano. Un motor
            // reiniciado en background es un vibrador huérfano.
            break
        default:
            try? await engine?.start()
            isRunning = engine != nil
        }
    }

    private func loadPlayers(on engine: CHHapticEngine) throws {
        // Precargados: construir el patrón en el instante del evento cuesta 10-20 ms,
        // y en el agarre eso rompe la sensación de causa-efecto.
        for signal in HapticSignal.allCases {
            eventPlayers[signal] = try engine.makePlayer(with: Self.pattern(for: signal))
        }
        alignmentPlayer = try engine.makeAdvancedPlayer(with: Self.alignmentPattern())
        alignmentPlayer?.loopEnabled = true
        proximityPlayer = try engine.makeAdvancedPlayer(with: Self.proximityPattern())
    }

    // MARK: - Señales de evento

    func play(_ signal: HapticSignal) async {
        // La muerte cancela todo antes de sonar: un continuous huérfano por encima
        // del golpe final ensucia justo el momento que tiene que cerrar la partida.
        if signal == .death { await stopContinuous() }

        await audio.play(signal)
        guard isRunning, let player = eventPlayers[signal] else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    // MARK: - Proximidad (el ritmo es la distancia)

    func updateProximity(distance: CGFloat?) async {
        let cue = distance.flatMap(ProximityMapping.cue(forDistance:))
        currentCue = cue

        if cue == nil {
            proximityLoop?.cancel()
            proximityLoop = nil
            return
        }
        if proximityLoop == nil { startProximityLoop() }
    }

    private func startProximityLoop() {
        proximityLoop = Task { [weak self] in
            await self?.runProximityLoop()
        }
    }

    /// El ritmo lo lleva el motor con su propio reloj, no un player en loop con
    /// parámetros dinámicos (D-013): la cadencia *es* la información, y así se
    /// controla exactamente, pulso a pulso.
    private func runProximityLoop() async {
        while !Task.isCancelled, let cue = currentCue {
            await audio.playProximityClick(intensity: cue.intensity)

            if isRunning, let player = proximityPlayer {
                try? player.sendParameters([
                    CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                             value: Float(cue.intensity),
                                             relativeTime: 0),
                    CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                             value: Float(cue.sharpness),
                                             relativeTime: 0)
                ], atTime: CHHapticTimeImmediate)
                try? player.start(atTime: CHHapticTimeImmediate)
            }

            try? await Task.sleep(for: .seconds(Double(cue.interval)))
        }
        proximityLoop = nil
    }

    // MARK: - Alineación (la presencia es el sí)

    func updateAlignment(clearance: CGFloat?) async {
        let intensity = clearance.flatMap(ProximityMapping.alignmentIntensity(clearance:))
        await audio.updateAlignment(intensity: intensity)

        guard isRunning, let player = alignmentPlayer else { return }

        guard let intensity else {
            if alignmentActive {
                try? player.stop(atTime: CHHapticTimeImmediate)
                alignmentActive = false
            }
            return
        }

        // Se modula el player existente, no se recrea: recrear players a 60 Hz agota
        // el motor y produce cortes audibles.
        try? player.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: Float(intensity),
                                     relativeTime: 0)
        ], atTime: CHHapticTimeImmediate)

        if !alignmentActive {
            do {
                try player.start(atTime: CHHapticTimeImmediate)
                alignmentActive = true
            } catch {
                alignmentActive = false
            }
        }
    }

    func stopContinuous() async {
        currentCue = nil
        proximityLoop?.cancel()
        proximityLoop = nil

        if alignmentActive, let player = alignmentPlayer {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
        alignmentActive = false
        await audio.stopContinuous()
    }

    // MARK: - Patrones

    private static func transient(_ intensity: CGFloat,
                                  _ sharpness: CGFloat,
                                  at time: TimeInterval = 0) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient,
                      parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness))
                      ],
                      relativeTime: time)
    }

    private static func continuous(_ intensity: CGFloat,
                                   _ sharpness: CGFloat,
                                   at time: TimeInterval,
                                   duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous,
                      parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness))
                      ],
                      relativeTime: time,
                      duration: duration)
    }

    private static func pattern(for signal: HapticSignal) throws -> CHHapticPattern {
        switch signal {
        case .grab:
            // Sharpness máxima: un enganche mecánico debe sentirse como un clic.
            return try CHHapticPattern(
                events: [transient(Tuning.Haptics.grabIntensity, Tuning.Haptics.grabSharpness)],
                parameters: [])

        case .release:
            // Sharpness baja: golpe sordo. El contraste tímbrico con el agarre es lo
            // que los hace inconfundibles a ciegas.
            return try CHHapticPattern(
                events: [transient(Tuning.Haptics.releaseIntensity, Tuning.Haptics.releaseSharpness)],
                parameters: [])

        case .score:
            return try CHHapticPattern(
                events: [transient(Tuning.Haptics.scoreIntensity, Tuning.Haptics.scoreSharpness)],
                parameters: [])

        case .death:
            // Impacto y resonancia: el decay es lo que cierra la partida sin que el
            // jugador tenga que mirar la pantalla.
            let decay = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1),
                    CHHapticParameterCurve.ControlPoint(
                        relativeTime: TimeInterval(Tuning.Haptics.deathDecayDuration), value: 0)
                ],
                relativeTime: 0.02)
            return try CHHapticPattern(
                events: [
                    transient(Tuning.Haptics.deathIntensity, Tuning.Haptics.deathSharpness),
                    continuous(Tuning.Haptics.deathDecayIntensity,
                               Tuning.Haptics.deathDecaySharpness,
                               at: 0.02,
                               duration: TimeInterval(Tuning.Haptics.deathDecayDuration))
                ],
                parameterCurves: [decay])

        case .blindEnter:
            // Dos golpes: un patrón rítmico que no existe en ninguna otra señal del
            // vocabulario, así que no se confunde con el tren de proximidad.
            return try CHHapticPattern(
                events: [
                    transient(Tuning.Haptics.blindEnterIntensity, Tuning.Haptics.blindEnterSharpness),
                    transient(Tuning.Haptics.blindEnterIntensity,
                              Tuning.Haptics.blindEnterSharpness,
                              at: TimeInterval(Tuning.Haptics.blindEnterGap))
                ],
                parameters: [])

        case .blindExit:
            // El único patrón ascendente del idioma: alivio.
            let rise = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(
                        relativeTime: 0, value: Float(Tuning.Haptics.blindExitRampFrom)),
                    CHHapticParameterCurve.ControlPoint(
                        relativeTime: TimeInterval(Tuning.Haptics.blindExitRampDuration),
                        value: Float(Tuning.Haptics.blindExitRampTo))
                ],
                relativeTime: 0.02)
            return try CHHapticPattern(
                events: [
                    transient(Tuning.Haptics.blindExitIntensity, Tuning.Haptics.blindExitSharpness),
                    continuous(Tuning.Haptics.blindExitRampTo,
                               Tuning.Haptics.blindExitSharpness,
                               at: 0.02,
                               duration: TimeInterval(Tuning.Haptics.blindExitRampDuration))
                ],
                parameterCurves: [rise])
        }
    }

    /// Textura base de alineación. Su intensidad se modula en vivo; aquí solo se
    /// fija el timbre: sharpness muy baja, un zumbido sordo y redondo.
    private static func alignmentPattern() throws -> CHHapticPattern {
        try CHHapticPattern(
            events: [continuous(1.0, Tuning.Haptics.alignSharpness, at: 0, duration: 1.0)],
            parameters: [])
    }

    /// Pulso base de proximidad. Intensidad y sharpness se envían por parámetro
    /// dinámico antes de cada disparo.
    private static func proximityPattern() throws -> CHHapticPattern {
        try CHHapticPattern(events: [transient(1.0, 1.0)], parameters: [])
    }
}
