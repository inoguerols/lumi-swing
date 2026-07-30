import SpriteKit

/// SpriteKit hace de renderer, input y bucle de juego. La física no es suya:
/// `GameSimulation` es la dueña del estado y esta clase solo lo dibuja
/// (ver D-002 en docs/decisiones.md).
final class GameScene: SKScene {

    private var simulation = GameSimulation(seed: Tuning.WorldGen.initialSeed)
    private var holding = false
    private var lastUpdateTime: TimeInterval?

    /// La escena habla con el protocolo, nunca con Core Haptics.
    private let haptics: any HapticsEngine

    private let worldNode = SKNode()
    private let cameraNode = SKCameraNode()
    private let playerNode = SKShapeNode(circleOfRadius: Tuning.Player.radius)
    private let ropeNode = SKShapeNode()
    private var chunkNodes: [Int: SKNode] = [:]
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let deathLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let blindNoticeLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var darknessNode = SKShapeNode()

    /// 0 = se ve todo, 1 = a ciegas. Se interpola en vez de conmutar: el corte seco
    /// a negro asusta, y la penumbra progresiva avisa de lo que llega.
    private var darkness: CGFloat = 0

    /// Sin Taptic Engine la ceguera total no es un reto, es un muro: se deja un
    /// contorno tenue (docs/lenguaje-haptico.md §6.1).
    private var assistedMode = false

    /// Throttle de las llamadas al motor háptico.
    private var proximityBucket: Int?
    private var alignmentBucket: Int?

    private var trailNodes: [SKShapeNode] = []
    private var trailPositions: [CGPoint] = []
    private var trailTimer: CGFloat = 0
    private var shakeRemaining: CGFloat = 0
    private var shakeRng = SplitMix64(seed: 0x5EED)
    /// Posición de cámara sin el temblor sumado.
    private var cameraBase = CGPoint.zero

    init(size: CGSize, haptics: any HapticsEngine) {
        self.haptics = haptics
        super.init(size: size)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0, y: 0)
        backgroundColor = Palette.night
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Péndulo construye su escena en código, no desde un .sks")
    }

    override func didMove(to view: SKView) {
        guard worldNode.parent == nil else { return }

        addChild(worldNode)
        addChild(cameraNode)
        camera = cameraNode

        buildBounds()

        ropeNode.strokeColor = Palette.rope
        ropeNode.lineWidth = 4
        worldNode.addChild(ropeNode)

        playerNode.fillColor = Palette.lantern
        playerNode.strokeColor = Palette.lanternGlow
        playerNode.lineWidth = 10
        playerNode.glowWidth = 12
        // El farolillo también es una luz: se ve a ciegas. Si desapareciera, el
        // jugador perdería la única referencia de dónde está.
        playerNode.zPosition = Self.lightZPosition
        ropeNode.zPosition = Self.lightZPosition - 1
        worldNode.addChild(playerNode)

        buildTrail()

        buildHUD()

        syncWorld()
        // El primer frame coloca la cámara sin interpolar: si no, entra volando.
        cameraBase = CameraController.target(for: simulation.body.position)
        cameraNode.position = cameraBase

        let haptics = self.haptics
        Task {
            await haptics.prepare()
            // Sin Taptic Engine se activa el refuerzo visual: la ceguera total solo
            // es un reto si hay un canal que la sustituya.
            assistedMode = await haptics.capabilities.needsFullSubstitution
        }
    }

    /// El HUD cuelga de la cámara, así que viaja con ella sin recolocarse por frame.
    private func buildHUD() {
        scoreLabel.fontSize = Tuning.HUD.scoreFontSize
        scoreLabel.fontColor = Palette.lantern
        scoreLabel.position = CGPoint(x: 0, y: Tuning.HUD.scoreOffsetY)
        scoreLabel.text = "0"
        cameraNode.addChild(scoreLabel)

        deathLabel.fontSize = Tuning.HUD.deathFontSize
        deathLabel.fontColor = Palette.rope
        deathLabel.position = CGPoint(x: 0, y: Tuning.HUD.deathOffsetY)
        deathLabel.text = "toca para volver"
        deathLabel.isHidden = true
        cameraNode.addChild(deathLabel)

        // El velo se dibuja generoso porque `.aspectFill` recorta distinto en cada
        // iPhone, y un borde de mundo asomando por una esquina delataría el truco.
        let veil = CGRect(x: -Tuning.World.sceneWidth * 0.7,
                          y: -Tuning.World.sceneHeight * 0.7,
                          width: Tuning.World.sceneWidth * 1.4,
                          height: Tuning.World.sceneHeight * 1.4)
        darknessNode = SKShapeNode(rect: veil)
        darknessNode.fillColor = .black
        darknessNode.strokeColor = .clear
        darknessNode.alpha = 0
        darknessNode.zPosition = 10
        cameraNode.addChild(darknessNode)

        blindNoticeLabel.fontSize = Tuning.HUD.deathFontSize
        blindNoticeLabel.fontColor = Palette.rope
        blindNoticeLabel.position = CGPoint(x: 0, y: Tuning.HUD.blindNoticeOffsetY)
        blindNoticeLabel.text = "a ciegas · fíate del tacto"
        blindNoticeLabel.alpha = 0
        blindNoticeLabel.zPosition = 11
        cameraNode.addChild(blindNoticeLabel)
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdateTime = currentTime }
        guard let lastUpdateTime else { return }

        let dt = CGFloat(currentTime - lastUpdateTime)
        guard dt > 0 else { return }

        for event in simulation.advance(dt: dt, holding: holding) {
            switch event {
            case .scored:
                scoreLabel.text = "\(simulation.score)"
                emit(.score)
            case .died:
                deathLabel.isHidden = false
                shakeRemaining = Tuning.Camera.deathShakeDuration
                emit(.death)
            case .grabbed:
                squashOnGrab()
                emit(.grab)
            case .released:
                emit(.release)
            case .missedGrab:
                // Pulsar sobre el vacío no dice nada: el silencio ya informa de que
                // no hay nada ahí. Una señal de error castigaría al jugador por
                // explorar, que es justo como se aprende un juego de un solo input.
                break
            case .enteredBlindZone:
                emit(.blindEnter)
                showBlindNoticeIfFirstTime()
            case .exitedBlindZone:
                emit(.blindExit)
            }
        }

        updateDarkness(dt: dt)
        updateSky()
        updateTrail(dt: dt)
        feedHapticMap()
        syncWorld()

        // La sacudida se suma encima de la posición base y NO se realimenta: si el
        // suavizado leyera la posición ya temblada, el temblor se perseguiría a sí
        // mismo y la cámara acabaría a la deriva.
        cameraBase = CameraController.smoothed(
            current: cameraBase,
            target: CameraController.target(for: simulation.body.position),
            dt: dt)

        shakeRemaining = max(0, shakeRemaining - dt)
        let shake = Effects.shakeOffset(remaining: shakeRemaining, rng: &shakeRng)
        cameraNode.position = CGPoint(x: cameraBase.x + shake.x, y: cameraBase.y + shake.y)
    }

    // MARK: - Input (uno solo: pulsado o no)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if simulation.isDead {
            restart()
            return
        }
        holding = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { holding = false }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { holding = false }

    /// Reinicio sin reconstruir la escena: resetear structs y reposicionar nodos
    /// cuesta un frame. Instanciar una `SKScene` nueva se comería el presupuesto
    /// de 300 ms del brief entero.
    private func restart() {
        simulation.reset(seed: Tuning.WorldGen.initialSeed)
        for node in chunkNodes.values { node.removeFromParent() }
        chunkNodes.removeAll()

        holding = false
        lastUpdateTime = nil
        deathLabel.isHidden = true
        scoreLabel.text = "0"

        darkness = 0
        darknessNode.alpha = 0
        proximityBucket = nil
        alignmentBucket = nil
        shakeRemaining = 0
        trailPositions.removeAll()
        trailTimer = 0
        playerNode.removeAllActions()
        playerNode.xScale = 1
        playerNode.yScale = 1
        let haptics = self.haptics
        Task { await haptics.stopContinuous() }

        syncWorld()
        cameraBase = CameraController.target(for: simulation.body.position)
        cameraNode.position = cameraBase
    }

    // MARK: - Game feel

    /// Estela: nodos reutilizados que se recolocan sobre posiciones pasadas. Un
    /// `SKEmitterNode` daría más humo, pero también un rastro que no sigue
    /// exactamente el arco — y aquí el arco es la información.
    private func buildTrail() {
        for index in 0..<Tuning.Feel.trailNodeCount {
            let node = SKShapeNode(circleOfRadius: Effects.trailRadius(index: index))
            node.fillColor = Palette.lantern
            node.strokeColor = .clear
            // Aditivo: un ámbar translúcido sobre un fondo oscuro *oscurece*, y la
            // estela salía marrón sucia. Sumando luz, la estela brilla, que es lo
            // que hace un farolillo al moverse.
            node.blendMode = .add
            node.alpha = 0
            node.zPosition = Self.lightZPosition - 2
            worldNode.addChild(node)
            trailNodes.append(node)
        }
    }

    private func updateTrail(dt: CGFloat) {
        trailTimer -= dt
        if trailTimer <= 0 {
            trailTimer = Effects.trailSampleInterval
            trailPositions.insert(simulation.body.position, at: 0)
            if trailPositions.count > trailNodes.count { trailPositions.removeLast() }
        }

        for (index, node) in trailNodes.enumerated() {
            guard index < trailPositions.count else {
                node.alpha = 0
                continue
            }
            node.position = trailPositions[index]
            node.alpha = Effects.trailAlpha(index: index)
        }
    }

    /// Squash & stretch al agarrarse: el farolillo se estira en vertical y vuelve.
    /// Sin esto el agarre es un cambio de estado invisible; con esto es un tirón.
    private func squashOnGrab() {
        playerNode.removeAllActions()
        playerNode.xScale = 1
        playerNode.yScale = 1
        let total = TimeInterval(Tuning.Feel.squashDuration)
        playerNode.run(.sequence([
            .scaleX(to: 1 / Tuning.Feel.squashScale,
                    y: Tuning.Feel.squashScale,
                    duration: total * 0.35),
            .scale(to: 1, duration: total * 0.65)
        ]))
    }

    private func updateSky() {
        guard let wall = simulation.nextChunk?.index else { return }
        backgroundColor = Palette.sky(at: Effects.skyPhase(forWall: wall))
    }

    // MARK: - Zonas a ciegas

    private func updateDarkness(dt: CGFloat) {
        let target: CGFloat = simulation.isBlind ? 1 : 0
        let rate = 1 / Tuning.BlindZone.darkenDuration
        darkness = lerp(darkness, target, 1 - exponentialDecay(rate: rate, dt: dt))
        darknessNode.alpha = darkness * Tuning.BlindZone.darkAlpha
    }

    /// Solo la primera vez en la vida de la instalación: a partir de ahí, el cartel
    /// sería ruido. Quien ya sabe que los muros desaparecen no necesita que se lo
    /// recuerden cada doce muros.
    private func showBlindNoticeIfFirstTime() {
        let key = "pendulo.blindNoticeSeen"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        blindNoticeLabel.removeAllActions()
        blindNoticeLabel.run(.sequence([
            .fadeIn(withDuration: 0.35),
            .wait(forDuration: TimeInterval(Tuning.HUD.blindNoticeDuration)),
            .fadeOut(withDuration: 0.6)
        ]))
    }

    /// Traduce la geometría a idioma háptico. Solo habla cuando cambia algo que se
    /// puede sentir: sin el escalonado serían 120 mensajes por segundo al actor
    /// diciendo casi lo mismo.
    private func feedHapticMap() {
        guard simulation.isBlind,
              let distance = simulation.distanceToNextWall else {
            guard proximityBucket != nil || alignmentBucket != nil else { return }
            proximityBucket = nil
            alignmentBucket = nil
            let haptics = self.haptics
            Task { await haptics.stopContinuous() }
            return
        }

        let bucket = Int(distance / Tuning.Haptics.proximityUpdateQuantum)
        if bucket != proximityBucket {
            proximityBucket = bucket
            let haptics = self.haptics
            Task { await haptics.updateProximity(distance: distance) }
        }

        // El margen puede ser negativo (no cabe); el motor entiende `nil` como
        // "desalineado" y esa es toda la señal que hace falta.
        let clearance = simulation.clearanceAtNextWall ?? -1
        let alignBucket = clearance > 0
            ? Int(clearance / Tuning.Haptics.alignmentUpdateQuantum)
            : -1
        if alignBucket != alignmentBucket {
            alignmentBucket = alignBucket
            let haptics = self.haptics
            let value: CGFloat? = clearance > 0 ? clearance : nil
            Task { await haptics.updateAlignment(clearance: value) }
        }
    }

    /// Fire-and-forget: el motor háptico es un actor y no puede bloquear el frame.
    /// Si un pulso llega dos milisegundos tarde no pasa nada; si el frame se pierde,
    /// sí.
    private func emit(_ signal: HapticSignal) {
        let haptics = self.haptics
        Task { await haptics.play(signal) }
    }

    // MARK: - Presentación

    private func syncWorld() {
        let live = Set(simulation.chunks.map(\.index))
        for (index, node) in chunkNodes where !live.contains(index) {
            node.removeFromParent()
            chunkNodes.removeValue(forKey: index)
        }
        // ponytail: crear y soltar cuatro nodos cada ~1 s no justifica un pool.
        for chunk in simulation.chunks where chunkNodes[chunk.index] == nil {
            let node = makeChunkNode(chunk)
            chunkNodes[chunk.index] = node
            worldNode.addChild(node)
        }

        for chunk in simulation.chunks where chunk.isBlind {
            chunkNodes[chunk.index]?
                .childNode(withName: Self.wallsNodeName)?
                .alpha = wallAlpha(for: chunk)
        }

        playerNode.position = simulation.body.position

        if let attachment = simulation.body.attachment {
            let path = CGMutablePath()
            path.move(to: attachment.anchor)
            path.addLine(to: simulation.body.position)
            ropeNode.path = path
            ropeNode.isHidden = false
        } else {
            ropeNode.isHidden = true
        }
    }

    private func makeChunkNode(_ chunk: Chunk) -> SKNode {
        let container = SKNode()
        let wall = chunk.wall
        let thickness = Tuning.World.wallThickness

        // Los muros van en su propio subnodo para poder desvanecerlos sin arrastrar
        // a los faroles.
        let walls = SKNode()
        walls.name = Self.wallsNodeName

        // Dos tramos: del suelo al borde inferior del hueco, y del superior al techo.
        let segments = [
            (Tuning.World.floorY, wall.gapBottomY),
            (wall.gapTopY, Tuning.World.ceilingY)
        ]
        for (bottom, top) in segments where top > bottom {
            let node = SKShapeNode(rect: CGRect(x: wall.x - thickness / 2,
                                                y: bottom,
                                                width: thickness,
                                                height: top - bottom))
            node.fillColor = Palette.wall
            node.strokeColor = Palette.wallEdge
            node.lineWidth = 2
            walls.addChild(node)
        }
        walls.alpha = wallAlpha(for: chunk)
        container.addChild(walls)

        // Los faroles quedan POR ENCIMA del velo: un farol es una luz, y en la
        // oscuridad las luces son justo lo que sí se ve. Además es lo que hace la
        // zona a ciegas jugable en vez de imposible — sin asideros visibles no
        // habría forma de columpiarse.
        let lanterns = SKNode()
        lanterns.zPosition = Self.lightZPosition
        for anchor in chunk.anchors {
            let node = SKShapeNode(circleOfRadius: Tuning.World.anchorRadius)
            node.position = anchor.position
            node.fillColor = Palette.anchorIdle
            node.strokeColor = Palette.lantern
            node.lineWidth = 2
            node.glowWidth = 4
            lanterns.addChild(node)
        }
        container.addChild(lanterns)

        return container
    }

    private static let wallsNodeName = "walls"
    private static let lightZPosition: CGFloat = 20

    private func wallAlpha(for chunk: Chunk) -> CGFloat {
        guard chunk.isBlind else { return 1 }
        let hidden = assistedMode ? Tuning.BlindZone.assistedOutlineAlpha : 0
        return lerp(1, hidden, darkness)
    }

    private func buildBounds() {
        let bars = [
            CGRect(x: 0,
                   y: Tuning.World.floorY - Tuning.World.boundsThickness,
                   width: Tuning.World.worldLength,
                   height: Tuning.World.boundsThickness),
            CGRect(x: 0,
                   y: Tuning.World.ceilingY,
                   width: Tuning.World.worldLength,
                   height: Tuning.World.boundsThickness)
        ]
        for rect in bars {
            let node = SKShapeNode(rect: rect)
            node.fillColor = Palette.bounds
            node.strokeColor = Palette.wallEdge
            node.lineWidth = 2
            worldNode.addChild(node)
        }
    }
}
