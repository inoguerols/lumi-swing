import CoreGraphics
import Foundation
import Testing
@testable import LumiSwing

@Suite("Flores marchitas")
struct WitherTests {

    private let step: CGFloat = 1.0 / 120

    /// Cuelga a Lumi de la flor llave del muro `wall` y lo mantiene ahí,
    /// re-anclando la posición cada paso (misma técnica que los tests de ritmo):
    /// la física sigue corriendo pero el cuerpo no puede chocar con nada, así que
    /// lo único que se mide es el temporizador de marchitado.
    private struct Rig {
        var sim: GameSimulation
        let anchor: CGPoint
        let hang: CGPoint
        private let step: CGFloat

        init(wall: Int, step: CGFloat, seed: UInt64 = Tuning.WorldGen.initialSeed) {
            sim = GameSimulation(seed: seed)
            anchor = WorldGenerator.chunk(index: wall, seed: seed).anchors[0].position
            // A 60 pt: cualquier otra ancla queda a ≥90 pt en horizontal, así que
            // el agarre elige siempre esta flor.
            hang = CGPoint(x: anchor.x, y: anchor.y - 60)
            self.step = step
            sim.placeBody(at: hang)
            // Un paso sin agarrar: `refillChunks` recoloca la ventana de chunks
            // alrededor de la nueva posición antes del primer agarre.
            _ = sim.advance(dt: step, holding: false)
        }

        /// Avanza `seconds` manteniendo (o no) pulsado, y devuelve los eventos.
        mutating func advance(seconds: CGFloat, holding: Bool) -> [GameEvent] {
            var events: [GameEvent] = []
            var remaining = seconds
            while remaining > 0 {
                sim.placeBody(at: hang)
                events += sim.advance(dt: step, holding: holding)
                remaining -= step
            }
            return events
        }
    }

    @Test("Una flor marchita cae al agotar el presupuesto y suelta a Lumi")
    func witheredFlowerFallsAndReleases() {
        var rig = Rig(wall: Tuning.Wither.firstWall, step: step)

        let grabbing = rig.advance(seconds: step, holding: true)
        #expect(grabbing.contains(.grabbed))
        #expect(rig.sim.body.attachment?.anchor == rig.anchor)

        let events = rig.advance(seconds: Tuning.Wither.grabBudget + 0.5, holding: true)
        #expect(events.contains(.flowerFell(rig.anchor)))
        #expect(rig.sim.body.attachment == nil)
        #expect(rig.sim.witherProgress(wall: Tuning.Wither.firstWall, slot: 0) == 1)
        #expect(rig.sim.flowerHasFallen(wall: Tuning.Wither.firstWall, slot: 0))
    }

    @Test("La flor caída no se puede volver a agarrar")
    func fallenFlowerIsNotGrabbable() {
        var rig = Rig(wall: Tuning.Wither.firstWall, step: step)
        _ = rig.advance(seconds: step, holding: true)
        _ = rig.advance(seconds: Tuning.Wither.grabBudget + 0.5, holding: true)
        #expect(rig.sim.flowerHasFallen(wall: Tuning.Wither.firstWall, slot: 0))

        // Soltar el dedo y volver a pulsar: el flanco de agarre no debe volver a
        // enganchar a la flor caída (como mucho, a otra ancla viva).
        _ = rig.advance(seconds: step, holding: false)
        _ = rig.advance(seconds: step, holding: true)
        #expect(rig.sim.body.attachment?.anchor != rig.anchor)
    }

    @Test("El desgaste es acumulativo: soltarse no devuelve pétalos")
    func witherIsCumulativeAcrossGrabs() {
        var rig = Rig(wall: Tuning.Wither.firstWall, step: step)

        _ = rig.advance(seconds: step, holding: true)
        _ = rig.advance(seconds: 2.5, holding: true)
        let midway = rig.sim.witherProgress(wall: Tuning.Wither.firstWall, slot: 0)
        #expect(midway > 0.5 && midway < 1)

        // Soltarse y esperar no regenera nada.
        _ = rig.advance(seconds: 1.0, holding: false)
        #expect(rig.sim.witherProgress(wall: Tuning.Wither.firstWall, slot: 0) >= midway)

        // Re-agarrar y gastar el resto del presupuesto: cae.
        _ = rig.advance(seconds: step, holding: true)
        #expect(rig.sim.body.attachment?.anchor == rig.anchor)
        let events = rig.advance(seconds: 2.0, holding: true)
        #expect(events.contains(.flowerFell(rig.anchor)))
    }

    @Test("Las flores del tramo de aprendizaje no se marchitan nunca")
    func learningFlowersNeverWither() {
        var rig = Rig(wall: 2, step: step)

        _ = rig.advance(seconds: step, holding: true)
        #expect(rig.sim.body.attachment?.anchor == rig.anchor)

        let events = rig.advance(seconds: Tuning.Wither.grabBudget * 2, holding: true)
        #expect(!events.contains { if case .flowerFell = $0 { return true } else { return false } })
        #expect(rig.sim.body.attachment?.anchor == rig.anchor)
        #expect(rig.sim.witherProgress(wall: 2, slot: 0) == 0)
    }

    @Test("El reset limpia el marchitado")
    func resetClearsWitherState() {
        var rig = Rig(wall: Tuning.Wither.firstWall, step: step)
        _ = rig.advance(seconds: step, holding: true)
        _ = rig.advance(seconds: Tuning.Wither.grabBudget + 0.5, holding: true)
        #expect(rig.sim.flowerHasFallen(wall: Tuning.Wither.firstWall, slot: 0))

        rig.sim.reset(seed: Tuning.WorldGen.initialSeed)
        #expect(!rig.sim.flowerHasFallen(wall: Tuning.Wither.firstWall, slot: 0))
        #expect(rig.sim.witherProgress(wall: Tuning.Wither.firstWall, slot: 0) == 0)
    }

    /// La condición del game-director para dar el slice por bueno: el tramo
    /// marchito debe seguir siendo superable (D-008). Misma búsqueda aleatoria
    /// que `SolvabilityTests`, pero soltando al bot justo después del muro 13,
    /// donde todas las flores ya se marchitan.
    @Test("El tramo de flores marchitas sigue siendo superable")
    func witheredSectionIsTraversable() {
        let entryWall = Tuning.Wither.firstWall - 1
        let entry = CGPoint(
            x: DifficultyCurve.wallX(forWall: entryWall) + 50,
            y: WorldGenerator.gapCenterY(forWall: entryWall, seed: Tuning.WorldGen.initialSeed))

        var best = 0
        for attempt in UInt64(0)..<400 {
            var simulation = GameSimulation(seed: Tuning.WorldGen.initialSeed)
            simulation.placeBody(at: entry)
            var rng = SplitMix64(seed: 0x717AE2 &+ attempt)
            var holding = false
            var untilNextDecision: CGFloat = 0
            var elapsed: CGFloat = 0

            while !simulation.isDead && elapsed < 20 {
                if untilNextDecision <= 0 {
                    holding = rng.nextCGFloat(in: 0...1) < 0.5
                    untilNextDecision = rng.nextCGFloat(in: 0.05...0.35)
                }
                _ = simulation.advance(dt: step, holding: holding)
                elapsed += step
                untilNextDecision -= step
            }
            best = max(best, simulation.score)
            if best >= 3 { break }
        }

        #expect(best >= 3, "Mejor run del bot en el tramo marchito: \(best) muros.")
    }
}
