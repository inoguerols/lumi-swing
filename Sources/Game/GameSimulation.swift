import CoreGraphics

/// Lo que la simulación le cuenta al mundo exterior. `GameScene` los reenvía al
/// motor háptico (S3) sin que la simulación sepa que existe Core Haptics.
enum GameEvent: Sendable, Equatable {
    case grabbed
    case released
    case missedGrab
}

/// Orquestador puro. No sabe que existen SpriteKit ni Core Haptics: avanza y
/// devuelve eventos. Dada una semilla y una secuencia de inputs, el resultado es
/// siempre el mismo — es lo que permite testear la mecánica sin simulador.
struct GameSimulation: Sendable {

    private(set) var body: PendulumBody
    private(set) var chunks: [Chunk] = []

    private var seed: UInt64
    private var nextChunkIndex = 1
    private var wasHolding = false

    init(seed: UInt64) {
        self.seed = seed
        self.body = Self.startingBody()
        refillChunks()
    }

    var anchors: [Anchor] { chunks.flatMap(\.anchors) }

    mutating func reset(seed: UInt64) {
        self.seed = seed
        body = Self.startingBody()
        chunks = []
        nextChunkIndex = 1
        wasHolding = false
        refillChunks()
    }

    mutating func advance(dt: CGFloat, holding: Bool) -> [GameEvent] {
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
        refillChunks()
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
