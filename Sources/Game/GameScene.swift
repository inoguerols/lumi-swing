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
    private let model: AppModel
    private let settings: GameSettings

    private let worldNode = SKNode()
    private let cameraNode = SKCameraNode()
    /// La luciérnaga entera. El abdomen es el que mide el radio de colisión; alas,
    /// ojos y antenas van dentro o se leen vaporosos, y nunca engañan sobre qué mata.
    private let playerNode = SKNode()
    private let abdomenNode = SKShapeNode(circleOfRadius: Tuning.Player.radius)
    private var wingNodes: [SKShapeNode] = []
    private let ropeNode = SKShapeNode()

    /// Decorado: cielo y dos capas de vegetación que se quedan atrás.
    private let skyNode = SKSpriteNode()
    private let canopyFarNode = SKNode()
    private let canopyNearNode = SKNode()
    private let pollenNode = SKNode()

    /// Latido del abdomen, sincronizado con el háptico de proximidad.
    private var blinkTimer: CGFloat = 0
    private var chunkNodes: [Int: SKNode] = [:]
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let blindNoticeLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let darknessNode = SKSpriteNode()

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

    init(size: CGSize, haptics: any HapticsEngine, model: AppModel, settings: GameSettings) {
        self.haptics = haptics
        self.model = model
        self.settings = settings
        super.init(size: size)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0, y: 0)
        backgroundColor = Palette.night
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Lumi Swing construye su escena en código, no desde un .sks")
    }

    override func didMove(to view: SKView) {
        guard worldNode.parent == nil else { return }

        addChild(cameraNode)
        camera = cameraNode
        buildBackdrop()

        addChild(worldNode)
        buildBounds()

        ropeNode.strokeColor = Palette.vine
        ropeNode.lineWidth = 5
        worldNode.addChild(ropeNode)

        buildFirefly()
        // La luciérnaga también es una luz: se ve a ciegas. Si desapareciera, el
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

    // MARK: - Decorado

    /// Cielo, vegetación y polen. Todo cuelga de la **cámara**, no del mundo: así se
    /// mueve solo por parallax y nunca hay que reciclarlo ni generarlo dos veces.
    private func buildBackdrop() {
        let width = Tuning.World.sceneWidth * 2
        let height = Tuning.World.sceneHeight * 1.4

        skyNode.texture = TextureFactory.verticalGradient(
            size: CGSize(width: 8, height: 256), topAlpha: 1, bottomAlpha: 0.25)
        skyNode.size = CGSize(width: width, height: height)
        skyNode.color = Palette.night
        skyNode.colorBlendFactor = 1
        skyNode.zPosition = -100
        cameraNode.addChild(skyNode)

        // Dos capas: la lejana casi se confunde con el cielo, la cercana recorta
        // contra él. Esa diferencia es toda la profundidad.
        addCanopy(to: canopyFarNode,
                  height: Tuning.Scenery.canopyFarHeight,
                  color: Palette.canopyFar,
                  seed: 0xCA_0F,
                  zPosition: -90,
                  // Arrancan en el suelo del área de juego, no en el borde del velo:
                  // si no, la vegetación queda por debajo de la pantalla y el fondo
                  // vuelve a ser un color liso.
                  bottom: -Tuning.World.playfieldHeight / 2)
        addCanopy(to: canopyNearNode,
                  height: Tuning.Scenery.canopyNearHeight,
                  color: Palette.canopyNear,
                  seed: 0xCA_1F,
                  zPosition: -80,
                  // Arrancan en el suelo del área de juego, no en el borde del velo:
                  // si no, la vegetación queda por debajo de la pantalla y el fondo
                  // vuelve a ser un color liso.
                  bottom: -Tuning.World.playfieldHeight / 2)
        cameraNode.addChild(canopyFarNode)
        cameraNode.addChild(canopyNearNode)

        buildMoon(height: height)
        buildPollen(width: width, height: height)
        cameraNode.addChild(pollenNode)
    }

    /// La luna, arriba y fija respecto a la cámara: está tan lejos que no tiene
    /// parallax. Es la fuente de la luz de toda la escena — sin ella el cielo era un
    /// verde plano sin causa.
    private func buildMoon(height: CGFloat) {
        let halo = SKShapeNode(circleOfRadius: Tuning.Scenery.moonRadius * 3.2)
        halo.fillColor = Palette.moonHalo
        halo.strokeColor = .clear
        halo.blendMode = .add
        halo.alpha = 0.5

        let disc = SKShapeNode(circleOfRadius: Tuning.Scenery.moonRadius)
        disc.fillColor = Palette.moon
        disc.strokeColor = .clear
        disc.glowWidth = Tuning.Scenery.moonRadius * 0.6

        let moon = SKNode()
        moon.addChild(halo)
        moon.addChild(disc)
        moon.position = CGPoint(x: Tuning.World.sceneWidth * 0.30,
                                y: height * 0.5 - Tuning.Scenery.moonRadius * 3)
        moon.zPosition = -95
        cameraNode.addChild(moon)
    }

    /// Dos copias de la silueta, una al lado de otra: al desplazarse por parallax
    /// siempre hay tela cubriendo el hueco que deja la otra.
    private func addCanopy(to parent: SKNode,
                           height: CGFloat,
                           color: SKColor,
                           seed: UInt64,
                           zPosition: CGFloat,
                           bottom: CGFloat) {
        let width = Tuning.World.sceneWidth * 1.5
        let texture = TextureFactory.canopy(width: width,
                                            height: height,
                                            seed: seed,
                                            bumps: Tuning.Scenery.canopyBumps)
        for index in -1...1 {
            let node = SKSpriteNode(texture: texture,
                                    size: CGSize(width: width, height: height))
            node.color = color
            node.colorBlendFactor = 1
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.position = CGPoint(x: CGFloat(index) * width, y: bottom)
            node.zPosition = zPosition
            parent.addChild(node)
        }
    }

    private func buildPollen(width: CGFloat, height: CGFloat) {
        var rng = SplitMix64(seed: 0xF0_11_E7)
        for _ in 0..<Tuning.Scenery.pollenCount {
            let mote = SKShapeNode(circleOfRadius: Tuning.Scenery.pollenRadius)
            mote.fillColor = Palette.pollen
            mote.strokeColor = .clear
            mote.blendMode = .add
            mote.alpha = rng.nextCGFloat(in: 0.06...0.22)
            mote.zPosition = -70
            mote.position = CGPoint(x: rng.nextCGFloat(in: (-width / 2)...(width / 2)),
                                    y: rng.nextCGFloat(in: (-height / 2)...(height / 2)))

            // Deriva lenta: el aire de la selva se mueve, pero nada aquí pide
            // atención. Si el polen distrajera, competiría con las luces que sí
            // informan.
            let drift = TimeInterval(Tuning.Scenery.pollenDriftDuration
                                     * rng.nextCGFloat(in: 0.7...1.5))
            mote.run(.repeatForever(.sequence([
                .moveBy(x: rng.nextCGFloat(in: -30...30),
                        y: rng.nextCGFloat(in: 20...60),
                        duration: drift),
                .moveBy(x: rng.nextCGFloat(in: -30...30),
                        y: rng.nextCGFloat(in: -60...(-20)),
                        duration: drift)
            ])))
            pollenNode.addChild(mote)
        }
    }

    /// Las capas se quedan atrás respecto a la cámara. Como cuelgan de ella, basta
    /// con moverlas en sentido contrario una fracción de lo que se ha movido.
    private func updateParallax() {
        let camera = cameraBase
        canopyFarNode.position = CGPoint(
            x: -camera.x * Tuning.Scenery.parallaxFar,
            y: -camera.y * Tuning.Scenery.parallaxFar * 0.3)
        canopyNearNode.position = CGPoint(
            x: -camera.x * Tuning.Scenery.parallaxNear,
            y: -camera.y * Tuning.Scenery.parallaxNear * 0.3)
    }

    // MARK: - La luciérnaga

    private func buildFirefly() {
        // Alas primero: van detrás del cuerpo y se leen translúcidas, para que nadie
        // las confunda con masa sólida.
        for side in [-1, 1] as [CGFloat] {
            let wing = SKShapeNode(ellipseOf: CGSize(width: Tuning.Scenery.wingLength,
                                                     height: Tuning.Scenery.wingWidth))
            wing.fillColor = Palette.fireflyWing
            wing.strokeColor = .clear
            wing.blendMode = .add
            wing.position = CGPoint(x: side * Tuning.Player.radius * 0.5,
                                    y: Tuning.Player.radius * 0.55)
            wing.zRotation = side * 0.45
            playerNode.addChild(wing)
            wingNodes.append(wing)
        }

        abdomenNode.fillColor = Palette.firefly
        abdomenNode.strokeColor = Palette.fireflyGlow
        abdomenNode.lineWidth = 10
        abdomenNode.glowWidth = 16
        playerNode.addChild(abdomenNode)

        for side in [-1, 1] as [CGFloat] {
            let eye = SKShapeNode(circleOfRadius: Tuning.Scenery.eyeRadius)
            eye.fillColor = Palette.fireflyDetail
            eye.strokeColor = .clear
            eye.position = CGPoint(x: side * Tuning.Player.radius * 0.34,
                                   y: Tuning.Player.radius * 0.30)
            playerNode.addChild(eye)

            let antenna = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: side * Tuning.Player.radius * 0.3,
                                  y: Tuning.Player.radius * 0.7))
            path.addQuadCurve(
                to: CGPoint(x: side * Tuning.Scenery.antennaLength,
                            y: Tuning.Player.radius + Tuning.Scenery.antennaLength * 0.8),
                control: CGPoint(x: side * Tuning.Scenery.antennaLength * 0.4,
                                 y: Tuning.Player.radius + Tuning.Scenery.antennaLength * 0.6))
            antenna.path = path
            antenna.strokeColor = Palette.fireflyDetail
            antenna.lineWidth = 2.5
            antenna.lineCap = .round
            playerNode.addChild(antenna)
        }

        startWingFlap()
    }

    private func startWingFlap() {
        let duration = TimeInterval(Tuning.Scenery.wingFlapDuration)
        for wing in wingNodes {
            wing.removeAllActions()
            wing.run(.repeatForever(.sequence([
                .scaleY(to: 0.45, duration: duration),
                .scaleY(to: 1.0, duration: duration)
            ])))
        }
    }

    /// El abdomen late al ritmo del háptico de proximidad: las luciérnagas parpadean
    /// de por sí, y aquí ese parpadeo **es el mapa**. Quien juega con el móvil sobre
    /// la mesa aprende el idioma igual que quien lo lleva en la mano.
    private func updateBlink(dt: CGFloat) {
        let interval = simulation.isBlind
            ? (simulation.distanceToNextWall
                .flatMap(ProximityMapping.cue(forDistance:))?.interval
                ?? Tuning.Scenery.idleBlinkInterval)
            : Tuning.Scenery.idleBlinkInterval

        blinkTimer -= dt
        if blinkTimer <= 0 {
            blinkTimer = interval
            abdomenNode.removeAllActions()
            abdomenNode.alpha = Tuning.Scenery.blinkBrightAlpha
            abdomenNode.run(.fadeAlpha(to: Tuning.Scenery.blinkDimAlpha,
                                       duration: TimeInterval(interval) * 0.6))
        }
    }

    /// El HUD cuelga de la cámara, así que viaja con ella sin recolocarse por frame.
    private func buildHUD() {
        scoreLabel.fontSize = Tuning.HUD.scoreFontSize
        scoreLabel.fontColor = Palette.lantern
        scoreLabel.position = CGPoint(x: 0, y: Tuning.HUD.scoreOffsetY)
        scoreLabel.text = "0"
        // Oculto fuera de la partida: en el menú era un "0" gigante flotando sobre
        // la tarjeta sin significar nada, y en el game over duplicaba al de la ficha.
        scoreLabel.alpha = 0
        cameraNode.addChild(scoreLabel)

        // El velo se dibuja generoso porque `.aspectFill` recorta distinto en cada
        // iPhone, y un borde de mundo asomando por una esquina delataría el truco.
        //
        // Y no es negro plano: lleva un agujero suave que sigue a la luciérnaga. La
        // diferencia entre «el juego te ha apagado la pantalla» y «tu luz solo llega
        // hasta aquí» es exactamente esta textura.
        let veilSide = max(Tuning.World.sceneWidth, Tuning.World.sceneHeight) * 2
        darknessNode.texture = TextureFactory.lightHole(
            size: 512,
            holeRadius: 512 * Tuning.Scenery.lightHoleRadius / veilSide)
        darknessNode.size = CGSize(width: veilSide, height: veilSide)
        darknessNode.alpha = 0
        darknessNode.zPosition = 10
        worldNode.addChild(darknessNode)

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
        // Sin esta guarda, la escena corre durante los frames que hay entre que
        // aparece y que el shell la pausa: el farolillo cae, muere, y el jugador se
        // encuentra la pantalla de game over antes de haber tocado nada.
        //
        // El temblor de muerte queda FUERA de ella y se resuelve antes: la muerte
        // cambia la fase a `.dead` en el mismo frame que arranca el temblor, así que
        // si se saliera aquí el temblor se calcularía una sola vez y la cámara se
        // quedaría congelada descentrada — el efecto no se veía nunca y parecía un
        // salto de cámara roto.
        if let previous = lastUpdateTime, model.phase != .playing {
            settleShake(dt: CGFloat(currentTime - previous))
        }
        guard model.phase == .playing else { return }
        guard let lastUpdateTime else { return }

        let dt = CGFloat(currentTime - lastUpdateTime)
        guard dt > 0 else { return }

        for event in simulation.advance(dt: dt, holding: Self.isDemo ? demoInput() : holding) {
            switch event {
            case .scored(let points):
                scoreLabel.text = "\(simulation.score)"
                model.score = simulation.score
                popScore(doubled: points > 1)
                emit(.score)
            case .died:
                shakeRemaining = Tuning.Camera.deathShakeDuration
                emit(.death)
                model.score = simulation.score
                model.isNewRecord = settings.record(score: simulation.score)
                model.best = settings.best
                GameCenter.submit(score: simulation.score)
                model.phase = .dead
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
        updateBlink(dt: dt)
        feedHapticMap()
        syncWorld()
        updateParallax()

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
        // Fuera de la partida manda el shell de SwiftUI: si la escena atendiera
        // toques con el menú abierto, el botón "Jugar" arrancaría un run y el toque
        // que lo pulsó ya contaría como un agarre.
        guard model.phase == .playing else { return }
        holding = true
    }

    /// Arranca una partida nueva. Lo llama el shell, no la propia escena.
    func startRun() {
        restart()
        lastUpdateTime = nil
        scoreLabel.alpha = 0
        scoreLabel.run(.fadeIn(withDuration: 0.2))
    }

    /// Deja el mundo quieto y visible detrás del menú.
    func showMenuBackdrop() {
        restart()
        lastUpdateTime = nil
        scoreLabel.alpha = 0
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

    /// El marcador acusa cada punto. Ocurre cada par de segundos, así que el pop es
    /// corto; y a ciegas es mayor y vira al cian de las flores, porque ese muro vale
    /// el doble y el GDD pide que el marcador lo **recompense**, no que lo tolere.
    private func popScore(doubled: Bool) {
        let scale = doubled ? Tuning.HUD.scorePopDoubled : Tuning.HUD.scorePop
        scoreLabel.removeAllActions()
        scoreLabel.setScale(1)
        scoreLabel.run(.sequence([
            .scale(to: scale, duration: 0.06),
            .scale(to: 1.0, duration: 0.14)
        ]))

        guard doubled else { return }
        scoreLabel.fontColor = Palette.moonflower
        scoreLabel.run(.sequence([
            .wait(forDuration: 0.25),
            .run { [weak self] in self?.scoreLabel.fontColor = Palette.lantern }
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

        let peak = settings.reduceFlashing
            ? Tuning.BlindZone.reducedDarkAlpha
            : Tuning.BlindZone.darkAlpha
        darknessNode.alpha = darkness * peak
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
        let channelsOff = !settings.hapticsEnabled && !settings.audioEnabled
        guard !channelsOff,
              simulation.isBlind,
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

    /// Deja que el temblor termine aunque la partida ya haya acabado, y devuelve la
    /// cámara a su sitio al agotarse.
    private func settleShake(dt: CGFloat) {
        guard shakeRemaining > 0 else { return }
        shakeRemaining = max(0, shakeRemaining - dt)
        let shake = Effects.shakeOffset(remaining: shakeRemaining, rng: &shakeRng)
        cameraNode.position = CGPoint(x: cameraBase.x + shake.x, y: cameraBase.y + shake.y)
    }

    // MARK: - Modo demo

    /// Se juega solo. Sirve para capturas y para grabar el vídeo de la ficha de la
    /// App Store: capturar un juego de reflejos a mano da fotos torcidas, y aquí la
    /// pose importa —la luciérnaga colgando de una flor con la liana tensa cuenta el
    /// juego en una imagen—.
    ///
    /// Solo se activa con `-demo` en la línea de lanzamiento; en una partida normal
    /// esta rama no existe.
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    private func demoInput() -> Bool {
        let body = simulation.body
        guard let attachment = body.attachment else {
            return simulation.anchors.contains { anchor in
                anchor.position.x > body.position.x
                    && body.position.distance(to: anchor.position) <= Tuning.Pendulum.grabRadius
            }
        }
        // Suelta pasado el punto bajo, cuando la inercia ya empuja hacia delante.
        let pastLowestPoint = body.position.x > attachment.anchor.x
        return !(pastLowestPoint && body.velocity.dx > 0 && body.velocity.dy > 0)
    }

    /// Fire-and-forget: el motor háptico es un actor y no puede bloquear el frame.
    /// Si un pulso llega dos milisegundos tarde no pasa nada; si el frame se pierde,
    /// sí.
    private func emit(_ signal: HapticSignal) {
        guard settings.hapticsEnabled || settings.audioEnabled else { return }
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
        darknessNode.position = simulation.body.position
        highlightReachableFlowers()
        swayStems(time: lastUpdateTime ?? 0)

        if let attachment = simulation.body.attachment {
            // La liana cuelga cuando está floja y se tensa al tirar. Una línea recta
            // constante era la mitad de la sensación de "todo demasiado fijo": una
            // liana de verdad tiene comba, y esa comba desaparece justo cuando el
            // tirón manda.
            let position = simulation.body.position
            let distance = position.distance(to: attachment.anchor)
            let slack = max(0, attachment.ropeLength - distance)

            let path = CGMutablePath()
            path.move(to: attachment.anchor)
            let midpoint = CGPoint(x: (attachment.anchor.x + position.x) / 2,
                                   y: (attachment.anchor.y + position.y) / 2)
            path.addQuadCurve(to: position,
                              control: CGPoint(x: midpoint.x,
                                               y: midpoint.y - slack * Self.ropeSagFactor))
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
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(chunk.index)) &* 0x9E37_79B9)
        for (bottom, top) in segments where top > bottom {
            walls.addChild(makeTrunk(rect: CGRect(x: wall.x - thickness / 2,
                                                  y: bottom,
                                                  width: thickness,
                                                  height: top - bottom),
                                     rng: &rng))
        }

        // Musgo lunar en los dos bordes del hueco. Señala la **puerta**, no la pared:
        // el ojo se va a donde hay que ir. Se dibuja hacia dentro del tronco, nunca
        // fuera, para no mentir sobre dónde está la colisión.
        for edgeY in [wall.gapBottomY, wall.gapTopY] {
            let moss = SKShapeNode(rect: CGRect(x: wall.x - thickness / 2,
                                                y: edgeY - Self.mossThickness / 2,
                                                width: thickness,
                                                height: Self.mossThickness))
            moss.fillColor = Palette.moss
            moss.strokeColor = .clear
            moss.alpha = 0.8
            moss.glowWidth = 3
            walls.addChild(moss)
        }
        walls.alpha = wallAlpha(for: chunk)
        container.addChild(walls)

        // Las flores quedan POR ENCIMA del velo: una flor de luna es una luz, y en la
        // oscuridad las luces son justo lo que sí se ve. Además es lo que hace la
        // zona a ciegas jugable en vez de imposible — sin asideros visibles no
        // habría forma de columpiarse.
        let flowers = SKNode()
        flowers.zPosition = Self.lightZPosition
        flowers.name = Self.flowersNodeName
        for anchor in chunk.anchors {
            flowers.addChild(makeMoonflower(at: anchor.position))
        }
        container.addChild(flowers)

        // Cada chunk dibuja su tramo de maleza y de dosel. Se genera por chunk y no
        // a lo largo de todo el mundo por una razón práctica: el mundo mide 200.000
        // pt y sembrarlo entero de hierba serían miles de nodos para tres pantallas
        // de juego.
        container.addChild(makeEdges(from: previousWallX(of: chunk), to: chunk.wall.x, rng: &rng))

        return container
    }

    private func previousWallX(of chunk: Chunk) -> CGFloat {
        chunk.index > 1
            ? DifficultyCurve.wallX(forWall: chunk.index - 1)
            : Tuning.Player.startX - Tuning.World.wallThickness
    }

    /// Maleza en el suelo y hojas colgando del dosel.
    ///
    /// Es decoración pura: crece **hacia dentro** del área jugable pero no colisiona,
    /// porque suelo y techo ya matan por su cuenta en `Collision`. Se queda corta a
    /// propósito para que nadie la confunda con un obstáculo.
    private func makeEdges(from startX: CGFloat, to endX: CGFloat, rng: inout SplitMix64) -> SKNode {
        let node = SKNode()
        guard endX > startX else { return node }

        let step = Tuning.Scenery.undergrowthSpacing
        var x = startX
        while x < endX {
            let width = rng.nextCGFloat(in: (step * 0.8)...(step * 1.6))
            let height = rng.nextCGFloat(in: (step * 0.5)...(step * 1.5))

            let blade = CGMutablePath()
            blade.move(to: CGPoint(x: x, y: Tuning.World.floorY))
            blade.addQuadCurve(to: CGPoint(x: x + width, y: Tuning.World.floorY),
                               control: CGPoint(x: x + width / 2, y: Tuning.World.floorY + height))
            let grass = SKShapeNode(path: blade)
            grass.fillColor = Palette.grass
            grass.strokeColor = .clear
            grass.alpha = 0.9
            node.addChild(grass)

            let leafHeight = rng.nextCGFloat(in: (step * 0.4)...(step * 1.2))
            let leafPath = CGMutablePath()
            leafPath.move(to: CGPoint(x: x, y: Tuning.World.ceilingY))
            leafPath.addQuadCurve(to: CGPoint(x: x + width, y: Tuning.World.ceilingY),
                                  control: CGPoint(x: x + width / 2,
                                                   y: Tuning.World.ceilingY - leafHeight))
            let leaf = SKShapeNode(path: leafPath)
            leaf.fillColor = Palette.leaf
            leaf.strokeColor = .clear
            leaf.alpha = 0.9
            node.addChild(leaf)

            x += width
        }
        return node
    }

    /// Un tronco, no una barra.
    ///
    /// Todo el dibujo cae **dentro** del rectángulo de colisión: el canto iluminado,
    /// las vetas y el redondeo van hacia dentro, nunca sobresalen. Lo que se ve tiene
    /// que ser exactamente lo que mata (pilar 2 del GDD), así que la decoración puede
    /// quitar superficie visual pero jamás añadirla.
    private func makeTrunk(rect: CGRect, rng: inout SplitMix64) -> SKNode {
        let node = SKNode()

        let body = SKShapeNode(rect: rect, cornerRadius: 5)
        body.fillColor = Palette.trunk
        body.strokeColor = Palette.trunkEdge
        body.lineWidth = 2
        node.addChild(body)

        // El canto que mira a la luna, que está arriba a la izquierda.
        let lit = SKShapeNode(rect: CGRect(x: rect.minX + 2,
                                           y: rect.minY + 2,
                                           width: rect.width * 0.28,
                                           height: rect.height - 4),
                              cornerRadius: 3)
        lit.fillColor = Palette.trunkLit
        lit.strokeColor = .clear
        lit.alpha = 0.75
        node.addChild(lit)

        // Vetas: líneas verticales quebradas, con la semilla del chunk para que el
        // mismo tronco tenga siempre la misma corteza.
        for _ in 0..<3 {
            let path = CGMutablePath()
            let x = rng.nextCGFloat(in: (rect.minX + 10)...(rect.maxX - 8))
            var y = rect.minY + rng.nextCGFloat(in: 0...80)
            path.move(to: CGPoint(x: x, y: y))
            while y < rect.maxY {
                y = min(rect.maxY, y + rng.nextCGFloat(in: 90...220))
                path.addLine(to: CGPoint(x: x + rng.nextCGFloat(in: -4...4), y: y))
            }
            let vein = SKShapeNode(path: path)
            vein.strokeColor = Palette.bark
            vein.lineWidth = 2.5
            vein.alpha = 0.55
            node.addChild(vein)
        }

        return node
    }

    /// Una flor de luna colgando de su tallo.
    ///
    /// El tallo es la mejora de legibilidad más barata del proyecto: un punto que
    /// flota no dice «cuélgate de mí»; algo que cuelga, sí. Es la afordancia que
    /// tendría una liana, a coste de una línea por flor.
    private func makeMoonflower(at position: CGPoint) -> SKNode {
        let node = SKNode()
        node.position = position

        let stem = SKShapeNode()
        stem.name = Self.stemNodeName
        stem.strokeColor = Palette.stem
        stem.lineWidth = 3
        node.addChild(stem)

        let corolla = SKNode()
        corolla.name = Self.corollaNodeName
        let petalCount = Tuning.Scenery.flowerPetalCount
        let petalSize = Tuning.Scenery.flowerPetalLength

        // Pétalos **anchos y solapados**, no radios finos apuntando hacia fuera. Con
        // elipses estrechas la silueta salía en punta y todo el mundo la leía como
        // una estrella; una corola es un contorno redondo y continuo con lóbulos, y
        // el solape es lo que la cierra.
        for index in 0..<petalCount {
            let angle = CGFloat(index) / CGFloat(petalCount) * 2 * .pi
            let petal = SKShapeNode(circleOfRadius: petalSize * 0.52)
            petal.fillColor = Palette.moonflower
            petal.strokeColor = .clear
            petal.alpha = 0.9
            petal.position = CGPoint(x: cos(angle) * petalSize * 0.46,
                                     y: sin(angle) * petalSize * 0.46)
            corolla.addChild(petal)
        }

        let core = SKShapeNode(circleOfRadius: Tuning.Scenery.flowerCoreRadius)
        core.fillColor = Palette.moonflowerCore
        core.strokeColor = Palette.moonflowerGlow
        core.lineWidth = 6
        core.glowWidth = 8
        corolla.addChild(core)

        node.addChild(corolla)
        return node
    }

    private static let wallsNodeName = "walls"
    private static let flowersNodeName = "flowers"
    private static let corollaNodeName = "corolla"
    private static let stemNodeName = "stem"
    private static let mossThickness: CGFloat = 10
    /// Cuánto cuelga la liana por cada punto de holgura.
    private static let ropeSagFactor: CGFloat = 0.9
    private static let lightZPosition: CGFloat = 20

    /// La flor que está al alcance se abre y brilla. Enseña el radio de agarre
    /// jugando, sin cartel: pulsar cuando algo está abierto engancha, y el jugador
    /// deduce la regla en dos intentos.
    /// Los tallos ondulan; las flores **no se mueven**.
    ///
    /// Es deliberado: la flor es el asidero, y su posición de dibujo tiene que ser
    /// exactamente la que usa la física. Mecer la flor daría más vida y mentiría
    /// sobre dónde te vas a enganchar, que en un juego de precisión se paga caro.
    /// Así que ondula la comba del tallo entre el techo y la flor, mientras los dos
    /// extremos se quedan clavados donde están.
    private func swayStems(time: TimeInterval) {
        for chunk in simulation.chunks {
            guard let flowers = chunkNodes[chunk.index]?
                .childNode(withName: Self.flowersNodeName) else { continue }

            for (index, flower) in flowers.children.enumerated() {
                guard index < chunk.anchors.count,
                      let stem = flower.childNode(withName: Self.stemNodeName) as? SKShapeNode
                else { continue }

                let top = Tuning.World.ceilingY - chunk.anchors[index].position.y
                // Fase propia por flor: si todas ondularan a la vez parecerían una
                // cortina, no una selva.
                let phase = Double(chunk.index) * 1.7 + Double(index) * 2.9
                let sway = CGFloat(sin(time * Double(Tuning.Scenery.stemSwaySpeed) + phase))
                    * Tuning.Scenery.stemSwayAmplitude

                let path = CGMutablePath()
                path.move(to: .zero)
                path.addQuadCurve(to: CGPoint(x: 0, y: top),
                                  control: CGPoint(x: sway, y: top * 0.5))
                stem.path = path
            }
        }
    }

    private func highlightReachableFlowers() {
        let position = simulation.body.position
        for chunk in simulation.chunks {
            guard let flowers = chunkNodes[chunk.index]?
                .childNode(withName: Self.flowersNodeName) else { continue }

            for (index, flower) in flowers.children.enumerated() {
                guard index < chunk.anchors.count,
                      let corolla = flower.childNode(withName: Self.corollaNodeName) else { continue }

                let reachable = position.distance(to: chunk.anchors[index].position)
                    <= Tuning.Pendulum.grabRadius
                let target: CGFloat = reachable ? Tuning.Scenery.flowerReadyScale : 1
                corolla.setScale(lerp(corolla.xScale, target, 0.25))
                corolla.alpha = reachable ? 1 : 0.75
            }
        }
    }

    private func wallAlpha(for chunk: Chunk) -> CGFloat {
        guard chunk.isBlind else { return 1 }
        // El contorno tenue aparece si no hay Taptic Engine, si el jugador ha
        // apagado los hápticos, o si lo ha pedido por accesibilidad. Los tres casos
        // son el mismo: se ha quedado sin el canal que sustituía a la vista.
        let assisted = assistedMode || settings.needsAssistedBlindZones
        let hidden = assisted ? Tuning.BlindZone.assistedOutlineAlpha : 0
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
            node.fillColor = Palette.ground
            node.strokeColor = Palette.trunkEdge
            node.lineWidth = 2
            worldNode.addChild(node)
        }
    }
}
