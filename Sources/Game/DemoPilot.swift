import CoreGraphics

/// El bot de la demo (`-demo`), que pilota las capturas y el vídeo de la ficha.
///
/// No es un controlador: es **búsqueda + replay**. Escribir un buen controlador
/// de péndulo es un problema de control en sí mismo (el heurístico anterior
/// moría hacia el muro 8, antes de la primera zona a ciegas). Pero el mundo es
/// determinista —misma seed, misma física— así que basta buscar offline, muro a
/// muro, una secuencia de pulsaciones que sobrevive, y reproducirla a timestep
/// fijo. Es la misma idea que el test de transitabilidad de GameplayTests, con
/// memoria: cada muro superado consolida el estado y se busca solo el siguiente.
///
/// La búsqueda es en profundidad **con retroceso**, y eso no es un adorno: la
/// versión anterior consolidaba el primer estado que cruzaba cada muro y no lo
/// soltaba nunca. Cruzar un muro con la velocidad equivocada deja al farolillo en
/// un callejón sin salida —el muro siguiente ya no es alcanzable haga lo que
/// haga—, y allí la búsqueda se quedaba tirando miles de rollouts contra una
/// pared imposible hasta agotarlos: segundos de main thread congelado y un plan
/// que no llegaba ni a la mitad. Ahora, si un muro no se deja cruzar, se deshace
/// el anterior y se prueba otra forma de cruzarlo.
enum DemoPilot {

    /// El replay solo es fiel si la simulación avanza con este mismo paso.
    static let stepDT: CGFloat = 1.0 / 120

    /// Cuánto juego queremos grabado, en puntos (a ciegas valen doble): 40 ≈ muro
    /// 28, unos 34 s de partida — de sobra para el arco del clip (puertas →
    /// oscuridad → travesía → vuelta a la luz) con varias pantallas seguidas.
    static let targetScore = 40

    /// Techo duro de trabajo, en pasos de simulación. Es el seguro contra lo que
    /// pasó: por muy retorcido que se ponga el mundo, la búsqueda para y devuelve
    /// el mejor plan que tenga en vez de colgar el arranque. Se mide en pasos y no
    /// en segundos a propósito — así el plan es el mismo en cualquier máquina, que
    /// es lo único que hace reproducible una captura.
    static let stepBudget = 150_000

    /// Cuántos intentos se le dan a un muro antes de retroceder al anterior. Bajo
    /// a propósito: insistir en un nodo malo es justo lo que ahogaba a la versión
    /// greedy, y con retroceso sale más barato probar otra entrada al muro que
    /// otras mil salidas desde el mismo sitio.
    static let rolloutsPerVisit = 60

    /// Cuánto se deja correr un intento antes de darlo por perdido. Cruzar un muro
    /// cuesta ~1 s de juego; más allá de esto el farolillo está dando vueltas sin
    /// avanzar y el intento solo gasta presupuesto.
    static let rolloutSeconds: CGFloat = 3

    /// Plan para la seed del juego, calculado una vez por proceso al primer uso
    /// (solo lo toca el path de demo, así que una partida normal no paga nada).
    static let plan: [Bool] = searchPlan(seed: Tuning.WorldGen.initialSeed,
                                         targetScore: targetScore)

    static func searchPlan(seed: UInt64,
                           targetScore: Int,
                           stepBudget: Int = DemoPilot.stepBudget) -> [Bool] {
        var rng = SplitMix64(seed: 0xDE_0B_07)
        // Cada nodo es un muro cruzado: el estado del mundo y hasta dónde del plan
        // llegaban las pulsaciones que llevaron hasta él. Retroceder es descartar
        // el último y recortar el plan a esa marca.
        var stack: [(sim: GameSimulation, planLength: Int)] = [(GameSimulation(seed: seed), 0)]
        var plan: [Bool] = []
        var best: [Bool] = []
        var bestScore = 0
        var steps = 0

        while let node = stack.last, node.sim.score < targetScore, steps < stepBudget {
            let goal = node.sim.score + 1
            var solved = false

            for _ in 0..<rolloutsPerVisit where !solved && steps < stepBudget {
                var sim = node.sim
                var segment: [Bool] = []
                var holding = false
                var untilNextDecision: CGFloat = 0
                var elapsed: CGFloat = 0

                while elapsed < rolloutSeconds, !sim.isDead, sim.score < goal {
                    if untilNextDecision <= 0 {
                        holding = rng.nextCGFloat(in: 0...1) < 0.5
                        untilNextDecision = rng.nextCGFloat(in: 0.05...0.35)
                    }
                    _ = sim.advance(dt: stepDT, holding: holding)
                    segment.append(holding)
                    elapsed += stepDT
                    untilNextDecision -= stepDT
                }
                steps += segment.count

                if sim.score >= goal, !sim.isDead {
                    plan += segment
                    stack.append((sim, plan.count))
                    solved = true
                    if sim.score > bestScore {
                        bestScore = sim.score
                        best = plan
                    }
                }
            }

            if !solved {
                stack.removeLast()
                guard let parent = stack.last else { break }
                plan.removeLast(plan.count - parent.planLength)
            }
        }

        // Con el presupuesto agotado (o el mundo sin solución) se devuelve el plan
        // más largo que se llegó a ver, no el que hubiera en la mano al parar: al
        // retroceder, el de la mano es siempre más corto.
        return best
    }
}
