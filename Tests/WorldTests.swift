import CoreGraphics
import Testing
@testable import Pendulo

@Suite("Mundo, dificultad y zonas a ciegas")
struct WorldTests {

    @Test("La curva de dificultad coincide con el GDD")
    func difficultyCurveMatchesGDD() {
        #expect(DifficultyCurve.spacing(forWall: 10) == Tuning.WorldGen.spacingStart)
        #expect(DifficultyCurve.gapHeight(forWall: 10) == Tuning.WorldGen.gapStart)
        // Llega un punto en el que ambas tocan su piso y ahí se quedan: el juego se
        // vuelve exigente, no imposible. (El muro exacto depende de dónde arranque el
        // hueco; lo que importa es que el piso existe y no se rebasa.)
        #expect(DifficultyCurve.spacing(forWall: 100) == Tuning.WorldGen.spacingFloor)
        #expect(DifficultyCurve.gapHeight(forWall: 100) == Tuning.WorldGen.gapFloor)
    }

    @Test("La dificultad nunca retrocede")
    func difficultyIsMonotonic() {
        for wall in 1..<200 {
            #expect(DifficultyCurve.spacing(forWall: wall + 1) <= DifficultyCurve.spacing(forWall: wall))
            #expect(DifficultyCurve.gapHeight(forWall: wall + 1) <= DifficultyCurve.gapHeight(forWall: wall))
        }
    }

    @Test("Las zonas a ciegas caen donde dice el GDD")
    func blindZoneSchedule() {
        #expect(!BlindZones.isBlind(wall: 10))
        #expect(BlindZones.isBlind(wall: 11))
        #expect(BlindZones.isBlind(wall: 13))
        #expect(!BlindZones.isBlind(wall: 14))
        #expect(BlindZones.isBlind(wall: 23))
        #expect(BlindZones.isBlind(wall: 25))
        #expect(!BlindZones.isBlind(wall: 26))
        // Tercera zona: ya dura cuatro muros.
        #expect(BlindZones.isBlind(wall: 38))
        #expect(!BlindZones.isBlind(wall: 39))
    }

    @Test("El mismo índice y semilla dan el mismo chunk, en cualquier orden")
    func generationIsDeterministic() {
        let forward = (1...20).map { WorldGenerator.chunk(index: $0, seed: 42) }
        let backward = Array((1...20).reversed().map { WorldGenerator.chunk(index: $0, seed: 42) }.reversed())
        #expect(forward == backward)
    }

    @Test("Semillas distintas dan mundos distintos")
    func seedsDiverge() {
        let a = (1...20).map { WorldGenerator.chunk(index: $0, seed: 1) }
        let b = (1...20).map { WorldGenerator.chunk(index: $0, seed: 2) }
        #expect(a != b)
    }

    @Test("El hueco siempre cabe con su margen")
    func gapAlwaysFits() {
        for index in 1...200 {
            let wall = WorldGenerator.chunk(index: index, seed: 7).wall
            #expect(wall.gapBottomY >= Tuning.World.floorY + Tuning.WorldGen.gapEdgeMargin - 0.001)
            #expect(wall.gapTopY <= Tuning.World.ceilingY - Tuning.WorldGen.gapEdgeMargin + 0.001)
        }
    }

    @Test("En zona a ciegas el hueco es más generoso")
    func blindGapIsMoreForgiving() {
        for index in 1...200 where BlindZones.isBlind(wall: index) {
            let chunk = WorldGenerator.chunk(index: index, seed: 7)
            #expect(chunk.isBlind)
            #expect(chunk.wall.gapHeight == DifficultyCurve.gapHeight(forWall: index)
                    + Tuning.WorldGen.blindGapBonus)
        }
    }

    @Test("Cada chunk tiene anclas alcanzables y despejadas de los muros")
    func anchorsAreReachableAndClear() {
        for index in 1...200 {
            let chunk = WorldGenerator.chunk(index: index, seed: 7)
            let previousWallX = index > 1
                ? DifficultyCurve.wallX(forWall: index - 1)
                : Tuning.Player.startX

            #expect(!chunk.anchors.isEmpty)
            // La invariante que de verdad importa: desde CUALQUIER farol del chunk,
            // colgando, se llega a la altura del hueco. Antes las anclas se sorteaban
            // por su cuenta y el 45 % de los huecos era inalcanzable balanceándose.
            let reachable = WorldGenerator.anchorHeightRange(forGapCenterY: chunk.wall.gapCenterY)
            for anchor in chunk.anchors {
                #expect(anchor.position.y >= reachable.lowerBound - 0.001)
                #expect(anchor.position.y <= reachable.upperBound + 0.001)
                #expect(anchor.position.y <= Tuning.World.ceilingY)
                #expect(anchor.position.x >= previousWallX + Tuning.WorldGen.anchorWallClearance - 0.001)
                #expect(anchor.position.x <= chunk.wall.x - Tuning.WorldGen.anchorWallClearance + 0.001)
            }
            if chunk.anchors.count == 2 {
                let separation = abs(chunk.anchors[1].position.x - chunk.anchors[0].position.x)
                #expect(separation >= Tuning.WorldGen.anchorMinSeparationX - 0.001)
            }
        }
    }

    @Test("La ventana viva de chunks no crece con el tiempo")
    func liveWindowStaysBounded() {
        var simulation = GameSimulation(seed: 1)
        for _ in 0..<2000 {
            _ = simulation.advance(dt: 1.0 / 120, holding: false)
            #expect(simulation.chunks.count == Tuning.WorldGen.liveChunkCount)
        }
    }
}
