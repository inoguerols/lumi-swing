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
enum DemoPilot {

    /// El replay solo es fiel si la simulación avanza con este mismo paso.
    static let stepDT: CGFloat = 1.0 / 120

    /// Plan para la seed del juego, calculado una vez por proceso al primer uso
    /// (solo lo toca el path de demo, así que una partida normal no paga nada).
    /// El objetivo es en puntos, y a ciegas valen doble: 26 ≈ muro 18 — de sobra
    /// para el arco del clip (puertas → oscuridad → travesía → vuelta a la luz).
    static let plan: [Bool] = searchPlan(seed: Tuning.WorldGen.initialSeed, targetScore: 26)

    static func searchPlan(seed: UInt64, targetScore: Int) -> [Bool] {
        var base = GameSimulation(seed: seed)
        var plan: [Bool] = []
        var rng = SplitMix64(seed: 0xDE_0B_07)

        while base.score < targetScore {
            let objetivo = base.score + 1
            var logrado = false

            for _ in 0..<4000 where !logrado {
                var sim = base
                var segmento: [Bool] = []
                var holding = false
                var untilNextDecision: CGFloat = 0
                var elapsed: CGFloat = 0

                while elapsed < 8, !sim.isDead, sim.score < objetivo {
                    if untilNextDecision <= 0 {
                        holding = rng.nextCGFloat(in: 0...1) < 0.5
                        untilNextDecision = rng.nextCGFloat(in: 0.05...0.35)
                    }
                    _ = sim.advance(dt: stepDT, holding: holding)
                    segmento.append(holding)
                    elapsed += stepDT
                    untilNextDecision -= stepDT
                }

                if sim.score >= objetivo, !sim.isDead {
                    base = sim
                    plan += segmento
                    logrado = true
                }
            }

            // ponytail: si un muro se resiste tras 4000 intentos, el plan llega
            // hasta donde llegue y la escena cae al heurístico antiguo.
            if !logrado { break }
        }
        return plan
    }
}
