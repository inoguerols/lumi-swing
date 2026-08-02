import CoreGraphics
import Testing
@testable import LumiSwing

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

    @Test("La rampa del velo se liga a la distancia al muro de entrada, no a un salto")
    func telegraphProgressRampsWithDistance() {
        let spacing: CGFloat = 300

        // A más de una separación de muro, aún no se nota nada.
        #expect(BlindZones.telegraphProgress(distanceToEntry: spacing * 2, wallSpacing: spacing) == 0)
        // A mitad de esa ventana de aviso, va a medias.
        #expect(BlindZones.telegraphProgress(distanceToEntry: spacing / 2, wallSpacing: spacing) == 0.5)
        // Justo en el muro de entrada, cerrado del todo.
        #expect(BlindZones.telegraphProgress(distanceToEntry: 0, wallSpacing: spacing) == 1)
        // Ya pasado el muro (distancia negativa): sigue cerrado, no se dispara.
        #expect(BlindZones.telegraphProgress(distanceToEntry: -50, wallSpacing: spacing) == 1)
    }

    @Test("El velo se telegrafía antes de cruzar el muro de entrada, no de golpe al cruzarlo")
    func blindZoneTelegraphsAheadOfEntry() {
        var simulation = GameSimulation(seed: 1)
        let entryIndex = Tuning.BlindZone.firstWall
        let entryX = DifficultyCurve.wallX(forWall: entryIndex)
        let spacing = DifficultyCurve.spacing(forWall: entryIndex - 1)
        let window = spacing * Tuning.BlindZone.telegraphWalls

        // A más de una separación de muro del muro de entrada, el velo sigue abierto.
        // (El margen extra de 100 pt deja el farolillo bien lejos del cuerpo sólido
        // del muro anterior, igual que `pastWallMargin`.)
        simulation.placeBody(at: CGPoint(x: entryX - window - 100, y: Tuning.Player.startY))
        _ = simulation.advance(dt: 1.0 / 120, holding: false)
        #expect(simulation.blindZoneTelegraph == 0)

        // A mitad de esa ventana ya se está cerrando, pero no del todo.
        simulation.placeBody(at: CGPoint(x: entryX - window / 2, y: Tuning.Player.startY))
        _ = simulation.advance(dt: 1.0 / 120, holding: false)
        #expect(simulation.blindZoneTelegraph > 0 && simulation.blindZoneTelegraph < 1)

        // Ya dentro de la zona (justo tras cruzar el muro de entrada), cerrado del
        // todo — y sin que se abra un instante camino del siguiente muro a ciegas.
        simulation.placeBody(at: CGPoint(x: entryX + Self.pastWallMargin, y: Tuning.Player.startY))
        _ = simulation.advance(dt: 1.0 / 120, holding: false)
        #expect(simulation.blindZoneTelegraph == 1)
    }

    @Test("El eco se apaga zona a zona: máximo en la primera, cero al acabar la enseñanza")
    func echoFadesAcrossTeachingZones() {
        #expect(BlindZones.ghostAlpha(zonesExperienced: 0) == Tuning.BlindTeaching.initialAlpha)

        // Estrictamente decreciente mientras dura la enseñanza: si dos zonas
        // seguidas se vieran igual, el jugador no notaría que se le está retirando.
        for lived in 1..<Tuning.BlindTeaching.teachingZones {
            #expect(BlindZones.ghostAlpha(zonesExperienced: lived)
                    < BlindZones.ghostAlpha(zonesExperienced: lived - 1))
            #expect(BlindZones.ghostAlpha(zonesExperienced: lived) > 0)
        }
    }

    @Test("Pasada la enseñanza, a ciegas de verdad para siempre")
    func echoIsGoneAfterTeachingZones() {
        for lived in Tuning.BlindTeaching.teachingZones...(Tuning.BlindTeaching.teachingZones + 50) {
            #expect(BlindZones.ghostAlpha(zonesExperienced: lived) == 0)
        }
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
