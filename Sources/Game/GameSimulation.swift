import CoreGraphics

/// Lo que la simulación le cuenta al mundo exterior. `GameScene` los reenvía al
/// motor háptico (S3) sin que la simulación sepa que existe Core Haptics.
enum GameEvent: Sendable, Equatable {
    case grabbed
    case released
    case missedGrab
    /// Una flor marchita agotó su presupuesto de agarre y cayó, soltando a Lumi
    /// con su velocidad exacta. Lleva la posición de la flor para que la escena
    /// sepa cuál animar.
    case flowerFell(CGPoint)
    /// Cuántos puntos sumó ese muro: 1, o el doble si era a ciegas.
    case scored(Int)
    case died(ObstacleKind)
    case enteredBlindZone
    case exitedBlindZone
}

/// Orquestador puro. No sabe que existen SpriteKit ni Core Haptics: avanza y
/// devuelve eventos. Dada una semilla y una secuencia de inputs, el resultado es
/// siempre el mismo — es lo que permite testear la mecánica sin simulador.
struct GameSimulation: Sendable {

    private(set) var body: PendulumBody
    private(set) var chunks: [Chunk] = []
    private(set) var score = 0
    private(set) var isDead = false
    /// Mejor media móvil de 10 s de `|velocidad|` alcanzada en la partida, en
    /// puntos por segundo. Sustituye al pico (que saturaba en `Pendulum.maxSpeed`
    /// en cualquier caída): solo premia mantener el ritmo, no un instante. Solo
    /// crece, y se queda en 0 si la partida no llega a durar la ventana completa
    /// (`Tuning.Pace.windowSeconds`) — se resetea al empezar una partida nueva.
    private(set) var bestPace: CGFloat = 0

    /// El mismo ritmo, convertido a metros por segundo para mostrarlo. La
    /// conversión vive en `Tuning` y no aquí porque es puramente de presentación.
    var bestPaceMetersPerSecond: CGFloat { bestPace / Tuning.Units.pointsPerMeter }

    private var seed: UInt64
    private var nextChunkIndex = 1
    private var wasHolding = false
    /// Los muros se cruzan en orden, así que basta con recordar el último puntuado.
    private var lastScoredWall = 0
    private var wasBlind = false

    /// Cubos de la media móvil del ritmo: ver `recordPace`. Tamaño fijo
    /// (`Tuning.Pace.bucketCount`), sin asignaciones por frame.
    private var paceBucketSums: [CGFloat]
    private var paceBucketDurations: [CGFloat]
    /// A qué "vuelta" del reloj pertenece cada cubo. -1 marca uno que nunca se
    /// escribió, para distinguirlo de la vuelta real 0.
    private var paceBucketEpochs: [Int]
    /// Tiempo total transcurrido en la partida, en segundos.
    private var paceElapsed: CGFloat = 0

    init(seed: UInt64) {
        self.seed = seed
        self.body = Self.startingBody()
        self.paceBucketSums = Array(repeating: 0, count: Tuning.Pace.bucketCount)
        self.paceBucketDurations = Array(repeating: 0, count: Tuning.Pace.bucketCount)
        self.paceBucketEpochs = Array(repeating: -1, count: Tuning.Pace.bucketCount)
        refillChunks()
    }

    var anchors: [Anchor] { chunks.flatMap(\.anchors) }

    /// Identidad de una flor: el muro al que pertenece y su hueco en la lista de
    /// anclas. Las `Anchor` son valores sin identidad propia, pero un chunk vivo
    /// nunca cambia de anclas y los índices de muro no se repiten en una partida,
    /// así que el par es estable mientras la flor exista.
    struct FlowerID: Hashable, Sendable {
        let wall: Int
        let slot: Int
    }

    /// Segundos de agarre ya gastados por flor marchita. Acumulativo a propósito:
    /// reiniciar al soltar permitiría descansar infinito a base de micro-toques,
    /// que es justo lo que la mecánica existe para impedir.
    private var witherSpent: [FlowerID: CGFloat] = [:]
    /// Flores que ya cayeron. No se pueden volver a agarrar.
    private var fallenFlowers: Set<FlowerID> = []

    private func flowerID(at position: CGPoint) -> FlowerID? {
        for chunk in chunks where chunk.index >= Tuning.Wither.firstWall {
            for (slot, anchor) in chunk.anchors.enumerated()
            where anchor.position == position {
                return FlowerID(wall: chunk.index, slot: slot)
            }
        }
        return nil
    }

    /// Anclas a las que aún se puede agarrar: todas menos las flores caídas.
    private var grabbableAnchors: [Anchor] {
        chunks.flatMap { chunk in
            chunk.anchors.enumerated()
                .filter { !fallenFlowers.contains(FlowerID(wall: chunk.index, slot: $0.offset)) }
                .map(\.element)
        }
    }

    /// 0 = flor intacta, 1 = presupuesto agotado (o flor ya caída). Para las
    /// flores anteriores a `Wither.firstWall` siempre es 0.
    func witherProgress(wall: Int, slot: Int) -> CGFloat {
        guard wall >= Tuning.Wither.firstWall else { return 0 }
        let id = FlowerID(wall: wall, slot: slot)
        if fallenFlowers.contains(id) { return 1 }
        return min(1, (witherSpent[id] ?? 0) / Tuning.Wither.grabBudget)
    }

    func flowerHasFallen(wall: Int, slot: Int) -> Bool {
        fallenFlowers.contains(FlowerID(wall: wall, slot: slot))
    }

    /// El muro que el jugador tiene delante. Es el que define todo lo que pasa a
    /// ciegas: la distancia que marca el ritmo y el hueco que marca la alineación.
    var nextChunk: Chunk? {
        chunks.first { $0.wall.x > body.position.x }
    }

    var isBlind: Bool { nextChunk?.isBlind ?? false }

    /// Distancia horizontal al muro siguiente, o `nil` si no hay ninguno delante.
    var distanceToNextWall: CGFloat? {
        nextChunk.map { $0.wall.x - body.position.x }
    }

    /// El último muro que se ha dejado atrás, si sigue vivo en la ventana. Sirve
    /// para saber si ya se está dentro de una zona a ciegas (en vez de solo
    /// acercándose a ella): mientras el muro de detrás sea a ciegas, el que viene
    /// justo después también lo es casi siempre, y el velo no debe abrirse un
    /// instante entre los dos.
    private var lastCrossedChunk: Chunk? {
        chunks.last { $0.wall.x <= body.position.x }
    }

    /// Cuánto debería estar cerrado el velo ahora mismo: 1 si ya se está dentro
    /// de una zona a ciegas, y si no, la rampa de anticipación hacia la próxima
    /// (0 lejos, 1 justo al llegar al muro de entrada). Sustituye al antiguo
    /// interruptor binario atado a `isBlind`, que saltaba a oscuro entero sin
    /// avisar antes.
    var blindZoneTelegraph: CGFloat {
        if lastCrossedChunk?.isBlind == true { return 1 }
        guard let entry = chunks.first(where: { $0.isBlind && $0.wall.x >= body.position.x })
        else { return 0 }
        let distance = entry.wall.x - body.position.x
        let spacing = DifficultyCurve.spacing(forWall: entry.index - 1)
        return BlindZones.telegraphProgress(distanceToEntry: distance, wallSpacing: spacing)
    }

    /// Cuánto le sobra al farolillo para pasar por el hueco siguiente. Negativo
    /// significa que, tal y como va, no cabe.
    var clearanceAtNextWall: CGFloat? {
        nextChunk.map { ProximityMapping.clearance(playerY: body.position.y, wall: $0.wall) }
    }

    /// Coloca el farolillo sin tocar nada más. Existe para los tests y para la
    /// depuración: permite examinar un tramo concreto del mundo sin tener que
    /// llegar hasta él jugando.
    mutating func placeBody(at position: CGPoint) {
        body.position = position
    }

    mutating func reset(seed: UInt64) {
        self.seed = seed
        body = Self.startingBody()
        chunks = []
        nextChunkIndex = 1
        wasHolding = false
        lastScoredWall = 0
        score = 0
        isDead = false
        wasBlind = false
        bestPace = 0
        witherSpent = [:]
        fallenFlowers = []
        paceBucketSums = Array(repeating: 0, count: Tuning.Pace.bucketCount)
        paceBucketDurations = Array(repeating: 0, count: Tuning.Pace.bucketCount)
        paceBucketEpochs = Array(repeating: -1, count: Tuning.Pace.bucketCount)
        paceElapsed = 0
        refillChunks()
    }

    mutating func advance(dt: CGFloat, holding: Bool) -> [GameEvent] {
        guard !isDead else { return [] }
        var events: [GameEvent] = []

        // El input es un flanco, no un estado: pulsar engancha una vez, no cada frame.
        if holding, !wasHolding {
            events.append(body.grab(anchors: grabbableAnchors) ? .grabbed : .missedGrab)
        } else if !holding, wasHolding, body.isAttached {
            body.release()
            events.append(.released)
        }
        wasHolding = holding

        body.advance(dt: dt, holding: holding)
        // El mismo techo que aplica `PendulumBody` a sus subpasos: tras un hipo
        // real, un dt enorme pesaría de más en la media en vez de descartarse.
        recordPace(dt: min(dt, Tuning.Pendulum.maxFrameDelta), speed: body.velocity.length)

        // Marchitado: colgarse de una flor marchita consume su presupuesto. Al
        // agotarse, la flor cae y suelta a Lumi con su velocidad exacta — sin
        // boost: el impulso extra es el premio de soltarse a tiempo.
        if let attachment = body.attachment, let id = flowerID(at: attachment.anchor) {
            let spent = (witherSpent[id] ?? 0) + min(dt, Tuning.Pendulum.maxFrameDelta)
            witherSpent[id] = spent
            if spent >= Tuning.Wither.grabBudget {
                fallenFlowers.insert(id)
                body.release(boosted: false)
                events.append(.flowerFell(attachment.anchor))
            }
        }

        if let obstacle = Collision.hit(position: body.position,
                                        radius: Tuning.Player.radius,
                                        chunks: chunks) {
            isDead = true
            events.append(.died(obstacle))
            return events
        }

        events.append(contentsOf: collectScore())
        refillChunks()

        // La frontera de la zona se anuncia después de puntuar y regenerar, para que
        // `nextChunk` ya sea el muro que el jugador tiene realmente delante.
        let blindNow = isBlind
        if blindNow != wasBlind {
            events.append(blindNow ? .enteredBlindZone : .exitedBlindZone)
            wasBlind = blindNow
        }

        return events
    }

    private mutating func collectScore() -> [GameEvent] {
        var events: [GameEvent] = []
        for chunk in chunks
        where chunk.index > lastScoredWall && body.position.x >= chunk.wall.x {
            lastScoredWall = chunk.index
            // La mecánica firma no se tolera: se recompensa.
            let points = chunk.isBlind ? Tuning.BlindZone.scoreMultiplier : 1
            score += points
            events.append(.scored(points))
        }
        return events
    }

    /// Reparte `dt` entre los cubos de la ventana de 10 s que atraviesa, acumula
    /// tiempo y velocidad en cada uno de forma incremental, y actualiza
    /// `bestPace` con la media resultante — solo una vez que la partida ya dura
    /// la ventana completa (spec: partidas más cortas no puntúan ritmo).
    ///
    /// `dt` real es siempre mucho menor que la duración de un cubo
    /// (`windowSeconds / bucketCount`), así que el bucle de abajo cruza como
    /// mucho un par de fronteras por llamada, nunca miles.
    private mutating func recordPace(dt: CGFloat, speed: CGFloat) {
        guard dt > 0 else { return }
        let bucketDuration = Tuning.Pace.windowSeconds / CGFloat(Tuning.Pace.bucketCount)

        var t = paceElapsed
        var remaining = dt
        while remaining > 0 {
            let epoch = Int(t / bucketDuration)
            let epochEnd = CGFloat(epoch + 1) * bucketDuration
            let slice = min(remaining, epochEnd - t)
            let index = epoch % Tuning.Pace.bucketCount

            if paceBucketEpochs[index] != epoch {
                paceBucketSums[index] = 0
                paceBucketDurations[index] = 0
                paceBucketEpochs[index] = epoch
            }
            paceBucketSums[index] += speed * slice
            paceBucketDurations[index] += slice

            t += slice
            remaining -= slice
        }
        paceElapsed += dt

        guard paceElapsed >= Tuning.Pace.windowSeconds else { return }
        let totalDuration = paceBucketDurations.reduce(0, +)
        guard totalDuration > 0 else { return }
        let average = paceBucketSums.reduce(0, +) / totalDuration
        bestPace = max(bestPace, average)
    }

    private static func startingBody() -> PendulumBody {
        PendulumBody(position: CGPoint(x: Tuning.Player.startX, y: Tuning.Player.startY),
                     velocity: CGVector(dx: Tuning.Player.initialVelocityX,
                                        dy: Tuning.Player.initialVelocityY))
    }

    /// Ventana viva: descarta lo que queda más de un chunk atrás y materializa por
    /// delante. El mundo completo nunca está en memoria.
    private mutating func refillChunks() {
        chunks.removeAll { chunk in
            chunk.wall.x < body.position.x - DifficultyCurve.spacing(forWall: chunk.index)
        }

        // Si el jugador se ha puesto por delante de todo el mundo materializado, el
        // índice salta hasta alcanzarlo: seguir generando muros que ya quedaron atrás
        // dejaría la ventana permanentemente a su espalda. El bucle termina siempre
        // porque `wallX` crece al menos `spacingFloor` por muro.
        if !chunks.contains(where: { $0.wall.x > body.position.x }) {
            chunks.removeAll()
            while DifficultyCurve.wallX(forWall: nextChunkIndex) <= body.position.x {
                nextChunkIndex += 1
            }
        }

        while chunks.count < Tuning.WorldGen.liveChunkCount {
            chunks.append(WorldGenerator.chunk(index: nextChunkIndex, seed: seed))
            nextChunkIndex += 1
        }
    }
}

/// Cámara adelantada en X (compra la anticipación que portrait no regala) y con
/// seguimiento vertical parcial, para que el horizonte siga siendo una referencia
/// estable mientras el farolillo oscila.
enum CameraController {
    static func target(for position: CGPoint) -> CGPoint {
        CGPoint(x: position.x + Tuning.World.sceneWidth * Tuning.Camera.lookAheadFactor,
                y: lerp(Tuning.World.sceneHeight / 2, position.y, Tuning.Camera.verticalFollow))
    }

    static func smoothed(current: CGPoint, target: CGPoint, dt: CGFloat) -> CGPoint {
        let t = 1 - exponentialDecay(rate: Tuning.Camera.smoothing, dt: dt)
        return CGPoint(x: lerp(current.x, target.x, t),
                       y: lerp(current.y, target.y, t))
    }
}
