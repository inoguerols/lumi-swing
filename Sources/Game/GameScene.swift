import SpriteKit

/// SpriteKit hace de renderer, input y bucle de juego. La física no es suya:
/// `GameSimulation` es la dueña del estado y esta clase solo lo dibuja
/// (ver D-002 en docs/decisiones.md).
final class GameScene: SKScene {

    private var simulation = GameSimulation(seed: Tuning.WorldGen.initialSeed)
    private var holding = false
    private var lastUpdateTime: TimeInterval?

    private let worldNode = SKNode()
    private let cameraNode = SKCameraNode()
    private let playerNode = SKShapeNode(circleOfRadius: Tuning.Player.radius)
    private let ropeNode = SKShapeNode()
    private var chunkNodes: [Int: SKNode] = [:]
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let deathLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")

    override init(size: CGSize) {
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
        worldNode.addChild(playerNode)

        buildHUD()

        syncWorld()
        // El primer frame coloca la cámara sin interpolar: si no, entra volando.
        cameraNode.position = CameraController.target(for: simulation.body.position)
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
            case .died:
                deathLabel.isHidden = false
            case .grabbed, .released, .missedGrab:
                break   // su sitio son los hápticos (S3), no la pantalla
            }
        }

        syncWorld()
        cameraNode.position = CameraController.smoothed(
            current: cameraNode.position,
            target: CameraController.target(for: simulation.body.position),
            dt: dt)
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

        syncWorld()
        cameraNode.position = CameraController.target(for: simulation.body.position)
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
            container.addChild(node)
        }

        for anchor in chunk.anchors {
            let node = SKShapeNode(circleOfRadius: Tuning.World.anchorRadius)
            node.position = anchor.position
            node.fillColor = Palette.anchorIdle
            node.strokeColor = Palette.lantern
            node.lineWidth = 2
            node.glowWidth = 4
            container.addChild(node)
        }

        return container
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
