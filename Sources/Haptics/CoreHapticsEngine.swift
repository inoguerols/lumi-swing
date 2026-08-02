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
    private var ensureTask: Task<Void, Never>?

    private let audio = AudioCueEngine()
    private(set) var resetCount = 0
    private(set) var isRunning = false

    /// Los interruptores de Ajustes. Se filtran por separado a propósito: hápticos
    /// OFF + sonido ON tiene que dar solo sonido, y hasta ahora el motor tocaba los
    /// dos canales igual porque la escena decidía con un OR.
    private var hapticsEnabled = true
    private var audioEnabled = true

    /// Sustituye el arranque del hardware. Solo lo usan los tests: el simulador no
    /// tiene Taptic Engine y el ciclo de vida (interrupción → vuelta a primer plano)
    /// hay que probarlo igual. En producción es `nil` y manda `CHHapticEngine`.
    private let hardwareStartOverride: (@Sendable () -> Bool)?

    init(hardwareStartOverride: (@Sendable () -> Bool)? = nil) {
        self.hardwareStartOverride = hardwareStartOverride
    }

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
        if let hardwareStartOverride {
            isRunning = hardwareStartOverride()
            return
        }

        let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        await audio.start(substituting: !supported)
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

    /// Rearranca lo que la interrupción se llevó. Es la respuesta al bug de "a veces
    /// no vibra": una llamada, Siri o el auto-shutdown paraban el motor y nadie lo
    /// volvía a arrancar (docs/lenguaje-haptico.md §7).
    ///
    /// Idempotente y barata cuando ya está todo en pie, así que se llama al volver a
    /// primer plano y también como guard perezoso antes de cada señal.
    func ensureRunning() async {
        // Single-flight: scenePhase, el stoppedHandler y los guards perezosos de
        // play()/runProximityLoop() pueden llamar aquí a la vez, y el cuerpo tiene
        // puntos de suspensión antes de escribir `isRunning`. Dos vuelos solapados
        // duplicaban el bucle de proximidad o dejaban `isRunning=false` con el motor
        // arrancado — el mismo bug que este método existe para arreglar.
        if let inFlight = ensureTask {
            await inFlight.value
            return
        }
        let task = Task { await ensureRunningBody() }
        ensureTask = task
        await task.value
        ensureTask = nil
    }

    private func ensureRunningBody() async {
        if let hardwareStartOverride {
            if !isRunning { isRunning = hardwareStartOverride() }
            return
        }

        let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        // La interrupción también se lleva la AVAudioSession y el AVAudioEngine: sin
        // esto el canal de sonido vuelve mudo aunque los hápticos revivan. Va antes
        // que los hápticos porque es el orden que exige el audio: sesión → motor →
        // players; si falla, se reintenta en el siguiente evento de ciclo de vida.
        await audio.start(substituting: !supported)

        guard supported, !isRunning else { return }
        guard let engine else {
            // El arranque en frío falló (o nunca ocurrió): se reintenta entero.
            await prepare()
            return
        }

        do {
            try await engine.start()
            try loadPlayers(on: engine)
            isRunning = true
            // Si la interrupción pilló al jugador a ciegas, el mapa vuelve solo.
            if currentCue != nil, proximityLoop == nil { startProximityLoop() }
        } catch {
            isRunning = false
        }
    }

    /// Los interruptores de Ajustes, empujados desde el shell. Apagar los hápticos
    /// tiene que callar la textura de alineación en el acto, no al siguiente evento.
    func setChannels(haptics hapticsOn: Bool, audio audioOn: Bool) async {
        hapticsEnabled = hapticsOn
        audioEnabled = audioOn

        if !hapticsOn, alignmentActive, let player = alignmentPlayer {
            try? player.stop(atTime: CHHapticTimeImmediate)
            alignmentActive = false
        }
        if !audioOn { await audio.stopContinuous() }
        await audio.setAmbienceEnabled(audioOn)
    }

    /// El ambiente de selva, atenuado por la escena. No pasa por `audioEnabled`
    /// aquí: el motor de audio ya guarda el interruptor por su cuenta, así que el
    /// ducking se conserva aunque el sonido esté apagado y no hay que reconstruirlo
    /// al volver a encenderlo.
    func setAmbience(gain: CGFloat) async {
        await audio.setAmbienceGain(gain)
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
            // `currentCue` sigue en pie y el bucle lo retoma. El guard evita duplicar
            // el bucle si un `ensureRunning()` concurrente ya lo levantó.
            if currentCue != nil, proximityLoop == nil { startProximityLoop() }
        } catch {
            isRunning = false
        }
    }

    /// Interno, no privado, para que el test del ciclo de vida pueda provocar la
    /// interrupción sin hardware.
    func handleStopped(_ reason: CHHapticEngine.StoppedReason) async {
        isRunning = false
        alignmentActive = false
        proximityLoop?.cancel()
        proximityLoop = nil

        switch reason {
        case .audioSessionInterrupt, .applicationSuspended:
            // No se rearranca aquí: se espera a volver a primer plano, donde el
            // observador de `scenePhase` llama a `ensureRunning()`. Un motor
            // reiniciado en background es un vibrador huérfano.
            break
        default:
            await ensureRunning()
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

        if audioEnabled { await audio.play(signal) }

        guard hapticsEnabled else { return }
        // Guard perezoso: cubre el auto-shutdown y la carrera con el `stoppedHandler`
        // sin pagar nada cuando el motor ya está vivo.
        if !isRunning { await ensureRunning() }
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
            if audioEnabled { await audio.playProximityClick(intensity: cue.intensity) }

            if hapticsEnabled, !isRunning { await ensureRunning() }

            if hapticsEnabled, isRunning, let player = proximityPlayer {
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
        await audio.updateAlignment(intensity: audioEnabled ? intensity : nil)

        guard hapticsEnabled, isRunning, let player = alignmentPlayer else { return }

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

    /// Irse a background. `stopContinuous()` calla lo que vibra; esto además apaga
    /// el audio del todo, para que la vuelta a primer plano rehaga sesión y motor
    /// en orden en vez de encontrarse un `AVAudioEngine` que el sistema paró por
    /// debajo (crash de la build 7 al volver de background).
    func suspend() async {
        await stopContinuous()
        await audio.suspend()
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
