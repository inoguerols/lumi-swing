import CoreImage
import SpriteKit
import UIKit

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
    /// Lumi entera: una bola de luz con ojazos y cola de cometa. El glow
    /// **es** el cuerpo; no hay anatomía de insecto que leer a 36 px.
    ///
    /// `bodyGroup` es la bola, y es lo único que gira con la pose y se
    /// estira con la velocidad; la cara cuelga de `playerNode` y solo se ladea
    /// una fracción del giro (`faceLeanFactor`). Su masa dibujada cabe entera dentro de
    /// `Tuning.Player.radius`, que sigue siendo **el** radio de colisión (la cuenta
    /// está en `Tuning.Scenery.bodyRadius`). Lo que asoma fuera —bloom, motas,
    /// halo, estela— es luz difusa, nunca masa. `haloNode` va detrás de todo y es el
    /// único que late con el pulso háptico; las tres capas de luz parpadean además
    /// con el aura viva (`updateAura`).
    private let playerNode = SKNode()
    private let haloNode = SKSpriteNode()
    /// Las tres capas de luz difusa (ambiente, puente y halo) cuelgan de este grupo
    /// y no directamente del jugador: la deriva del aura mueve la luz entera sin
    /// tocar cuerpo ni cara — la masa dibujada no puede salirse del círculo que mata.
    private let lightGroup = SKNode()
    /// Estado del aura viva: capas con su alpha base y sus fases sorteadas, reloj
    /// propio y envolvente del pulso háptico (1 en el pico, decae linealmente a 0).
    private var auraLayers: [(node: SKSpriteNode, baseAlpha: CGFloat, seed: Effects.AuraLayerSeed)] = []
    private var auraTime: CGFloat = 0
    private var haloPulse: CGFloat = 0
    private var haloPulseDuration: CGFloat = 1
    private let bodyGroup = SKNode()
    /// La cara (solo los ojos): vive fuera de `bodyGroup` para no estirarse con
    /// la velocidad, pero `updatePose` la ladea una fracción del giro del cuerpo.
    private let faceGroup = SKNode()
    private let ropeNode = SKShapeNode()

    /// La textura suave que comparten cuerpo, bloom, halo y estela: se genera una
    /// vez al montar la escena (`buildFirefly` corre antes que `buildTrail`).
    private var lightTexture = SKTexture()

    /// Estado del muelle de la pose: ángulo actual y velocidad angular. Vive aquí y
    /// no en la simulación porque es presentación pura — la física no gira.
    private var poseAngle: CGFloat = 0
    private var poseAngularVelocity: CGFloat = 0

    /// Se lee al montar y al empezar cada partida, no por frame. Solo apaga
    /// chispas y baja la estela: la pose y la cola no son movimiento gratuito,
    /// son la información de dónde estás y hacia dónde vas.
    private var reduceMotion = false
    private var sparkTimer: CGFloat = 0
    private var sparkRng = SplitMix64(seed: 0x5A_9A)

    /// Decorado: cielo y dos capas de vegetación que se quedan atrás.
    private let skyNode = SKSpriteNode()
    private let canopyFarNode = SKNode()
    private let canopyNearNode = SKNode()
    private let pollenNode = SKNode()
    /// La luna. Ya no clavada a la cámara (F6): `updateParallax` la mueve una
    /// fracción mínima de lo que se mueve la cámara, partiendo de esta posición.
    private let moonNode = SKNode()
    private var moonHomePosition = CGPoint.zero

    /// Latido del halo, sincronizado con el háptico de proximidad.
    private var blinkTimer: CGFloat = 0
    private var chunkNodes: [Int: SKNode] = [:]
    private let scoreLabel = SKLabelNode(fontNamed: GameScene.sfRoundedFontName(weight: .heavy))
    private let blindNoticeLabel = SKLabelNode(fontNamed: GameScene.sfRoundedFontName(weight: .semibold))
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

    /// El ambiente de selva se apaga dentro de la zona a ciegas. Se engancha a
    /// `simulation.isBlind` —el mismo estado que dispara `blindEnter`/`blindExit`—
    /// y no a la rampa del velo: el velo se telegrafía un muro antes a propósito,
    /// pero el silencio tiene que caer con el muro, no anunciarlo.
    private var ambience = AmbienceDucking()
    private var ambienceBucket: Int?

    private var trailNodes: [SKSpriteNode] = []
    private var trailPositions: [CGPoint] = []
    private var trailTimer: CGFloat = 0
    private var shakeRemaining: CGFloat = 0
    private var shakeRng = SplitMix64(seed: 0x5EED)

    // Replay de la demo: el plan de DemoPilot solo es fiel a timestep fijo, así
    // que en demo la simulación avanza en pasos de 1/120 con un acumulador.
    private var demoStep = 0
    private var demoAccumulator: CGFloat = 0
    /// Posición de cámara sin el temblor sumado.
    private var cameraBase = CGPoint.zero

    /// Apple no publica un nombre de familia estable para SF Rounded, así que se pide
    /// el descriptor `.rounded` del sistema y se lee su nombre real, igual que hace
    /// `Shell.swift` con `.font(.system(design: .rounded))`. Si el sistema no lo sirve
    /// (nunca debería en iOS 13+), cae a Avenir Next en vez de fallar en silencio.
    private static func sfRoundedFontName(weight: UIFont.Weight) -> String {
        let system = UIFont.systemFont(ofSize: 20, weight: weight)
        guard let roundedDescriptor = system.fontDescriptor.withDesign(.rounded) else {
            assertionFailure("SF Rounded no disponible: usando Avenir Next de respaldo")
            return "AvenirNext-Bold"
        }
        let rounded = UIFont(descriptor: roundedDescriptor, size: 20)
        assert(UIFont(name: rounded.fontName, size: 20) != nil,
               "SKLabelNode no podrá cargar la fuente \(rounded.fontName)")
        return rounded.fontName
    }

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

        reduceMotion = UIAccessibility.isReduceMotionEnabled

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

        moonNode.addChild(halo)
        moonNode.addChild(disc)
        moonHomePosition = CGPoint(x: Tuning.World.sceneWidth * 0.30,
                                   y: height * 0.5 - Tuning.Scenery.moonRadius * 3)
        moonNode.position = moonHomePosition
        moonNode.zPosition = -95
        cameraNode.addChild(moonNode)
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
            // Bokeh, no confeti: radio y alpha distintos por partícula, y un
            // fundido cíclico desfasado — discos idénticos, estáticos y de alpha
            // uniforme se leían como pegatinas sobre el cristal.
            let mote = SKShapeNode(circleOfRadius: rng.nextCGFloat(
                in: Tuning.Scenery.pollenRadiusMin...Tuning.Scenery.pollenRadiusMax))
            mote.fillColor = Palette.pollen
            mote.strokeColor = .clear
            mote.blendMode = .add
            let peakAlpha = rng.nextCGFloat(in: 0.06...0.22)
            mote.alpha = peakAlpha
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

            let fade = TimeInterval(Tuning.Scenery.pollenFadeDuration
                                    * rng.nextCGFloat(in: 0.7...1.4))
            let dim = SKAction.fadeAlpha(to: peakAlpha * Tuning.Scenery.pollenFadeFloor,
                                         duration: fade)
            dim.timingMode = .easeInEaseOut
            let brighten = SKAction.fadeAlpha(to: peakAlpha, duration: fade)
            brighten.timingMode = .easeInEaseOut
            mote.run(.sequence([
                // El desfase por partícula: sin él, toda la selva respiraría a la vez.
                .wait(forDuration: TimeInterval(rng.nextCGFloat(in: 0...CGFloat(fade * 2)))),
                .repeatForever(.sequence([dim, brighten]))
            ]))
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
        moonNode.position = CGPoint(
            x: moonHomePosition.x - camera.x * Tuning.Scenery.parallaxMoon,
            y: moonHomePosition.y - camera.y * Tuning.Scenery.parallaxMoon * 0.3)
    }

    // MARK: - Lumi

    /// Tres elementos y ni uno más: bola de luz, ojazos y cola. El
    /// orden de dibujo es el orden de lectura — primero la luz, luego lo oscuro
    /// encima, que es lo único que sobrevive al tamaño de un icono.
    private func buildFirefly() {
        lightTexture = Self.makeLightTexture()

        // Las capas de luz difusa van en su propio grupo: `updateAura` lo hace
        // derivar 1-2 pt alrededor del cuerpo, como la luz de una llama.
        playerNode.addChild(lightGroup)
        var auraRng = SplitMix64(seed: 0xA0_9A)

        // Luz ambiente primero: el halo más ancho y más tenue, el que hace que la
        // luz BAÑE el fondo — el verde de la selva se aclara alrededor de Lumi
        // porque este sprite aditivo se dibuja encima de troncos y dosel (el
        // jugador va a z20 y la escenografía por debajo). Ligeramente verdoso para
        // aclarar el fondo hacia su propio matiz y que el personaje pertenezca a
        // la escena en vez de flotar recortado sobre ella.
        let ambientSide = Tuning.Player.radius * Tuning.Scenery.ambientRadiusScale * 2
        let ambient = SKSpriteNode(texture: lightTexture,
                                   size: CGSize(width: ambientSide, height: ambientSide))
        ambient.color = Palette.fireflyAmbient
        ambient.colorBlendFactor = 1
        ambient.blendMode = .add
        ambient.alpha = Tuning.Scenery.ambientAlpha
        lightGroup.addChild(ambient)
        auraLayers.append((ambient, Tuning.Scenery.ambientAlpha,
                           Effects.AuraLayerSeed(rng: &auraRng)))

        // Halo intermedio: entre el halo pegado al cuerpo (1,8·r) y la luz
        // ambiente (4,6·r) quedaba un escalón visible — la zona brillante
        // terminaba de golpe y luego empezaba un disco tenue. Este puente cálido
        // hace que la caída sea continua: cuatro radios, cuatro alfas.
        let midSide = Tuning.Player.radius * Tuning.Scenery.midHaloRadiusScale * 2
        let midHalo = SKSpriteNode(texture: lightTexture,
                                   size: CGSize(width: midSide, height: midSide))
        midHalo.color = Palette.firefly
        midHalo.colorBlendFactor = 1
        midHalo.blendMode = .add
        midHalo.alpha = Tuning.Scenery.midHaloAlpha
        lightGroup.addChild(midHalo)
        auraLayers.append((midHalo, Tuning.Scenery.midHaloAlpha,
                           Effects.AuraLayerSeed(rng: &auraRng)))

        // Halo después: aditivo, y el único nodo al que llega el pulso háptico (ver
        // `updateBlink`). Es un sprite con la textura difusa y no un círculo: un
        // disco aditivo con canto duro se lee como un aro. Con el ambiente, el
        // halo y las capas de bloom del cuerpo, la luz cae en tres radios y tres
        // alfas distintos, no en un único aro.
        let haloSide = Tuning.Player.radius * Tuning.Scenery.haloRadiusScale * 2
        haloNode.texture = lightTexture
        haloNode.size = CGSize(width: haloSide, height: haloSide)
        haloNode.color = Palette.fireflyGlow
        haloNode.colorBlendFactor = 1
        haloNode.blendMode = .add
        haloNode.alpha = Tuning.Scenery.haloDimAlpha
        lightGroup.addChild(haloNode)
        auraLayers.append((haloNode, Tuning.Scenery.haloDimAlpha,
                           Effects.AuraLayerSeed(rng: &auraRng)))

        // Las motas cuelgan del jugador, no del cuerpo: no rotan con la pose ni se
        // estiran con la velocidad, porque son aire iluminado, no anatomía.
        buildMotes()

        playerNode.addChild(bodyGroup)
        buildLightBall()
        buildFace()
    }

    /// El cuerpo **es** la luz: la misma textura difusa repetida en capas aditivas
    /// concéntricas para el bloom, y encima la bola sólida. Ninguna capa tiene canto
    /// duro porque todas mueren en alpha 0 dentro de su propia textura.
    private func buildLightBall() {
        let side = Self.lightTextureSide
        for step in 0..<Tuning.Scenery.bodyGlowLayers {
            let t = CGFloat(step + 1) / CGFloat(Tuning.Scenery.bodyGlowLayers)
            let scale = lerp(1.15, Tuning.Scenery.bodyGlowScale, t)
            let glow = SKSpriteNode(texture: lightTexture,
                                    size: CGSize(width: side * scale, height: side * scale))
            glow.blendMode = .add
            glow.alpha = Tuning.Scenery.bodyGlowAlpha / CGFloat(Tuning.Scenery.bodyGlowLayers)
            bodyGroup.addChild(glow)
        }

        let ball = SKSpriteNode(texture: lightTexture,
                                size: CGSize(width: side, height: side))
        bodyGroup.addChild(ball)

        // Microvida: la bola respira ±5% cada ~1,2 s, con duraciones jitteradas
        // (SplitMix64, determinista: nada de Date ni random del sistema) para que
        // el pulso no sea un metrónomo píxel-idéntico. Ocho ciclos distintos
        // encadenados y repetidos bastan para que el bucle no se lea. Con Reduce
        // Motion respira a la mitad — una luz viva es estética, no movimiento.
        let pulseAmount = reduceMotion
            ? 1 + (Tuning.Scenery.corePulseScale - 1) / 2
            : Tuning.Scenery.corePulseScale
        var pulseRng = SplitMix64(seed: 0x9015_E5)
        var pulses: [SKAction] = []
        for _ in 0..<8 {
            for target in [pulseAmount, 1] {
                let jitter = pulseRng.nextCGFloat(
                    in: (1 - Tuning.Scenery.corePulseJitter)...(1 + Tuning.Scenery.corePulseJitter))
                let half = SKAction.scale(
                    to: target,
                    duration: TimeInterval(Tuning.Scenery.corePulseDuration * jitter) / 2)
                half.timingMode = .easeInEaseOut
                pulses.append(half)
            }
        }
        ball.run(.repeatForever(.sequence(pulses)))

        // Y el núcleo parpadea por ENCIMA del cuerpo, nunca restándole alpha (F4
        // prohíbe que el cuerpo se transparente): un segundo sprite aditivo
        // pequeño cuya intensidad ondula con periodos desiguales, para que no se
        // lea como un metrónomo. Reduce Motion lo apaga.
        guard !reduceMotion else { return }
        let core = SKSpriteNode(texture: lightTexture,
                                size: CGSize(width: side * 0.6, height: side * 0.6))
        core.blendMode = .add
        core.alpha = Tuning.Scenery.coreFlickerAlphaLow
        bodyGroup.addChild(core)
        core.run(.repeatForever(.sequence([
            .fadeAlpha(to: Tuning.Scenery.coreFlickerAlphaHigh, duration: 0.45),
            .fadeAlpha(to: Tuning.Scenery.coreFlickerAlphaLow, duration: 0.7),
            .fadeAlpha(to: Tuning.Scenery.coreFlickerAlphaHigh * 0.8, duration: 0.3),
            .fadeAlpha(to: Tuning.Scenery.coreFlickerAlphaLow, duration: 0.55)
        ])))
    }

    /// La cara: dos ojazos con su brillo, y nada más — ni boca, ni cejas, ni
    /// masa oscura encima (vía Limbo/Sein: el personaje es luminoso hasta el
    /// núcleo, y a 36 px cada trazo extra emborrona los dos que sí se leen).
    ///
    /// La cara cuelga del jugador, NO de `bodyGroup` — el cuerpo y el glow rotan
    /// y se estiran con la física; la cara solo se ladea una fracción del giro
    /// (`updatePose`), que devuelve el swing a la lectura sin tumbar la mirada.
    /// Los ojos van en su propio sprite para poder parpadear (squash vertical
    /// rápido); el parpadeo sobrevive a Reduce Motion.
    private func buildFace() {
        let side = (Tuning.Scenery.bodyRadius + Tuning.Scenery.facePadding) * 2

        let eyes = SKSpriteNode(texture: Self.makeEyesTexture(),
                                size: CGSize(width: side, height: side))
        // El ancla en la línea de los ojos: el squash del parpadeo cierra los
        // párpados en su sitio en vez de arrastrar los ojos hacia el centro.
        eyes.anchorPoint = CGPoint(x: 0.5, y: 0.5 + Tuning.Scenery.eyeOffsetY / side)
        eyes.position = CGPoint(x: 0, y: Tuning.Scenery.eyeOffsetY)
        faceGroup.addChild(eyes)

        // Cadena de parpadeos con jitter determinista, prehorneada y repetida:
        // ocho intervalos distintos bastan para que no se lea el bucle.
        var rng = SplitMix64(seed: 0xB11_4C)
        var blinks: [SKAction] = []
        for _ in 0..<8 {
            let wait = rng.nextCGFloat(
                in: Tuning.Scenery.eyeBlinkIntervalMin...Tuning.Scenery.eyeBlinkIntervalMax)
            blinks.append(.wait(forDuration: TimeInterval(wait)))
            blinks.append(.scaleY(to: Tuning.Scenery.eyeBlinkSquash,
                                  duration: TimeInterval(Tuning.Scenery.eyeBlinkCloseDuration)))
            blinks.append(.scaleY(to: 1,
                                  duration: TimeInterval(Tuning.Scenery.eyeBlinkOpenDuration)))
        }
        eyes.run(.repeatForever(.sequence(blinks)))

        playerNode.addChild(faceGroup)
    }

    /// Dos o tres motas cálidas flotando cerca. Nodos animados y no un emisor: son
    /// tres partículas con deriva lenta, y un `SKEmitterNode` para eso es traer un
    /// sistema entero para colgarle tres puntos.
    private func buildMotes() {
        // Corro de motas en un contenedor que gira despacio: la deriva vertical de
        // cada mota más la órbita del corro es lo que las hace aire y no adorno.
        // Con Reduce Motion la órbita se para; la deriva suave se queda.
        let ring = SKNode()
        ring.zPosition = -1
        playerNode.addChild(ring)
        if !reduceMotion {
            ring.run(.repeatForever(.rotate(byAngle: 2 * .pi,
                                            duration: TimeInterval(Tuning.Scenery.moteOrbitDuration))))
        }

        var rng = SplitMix64(seed: 0xB0_7A5)
        for index in 0..<Tuning.Scenery.moteCount {
            // Sprite con la textura difusa y no un círculo: una mota es luz, y un
            // `SKShapeNode` por pequeño que sea deja un canto duro.
            let moteSide = Tuning.Scenery.moteRadius * 2 * rng.nextCGFloat(in: 0.6...1.5)
            let mote = SKSpriteNode(texture: lightTexture,
                                    size: CGSize(width: moteSide * 2.4, height: moteSide * 2.4))
            mote.color = Palette.firefly
            mote.colorBlendFactor = 1
            mote.blendMode = .add
            // Ángulo y radio con jitter: nada de puntos uniformes alineados.
            let angle = CGFloat(index) / CGFloat(Tuning.Scenery.moteCount) * 2 * .pi
                + rng.nextCGFloat(in: -0.6...0.6)
            let orbit = Tuning.Player.radius * Tuning.Scenery.moteOrbit
                * rng.nextCGFloat(in: 0.75...1.3)
            mote.position = CGPoint(x: cos(angle) * orbit, y: sin(angle) * orbit)
            mote.alpha = rng.nextCGFloat(in: 0.2...0.5)

            let drift = TimeInterval(Tuning.Scenery.moteDriftDuration * rng.nextCGFloat(in: 0.8...1.4))
            let up = SKAction.group([
                .moveBy(x: rng.nextCGFloat(in: -14...14), y: rng.nextCGFloat(in: 8...20), duration: drift),
                .fadeAlpha(to: 0.10, duration: drift)
            ])
            let down = SKAction.group([
                .moveBy(x: rng.nextCGFloat(in: -14...14), y: rng.nextCGFloat(in: -20...(-8)), duration: drift),
                .fadeAlpha(to: rng.nextCGFloat(in: 0.35...0.5), duration: drift)
            ])
            mote.run(.repeatForever(.sequence([up, down])))
            ring.addChild(mote)
        }
    }

    /// Lado del sprite que usa la textura difusa, en puntos de juego: la bola sólida
    /// mide `bodyRadius`, y alrededor lleva el desvanecido hasta alpha 0.
    private static var lightTextureSide: CGFloat {
        Tuning.Scenery.bodyRadius * 2 / Tuning.Scenery.bodyEdgeFade
    }

    /// La bola de luz: degradado radial de núcleo blanco caliente a ámbar que
    /// termina en **alpha 0 antes del canto de la textura**. Ese último tramo
    /// transparente es la diferencia entre una luz y una pegatina redonda: un
    /// `SKShapeNode` circular siempre acaba en un filo, por suave que sea el color.
    ///
    /// Se genera una vez y la comparten cuerpo, bloom, halo y estela.
    private static func makeLightTexture() -> SKTexture {
        let scale = Tuning.Scenery.bodyTextureScale
        let side = max(1, Int(lightTextureSide * scale))
        let space = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(data: nil,
                                      width: side,
                                      height: side,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(
                colorsSpace: space,
                // Tres paradas con el matiz desplazado (blanco cálido → ámbar →
                // naranja quemado que muere en alpha 0): la parada dura de alpha
                // que había en 0,88 dibujaba el anillo naranja como una frontera.
                // Ahora la interpolación núcleo→canto es continua en matiz y en
                // alpha; el banding restante lo mata el ruido horneado de abajo.
                colors: [Palette.fireflyCore.cgColor,
                         Palette.fireflyAmber.cgColor,
                         Palette.fireflyEmber.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, Tuning.Scenery.bodyEdgeFade, 1])
        else { return SKTexture() }

        let center = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        context.drawRadialGradient(gradient,
                                   startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: CGFloat(side) / 2,
                                   options: [])

        // Ruido determinista del 1-2% por canal, horneado UNA vez: dither contra
        // el banding del degradado. No toca el alpha, y cada canal se acota a su
        // alpha premultiplicado para que la textura siga siendo válida.
        if let data = context.data {
            var rng = SplitMix64(seed: 0xD1_7E4)
            let bytesPerRow = context.bytesPerRow
            let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * side)
            for row in 0..<side {
                for column in 0..<side {
                    let index = row * bytesPerRow + column * 4
                    let alpha = pixels[index + 3]
                    let factor = 1 + Tuning.Scenery.lightTextureNoise
                        * rng.nextCGFloat(in: -1...1)
                    guard alpha > 0 else { continue }
                    for channel in 0..<3 {
                        let value = CGFloat(pixels[index + channel]) * factor
                        pixels[index + channel] = UInt8(min(value.rounded(), CGFloat(alpha)))
                    }
                }
            }
        }

        guard let image = context.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: image)
    }

    /// Contexto cuadrado centrado y a escala de juego para hornear la cara.
    private static func makeFaceContext(side: Int, scale: CGFloat) -> CGContext? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: side,
                                      height: side,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        context.scaleBy(x: scale, y: scale)
        return context
    }

    /// Blur gaussiano horneado UNA vez, en píxeles de textura sobremuestreada.
    /// `facePadding` garantiza que la cola del blur cabe sin recortarse.
    private static func blurred(_ image: CGImage, side: Int, scale: CGFloat) -> CGImage? {
        let soft = CIImage(cgImage: image)
            .applyingGaussianBlur(sigma: Double(Tuning.Scenery.faceBlurSigma * scale))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        return CIContext().createCGImage(soft, from: soft.extent)
    }

    /// Los ojos, casi negros y con blur… y encima, SIN blur, los dos brillos
    /// blancos: el highlight nítido sobre el ojo blando es lo que hace la mirada
    /// viva en vez de un par de agujeros desenfocados.
    private static func makeEyesTexture() -> SKTexture {
        let scale = Tuning.Scenery.bodyTextureScale
        let side = max(1, Int((Tuning.Scenery.bodyRadius + Tuning.Scenery.facePadding) * 2 * scale))
        guard let context = makeFaceContext(side: side, scale: scale) else { return SKTexture() }

        for eyeSide in [-1, 1] as [CGFloat] {
            let eyeCenter = CGPoint(x: eyeSide * Tuning.Scenery.eyeOffsetX,
                                    y: Tuning.Scenery.eyeOffsetY)
            context.setFillColor(Palette.fireflyEye.cgColor)
            context.fillEllipse(in: CGRect(x: eyeCenter.x - Tuning.Scenery.eyeRadius,
                                           y: eyeCenter.y - Tuning.Scenery.eyeRadius,
                                           width: Tuning.Scenery.eyeRadius * 2,
                                           height: Tuning.Scenery.eyeRadius * 2))
        }

        guard let sharpEyes = context.makeImage(),
              let softEyes = blurred(sharpEyes, side: side, scale: scale),
              let composite = makeFaceContext(side: side, scale: scale)
        else { return SKTexture() }

        // El contexto ya está transformado: se deshace para pegar la imagen
        // blanda tal cual y se vuelve a aplicar para dibujar los brillos encima.
        composite.saveGState()
        composite.concatenate(composite.ctm.inverted())
        composite.draw(softEyes, in: CGRect(x: 0, y: 0, width: side, height: side))
        composite.restoreGState()

        for eyeSide in [-1, 1] as [CGFloat] {
            // Hacia dentro y arriba en los dos ojos: los dos brillos apuntando al
            // mismo sitio es lo que hace que la mirada converja en algo.
            let highlightCenter = CGPoint(
                x: eyeSide * Tuning.Scenery.eyeOffsetX
                    - eyeSide * Tuning.Scenery.eyeHighlightOffset,
                y: Tuning.Scenery.eyeOffsetY + Tuning.Scenery.eyeHighlightOffset)
            composite.setFillColor(Palette.fireflyCore.cgColor)
            composite.fillEllipse(in: CGRect(
                x: highlightCenter.x - Tuning.Scenery.eyeHighlightRadius,
                y: highlightCenter.y - Tuning.Scenery.eyeHighlightRadius,
                width: Tuning.Scenery.eyeHighlightRadius * 2,
                height: Tuning.Scenery.eyeHighlightRadius * 2))
        }

        guard let output = composite.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: output)
    }

    /// La pose, que es la mitad del personaje.
    ///
    /// Colgado, Lumi **no** se alinea con la liana: adopta solo una fracción de su
    /// ángulo (`uprightBias`) y se queda casi erguida, como quien se agarra a una
    /// rama en vez de colgar como un badajo. En vuelo libre se inclina hacia donde
    /// va con el mismo sesgo: la cara (los ojos) debe leerse siempre, y un
    /// cuerpo que rota 90° con la velocidad la tumba de lado.
    ///
    /// Y no persigue ese objetivo con una interpolación, sino con un muelle
    /// amortiguado de segundo orden: el giro llega tarde y se pasa un poco de frenada
    /// al cambiar de sentido, que es exactamente lo que separa un cuerpo con masa de
    /// un valor suavizado.
    private func updatePose(dt: CGFloat) {
        let body = simulation.body
        // Un hipo del sistema no puede reventar el muelle: con un dt enorme la
        // integración explota y el cuerpo saldría girando.
        let step = min(dt, Tuning.Pendulum.maxFrameDelta)
        let speedFactor = clamp(body.velocity.length / Tuning.Pendulum.maxSpeed, 0, 1)

        let target: CGFloat
        if let attachment = body.attachment {
            let axis = attachment.anchor - body.position
            target = (atan2(axis.dy, axis.dx) - .pi / 2) * Tuning.Scenery.uprightBias
        } else if body.velocity.length > 1 {
            // Normalizado a [-π, π] ANTES de escalar: -5π/4 y 3π/4 son el mismo
            // ángulo, pero multiplicados por el sesgo inclinan a lados opuestos.
            let raw = Self.shortestAngle(
                from: 0, to: atan2(body.velocity.dy, body.velocity.dx) - .pi / 2)
            target = raw * Tuning.Scenery.uprightBias
        } else {
            target = poseAngle
        }

        let delta = Self.shortestAngle(from: poseAngle, to: target)
        poseAngularVelocity += (Tuning.Scenery.poseStiffness * delta
                                - Tuning.Scenery.poseDamping * poseAngularVelocity) * step
        poseAngle += poseAngularVelocity * step
        bodyGroup.zRotation = poseAngle
        // El cuerpo es radialmente simétrico, así que sin esto el giro físico era
        // invisible: la cara se ladea con el swing, pero solo una fracción, para
        // que la mirada no se tumbe en pleno arco.
        faceGroup.zRotation = poseAngle * Tuning.Scenery.faceLeanFactor

        // El estiramiento sigue a la velocidad sin suavizar (la velocidad ya es
        // continua) y su tope está calculado contra el squash del agarre en
        // `Tuning.Scenery.bodyRadius`: el producto de los dos nunca saca la bola del
        // círculo de colisión.
        let stretch = 1 + speedFactor * Tuning.Scenery.stretchAtMaxSpeed
        bodyGroup.yScale = stretch
        bodyGroup.xScale = 1 / stretch
    }

    /// Diferencia de ángulos por el camino corto: sin esto, pasar de +π a −π daría
    /// una vuelta entera de más.
    private static func shortestAngle(from: CGFloat, to: CGFloat) -> CGFloat {
        var delta = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }

    /// Chispas detrás del cuerpo en vuelo libre y rápido. No informan de nada que la
    /// estela no diga ya: son el premio de ir rápido, y por eso son lo primero que se
    /// apaga con Reduce Motion — la pose y la cola no, que esas sí cuentan dónde
    /// estás y hacia dónde vas.
    private func updateSparks(dt: CGFloat) {
        let body = simulation.body
        guard !reduceMotion, !body.isAttached,
              body.velocity.length
                > Tuning.Pendulum.maxSpeed * Tuning.Scenery.sparkSpeedThreshold else { return }

        sparkTimer -= dt
        guard sparkTimer <= 0 else { return }
        sparkTimer = Tuning.Scenery.sparkInterval

        // ponytail: un nodo cada 90 ms que se borra solo no justifica un pool.
        // Textura difusa y no círculo: también las chispas mueren sin canto.
        let sparkSide = Tuning.Scenery.sparkRadius * sparkRng.nextCGFloat(in: 0.5...1) * 2.4
        let spark = SKSpriteNode(texture: lightTexture,
                                 size: CGSize(width: sparkSide * 2, height: sparkSide * 2))
        spark.color = Palette.fireflyCore
        spark.colorBlendFactor = 1
        spark.blendMode = .add
        spark.alpha = 0.75
        spark.zPosition = Self.lightZPosition - 2
        spark.position = body.position
        worldNode.addChild(spark)

        let back = body.velocity.normalized * -Tuning.Player.radius
        let life = TimeInterval(Tuning.Scenery.sparkLifetime)
        spark.run(.sequence([
            .group([
                .moveBy(x: back.dx + sparkRng.nextCGFloat(in: -18...18),
                        y: back.dy + sparkRng.nextCGFloat(in: -18...18),
                        duration: life),
                .fadeOut(withDuration: life),
                .scale(to: 0.2, duration: life)
            ]),
            .removeFromParent()
        ]))
    }

    /// El halo late al ritmo del háptico de proximidad: las luciérnagas parpadean
    /// de por sí, y aquí ese parpadeo **es el mapa**. Quien juega con el móvil sobre
    /// la mesa aprende el idioma igual que quien lo lleva en la mano. El cuerpo ya
    /// no lo toca (F4) — solo el halo late en alpha y escala.
    private func updateBlink(dt: CGFloat) {
        let interval = simulation.isBlind
            ? (simulation.distanceToNextWall
                .flatMap(ProximityMapping.cue(forDistance:))?.interval
                ?? Tuning.Scenery.idleBlinkInterval)
            : Tuning.Scenery.idleBlinkInterval

        blinkTimer -= dt
        if blinkTimer <= 0 {
            blinkTimer = interval
            // El pulso ya no es un SKAction sino una envolvente por frame: así
            // `updateAura` puede componerlo ENCIMA del parpadeo orgánico sin que
            // uno pise al otro (el pico del pulso manda; la base respira).
            haloPulse = 1
            haloPulseDuration = interval * Tuning.Scenery.haloPulseDecayFraction

            // El agujero de luz del velo late con la misma cadencia: la oscuridad
            // entera se convierte en el Taptic Engine hecho visible, para quien
            // juega con el móvil sobre la mesa y no lo tiene en la mano.
            let duration = TimeInterval(haloPulseDuration)
            darknessNode.removeAllActions()
            darknessNode.setScale(1 - Tuning.BlindZone.breatheAmplitude)
            darknessNode.run(.scale(to: 1 + Tuning.BlindZone.breatheAmplitude, duration: duration))
        }
    }

    /// El aura viva: las tres capas de luz parpadean con osciladores deterministas
    /// desfasados (respiración, temblor y caídas tipo vela) y el centro luminoso
    /// deriva 1-2 pt respecto al cuerpo. Sobre esa base se suma el pulso háptico
    /// del halo, que en su pico pisa al parpadeo (lerp hacia el brillo pleno): la
    /// información de juego destaca sobre la vida, nunca al revés.
    private func updateAura(dt: CGFloat) {
        auraTime += dt
        let amplitude = reduceMotion ? Tuning.Scenery.auraReduceMotionFactor : 1
        for layer in auraLayers {
            let flicker = Effects.auraFlicker(time: auraTime,
                                              seed: layer.seed,
                                              amplitudeScale: amplitude)
            let scale = 1 + (flicker - 1) * Tuning.Scenery.auraScaleFraction
            if layer.node === haloNode {
                layer.node.alpha = lerp(layer.baseAlpha * flicker,
                                        Tuning.Scenery.haloBrightAlpha,
                                        haloPulse)
                layer.node.setScale(lerp(Tuning.Scenery.haloDimScale * scale,
                                         Tuning.Scenery.haloBrightScale,
                                         haloPulse))
            } else {
                layer.node.alpha = layer.baseAlpha * flicker
                layer.node.setScale(scale)
            }
        }
        lightGroup.position = Effects.auraDrift(time: auraTime, amplitudeScale: amplitude)
        // La envolvente decae DESPUÉS de aplicarse: el frame del pulso muestra el
        // pico exacto, incluso con los intervalos más cortos de proximidad.
        haloPulse = max(0, haloPulse - dt / max(haloPulseDuration, Tuning.Pendulum.physicsStep))
    }

    /// Fuera de partida (menú, game over) no hay física que avanzar, pero el
    /// mundo detrás no puede quedarse congelado (F6): el halo late, los tallos
    /// ondulan y el cielo sigue su propio ciclo por tiempo real en vez del ciclo
    /// por muro de `updateSky()`, que aquí no tiene muros que contar.
    private func updateMenuAmbience(dt: CGFloat, time: TimeInterval) {
        updateBlink(dt: dt)
        updateAura(dt: dt)
        swayStems(time: time)
        let phase = (time.truncatingRemainder(dividingBy: TimeInterval(Tuning.Scenery.menuSkyCycleDuration)))
            / TimeInterval(Tuning.Scenery.menuSkyCycleDuration)
        backgroundColor = Palette.sky(at: CGFloat(phase))
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
        // Por encima de flores (z20) y velo (z10): sin esto el empate de zPosition=0
        // con worldNode (añadido después) lo enterraba bajo el propio juego.
        scoreLabel.zPosition = 30
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
        blindNoticeLabel.text = String(localized: "a ciegas · fíate del tacto")
        blindNoticeLabel.alpha = 0
        blindNoticeLabel.zPosition = 30
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
        if let previous = lastUpdateTime, model.phase != .playing, model.phase != .paused {
            settleShake(dt: CGFloat(currentTime - previous))
            // Sin física que avanzar, el mundo detrás del menú no puede quedarse
            // congelado (F6): tallos, halo y cielo siguen su curso propio. Nada
            // de esto toca `simulation` ni el HUD, así que no rompe el game over.
            //
            // En pausa NO: aquí sí tiene que congelarse todo, ambiente incluido —
            // es lo que separa "estoy en el menú" de "he dejado la partida a
            // medias y voy a volver a ella".
            updateMenuAmbience(dt: CGFloat(currentTime - previous), time: currentTime)
            // Fuera de partida la selva suena entera, aunque el run haya muerto
            // dentro de una zona a ciegas.
            updateAmbience(blind: false, dt: CGFloat(currentTime - previous))
        }
        guard model.phase == .playing else { return }
        guard let lastUpdateTime else { return }

        let dt = CGFloat(currentTime - lastUpdateTime)
        guard dt > 0 else { return }

        let events: [GameEvent]
        if Self.isDemo {
            // Timestep fijo: el plan buscado por DemoPilot se reproduce paso a
            // paso; agotado el plan, el heurístico de demoInput() toma el relevo.
            var collected: [GameEvent] = []
            demoAccumulator += dt
            while demoAccumulator >= DemoPilot.stepDT {
                demoAccumulator -= DemoPilot.stepDT
                let hold = demoStep < DemoPilot.plan.count ? DemoPilot.plan[demoStep] : demoInput()
                collected += simulation.advance(dt: DemoPilot.stepDT, holding: hold)
                demoStep += 1
            }
            events = collected
        } else {
            events = simulation.advance(dt: dt, holding: holding)
        }
        for event in events {
            switch event {
            case .scored(let points):
                scoreLabel.text = "\(simulation.score)"
                model.score = simulation.score
                popScore(doubled: points > 1)
                // Un muro a ciegas puntúa el doble: cruzarlo con éxito es lo que
                // cuenta para dejar de necesitar el cartel de aviso.
                if points > 1 { settings.blindWallsCrossed += 1 }
                emit(.score)
            case .died:
                shakeRemaining = Tuning.Camera.deathShakeDuration
                emit(.death)
                model.endRun(score: simulation.score,
                             bestPaceMetersPerSecond: Double(simulation.bestPaceMetersPerSecond),
                             settings: settings)
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
                showBlindNoticeIfStillLearning()
                // Se cuenta la zona, no sus muros: lo que se aprende es el paso
                // entero. Es lo que va apagando el eco hasta que no vuelve más.
                settings.blindZonesEntered += 1
            case .exitedBlindZone:
                emit(.blindExit)
            }
        }

        updateDarkness(dt: dt)
        updateAmbience(blind: simulation.isBlind, dt: dt)
        updateSky()
        updateTrail(dt: dt)
        updatePose(dt: dt)
        updateSparks(dt: dt)
        updateBlink(dt: dt)
        updateAura(dt: dt)
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
        // Se relee aquí y no por frame: el ajuste cambia en Ajustes del sistema, no
        // a mitad de una partida.
        reduceMotion = UIAccessibility.isReduceMotionEnabled
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

    // MARK: - Intro

    private var introCompletion: (() -> Void)?

    /// El plano de apertura. iOS no permite launch screens animadas (son una
    /// imagen estática del sistema), así que el movimiento empieza aquí: la
    /// cámara nace pegada a la luciérnaga en la oscuridad y se retira en un
    /// único plano hasta el encuadre del menú, con el ambiente ya vivo detrás.
    /// Un toque lo salta (`skipIntro`).
    func playIntro(completion: @escaping () -> Void) {
        introCompletion = completion
        let body = simulation.body.position
        cameraNode.position = CGPoint(x: body.x, y: body.y + Tuning.Player.radius * 2)
        cameraNode.setScale(0.42)
        let pull = SKAction.group([
            SKAction.scale(to: 1, duration: 1.6),
            SKAction.move(to: cameraBase, duration: 1.6)
        ])
        pull.timingMode = .easeInEaseOut
        cameraNode.run(.sequence([
            .wait(forDuration: 0.4),
            pull,
            .run { [weak self] in self?.finishIntro() }
        ]))
    }

    func skipIntro() {
        guard introCompletion != nil else { return }
        finishIntro()
    }

    /// Tras una interrupción (banner de notificación, llamada) el display link
    /// puede quedarse renegociado a 60 Hz. Re-pedir 120 al volver es gratis.
    func refreshFrameRate() {
        view?.preferredFramesPerSecond = 120
    }

    // MARK: - Pausa por interrupción

    /// El sistema deja de estar activo en plena partida (fondo, notificación a
    /// pantalla completa, llamada, App Switcher). `isPaused` congela las
    /// `SKAction` de ambiente (respiración, parpadeo, deriva del polen) — pero
    /// SpriteKit sigue llamando a `update(_:)` con `isPaused = true` (no lo
    /// detiene), así que la simulación se congela por su cuenta: la guarda de
    /// `update(_:)` deja de avanzarla en cuanto el shell mueve `model.phase` a
    /// `.paused`. Suelta cualquier agarre pendiente para que la partida no
    /// vuelva con el dedo "puesto" sobre una flor que ya no se está tocando.
    func pauseForInterruption() {
        holding = false
        isPaused = true
    }

    /// Solo la llama el botón «Continuar». SKView se reactiva solo al volver a
    /// primer plano (por eso el shell reafirma `isPaused = true` ahí si seguimos
    /// en pausa) — pero nunca reanuda la partida por su cuenta: eso solo pasa
    /// aquí. `lastUpdateTime = nil` descarta el tiempo pasado en pausa para que
    /// el primer frame tras reanudar no devore un `dt` gigante, y `holding =
    /// false` asegura que el toque que soltó «Continuar» no se cuele como un
    /// agarre.
    func resumeFromPause() {
        holding = false
        lastUpdateTime = nil
        isPaused = false
    }

    private func finishIntro() {
        cameraNode.removeAllActions()
        cameraNode.position = cameraBase
        cameraNode.setScale(1)
        let completion = introCompletion
        introCompletion = nil
        completion?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { holding = false }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { holding = false }

    /// Reinicio sin reconstruir la escena: resetear structs y reposicionar nodos
    /// cuesta un frame. Instanciar una `SKScene` nueva se comería el presupuesto
    /// de 300 ms del brief entero.
    private func restart() {
        simulation.reset(seed: Tuning.WorldGen.initialSeed)
        demoStep = 0
        demoAccumulator = 0
        for node in chunkNodes.values { node.removeFromParent() }
        chunkNodes.removeAll()

        holding = false
        lastUpdateTime = nil
        scoreLabel.text = "0"

        darkness = 0
        darknessNode.alpha = 0
        darknessNode.removeAllActions()
        darknessNode.setScale(1)
        proximityBucket = nil
        alignmentBucket = nil
        ambienceBucket = nil
        shakeRemaining = 0
        trailPositions.removeAll()
        trailTimer = 0
        sparkTimer = 0
        // El aura arranca la partida desde la base, sin un pico heredado; su reloj
        // (`auraTime`) NO se resetea: la luz sigue viva sin costura entre menú y run.
        haloPulse = 0
        playerNode.removeAllActions()
        playerNode.xScale = 1
        playerNode.yScale = 1
        // La pose vuelve a reposo: erguida, quieta y sin estirar. Si no, el menú
        // heredaría la última pose de la muerte anterior — y el muelle arrancaría la
        // partida nueva con la velocidad angular con la que se estrelló.
        poseAngle = 0
        poseAngularVelocity = 0
        bodyGroup.zRotation = 0
        bodyGroup.xScale = 1
        bodyGroup.yScale = 1
        let haptics = self.haptics
        Task { await haptics.stopContinuous() }

        syncWorld()
        cameraBase = CameraController.target(for: simulation.body.position)
        cameraNode.position = cameraBase
    }

    // MARK: - Game feel

    /// La cola del cometa: nodos reutilizados que se recolocan sobre posiciones
    /// pasadas. Un `SKEmitterNode` daría más humo, pero también un rastro que no
    /// sigue exactamente el arco — y aquí el arco es la información.
    ///
    /// Nacen del propio cuerpo (la marca 0 se pinta encima del jugador, ancha) y se
    /// estrechan hacia atrás, que es lo que convierte un rastro de puntos en una
    /// cola. Misma textura difusa que la bola: círculos planos dejaban un canto duro
    /// que a velocidad alta se leía como un collar de cuentas.
    private func buildTrail() {
        for index in 0..<Tuning.Feel.trailNodeCount {
            let side = Effects.trailRadius(index: index) * 2 / Tuning.Scenery.bodyEdgeFade
            let node = SKSpriteNode(texture: lightTexture,
                                    size: CGSize(width: side, height: side))
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

        // La estela ES el velocímetro: no hay HUD de velocidad (spec §3), así que lo
        // único que dice "vas rápido" es cuánto rastro dejas. Con Reduce Motion se
        // atenúa, no desaparece: sigue siendo información.
        let speedFactor = clamp(simulation.body.velocity.length / Tuning.Pendulum.maxSpeed, 0, 1)
        let strength = lerp(0.35, 1, speedFactor) * (reduceMotion ? 0.5 : 1)

        // La marca 0 se pinta sobre la última posición muestreada, es decir sobre el
        // cuerpo: la cola nace de la bola en vez de empezar un paso por detrás, que
        // es lo que la desprendía del personaje.
        for (index, node) in trailNodes.enumerated() {
            guard index < trailPositions.count else {
                node.alpha = 0
                continue
            }
            node.position = trailPositions[index]
            node.alpha = Effects.trailAlpha(index: index) * strength
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
        // Antes conmutaba en el instante de cruzar el muro: ahora la rampa sigue
        // la distancia al muro de entrada, así que la noche se ve venir en vez de
        // caer encima.
        let target = simulation.blindZoneTelegraph
        let rate = 1 / Tuning.BlindZone.darkenDuration
        darkness = lerp(darkness, target, 1 - exponentialDecay(rate: rate, dt: dt))

        let peak = settings.reduceFlashing
            ? Tuning.BlindZone.reducedDarkAlpha
            : Tuning.BlindZone.darkAlpha
        darknessNode.alpha = darkness * peak
    }

    /// Traduce «estoy a ciegas» a volumen de ambiente. Escalonado como el mapa
    /// háptico: durante un fundido son décimas de segundo a 120 fps, y el motor no
    /// necesita enterarse de cada frame.
    private func updateAmbience(blind: Bool, dt: CGFloat) {
        ambience.update(blind: blind, dt: dt)
        let bucket = Int(ambience.gain / Tuning.Ambience.gainUpdateQuantum)
        guard bucket != ambienceBucket else { return }
        ambienceBucket = bucket
        let haptics = self.haptics
        let gain = ambience.gain
        Task { await haptics.setAmbience(gain: gain) }
    }

    /// Con qué opacidad se dibuja ahora mismo el eco de los muros invisibles.
    ///
    /// Tres factores: cuántas zonas a ciegas lleva vividas el jugador (la
    /// enseñanza, que se retira sola), lo cerrado que está el velo (el eco entra
    /// justo según se apaga el muro real, nunca encima de él) y el latido.
    ///
    /// El latido se lee del propio halo, que ya oscila al ritmo del pulso háptico
    /// de proximidad en `updateBlink`. Es la mitad de la enseñanza: ver el muro
    /// latir mientras se siente el pulso en el dedo es lo que ata una cosa a la
    /// otra, y leerlo de la misma fuente hace imposible que se desincronicen.
    private var blindEchoAlpha: CGFloat {
        // El contador sube al ENTRAR en la zona, así que mientras se vive una, la
        // que se está viviendo es la anterior a la cuenta.
        let lived = simulation.isBlind
            ? settings.blindZonesEntered - 1
            : settings.blindZonesEntered
        let base = BlindZones.ghostAlpha(zonesExperienced: lived)
        guard base > 0 else { return 0 }

        let span = Tuning.Scenery.haloBrightAlpha - Tuning.Scenery.haloDimAlpha
        let beat = clamp((haloNode.alpha - Tuning.Scenery.haloDimAlpha) / span, 0, 1)
        return base * darkness * lerp(Tuning.BlindTeaching.pulseFloor, 1, beat)
    }

    /// Se repite en cada zona nueva mientras el jugador no lleve suficientes
    /// muros a ciegas cruzados con éxito (`Tuning.BlindZone.noticeThreshold`):
    /// una sola vez por instalación era demasiado poco para que la mecánica se
    /// aprendiera de verdad, y para siempre habría sido ruido.
    private func showBlindNoticeIfStillLearning() {
        guard settings.needsBlindNotice else { return }

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
    ///
    /// El OR ya no decide qué canal suena —eso hacía que apagar los hápticos con el
    /// sonido encendido siguiera vibrando—: hoy es solo un atajo para no cruzar al
    /// actor cuando los dos canales están apagados. Quien filtra hápticos y audio por
    /// separado es el motor, que es también quien gobierna el bucle de proximidad y
    /// la textura de alineación (`setChannels`, empujado desde `RootView`).
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

        let echoAlpha = blindEchoAlpha
        for chunk in simulation.chunks where chunk.isBlind {
            chunkNodes[chunk.index]?
                .childNode(withName: Self.wallsNodeName)?
                .alpha = wallAlpha(for: chunk)
            chunkNodes[chunk.index]?
                .childNode(withName: Self.echoNodeName)?
                .alpha = echoAlpha
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
        // El segmento de abajo da al hueco por su canto superior; el de arriba, por
        // el inferior. `makeTrunk` necesita saberlo para poner el muñón de rama en
        // el lado correcto.
        let gapFacesTop = [true, false]
        var silhouettes: [CGPath] = []
        for (index, (bottom, top)) in segments.enumerated() where top > bottom {
            let trunk = makeTrunk(rect: CGRect(x: wall.x - thickness / 2,
                                               y: bottom,
                                               width: thickness,
                                               height: top - bottom),
                                  gapFacesTop: gapFacesTop[index],
                                  rng: &rng)
            walls.addChild(trunk.node)
            silhouettes.append(trunk.silhouette)
        }

        // Musgo lunar en los dos bordes del hueco. Señala la **puerta**, no la pared:
        // el ojo se va a donde hay que ir. Crece hacia dentro del tronco —nunca
        // hacia el hueco—, con un canto irregular y un par de matas colgando.
        let minX = wall.x - thickness / 2
        let maxX = wall.x + thickness / 2
        for (edgeY, intoTrunk) in [(wall.gapBottomY, CGFloat(1)), (wall.gapTopY, CGFloat(-1))] {
            walls.addChild(makeMossLip(edgeY: edgeY, minX: minX, maxX: maxX,
                                       intoTrunk: intoTrunk, rng: &rng))
        }
        walls.alpha = wallAlpha(for: chunk)
        container.addChild(walls)

        // El eco: la misma silueta del tronco —la que mata—, en frío y por encima
        // del velo, mientras el juego aún está enseñando la mecánica a ciegas. No
        // cuelga de `walls` a propósito: ese nodo se apaga con la oscuridad, y el
        // eco tiene que hacer justo lo contrario.
        if chunk.isBlind, !silhouettes.isEmpty {
            let echo = SKNode()
            echo.name = Self.echoNodeName
            echo.zPosition = Self.echoZPosition
            echo.alpha = 0
            for silhouette in silhouettes {
                let shape = SKShapeNode(path: silhouette)
                shape.fillColor = Palette.blindEcho
                shape.strokeColor = .clear
                echo.addChild(shape)
            }
            container.addChild(echo)
        }

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

    /// Un tronco tallado, no una barra.
    ///
    /// Todo el dibujo cae **dentro** del rectángulo de colisión: la silueta muerde
    /// hacia dentro con muescas de corteza, el canto iluminado sigue ese mismo borde
    /// irregular, y el muñón de rama y los nudos son masa que ya estaba ahí, nunca
    /// añadida fuera. Lo que se ve tiene que ser exactamente lo que mata (pilar 2 del
    /// GDD): la decoración solo puede quitar superficie, jamás añadirla.
    ///
    /// Devuelve también esa silueta: es lo que dibuja el eco de aprendizaje de las
    /// zonas a ciegas, y tiene que ser exactamente la misma forma, no una
    /// aproximación rectangular.
    private func makeTrunk(rect: CGRect, gapFacesTop: Bool,
                           rng: inout SplitMix64) -> (node: SKNode, silhouette: CGPath) {
        let node = SKNode()

        // Los dos cantos verticales, tallados con muescas deterministas por chunk.
        let leftEdge = carvedEdge(x: rect.minX, from: rect.minY, to: rect.maxY, inward: 1, rng: &rng)
        let rightEdge = carvedEdge(x: rect.maxX, from: rect.maxY, to: rect.minY, inward: -1, rng: &rng)

        let bodyPath = CGMutablePath()
        bodyPath.move(to: leftEdge[0])
        for point in leftEdge.dropFirst() { bodyPath.addLine(to: point) }
        for point in rightEdge { bodyPath.addLine(to: point) }
        bodyPath.closeSubpath()

        let body = SKShapeNode(path: bodyPath)
        body.fillColor = Palette.trunk
        body.strokeColor = Palette.trunkEdge
        body.lineWidth = 2
        body.lineJoin = .round
        node.addChild(body)

        // El canto que mira a la luna sigue el mismo borde tallado que el cuerpo,
        // no un rectángulo limpio — es la misma corteza, solo que iluminada.
        let litWidth = rect.width * Tuning.Scenery.trunkLitWidthFraction
        let litEdge = leftEdge.map { CGPoint(x: $0.x + 2, y: $0.y) }
        let litPath = CGMutablePath()
        litPath.move(to: litEdge[0])
        for point in litEdge.dropFirst() { litPath.addLine(to: point) }
        litPath.addLine(to: CGPoint(x: rect.minX + litWidth, y: rect.maxY))
        litPath.addLine(to: CGPoint(x: rect.minX + litWidth, y: rect.minY))
        litPath.closeSubpath()
        let lit = SKShapeNode(path: litPath)
        lit.fillColor = Palette.trunkLit
        lit.strokeColor = .clear
        lit.alpha = 0.75
        node.addChild(lit)

        // Nudos de corteza: marcas deterministas, siempre bien dentro del cuerpo.
        for _ in 0..<Tuning.Scenery.trunkKnotCount {
            let knot = SKShapeNode(circleOfRadius: rng.nextCGFloat(in: 3...6))
            knot.position = CGPoint(x: rng.nextCGFloat(in: (rect.minX + litWidth + 6)...(rect.maxX - 8)),
                                    y: rng.nextCGFloat(in: (rect.minY + 14)...(rect.maxY - 14)))
            knot.fillColor = Palette.bark
            knot.strokeColor = .clear
            knot.alpha = 0.6
            node.addChild(knot)
        }

        // Vetas: líneas verticales quebradas, con la semilla del chunk para que el
        // mismo tronco tenga siempre la misma corteza.
        for _ in 0..<3 {
            let path = CGMutablePath()
            let x = rng.nextCGFloat(in: (rect.minX + litWidth + 4)...(rect.maxX - 8))
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

        // Muñón de rama, hacia dentro, cerca del hueco: la puerta no es un corte
        // limpio, es donde el árbol perdió una rama. Nunca cruza el canto del hueco.
        let gapY = gapFacesTop ? rect.maxY : rect.minY
        let stumpSign: CGFloat = gapFacesTop ? -1 : 1
        let stumpY = gapY + stumpSign * min(Tuning.Scenery.trunkStumpMargin, rect.height * 0.3)
        let stumpBase = rect.minX + litWidth + 6
        let stumpLength = rect.width * 0.24
        let stump = SKShapeNode(rect: CGRect(x: stumpBase, y: stumpY - 4, width: stumpLength, height: 8),
                                cornerRadius: 3)
        stump.fillColor = Palette.bark
        stump.strokeColor = .clear
        stump.alpha = 0.8
        node.addChild(stump)
        let stumpCap = SKShapeNode(circleOfRadius: 5)
        stumpCap.position = CGPoint(x: stumpBase + stumpLength, y: stumpY)
        stumpCap.fillColor = Palette.trunkLit
        stumpCap.strokeColor = .clear
        stumpCap.alpha = 0.55
        node.addChild(stumpCap)

        return (node, bodyPath)
    }

    /// Puntos de un canto vertical del tronco, con muescas de corteza que muerden
    /// **hacia dentro** (`inward` es el signo hacia el centro del tronco) a
    /// intervalos deterministas. Nunca se sale de `x`, así que la silueta resultante
    /// siempre cabe dentro del rectángulo de colisión original.
    private func carvedEdge(x: CGFloat, from yStart: CGFloat, to yEnd: CGFloat,
                            inward: CGFloat, rng: inout SplitMix64) -> [CGPoint] {
        var points = [CGPoint(x: x, y: yStart)]
        let length = abs(yEnd - yStart)
        let direction: CGFloat = yEnd > yStart ? 1 : -1
        let notchCount = max(2, Int(length / Tuning.Scenery.trunkNotchSpacing))
        let step = length / CGFloat(notchCount)
        var y = yStart
        for _ in 0..<notchCount {
            let notchY = y + direction * step * rng.nextCGFloat(in: 0.35...0.65)
            let depth = rng.nextCGFloat(in: Tuning.Scenery.trunkNotchDepthMin...Tuning.Scenery.trunkNotchDepthMax)
            points.append(CGPoint(x: x, y: notchY - direction * step * 0.15))
            points.append(CGPoint(x: x + inward * depth, y: notchY))
            points.append(CGPoint(x: x, y: notchY + direction * step * 0.15))
            y += direction * step
        }
        points.append(CGPoint(x: x, y: yEnd))
        return points
    }

    /// El labio de musgo de un borde del hueco: un canto recto justo en `edgeY`
    /// (nunca lo cruza, para no asomar mole opaca al hueco) con un relieve
    /// irregular que muerde hacia dentro del tronco, más un par de matas colgando.
    /// Solo el `glowWidth` —difuminado, no masa— puede leerse fuera de `edgeY`.
    private func makeMossLip(edgeY: CGFloat, minX: CGFloat, maxX: CGFloat,
                             intoTrunk: CGFloat, rng: inout SplitMix64) -> SKNode {
        let node = SKNode()
        let width = maxX - minX
        let segments = 4
        let step = width / CGFloat(segments)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: minX, y: edgeY))
        for index in 0..<segments {
            let depth = rng.nextCGFloat(in: (Self.mossThickness * 0.5)...(Self.mossThickness * 1.5))
            let x0 = minX + CGFloat(index) * step
            let x1 = x0 + step
            path.addQuadCurve(to: CGPoint(x: x1, y: edgeY - intoTrunk * depth),
                              control: CGPoint(x: x0 + step / 2, y: edgeY - intoTrunk * depth))
        }
        path.addLine(to: CGPoint(x: maxX, y: edgeY))
        path.closeSubpath()

        let lip = SKShapeNode(path: path)
        lip.fillColor = Palette.moss
        lip.strokeColor = .clear
        lip.alpha = 0.8
        lip.glowWidth = 4
        node.addChild(lip)

        // 2-3 matas colgando, siempre hacia dentro del grosor del tronco.
        let tuftCount = Int(rng.nextCGFloat(in: 2...3.99))
        for _ in 0..<tuftCount {
            let tx = rng.nextCGFloat(in: (minX + 6)...(maxX - 6))
            let length = rng.nextCGFloat(in: (Self.mossThickness * 1.5)...(Self.mossThickness * 3))
            let tuftPath = CGMutablePath()
            tuftPath.move(to: CGPoint(x: tx, y: edgeY))
            tuftPath.addQuadCurve(to: CGPoint(x: tx + rng.nextCGFloat(in: -4...4),
                                              y: edgeY - intoTrunk * length),
                                  control: CGPoint(x: tx + rng.nextCGFloat(in: -3...3),
                                                   y: edgeY - intoTrunk * length * 0.5))
            let tuft = SKShapeNode(path: tuftPath)
            tuft.strokeColor = Palette.moss
            tuft.lineWidth = 2.5
            tuft.alpha = 0.7
            node.addChild(tuft)
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
    private static let echoNodeName = "echo"
    private static let mossThickness: CGFloat = 10
    /// Cuánto cuelga la liana por cada punto de holgura.
    private static let ropeSagFactor: CGFloat = 0.9
    private static let lightZPosition: CGFloat = 20
    /// Justo por encima del velo (10) y por debajo de las luces (20): el eco tiene
    /// que atravesar la oscuridad, pero nunca taparle nada a Lumi ni a las flores.
    private static let echoZPosition: CGFloat = 11

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

    /// Las losas de suelo y techo, con el borde que mira al área jugable tallado
    /// hacia dentro (F6) en vez de un canto recto: era eso, y no el letterboxing,
    /// lo que se leía como una banda muerta entrando entera en pantalla con
    /// `.aspectFill`. La hitbox (`floorY`/`ceilingY`) no cambia — el tallado solo
    /// resta superficie, nunca la añade (pilar 2 del GDD).
    private func buildBounds() {
        var floorRng = SplitMix64(seed: 0x6F_00_D0)
        var ceilingRng = SplitMix64(seed: 0xCE_11_60)

        // Desde x negativa: la cámara del menú enseña ~50 u antes del origen y
        // las losas cortadas en x=0 dejaban un canto feo a la izquierda.
        let leadIn: CGFloat = 600
        let floorRect = CGRect(x: -leadIn,
                               y: Tuning.World.floorY - Tuning.World.boundsThickness,
                               width: Tuning.World.worldLength + leadIn,
                               height: Tuning.World.boundsThickness)
        let floorEdge = carvedGroundEdge(y: Tuning.World.floorY,
                                         from: floorRect.minX, to: floorRect.maxX,
                                         inward: -1, rng: &floorRng)
        let floorPath = CGMutablePath()
        floorPath.move(to: CGPoint(x: floorRect.minX, y: floorRect.minY))
        floorPath.addLine(to: CGPoint(x: floorRect.maxX, y: floorRect.minY))
        for point in floorEdge.reversed() { floorPath.addLine(to: point) }
        floorPath.closeSubpath()
        addBoundsSlab(path: floorPath, color: Palette.groundSlab)

        let ceilingRect = CGRect(x: -leadIn,
                                 y: Tuning.World.ceilingY,
                                 width: Tuning.World.worldLength + leadIn,
                                 height: Tuning.World.boundsThickness)
        let ceilingEdge = carvedGroundEdge(y: Tuning.World.ceilingY,
                                           from: ceilingRect.minX, to: ceilingRect.maxX,
                                           inward: 1, rng: &ceilingRng)
        let ceilingPath = CGMutablePath()
        ceilingPath.move(to: CGPoint(x: ceilingRect.minX, y: ceilingRect.maxY))
        ceilingPath.addLine(to: CGPoint(x: ceilingRect.maxX, y: ceilingRect.maxY))
        for point in ceilingEdge.reversed() { ceilingPath.addLine(to: point) }
        ceilingPath.closeSubpath()
        addBoundsSlab(path: ceilingPath, color: Palette.canopySlab)
    }

    private func addBoundsSlab(path: CGPath, color: SKColor) {
        let node = SKShapeNode(path: path)
        node.fillColor = color
        node.strokeColor = Palette.trunkEdge
        node.lineWidth = 2
        worldNode.addChild(node)
    }

    /// El borde horizontal de una losa (suelo o techo), tallado hacia dentro con
    /// la misma idea que `carvedEdge` del tronco: nunca cruza `y`, así que la
    /// hitbox queda intacta y el tallado es puro recorte. `inward` es el signo
    /// hacia el interior de la losa (−1 hacia abajo para el suelo, +1 hacia
    /// arriba para el techo).
    private func carvedGroundEdge(y: CGFloat, from xStart: CGFloat, to xEnd: CGFloat,
                                  inward: CGFloat, rng: inout SplitMix64) -> [CGPoint] {
        var points = [CGPoint(x: xStart, y: y)]
        let length = xEnd - xStart
        let notchCount = max(2, Int(length / Tuning.Scenery.boundsEdgeSpacing))
        let step = length / CGFloat(notchCount)
        var x = xStart
        for _ in 0..<notchCount {
            let notchX = x + step * rng.nextCGFloat(in: 0.35...0.65)
            let depth = rng.nextCGFloat(in: Tuning.Scenery.boundsEdgeDepthMin...Tuning.Scenery.boundsEdgeDepthMax)
            points.append(CGPoint(x: notchX - step * 0.15, y: y))
            points.append(CGPoint(x: notchX, y: y + inward * depth))
            points.append(CGPoint(x: notchX + step * 0.15, y: y))
            x += step
        }
        points.append(CGPoint(x: xEnd, y: y))
        return points
    }
}
