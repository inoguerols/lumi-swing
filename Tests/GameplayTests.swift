import CoreGraphics
import Testing
@testable import Pendulo

@Suite("Colisiones")
struct CollisionTests {

    private let radius = Tuning.Player.radius

    private func chunk(gapCenterY: CGFloat = 975, gapHeight: CGFloat = 240) -> Chunk {
        Chunk(index: 1,
              wall: Wall(x: 1000, gapCenterY: gapCenterY, gapHeight: gapHeight),
              anchors: [],
              isBlind: false)
    }

    @Test("Por el centro del hueco se pasa limpio")
    func passesThroughGap() {
        let target = chunk()
        #expect(Collision.hit(position: CGPoint(x: target.wall.x, y: target.wall.gapCenterY),
                              radius: radius,
                              chunks: [target]) == nil)
    }

    @Test("Rozar el borde del hueco mata")
    func clipsGapEdge() {
        let target = chunk()
        let grazing = CGPoint(x: target.wall.x, y: target.wall.gapBottomY + radius - 1)
        #expect(Collision.hit(position: grazing, radius: radius, chunks: [target]) == .wall)
    }

    /// La esquina es donde fallan las implementaciones ingenuas: comprueban solo
    /// solapamiento por ejes y dejan pasar el círculo por la diagonal.
    @Test("La esquina del hueco también mata")
    func hitsGapCorner() {
        let target = chunk()
        let corner = CGPoint(x: target.wall.x - Tuning.World.wallThickness / 2,
                             y: target.wall.gapBottomY)
        let diagonal = CGPoint(x: corner.x - radius * 0.5, y: corner.y + radius * 0.5)
        #expect(Collision.hit(position: diagonal, radius: radius, chunks: [target]) == .wall)
    }

    @Test("Suelo y techo matan")
    func floorAndCeilingKill() {
        #expect(Collision.hit(position: CGPoint(x: 0, y: Tuning.World.floorY + radius - 1),
                              radius: radius, chunks: []) == .floor)
        #expect(Collision.hit(position: CGPoint(x: 0, y: Tuning.World.ceilingY - radius + 1),
                              radius: radius, chunks: []) == .ceiling)
    }

    @Test("Lejos del muro no pasa nada")
    func farFromWallIsSafe() {
        let target = chunk()
        #expect(Collision.hit(position: CGPoint(x: 500, y: 975),
                              radius: radius, chunks: [target]) == nil)
    }

    @Test("Morir congela la simulación")
    func deathStopsTheRun() {
        var simulation = GameSimulation(seed: 1)
        // Sin tocar nada, el farolillo cae hasta el suelo.
        var died = false
        for _ in 0..<2000 where !died {
            died = simulation.advance(dt: 1.0 / 120, holding: false)
                .contains { if case .died = $0 { return true } else { return false } }
        }
        #expect(died)

        let frozen = simulation.body.position
        let afterDeath = simulation.advance(dt: 1.0 / 120, holding: true)
        #expect(afterDeath.isEmpty)
        #expect(simulation.body.position == frozen)
    }

    @Test("Reiniciar deja la partida como nueva")
    func resetClearsEverything() {
        var simulation = GameSimulation(seed: 1)
        for _ in 0..<2000 { _ = simulation.advance(dt: 1.0 / 120, holding: false) }
        #expect(simulation.isDead)

        simulation.reset(seed: 1)
        #expect(!simulation.isDead)
        #expect(simulation.score == 0)
        #expect(simulation.body.position.x == Tuning.Player.startX)
    }
}

@Suite("Jugabilidad")
struct SolvabilityTests {

    /// Una partida jugada por una política aleatoria: cada 0,05–0,35 s decide si
    /// mantiene pulsado. Devuelve los puntos que consiguió.
    ///
    /// Es búsqueda, no un controlador. Escribir un buen bot de péndulo es un
    /// problema de control en sí mismo, y si el test dependiera de lo bueno que sea
    /// mi bot mediría mi bot, no el mundo. Muchas políticas al azar responden la
    /// única pregunta que importa aquí: ¿existe alguna forma de pasar?
    private func randomRun(world: UInt64, policy: UInt64, budget: CGFloat = 20) -> Int {
        var simulation = GameSimulation(seed: world)
        var rng = SplitMix64(seed: policy)
        let step: CGFloat = 1.0 / 120

        var holding = false
        var untilNextDecision: CGFloat = 0
        var elapsed: CGFloat = 0

        while !simulation.isDead && elapsed < budget {
            if untilNextDecision <= 0 {
                holding = rng.nextCGFloat(in: 0...1) < 0.5
                untilNextDecision = rng.nextCGFloat(in: 0.05...0.35)
            }
            _ = simulation.advance(dt: step, holding: holding)
            elapsed += step
            untilNextDecision -= step
        }
        return simulation.score
    }

    @Test("El mundo generado se puede recorrer")
    func generatedWorldIsTraversable() {
        var best = 0
        var report = ""

        for world in UInt64(1)...UInt64(4) {
            var bestHere = 0
            for attempt in UInt64(0)..<400 {
                bestHere = max(bestHere, randomRun(world: world, policy: world &* 10_000 &+ attempt))
            }
            best = max(best, bestHere)
            report += "mundo \(world): mejor \(bestHere) muros\n"
        }

        // Umbral deliberadamente bajo: esto detecta mundos intransitables, no mide
        // la calidad del juego. Si cae por debajo, el generador o el tuning de
        // física se han roto y ningún test de unidad lo habría notado.
        #expect(best >= 3, "Mejor run del bot: \(best) muros.\n\(report)")
    }
}
