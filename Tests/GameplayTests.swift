import CoreGraphics
import Foundation
import Testing
@testable import LumiSwing

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

/// Un punto lejos de cualquier muro (el primero nace en `firstWallX`) y a medio
/// camino entre suelo y techo. Recolocar el cuerpo aquí cada frame, antes de
/// avanzar, deja correr la física de verdad (la velocidad sigue evolucionando
/// con la gravedad) sin arriesgarse a chocar — así los tests de ritmo pueden
/// durar más que una caída libre real sin escribir un bot. Compartido entre
/// `PaceTests` y `DeathPathTests`.
private let paceTestSafePosition = CGPoint(x: 100, y: Tuning.World.sceneHeight / 2)

/// Empuja la simulación exactamente `seconds` de tiempo simulado, recolocando el
/// cuerpo en zona segura en cada paso, y devuelve las velocidades muestreadas.
@discardableResult
private func pinnedAdvance(_ simulation: inout GameSimulation, seconds: CGFloat,
                           dt: CGFloat = 1.0 / 120) -> [CGFloat] {
    var speeds: [CGFloat] = []
    var elapsed: CGFloat = 0
    while elapsed < seconds {
        simulation.placeBody(at: paceTestSafePosition)
        _ = simulation.advance(dt: dt, holding: false)
        speeds.append(simulation.body.velocity.length)
        elapsed += dt
    }
    return speeds
}

@Suite("Ritmo sostenido")
struct PaceTests {

    @Test("Una partida más corta que la ventana no puntúa ritmo")
    func shortRunScoresZeroPace() {
        var simulation = GameSimulation(seed: 3)
        pinnedAdvance(&simulation, seconds: Tuning.Pace.windowSeconds - 1)
        #expect(!simulation.isDead)
        #expect(simulation.bestPace == 0)
        #expect(simulation.bestPaceMetersPerSecond == 0)
    }

    @Test("Pasada la ventana, el ritmo deja de ser cero")
    func runAtLeastWindowScoresPace() {
        var simulation = GameSimulation(seed: 3)
        pinnedAdvance(&simulation, seconds: Tuning.Pace.windowSeconds + 0.5)
        #expect(!simulation.isDead)
        #expect(simulation.bestPace > 0)
    }

    /// La media móvil tiene que reaccionar a que la velocidad cambie DENTRO de la
    /// partida, no solo acumular desde el arranque: se compara con la media
    /// calculada a mano sobre las mismas muestras — al caer libremente sin
    /// agarrarse a nada, la velocidad arranca baja y sube hasta el tope, así que
    /// una media desde el inicio y una media de los últimos 10 s dan números
    /// claramente distintos si la ventana funciona de verdad.
    @Test("La media móvil de 10 s es la ventana reciente, no un acumulado desde el inicio")
    func movingAverageReflectsRecentWindow() {
        var simulation = GameSimulation(seed: 5)
        let dt: CGFloat = 1.0 / 120
        let totalSeconds = Tuning.Pace.windowSeconds + 3
        let samples = pinnedAdvance(&simulation, seconds: totalSeconds, dt: dt)
        #expect(!simulation.isDead)

        let windowSampleCount = Int((Tuning.Pace.windowSeconds / dt).rounded())
        let recentAverage = samples.suffix(windowSampleCount).reduce(0, +) / CGFloat(windowSampleCount)
        let sinceStartAverage = samples.reduce(0, +) / CGFloat(samples.count)

        // La ventana real y el acumulado desde el inicio no pueden coincidir: si
        // coincidieran, la "ventana" estaría acumulando desde el arranque, que es
        // justo el bug que este test existe para detectar.
        #expect(abs(recentAverage - sinceStartAverage) > 1,
               "recentAverage=\(recentAverage) sinceStartAverage=\(sinceStartAverage)")

        // La resolución de cubos (`Tuning.Pace.bucketCount`) introduce un margen
        // de redondeo de, como mucho, un cubo de ancho: no se espera coincidencia
        // exacta con la media a mano, solo que estén cerca.
        let tolerance = recentAverage * 0.05 + 5
        #expect(abs(simulation.bestPace - recentAverage) < tolerance,
               "ritmo=\(simulation.bestPace) media a mano=\(recentAverage)")
    }

    @Test("Morir congela el ritmo; solo reiniciar lo pone a cero")
    func paceFreezesOnDeathAndResets() {
        var simulation = GameSimulation(seed: 1)
        // Sin tocar nada, el farolillo cae hasta el suelo (mismo escenario que
        // "Morir congela la simulación" en CollisionTests) — dura bastante menos
        // que la ventana, así que el ritmo se queda en 0.
        for _ in 0..<2000 where !simulation.isDead {
            _ = simulation.advance(dt: 1.0 / 120, holding: false)
        }
        #expect(simulation.isDead)

        let frozen = simulation.bestPace
        #expect(frozen == 0)

        // Tras morir, `advance` no hace nada — el ritmo tampoco debe moverse.
        _ = simulation.advance(dt: 1.0 / 120, holding: true)
        #expect(simulation.bestPace == frozen)

        simulation.reset(seed: 1)
        #expect(simulation.bestPace == 0)
        #expect(simulation.bestPaceMetersPerSecond == 0)
    }

    @Test("El tope de velocidad del péndulo son 15 m/s")
    func conversionMatchesTuning() {
        // Fija la constante de presentación al valor documentado en
        // `Tuning.Units`: si alguien la cambia sin querer, este test lo nota.
        #expect(Tuning.Pendulum.maxSpeed / Tuning.Units.pointsPerMeter == 15)
    }

    @Test("`bestPaceMetersPerSecond` es siempre el ritmo en puntos dividido entre la constante")
    func paceConversionIsConsistent() {
        var simulation = GameSimulation(seed: 3)
        pinnedAdvance(&simulation, seconds: Tuning.Pace.windowSeconds + 1)
        #expect(simulation.bestPaceMetersPerSecond == simulation.bestPace / Tuning.Units.pointsPerMeter)
    }
}

@Suite("Camino de muerte")
@MainActor
struct DeathPathTests {

    /// Un `UserDefaults` propio: el récord del simulador no es de nadie.
    private func isolatedSettings() -> GameSettings {
        let suite = "pendulo.tests.death"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return GameSettings(defaults: defaults)
    }

    /// Que la simulación retenga el ritmo no sirve de nada si al morir se queda
    /// dentro de la simulación: este test recorre el camino completo hasta lo que
    /// lee `GameOverView` (`AppModel`) y lo que sobrevive a cerrar la app.
    ///
    /// Primero construye ritmo de verdad (recolocado en zona segura durante la
    /// ventana de 10 s, igual que `PaceTests`) y solo entonces lo deja caer sin
    /// red hasta chocar: así el ritmo que atraviesa el camino de muerte es
    /// distinto de cero, que es el caso que importa probar — una muerte
    /// instantánea siempre daría 0 y no probaría nada del pipeline.
    @Test("Al morir tras completar la ventana, el ritmo llega a la pantalla de fin y al récord")
    func deathCarriesPace() {
        var simulation = GameSimulation(seed: 1)
        pinnedAdvance(&simulation, seconds: Tuning.Pace.windowSeconds + 0.5)
        #expect(!simulation.isDead)

        // Ahora sin red: el farolillo, ya lanzado, cae hasta el suelo de verdad.
        for _ in 0..<2000 where !simulation.isDead {
            _ = simulation.advance(dt: 1.0 / 120, holding: false)
        }
        #expect(simulation.isDead)

        let pace = Double(simulation.bestPaceMetersPerSecond)
        #expect(pace > 0)

        let settings = isolatedSettings()
        let model = AppModel()
        model.endRun(score: simulation.score, bestPaceMetersPerSecond: pace, settings: settings)

        #expect(model.bestPaceMetersPerSecond == pace)
        #expect(settings.bestPace == pace)
        #expect(model.score == simulation.score)
        #expect(model.best == settings.best)
        #expect(model.phase == .dead)
    }
}

@Suite("Silueta de Lumi")
struct FireflySilhouetteTests {

    /// La bola se deforma dos veces y las dos se multiplican: el squash del agarre
    /// sobre el estiramiento por velocidad. Si el producto se pasa del radio de
    /// colisión, el dibujo miente sobre lo que mata (pilar 2 del GDD) — y eso es
    /// justo lo que pasaba con la anatomía anterior, que llegaba a ~35 pt sobre 26.
    @Test("La masa dibujada nunca sale del círculo de colisión")
    func drawnMassFitsInsideCollisionRadius() {
        let drawn = Tuning.Scenery.bodyRadius
            * Tuning.Feel.squashScale
            * (1 + Tuning.Scenery.stretchAtMaxSpeed)
        #expect(drawn <= Tuning.Player.radius)
    }

    /// Con amortiguación crítica el giro llega y se para en seco: se sigue leyendo
    /// como interpolación. El rebote es la mitad del efecto.
    @Test("El muelle de la pose está subamortiguado")
    func poseSpringIsUnderdamped() {
        #expect(Tuning.Scenery.poseDamping < 2 * Tuning.Scenery.poseStiffness.squareRoot())
        #expect(Tuning.Scenery.poseStiffness > 0)
    }

    /// A 1 el cuerpo se cuelga rígido de la liana, que es la pose que se quiso
    /// quitar; a 0 no se enteraría nunca del balanceo.
    @Test("El sesgo de verticalidad deja el cuerpo casi erguido")
    func uprightBiasKeepsTheBodyUpright() {
        #expect(Tuning.Scenery.uprightBias > 0)
        #expect(Tuning.Scenery.uprightBias < 0.5)
    }
}

@Suite("Bot de demo")
struct DemoPilotTests {

    /// La demo pilota las capturas y el vídeo de la ficha, y su plano estrella es
    /// la primera zona a ciegas (muros 11-13). Si el plan no llega vivo más allá,
    /// el material de App Store no se puede grabar — eso es exactamente lo que
    /// pasaba con el heurístico antiguo, que moría hacia el muro 8.
    @Test("El plan de la demo llega vivo al objetivo")
    func planReachesTargetScore() {
        var sim = GameSimulation(seed: Tuning.WorldGen.initialSeed)
        for hold in DemoPilot.plan {
            _ = sim.advance(dt: DemoPilot.stepDT, holding: hold)
            if sim.isDead { break }
        }
        #expect(!sim.isDead)
        #expect(sim.score >= DemoPilot.targetScore, "el plan replay llegó a \(sim.score) puntos")
    }

    /// El clip son ~20 s: un plan más corto deja al bot en manos del heurístico a
    /// mitad de grabación, que es cuando se estrella.
    @Test("El plan da para más de veinte segundos de juego")
    func planCoversTheClip() {
        #expect(CGFloat(DemoPilot.plan.count) * DemoPilot.stepDT > 20)
    }

    /// La regresión que congelaba el arranque con `-demo`: sin techo, un muro que
    /// no se deja cruzar se lleva por delante todo el tiempo del mundo. Con un
    /// objetivo inalcanzable la búsqueda tiene que rendirse dentro del presupuesto
    /// y devolver lo que llevara conseguido.
    @Test("La búsqueda se rinde dentro del presupuesto")
    func searchStopsWithinBudget() {
        let plan = DemoPilot.searchPlan(seed: Tuning.WorldGen.initialSeed,
                                        targetScore: 10_000,
                                        stepBudget: 20_000)
        #expect(plan.count <= 20_000)
        #expect(!plan.isEmpty)
    }
}
