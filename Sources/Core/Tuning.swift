import CoreGraphics

/// Todos los números del juego viven aquí. Un literal numérico suelto en lógica
/// de juego es un bug de disciplina, no una optimización.
///
/// Los valores iniciales son un punto de partida razonado, no medido: no hubo
/// prototipo web del que extraerlos (ver D-001 en docs/decisiones.md). Se ajustan
/// jugando, y cada ajuste debe tener una razón perceptual, no estética.
enum Tuning {

    // MARK: - Mundo

    enum World {
        /// La escena mide siempre lo mismo en puntos de juego, independientemente
        /// del iPhone. Ratio 900:1950 ≈ 2,167, casi idéntico al de un iPhone
        /// moderno (393:852), así que con `.aspectFill` apenas se recorta nada.
        static let sceneWidth: CGFloat = 900
        static let sceneHeight: CGFloat = 1950

        /// Franja jugable, centrada verticalmente. Es lo que garantizamos idéntico
        /// en todos los dispositivos: en un iPhone SE (ratio 1,78) `.aspectFill`
        /// deja ver ~1600 pt de alto, suficiente para cubrir estos 1500. Lo que
        /// sobra por arriba y por abajo es decoración, nunca juego.
        static let playfieldHeight: CGFloat = 1500
        static let floorY: CGFloat = (sceneHeight - playfieldHeight) / 2   // 225
        static let ceilingY: CGFloat = floorY + playfieldHeight            // 1725

        /// Grosor visual del muro. También su grosor de colisión: lo que se ve es
        /// lo que mata.
        static let wallThickness: CGFloat = 46

        /// Grosor de las barras de suelo y techo, y radio del farol de un ancla.
        static let boundsThickness: CGFloat = 80
        static let anchorRadius: CGFloat = 14

        /// Longitud de las barras de suelo y techo. Un run largo son ~50 muros a
        /// ~500 pt: 200.000 pt es holgura de sobra, y son dos nodos en vez de cien.
        static let worldLength: CGFloat = 200_000
    }

    // MARK: - Jugador

    enum Player {
        /// Radio de colisión del farolillo. Con hueco mínimo de 190 pt deja
        /// 69 pt de margen a cada lado: apretado pero no injusto.
        static let radius: CGFloat = 26

        static let startX: CGFloat = 200
        static let startY: CGFloat = World.sceneHeight / 2

        /// Velocidad de entrada. Hacia arriba y a la derecha, para que el primer
        /// gesto natural sea agarrarse a la primera ancla en lo alto del arco.
        static let initialVelocityX: CGFloat = 520
        static let initialVelocityY: CGFloat = 100
    }

    // MARK: - Física del péndulo

    enum Pendulum {
        /// Gravedad alta a propósito, para el peso del pilar 4 del GDD: con 1200 el
        /// farolillo flota y el arco se siente de gelatina.
        ///
        /// Bajada de 2800 a 2000 tras la primera medición real (S2): con 2800 el
        /// farolillo recorría los 1500 pt del playfield en 0,73 s, o sea que tocaba
        /// suelo antes de alcanzar el primer muro. A 2000 la caída completa dura
        /// 1,22 s y el medio arco con cuerda de 320 pt queda en 1,26 s — sigue
        /// siendo un péndulo con masa, pero deja tiempo para leer el mundo.
        static let gravity: CGFloat = 2000

        /// Tope de velocidad. Por encima, el jugador no puede reaccionar al muro
        /// siguiente y la muerte se vuelve ilegible (pilar 2).
        static let maxSpeed: CGFloat = 1500

        /// La cuerda toma la distancia real al ancla en el instante del agarre,
        /// acotada a este rango. Con L=320 pt y g=2800 el periodo es 2,12 s, o sea
        /// ~1,06 s por medio arco: justo lo que cuesta cruzar un chunk. Ese encaje
        /// entre ritmo del péndulo y ritmo del mundo es lo que hace que el juego
        /// se sienta cadencioso en vez de frenético.
        static let minRopeLength: CGFloat = 220
        static let maxRopeLength: CGFloat = 420

        /// Radio de búsqueda de ancla al pulsar. Igual a la cuerda máxima: si algo
        /// está a distancia agarrable, es agarrable.
        static let grabRadius: CGFloat = 430

        /// Penalización de distancia para anclas que quedan por detrás del jugador.
        /// Su distancia efectiva se multiplica por (1 + este valor), así que ante
        /// dos anclas equidistantes gana siempre la de delante. Sin esto el jugador
        /// se queda enganchado hacia atrás y pierde el avance, que es el fallo de
        /// game feel más común en juegos de swing.
        static let backwardAnchorPenalty: CGFloat = 0.55

        /// Aceleración tangencial mientras se mantiene pulsado, en la dirección en
        /// la que ya se mueve. Es el "bombeo": la única forma de ganar energía.
        static let tangentialPump: CGFloat = 1500
        static let maxTangentialSpeed: CGFloat = 1500

        /// Pequeño impulso extra al soltar. 1,0 se siente romo; por encima de 1,15
        /// el jugador sale disparado y pierde el control.
        static let releaseBoost: CGFloat = 1.06

        /// Arrastre exponencial (1/s): v *= exp(-drag * dt).
        /// En el aire se frena más que colgado, para que colgarse conserve la
        /// energía y el jugador sienta que la cuerda le "guarda" la inercia.
        static let airDrag: CGFloat = 0.35
        static let ropeDrag: CGFloat = 0.10

        /// Subpaso fijo de integración. La simulación avanza siempre en pasos de
        /// este tamaño, sin importar el frame rate: es lo que hace que el juego se
        /// comporte igual a 60 y a 120 Hz, y lo que hace la física testeable.
        static let physicsStep: CGFloat = 1.0 / 240.0

        /// Techo de delta por frame. Tras un hipo del sistema, mejor ir a
        /// cámara lenta un instante que teletransportar al jugador dentro de un muro.
        static let maxFrameDelta: CGFloat = 1.0 / 20.0
    }

    // MARK: - Cámara

    enum Camera {
        /// Cuánto se adelanta la cámara, en fracción del ancho de escena. En
        /// portrait el ancho visible es escaso: esto es lo que compra anticipación
        /// (ver D-003). Subirlo mucho deja al jugador pegado al borde izquierdo.
        static let lookAheadFactor: CGFloat = 0.22

        /// Seguimiento vertical parcial. A 1,0 la cámara persigue cada oscilación
        /// y marea; a 0,0 el jugador se sale por arriba. 0,35 mantiene el horizonte
        /// como referencia estable.
        static let verticalFollow: CGFloat = 0.35

        /// Suavizado exponencial (1/s). Más alto = cámara más pegada y nerviosa.
        static let smoothing: CGFloat = 12.0

        static let deathShakeAmplitude: CGFloat = 22
        static let deathShakeDuration: CGFloat = 0.35
    }

    // MARK: - Generación del mundo y dificultad

    enum WorldGen {
        static let firstWallX: CGFloat = 900

        /// Espaciado entre muros: rampa lineal desde `spacingStart` hasta
        /// `spacingFloor`, empezando a apretar en el muro `rampStartWall`.
        /// Rampa y no escalones: un salto brusco de dificultad se lee como
        /// injusticia, aunque los valores sean idénticos en media.
        static let spacingStart: CGFloat = 560
        static let spacingFloor: CGFloat = 440
        static let spacingDecayPerWall: CGFloat = 4.0

        /// Alto del hueco, misma forma de rampa.
        static let gapStart: CGFloat = 240
        static let gapFloor: CGFloat = 190
        static let gapDecayPerWall: CGFloat = 1.3

        /// El muro a partir del cual la dificultad empieza a subir. Los 10
        /// primeros son el tutorial silencioso del GDD.
        static let rampStartWall: Int = 10

        /// Bonificación de alto de hueco en zona a ciegas. La ceguera ya es la
        /// dificultad; exigir además precisión sería sumar dos castigos.
        static let blindGapBonus: CGFloat = 100

        /// Anclas por chunk. A partir de `singleAnchorFromWall` hay una
        /// probabilidad de que solo haya una, lo que fuerza a planear el arco.
        static let anchorsPerChunk: Int = 2
        static let singleAnchorFromWall: Int = 29
        static let singleAnchorChance: CGFloat = 0.25

        /// Las anclas cuelgan por encima del jugador: el farolillo se balancea por
        /// debajo, como un péndulo real.
        ///
        /// La franja se estrechó de [900, 1600] a [1050, 1450] al medir que un ancla
        /// a 1600 queda a más de `grabRadius` de la altura a la que vuela el jugador:
        /// era inalcanzable, y el mundo generaba tramos sin asidero. Con este rango y
        /// una cuerda de 220–420 pt, el farolillo oscila entre y≈630 y y≈1230, bien
        /// centrado en el playfield.
        static let anchorMinY: CGFloat = 1050
        static let anchorMaxY: CGFloat = 1450

        /// El hueco del primer muro se abre a la altura a la que arranca el jugador,
        /// no en cualquier punto del playfield. El GDD promete diez muros de tutorial
        /// silencioso: sortear el primer hueco 700 pt por encima o por debajo del
        /// punto de partida es lo contrario de un tutorial.
        static let firstGapVerticalSpread: CGFloat = 120

        /// El primer farol siempre está al alcance desde el punto de partida.
        /// El arranque no es sitio para poner a prueba la suerte del jugador: la
        /// distancia máxima que permiten estos rangos es 397 pt, por debajo de los
        /// 430 de `grabRadius`.
        static let firstAnchorMinOffsetX: CGFloat = 150
        static let firstAnchorMaxOffsetX: CGFloat = 300
        static let firstAnchorMinOffsetY: CGFloat = 100
        static let firstAnchorMaxOffsetY: CGFloat = 260

        /// Separación mínima entre las dos anclas de un chunk, y separación mínima
        /// de cada ancla respecto a los muros que delimitan el chunk.
        /// Están calibradas contra `spacingFloor` (440): 440 − 2·110 = 220 ≥ 200,
        /// así que incluso en el tramo más apretado siguen cabiendo dos anclas.
        /// Si subes cualquiera de las dos, los chunks tardíos se quedarán con una
        /// sola ancla sin que nadie lo haya decidido.
        static let anchorMinSeparationX: CGFloat = 200
        static let anchorWallClearance: CGFloat = 110

        /// Margen mínimo entre el hueco y suelo/techo, para que nunca haya un
        /// hueco pegado al borde en el que sea imposible entrar en ángulo.
        static let gapEdgeMargin: CGFloat = 180

        /// Ventana de chunks materializados: el actual y tres por delante.
        static let liveChunkCount: Int = 4

        /// Semilla del mundo mientras se tunea: fija, para que dos runs seguidos
        /// sean comparables. En S6 pasa a ser aleatoria por partida.
        static let initialSeed: UInt64 = 0xC0FFEE
    }

    // MARK: - Zonas a ciegas

    enum BlindZone {
        /// La primera llega en el muro 11: lo bastante tarde para haber aprendido
        /// a balancearse, lo bastante pronto para que la mecánica firma no quede
        /// escondida tras dos minutos de juego.
        static let firstWall: Int = 11
        static let period: Int = 12
        static let durationStart: Int = 3
        static let durationMax: Int = 6
        /// Cada cuántas zonas se alarga en un muro.
        static let durationGrowthEvery: Int = 2

        /// Multiplicador de puntuación dentro de la zona.
        static let scoreMultiplier: Int = 2

        static let darkenDuration: CGFloat = 0.8
        static let darkAlpha: CGFloat = 0.96
        /// Con «reducir parpadeos», el contraste entre ver y no ver se suaviza.
        /// Sigue siendo penumbra —la mecánica no se toca—, pero el salto de
        /// luminancia deja de ser agresivo.
        static let reducedDarkAlpha: CGFloat = 0.72
        /// Opacidad del contorno de los muros con el refuerzo visual asistido
        /// (sin Taptic Engine o con hápticos apagados).
        static let assistedOutlineAlpha: CGFloat = 0.12
    }

    // MARK: - Háptica
    //
    // La spec completa y el porqué de cada valor están en docs/lenguaje-haptico.md.
    // Este bloque es su traducción literal a código; si cambias algo aquí,
    // actualiza el documento (hay un test que compara ambos).

    enum Haptics {
        /// Más allá de esta distancia, silencio. El silencio también informa.
        static let proximityRange: CGFloat = 900

        static let proximityIntervalNear: CGFloat = 0.06
        static let proximityIntervalFar: CGFloat = 0.60
        /// Exponente de la curva de cadencia. Comprime el rango lejano y expande
        /// el cercano, de modo que la urgencia se siente en los últimos 300 pt.
        /// Con 1,0 la rampa es lineal y el jugador se estrella antes de notarla.
        static let proximityCurveExponent: CGFloat = 1.35

        static let proximityIntensityNear: CGFloat = 1.00
        static let proximityIntensityFar: CGFloat = 0.35
        /// Sharpness alta en todo el rango: el pulso debe ser seco y puntual, para
        /// no confundirse nunca con la textura continua de alineación.
        static let proximitySharpnessNear: CGFloat = 1.00
        static let proximitySharpnessFar: CGFloat = 0.75

        /// Alineación: textura sorda que existe SOLO si el jugador cabe por el
        /// hueco. Desalineado = silencio táctil (decisión D-005).
        static let alignSharpness: CGFloat = 0.12
        static let alignIntensityLow: CGFloat = 0.16
        static let alignIntensityHigh: CGFloat = 0.34
        /// Margen libre a partir del cual la textura llega a intensidad plena.
        /// Es lo que convierte un binario en un matiz: apenas perceptible =
        /// "pasas rozando", plena = "vas centrado".
        static let alignClearanceSpan: CGFloat = 90

        static let grabIntensity: CGFloat = 0.85
        static let grabSharpness: CGFloat = 1.00

        static let releaseIntensity: CGFloat = 0.45
        static let releaseSharpness: CGFloat = 0.25

        static let scoreIntensity: CGFloat = 0.40
        static let scoreSharpness: CGFloat = 0.65

        static let deathIntensity: CGFloat = 1.00
        static let deathSharpness: CGFloat = 0.90
        static let deathDecayDuration: CGFloat = 0.28
        static let deathDecayIntensity: CGFloat = 0.60
        static let deathDecaySharpness: CGFloat = 0.30

        /// Dos golpes separados: un patrón rítmico que no existe en ninguna otra
        /// señal del vocabulario, así que es imposible confundirlo.
        static let blindEnterIntensity: CGFloat = 0.70
        static let blindEnterSharpness: CGFloat = 0.40
        static let blindEnterGap: CGFloat = 0.12

        /// El único patrón ascendente del idioma: alivio.
        static let blindExitIntensity: CGFloat = 0.60
        static let blindExitSharpness: CGFloat = 0.70
        static let blindExitRampDuration: CGFloat = 0.18
        static let blindExitRampFrom: CGFloat = 0.15
        static let blindExitRampTo: CGFloat = 0.40

        /// Techo de intensidad simultánea. Si un evento coincide con proximidad a
        /// tope, el evento gana y ese pulso de proximidad se OMITE (no se atenúa:
        /// atenuarlo rompería la lectura del ritmo, que es la información).
        static let maxSimultaneousIntensity: CGFloat = 1.3

        /// Cada cuántos puntos de movimiento se le vuelve a hablar al motor. A
        /// 120 fps, una actualización por frame son 120 tareas por segundo cruzando
        /// la frontera del actor para decir prácticamente lo mismo. Con estos
        /// escalones el ritmo sigue siendo continuo al tacto y el motor recibe una
        /// fracción de los mensajes.
        static let proximityUpdateQuantum: CGFloat = 20
        static let alignmentUpdateQuantum: CGFloat = 15
    }

    // MARK: - Audio (refuerzo, y sustituto donde no hay Taptic)

    enum Audio {
        static let proximityClickFrequency: CGFloat = 1200
        static let proximityClickDuration: CGFloat = 0.018

        static let alignToneFrequency: CGFloat = 660
        /// −24 dB. El audio acompaña; si se oye por encima de la música del
        /// jugador, molesta.
        static let alignToneGain: CGFloat = 0.063

        static let scoreBlipFrequency: CGFloat = 880
        static let grabClickFrequency: CGFloat = 1600
        static let releaseThudFrequency: CGFloat = 220
        static let deathSweepDuration: CGFloat = 0.30

        /// Ganancia global cuando el audio es refuerzo (hay hápticos) frente a
        /// cuando es sustituto (no hay). Sustituyendo tiene que oírse de verdad.
        static let reinforcementGain: CGFloat = 0.45
        static let substituteGain: CGFloat = 1.0
    }

    // MARK: - HUD dentro de la escena
    //
    // El marcador es parte del juego, no del shell: vive en la escena y viaja con
    // la cámara. Los menús de SwiftUI llegan en S6.

    enum HUD {
        static let scoreFontSize: CGFloat = 120
        static let deathFontSize: CGFloat = 64
        /// Desplazamientos respecto al centro de la cámara.
        static let scoreOffsetY: CGFloat = 760
        static let deathOffsetY: CGFloat = -160
        static let blindNoticeOffsetY: CGFloat = 420
        /// Cuánto dura el cartel que explica las zonas a ciegas la primera vez.
        static let blindNoticeDuration: CGFloat = 2.2
    }

    // MARK: - Game feel

    enum Feel {
        /// Al agarrarse, el farolillo se estira en la dirección del tirón y vuelve.
        /// Es lo que convierte un cambio de estado en un golpe de masa.
        static let squashScale: CGFloat = 1.18
        static let squashDuration: CGFloat = 0.12

        static let trailNodeCount: Int = 14
        static let trailFadeDuration: CGFloat = 0.35
        /// Opacidad de la primera marca de estela. Por encima de ~0,45 la estela
        /// compite con el farolillo y deja de leerse quién es quién.
        static let trailPeakAlpha: CGFloat = 0.32
        /// Cuánto se estrecha la estela hacia el final.
        static let trailTailScale: CGFloat = 0.25

        /// Cada cuántos muros completa el cielo un ciclo entero. 24 es algo más que
        /// una partida buena: el jugador nota que el mundo respira, pero no ve el
        /// bucle repetirse dentro de un mismo run.
        static let paletteCycleWalls: Int = 24
        static let paletteTransitionDuration: CGFloat = 1.2

        /// Presupuesto del brief: del toque al nuevo run. Se mide, no se supone.
        static let restartBudget: CGFloat = 0.30
    }
}
