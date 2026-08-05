import CoreGraphics
import Testing
@testable import LumiSwing

@Suite("Lenguaje háptico")
struct HapticsTests {

    @Test("Más allá del alcance, silencio")
    func silenceBeyondRange() {
        #expect(ProximityMapping.cue(forDistance: Tuning.Haptics.proximityRange + 1) == nil)
        #expect(ProximityMapping.cue(forDistance: Tuning.Haptics.proximityRange) != nil)
    }

    /// La propiedad que sostiene toda la mecánica firma: si acercarse no acelera
    /// siempre el ritmo, el jugador no puede fiarse de lo que siente.
    @Test("Acercarse acelera el ritmo y sube la intensidad, sin excepciones")
    func mappingIsStrictlyMonotonic() {
        var distance = Tuning.Haptics.proximityRange
        var previous = ProximityMapping.cue(forDistance: distance)

        while distance > 0 {
            distance -= 10
            guard let current = ProximityMapping.cue(forDistance: distance),
                  let last = previous else {
                Issue.record("Hueco en el mapeo a \(distance) pt")
                return
            }
            #expect(current.interval < last.interval)
            #expect(current.intensity > last.intensity)
            #expect(current.sharpness >= last.sharpness)
            previous = current
        }
    }

    /// Los valores de la tabla de docs/lenguaje-haptico.md §2. Si alguien toca el
    /// exponente de la curva sin actualizar el documento, esto salta.
    @Test("La tabla del documento y el código dicen lo mismo",
          arguments: [(CGFloat(900), CGFloat(0.60)),
                      (700, 0.45),
                      (500, 0.32),
                      (350, 0.23),
                      (200, 0.15),
                      (100, 0.09),
                      (40, 0.07)])
    func matchesDocumentedTable(distance: CGFloat, expectedInterval: CGFloat) {
        guard let cue = ProximityMapping.cue(forDistance: distance) else {
            Issue.record("Sin señal a \(distance) pt, y el documento dice que hay una")
            return
        }
        #expect(abs(cue.interval - expectedInterval) < 0.02,
                "a \(distance) pt el documento promete \(expectedInterval) s y el código da \(cue.interval)")
    }

    @Test("Los extremos del rango coinciden con las constantes")
    func rangeEndsMatchConstants() throws {
        // Tolerancia y no igualdad exacta: el lerp con exponente pasa por `pow`, y
        // exigirle al binario que devuelva 0,6 clavado es exigirle algo que no
        // significa nada perceptualmente.
        let epsilon: CGFloat = 1e-9

        let near = try #require(ProximityMapping.cue(forDistance: 0))
        #expect(abs(near.interval - Tuning.Haptics.proximityIntervalNear) < epsilon)
        #expect(abs(near.intensity - Tuning.Haptics.proximityIntensityNear) < epsilon)
        #expect(abs(near.sharpness - Tuning.Haptics.proximitySharpnessNear) < epsilon)

        let far = try #require(ProximityMapping.cue(forDistance: Tuning.Haptics.proximityRange))
        #expect(abs(far.interval - Tuning.Haptics.proximityIntervalFar) < epsilon)
        #expect(abs(far.intensity - Tuning.Haptics.proximityIntensityFar) < epsilon)
    }

    // MARK: - Alineación

    @Test("Desalineado se dice callando")
    func misalignedIsSilence() {
        #expect(ProximityMapping.alignmentIntensity(clearance: 0) == nil)
        #expect(ProximityMapping.alignmentIntensity(clearance: -30) == nil)
        #expect(ProximityMapping.alignmentIntensity(clearance: 1) != nil)
    }

    @Test("Más margen libre, textura más plena")
    func alignmentScalesWithClearance() throws {
        let tight = try #require(ProximityMapping.alignmentIntensity(clearance: 5))
        let centred = try #require(
            ProximityMapping.alignmentIntensity(clearance: Tuning.Haptics.alignClearanceSpan))

        #expect(centred == Tuning.Haptics.alignIntensityHigh)
        #expect(tight < centred)
        // Nunca por debajo del umbral de percepción: si no, "pasas rozando" sería
        // indistinguible de "no cabes", que es la confusión más cara del juego.
        #expect(tight >= Tuning.Haptics.alignIntensityLow)
    }

    @Test("El margen se mide con el farolillo entero, no con su centro")
    func clearanceAccountsForPlayerRadius() {
        let wall = Wall(x: 0, gapCenterY: 1000, gapHeight: 240)
        // Centrado: le sobran 120 - 26 = 94 pt.
        #expect(ProximityMapping.clearance(playerY: 1000, wall: wall) == 120 - Tuning.Player.radius)
        // En el borde del hueco no cabe, aunque su centro sí esté dentro.
        #expect(ProximityMapping.clearance(playerY: 1120, wall: wall) < 0)
    }

    // MARK: - Contrato del motor

    @Test("El mock recibe lo que la escena le manda")
    func mockRecordsTheVocabulary() async {
        let engine = MockHapticsEngine()
        await engine.prepare()
        for signal in HapticSignal.allCases {
            await engine.play(signal)
        }
        await engine.updateProximity(distance: 300)
        await engine.updateAlignment(clearance: 40)
        await engine.stopContinuous()

        #expect(await engine.prepared)
        #expect(await engine.played == HapticSignal.allCases)
        #expect(await engine.proximity == [300])
        #expect(await engine.alignment == [40])
        #expect(await engine.stops == 1)
    }

    /// El bug de "a veces no vibra": una llamada entrante paraba el motor y nadie lo
    /// volvía a arrancar al volver a primer plano. Aquí se prueba la máquina de
    /// estados, no el hardware — el simulador no tiene Taptic Engine, así que el
    /// arranque real se sustituye por un doble inyectado.
    @Test("Tras una interrupción, volver a primer plano rearranca el motor")
    func engineRestartsAfterInterruption() async {
        let engine = CoreHapticsEngine(hardwareStartOverride: { true })
        await engine.prepare()
        #expect(await engine.isRunning)

        await engine.handleStopped(.applicationSuspended)
        #expect(await engine.isRunning == false, "una suspensión no rearranca sola: se espera al foreground")

        await engine.ensureRunning()
        #expect(await engine.isRunning)
    }

    /// El bloqueo del feedback de TestFlight (2026-08-04): morir columpiando y
    /// quedarse la vibración puesta para siempre. Los updates por-frame salen de
    /// la escena como Tasks sueltos, sin orden garantizado: uno creado justo
    /// antes de morir puede aterrizar tras el stopContinuous() de la muerte y
    /// rearrancar el continuo, que ya nadie para. El contrato: la muerte
    /// enmudece el mapa hasta que la escena arma la partida siguiente.
    @Test("Un update tardío no resucita la vibración después de morir")
    func deathSuppressesLateContinuousUpdates() async {
        let engine = CoreHapticsEngine(hardwareStartOverride: { true })
        await engine.prepare()

        await engine.play(.death)
        await engine.updateProximity(distance: 1)
        await engine.updateAlignment(clearance: 5)
        #expect(await engine.continuousActive == false,
                "el update en vuelo aterrizó tarde y no puede rearrancar el continuo")

        await engine.resetForRun()
        await engine.updateProximity(distance: 1)
        #expect(await engine.continuousActive,
                "la partida nueva levanta la mordaza y recupera el mapa háptico")
    }

    @Test("El guard perezoso de play() también rescata un motor parado")
    func playRevivesStoppedEngine() async {
        let engine = CoreHapticsEngine(hardwareStartOverride: { true })
        await engine.prepare()
        await engine.handleStopped(.applicationSuspended)

        await engine.play(.grab)
        #expect(await engine.isRunning)
    }

    // MARK: - Ciclo de vida del audio
    //
    // El crash de la build 7 (TestFlight, iOS 27): al volver de background,
    // `setChannels` llamaba a `stopContinuous()` y este rearmaba el player con
    // `play()`, que lanza NSException si el motor está parado. Estos tests fijan el
    // contrato: **parar nunca arranca nada**.

    @Test("Parar el continuo con el audio muerto es un no-op, no un play() a ciegas")
    func stoppingIdleAudioNeverStarts() async {
        let audio = AudioCueEngine()

        await audio.stopContinuous()
        await audio.updateAlignment(intensity: nil)
        await audio.stopContinuous()

        #expect(await audio.isActive == false)
    }

    @Test("Suspender deja el audio explícitamente muerto, pase lo que pase al arrancar")
    func suspendLeavesAudioDead() async {
        let audio = AudioCueEngine()
        // En simulador el arranque puede salir bien o mal: el contrato es el mismo.
        await audio.start(substituting: true)

        await audio.suspend()
        #expect(await audio.isActive == false)

        await audio.stopContinuous()
        #expect(await audio.isActive == false, "una parada no puede resucitar el audio")
    }

    /// La secuencia exacta del crash: background → los interruptores de Ajustes se
    /// empujan (`initial: true` al recomponer la vista) → vuelta a primer plano.
    @Test("Apagar canales con la app suspendida no rompe la vuelta a primer plano")
    func channelSwitchWhileSuspendedSurvives() async {
        let engine = CoreHapticsEngine(hardwareStartOverride: { true })
        await engine.prepare()

        await engine.suspend()
        await engine.setChannels(haptics: false, audio: false)

        await engine.ensureRunning()
        #expect(await engine.isRunning)
    }

    @Test("Sin Taptic Engine hay que sustituir, no solo reforzar")
    func substitutionKicksInWithoutHardware() {
        let withHardware = HapticsCapabilities(supportsHaptics: true, lowPowerMode: false)
        let without = HapticsCapabilities(supportsHaptics: false, lowPowerMode: false)
        #expect(!withHardware.needsFullSubstitution)
        #expect(without.needsFullSubstitution)
    }
}
