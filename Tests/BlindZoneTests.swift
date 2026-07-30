import CoreGraphics
import Testing
@testable import Pendulo

@Suite("Zonas a ciegas")
struct BlindZoneTests {

    /// Cuánto hay que adelantarse para quedar limpiamente al otro lado de un muro.
    /// El muro ocupa media anchura a cada lado del centro y el farolillo tiene su
    /// radio: colocarlo "justo pasado el muro" lo mete dentro y lo mata.
    private static let pastWallMargin =
        Tuning.World.wallThickness / 2 + Tuning.Player.radius + 100

    @Test("Entrar y salir de la zona se anuncia una sola vez")
    func bordersAreAnnouncedOnce() {
        var simulation = GameSimulation(seed: 1)
        var entries = 0
        var exits = 0

        // Se coloca el farolillo por delante de cada muro para recorrer el mundo sin
        // depender de saber jugar.
        for wall in 1...30 {
            simulation.placeBody(at: CGPoint(x: DifficultyCurve.wallX(forWall: wall) + Self.pastWallMargin,
                                             y: Tuning.Player.startY))
            for event in simulation.advance(dt: 1.0 / 120, holding: false) {
                if event == .enteredBlindZone { entries += 1 }
                if event == .exitedBlindZone { exits += 1 }
            }
        }

        // Dos zonas empiezan dentro de los primeros 30 muros (11 y 23; la tercera
        // cae en el 35), y cada una se abre y se cierra exactamente una vez.
        #expect(entries == 2)
        #expect(exits == 2)
    }

    @Test("El muro 11 es el primero a ciegas y el jugador se entera al llegar")
    func firstBlindZoneIsAtWallEleven() {
        var simulation = GameSimulation(seed: 1)
        simulation.placeBody(at: CGPoint(x: DifficultyCurve.wallX(forWall: 10) + 1,
                                         y: Tuning.Player.startY))
        let events = simulation.advance(dt: 1.0 / 120, holding: false)

        #expect(events.contains(.enteredBlindZone))
        #expect(simulation.isBlind)
        #expect(simulation.nextChunk?.index == 11)
    }

    @Test("A ciegas, el hueco es más generoso de lo que sería a la vista")
    func blindGapIsMoreForgiving() {
        let blind = WorldGenerator.chunk(index: 11, seed: 5)
        #expect(blind.isBlind)
        #expect(blind.wall.gapHeight
                == DifficultyCurve.gapHeight(forWall: 11) + Tuning.WorldGen.blindGapBonus)
    }

    /// La prueba de aceptación del slice: una zona a ciegas tiene que poder pasarse
    /// **usando solo la información que entregan los hápticos**. El agente de este
    /// test no mira el mundo; recibe exactamente lo mismo que un dedo — el ritmo de
    /// proximidad y si la textura de alineación está presente o no.
    /// Un intento guiado **solo** por lo que entregan los hápticos, empezando justo
    /// a la entrada de la primera zona a ciegas.
    ///
    /// Se coloca ahí a propósito: exigir que un agente llegue vivo hasta el muro 11
    /// mediría su habilidad general con el péndulo, no si el idioma háptico basta
    /// para cruzar un muro invisible — que es lo único que este slice promete.
    private func hapticGuidedRun(world: UInt64, policy: UInt64) -> Int {
        var simulation = GameSimulation(seed: world)
        simulation.placeBody(at: CGPoint(
            x: DifficultyCurve.wallX(forWall: Tuning.BlindZone.firstWall - 1) + Self.pastWallMargin,
            y: Tuning.Player.startY))

        var rng = SplitMix64(seed: policy)
        let step: CGFloat = 1.0 / 120

        var holding = false
        var untilDecision: CGFloat = 0
        var elapsed: CGFloat = 0

        while !simulation.isDead && elapsed < 60 {
            if untilDecision <= 0 {
                // Lo único que "siente" el agente: el ritmo de proximidad y si la
                // textura de alineación está presente. Nada de geometría.
                let cue = simulation.distanceToNextWall
                    .flatMap(ProximityMapping.cue(forDistance:))
                let textureIsPresent = simulation.clearanceAtNextWall
                    .flatMap(ProximityMapping.alignmentIntensity(clearance:)) != nil

                // Estrategia legible con el tacto: si la textura dice que cabes, sigue
                // haciendo lo mismo; si no, prueba otra cosa. El ritmo marca cada
                // cuánto se replantea la decisión: cuanto más cerca el muro, más a
                // menudo.
                if !textureIsPresent {
                    holding = rng.nextCGFloat(in: 0...1) < 0.5
                }
                untilDecision = cue.map { max(0.05, $0.interval) } ?? 0.2
            }

            _ = simulation.advance(dt: step, holding: holding)
            elapsed += step
            untilDecision -= step
        }
        return simulation.score
    }

    @Test("Se puede atravesar una zona a ciegas solo con la información háptica")
    func blindZoneIsSolvableFromHapticsAlone() {
        var best = 0
        var report = ""

        for world in UInt64(1)...UInt64(4) {
            var bestHere = 0
            for attempt in UInt64(0)..<400 {
                bestHere = max(bestHere,
                               hapticGuidedRun(world: world, policy: world &* 31_337 &+ attempt))
            }
            best = max(best, bestHere)
            report += "mundo \(world): \(bestHere) puntos\n"
        }

        // El primer muro a ciegas vale doble: 2 puntos significa haberlo cruzado sin
        // verlo, usando solo el ritmo y la textura. Si esto falla, la mecánica firma
        // no es superable a ciegas y el juego no tiene razón de ser.
        #expect(best >= Tuning.BlindZone.scoreMultiplier,
                "Mejor recorrido guiado solo por hápticos: \(best) puntos.\n\(report)")
    }
}
