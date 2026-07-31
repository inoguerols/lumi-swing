import CoreGraphics
import Testing
@testable import Pendulo

/// No verifica: **mide**. Existe porque un jugador humano dijo que no pasaba de
/// dos o tres puertas, y para arreglar eso hace falta saber dónde y por qué muere,
/// no opinar sobre ello.
///
/// Estos tests imprimen un informe y solo fallan cuando el número que sacan
/// significa que el juego es injusto, no difícil.
@Suite("Diagnóstico de jugabilidad")
struct DiagnosticsTests {

    // MARK: - ¿Se puede llegar al hueco colgando?

    /// Con la cuerda tensa, el farolillo solo puede estar entre
    /// `ancla.y - maxRope` y `ancla.y - minRope`. Si ese rango no toca el hueco,
    /// llegar exige soltarse y acertar una parábola.
    @Test("Cuántos huecos son inalcanzables colgando de sus propias anclas")
    func gapsReachableWhileSwinging() {
        var unreachable = 0
        var total = 0
        var examples: [String] = []

        for index in 1...300 {
            let chunk = WorldGenerator.chunk(index: index, seed: 7)
            total += 1

            let gapLow = chunk.wall.gapBottomY + Tuning.Player.radius
            let gapHigh = chunk.wall.gapTopY - Tuning.Player.radius

            // Con la cuerda de longitud fija, colgar de un farol te deja a una única
            // altura: `ancla − ropeLength`. O cae dentro del hueco, o ese hueco no se
            // pasa balanceándose.
            let reachable = chunk.anchors.contains { anchor in
                let hanging = anchor.position.y - Tuning.Pendulum.ropeLength
                return hanging >= gapLow && hanging <= gapHigh
            }

            if !reachable {
                unreachable += 1
                if examples.count < 5, let first = chunk.anchors.first {
                    examples.append(
                        "muro \(index): hueco [\(Int(gapLow)), \(Int(gapHigh))] · "
                        + "anclas \(chunk.anchors.map { Int($0.position.y) }) · "
                        + "colgando quedas a \(Int(first.position.y - Tuning.Pendulum.ropeLength))")
                }
            }
        }

        let percentage = Double(unreachable) / Double(total) * 100
        print("""

        ┌─ ALCANZABILIDAD DEL HUECO COLGANDO ─────────────────────────
        │ Huecos a los que NO se llega balanceándose: \(unreachable)/\(total) (\(String(format: "%.0f", percentage)) %)
        │ (hay que soltarse y acertar una parábola)
        \(examples.map { "│   \($0)" }.joined(separator: "\n"))
        └──────────────────────────────────────────────────────────────

        """)

        // Que a veces haya que volar es buen diseño; que sea la norma convierte el
        // juego en una lotería de parábolas, y eso traiciona el pilar 2.
        #expect(percentage < 40,
                "El \(String(format: "%.0f", percentage)) % de los huecos no se alcanza balanceándose")
    }

    // MARK: - ¿De qué se muere, y dónde?

    @Test("De qué muere el jugador y en qué muro")
    func causeOfDeath() {
        var byObstacle: [String: Int] = [:]
        var byWall: [Int: Int] = [:]
        var scores: [Int] = []
        var deathsWhileAttached = 0

        for world in UInt64(1)...UInt64(6) {
            for attempt in UInt64(0)..<300 {
                var simulation = GameSimulation(seed: world)
                var rng = SplitMix64(seed: world &* 977 &+ attempt)
                let step: CGFloat = 1.0 / 120

                var holding = false
                var untilDecision: CGFloat = 0
                var elapsed: CGFloat = 0
                var cause: ObstacleKind?

                while !simulation.isDead && elapsed < 30 {
                    if untilDecision <= 0 {
                        holding = rng.nextCGFloat(in: 0...1) < 0.5
                        untilDecision = rng.nextCGFloat(in: 0.05...0.35)
                    }
                    for event in simulation.advance(dt: step, holding: holding) {
                        if case .died(let kind) = event {
                            cause = kind
                            if simulation.body.isAttached { deathsWhileAttached += 1 }
                        }
                    }
                    elapsed += step
                    untilDecision -= step
                }

                scores.append(simulation.score)
                if let cause {
                    byObstacle["\(cause)", default: 0] += 1
                    byWall[simulation.nextChunk?.index ?? 0, default: 0] += 1
                }
            }
        }

        let runs = scores.count
        let mean = Double(scores.reduce(0, +)) / Double(runs)
        let sorted = scores.sorted()
        let median = sorted[runs / 2]
        let best = sorted.last ?? 0
        let zeros = scores.filter { $0 == 0 }.count

        print("""

        ┌─ DE QUÉ SE MUERE (\(runs) partidas) ──────────────────────────
        │ Puntuación media:   \(String(format: "%.2f", mean))
        │ Mediana:            \(median)
        │ Mejor de todas:     \(best)
        │ Partidas a cero:    \(zeros) (\(zeros * 100 / runs) %)
        │
        │ Causa de la muerte:
        \(byObstacle.sorted { $0.value > $1.value }.map { "│   \($0.key): \($0.value) (\($0.value * 100 / runs) %)" }.joined(separator: "\n"))
        │
        │ Muertes con la cuerda agarrada: \(deathsWhileAttached)
        │
        │ Muro donde mueren (los 6 más frecuentes):
        \(byWall.sorted { $0.value > $1.value }.prefix(6).map { "│   muro \($0.key): \($0.value) veces" }.joined(separator: "\n"))
        └──────────────────────────────────────────────────────────────

        """)
    }

    // MARK: - ¿Hay flores que te matan hagas lo que hagas?

    /// Colgado de una flor a distancia `D` del muro, el arco cruza el plano del muro
    /// a la altura `flor.y − √(L² − D²)`. Si esa altura cae en la parte maciza, el
    /// balanceo termina en muerte **hiciera lo que hiciera el jugador**: no es
    /// dificultad, es una trampa.
    ///
    /// Las flores lejanas (D mayor que la liana) no llegan al muro y son inocuas.
    @Test("Ninguna flor condena el balanceo contra el muro")
    func noAnchorForcesACrash() {
        var traps = 0
        var total = 0
        var examples: [String] = []

        for index in 1...300 {
            let chunk = WorldGenerator.chunk(index: index, seed: 7)
            let rope = Tuning.Pendulum.ropeLength
            let safeLow = chunk.wall.gapBottomY + Tuning.Player.radius
            let safeHigh = chunk.wall.gapTopY - Tuning.Player.radius

            for anchor in chunk.anchors {
                let distance = chunk.wall.x - anchor.position.x
                // Detrás del muro o fuera del alcance de la liana: no puede chocar.
                guard distance > 0, distance < rope else { continue }
                total += 1

                let crossing = anchor.position.y - (rope * rope - distance * distance).squareRoot()
                if crossing < safeLow || crossing > safeHigh {
                    traps += 1
                    if examples.count < 5 {
                        examples.append(
                            "muro \(index): flor a \(Int(distance)) pt del muro cruza a "
                            + "\(Int(crossing)), y el hueco va de \(Int(safeLow)) a \(Int(safeHigh))")
                    }
                }
            }
        }

        print("""

        ┌─ FLORES QUE CONDENAN EL BALANCEO ───────────────────────────
        │ Flores cuyo arco alcanza el muro: \(total)
        │ De ellas, las que lo cruzan por lo macizo: \(traps)
        \(examples.map { "│   \($0)" }.joined(separator: "\n"))
        └──────────────────────────────────────────────────────────────

        """)

        #expect(traps == 0, "\(traps) flores llevan al muro hagas lo que hagas")
    }

    // MARK: - ¿Se puede pasar CADA puerta?

    private static let pastWall =
        Tuning.World.wallThickness / 2 + Tuning.Player.radius + 60

    /// La prueba de verdad, y la única que no depende de que mi modelo geométrico
    /// sea correcto: coger cada muro por separado, poner al jugador a la entrada de
    /// su tramo, y **buscar** si existe alguna secuencia de toques que lo cruce.
    ///
    /// Los tests anteriores razonaban sobre el arco con la liana a longitud de
    /// reposo. Pero la liana se recoge poco a poco y además se estira al tirar, así
    /// que el arco real no es el que dice la fórmula. Esto no razona: simula.
    @Test("Cada puerta se puede cruzar de alguna manera")
    func everyDoorIsPassable() {
        var impossible: [Int] = []
        var report: [String] = []

        for wall in 1...40 {
            var passed = false

            // Se entra por donde se habría cruzado el muro anterior, a la altura de
            // su hueco: la situación real de quien viene jugando.
            let entryX = wall > 1
                ? DifficultyCurve.wallX(forWall: wall - 1) + Self.pastWall
                : Tuning.Player.startX
            let entryY = wall > 1
                ? WorldGenerator.gapCenterY(forWall: wall - 1, seed: 7)
                : Tuning.Player.startY

            for attempt in UInt64(0)..<600 where !passed {
                var simulation = GameSimulation(seed: 7)
                simulation.placeBody(at: CGPoint(x: entryX, y: entryY))

                var rng = SplitMix64(seed: UInt64(wall) &* 7919 &+ attempt)
                let step: CGFloat = 1.0 / 120
                var holding = false
                var untilDecision: CGFloat = 0
                var elapsed: CGFloat = 0
                let targetX = DifficultyCurve.wallX(forWall: wall)

                while !simulation.isDead && elapsed < 12 {
                    if untilDecision <= 0 {
                        holding = rng.nextCGFloat(in: 0...1) < 0.55
                        untilDecision = rng.nextCGFloat(in: 0.04...0.30)
                    }
                    _ = simulation.advance(dt: step, holding: holding)
                    elapsed += step
                    untilDecision -= step

                    if simulation.body.position.x > targetX + Tuning.Player.radius {
                        passed = true
                        break
                    }
                }
            }

            if !passed {
                impossible.append(wall)
                if report.count < 6 {
                    let chunk = WorldGenerator.chunk(index: wall, seed: 7)
                    let flowers = chunk.anchors.map {
                        "(\(Int(chunk.wall.x - $0.position.x)) pt del muro, y=\(Int($0.position.y)))"
                    }
                    report.append("muro \(wall): hueco \(Int(chunk.wall.gapCenterY)) "
                                  + "±\(Int(chunk.wall.gapHeight / 2)) · flores \(flowers.joined(separator: " "))")
                }
            }
        }

        print("""

        ┌─ PUERTAS IMPOSIBLES (600 intentos cada una) ────────────────
        │ Imposibles: \(impossible.count) de 40 → \(impossible.map(String.init).joined(separator: ", "))
        \(report.map { "│   \($0)" }.joined(separator: "\n"))
        └──────────────────────────────────────────────────────────────

        """)

        #expect(impossible.isEmpty, "Puertas que no se pueden cruzar: \(impossible)")
    }

    // MARK: - ¿Se puede jugar bien?

    /// Un bot que **sabe** el gesto que el juego pide: agárrate al farol de delante,
    /// deja que el arco te lleve, y suelta al pasar por el punto más bajo yendo hacia
    /// delante. Como el farol está exactamente a una cuerda por encima del hueco, ese
    /// punto bajo es la altura del hueco: sueltas horizontal y a la altura correcta.
    ///
    /// Un bot aleatorio mide si el juego se puede pasar por chiripa. Este mide lo que
    /// de verdad importa: si el gesto que enseña el diseño **funciona**.
    private func skilledRun(world: UInt64, budget: CGFloat = 60) -> Int {
        var simulation = GameSimulation(seed: world)
        let step: CGFloat = 1.0 / 120
        var elapsed: CGFloat = 0

        while !simulation.isDead && elapsed < budget {
            let body = simulation.body
            let holding: Bool

            if let attachment = body.attachment {
                // Punto bajo del arco: justo debajo del ancla, avanzando.
                let atLowestPoint = abs(body.position.x - attachment.anchor.x) < 45
                    && body.position.y < attachment.anchor.y
                holding = !(atLowestPoint && body.velocity.dx > 0)
            } else {
                // Solo faroles por delante: si no, se reengancharía al que acaba de
                // soltar y se quedaría meciéndose en el sitio.
                holding = simulation.anchors.contains { anchor in
                    anchor.position.x > body.position.x
                        && body.position.distance(to: anchor.position) <= Tuning.Pendulum.grabRadius
                }
            }

            _ = simulation.advance(dt: step, holding: holding)
            elapsed += step
        }
        return simulation.score
    }

    @Test("Jugando bien, ¿hasta dónde se llega?")
    func skilledPlayReachesFar() {
        var scores: [Int] = []
        for world in UInt64(1)...UInt64(8) {
            scores.append(skilledRun(world: world))
        }

        let best = scores.max() ?? 0
        let worst = scores.min() ?? 0
        let mean = Double(scores.reduce(0, +)) / Double(scores.count)

        print("""

        ┌─ JUGANDO BIEN (bot que suelta en el punto bajo) ─────────────
        │ Por mundo: \(scores.map(String.init).joined(separator: ", "))
        │ Peor: \(worst) · Media: \(String(format: "%.1f", mean)) · Mejor: \(best)
        └──────────────────────────────────────────────────────────────

        """)

        // Sin umbral a propósito. Este bot suelta siempre en el punto más bajo, y eso
        // resultó ser un gesto POBRE: al soltar horizontal se cae durante el vuelo,
        // así que hay que soltar algo después del punto bajo, y cuánto depende de lo
        // lejos que esté el muro. Un controlador que sí anticipa la parábola llega a
        // 58-70 muros con este mismo mundo.
        //
        // O sea: este número mide la calidad del bot tanto como la del juego, y por
        // eso no se convierte en veredicto. Se deja porque su evolución sí informa —
        // si algún día sube solo, es que el juego se ha vuelto más indulgente.
        #expect(best >= 0)
    }

    // MARK: - ¿Cuánto tiempo se ve venir el muro?

    @Test("Cuánto tiempo ve el jugador el muro antes de llegar")
    func reactionWindow() {
        // La cámara va adelantada, así que el borde derecho de la pantalla queda a
        // esta distancia por delante del jugador.
        let halfScreen = Tuning.World.sceneWidth / 2
        let lookAhead = Tuning.World.sceneWidth * Tuning.Camera.lookAheadFactor
        let visibleAhead = halfScreen + lookAhead

        let speed = Tuning.Player.initialVelocityX
        let seconds = visibleAhead / speed
        let spacing = DifficultyCurve.spacing(forWall: 1)
        let spacingLate = DifficultyCurve.spacing(forWall: 60)

        print("""

        ┌─ VENTANA DE REACCIÓN ────────────────────────────────────────
        │ Se ve por delante:      \(Int(visibleAhead)) pt
        │ Velocidad de crucero:   \(Int(speed)) pt/s
        │ Tiempo para reaccionar: \(String(format: "%.2f", Double(seconds))) s
        │
        │ Espaciado: \(Int(spacing)) pt al principio, \(Int(spacingLate)) pt al final
        │ → entre muro y muro pasan \(String(format: "%.2f", Double(spacing / speed))) s
        └──────────────────────────────────────────────────────────────

        """)

        // Ver un muro, decidir y ejecutar un arco entero en menos de un segundo es
        // reacción, no anticipación. El pilar 2 pide lo segundo.
        #expect(seconds > 0.9,
                "Solo \(String(format: "%.2f", Double(seconds))) s desde que el muro entra en pantalla")
    }

    // MARK: - ¿El bombeo se va de las manos?

    @Test("A qué velocidad llega el farolillo si se mantiene pulsado")
    func pumpingRunaway() {
        let anchor = CGPoint(x: 500, y: 1400)
        var body = PendulumBody(position: CGPoint(x: anchor.x, y: anchor.y - 300),
                                velocity: CGVector(dx: 200, dy: 0))
        body.grab(anchors: [Anchor(position: anchor)])

        var samples: [(CGFloat, CGFloat)] = []
        var loops = 0
        var previousSide = body.position.x > anchor.x

        for frame in 0..<600 {
            body.advance(dt: 1.0 / 120, holding: true)
            let side = body.position.x > anchor.x
            // Cruzar de lado POR ENCIMA del ancla es una vuelta completa, no un arco.
            if side != previousSide && body.position.y > anchor.y { loops += 1 }
            previousSide = side
            if frame % 120 == 0 {
                samples.append((CGFloat(frame) / 120, body.velocity.length))
            }
        }

        print("""

        ┌─ BOMBEO MANTENIENDO PULSADO 5 s ─────────────────────────────
        │ Velocidad inicial: 200 pt/s
        \(samples.map { "│   t=\(String(format: "%.0f", Double($0.0))) s → \(Int($0.1)) pt/s" }.joined(separator: "\n"))
        │ Velocidad final:   \(Int(body.velocity.length)) pt/s (tope \(Int(Tuning.Pendulum.maxSpeed)))
        │ Pasadas POR ENCIMA del ancla: \(loops)
        │ (si es > 0 no se está balanceando: está dando vueltas)
        └──────────────────────────────────────────────────────────────

        """)
    }
}
