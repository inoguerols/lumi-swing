import CoreGraphics

/// Lo que la simulación le cuenta al mundo exterior. `GameScene` los reenvía al
/// motor háptico (S3) sin que la simulación sepa que existe Core Haptics.
enum GameEvent: Sendable, Equatable {
    case grabbed
    case released
    case missedGrab
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

    private var seed: UInt64
    private var nextChunkIndex = 1
    private var wasHolding = false
    /// Los muros se cruzan en orden, así que basta con recordar el último puntuado.
    private var lastScoredWall = 0
    private var wasBlind = false

    init(seed: UInt64) {
        self.seed = seed
        self.body = Self.startingBody()
        refillChunks()
    }

    var anchors: [Anchor] { chunks.flatMap(\.anchors) }

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
        refillChunks()
    }

    mutating func advance(dt: CGFloat, holding: Bool) -> [GameEvent] {
        guard !isDead else { return [] }
        var events: [GameEvent] = []

        // El input es un flanco, no un estado: pulsar engancha una vez, no cada frame.
        if holding, !wasHolding {
            events.append(body.grab(anchors: anchors) ? .grabbed : .missedGrab)
        } else if !holding, wasHolding, body.isAttached {
            body.release()
            events.append(.released)
        }
        wasHolding = holding

        body.advance(dt: dt, holding: holding)

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
