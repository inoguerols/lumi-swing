import CoreGraphics
import Testing
@testable import Pendulo

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

    @Test("Sin Taptic Engine hay que sustituir, no solo reforzar")
    func substitutionKicksInWithoutHardware() {
        let withHardware = HapticsCapabilities(supportsHaptics: true, lowPowerMode: false)
        let without = HapticsCapabilities(supportsHaptics: false, lowPowerMode: false)
        #expect(!withHardware.needsFullSubstitution)
        #expect(without.needsFullSubstitution)
    }
}
