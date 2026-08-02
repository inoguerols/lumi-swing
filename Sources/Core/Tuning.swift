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
        ///
        /// Subido de 80 a 700 por una razón de encuadre: el área jugable son 1500 pt
        /// de los 1950 de escena, así que por arriba y por abajo sobra sitio — y con
        /// barras finas volvía a asomar el cielo **detrás** del suelo, que delataba
        /// que el mundo se acababa ahí. Ahora son sólidas hasta bien fuera de
        /// pantalla, incluso con la cámara siguiendo al jugador a lo alto.
        static let boundsThickness: CGFloat = 700
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

        /// **La cuerda mide siempre lo mismo.** Antes tomaba la distancia real al
        /// ancla en el instante del agarre, acotada a [220, 420] — y eso significaba
        /// que engancharse cerca del farol te dejaba colgando alto y engancharse
        /// lejos te dejaba colgando bajo, sin que el jugador lo decidiera ni pudiera
        /// preverlo. Como el farol se coloca justo a esta distancia por encima del
        /// hueco, con la cuerda fija **el punto más bajo del arco siempre queda
        /// alineado con el hueco**: el jugador solo tiene que decidir cuándo soltar,
        /// no a qué altura acabará. Un problema de dos dimensiones convertido en uno
        /// de una.
        ///
        /// Con L=320 y g=2000 el periodo es 2,5 s: ~1,26 s por medio arco, del orden
        /// de lo que cuesta cruzar un chunk. Ese encaje entre el ritmo del péndulo y
        /// el del mundo es lo que hace el juego cadencioso en vez de frenético.
        /// Bajada de 320 a 240 por una razón de cadena, no de gusto: la flor va una
        /// liana por encima del hueco, así que cuanto más larga sea la liana, más
        /// arriba queda la flor respecto a por donde acabas de pasar. Con 320 y un
        /// salto de hueco de 320, la flor quedaba a 640 pt del punto de entrada y el
        /// radio de agarre son 430: no había nada a lo que agarrarse, y 11 de cada
        /// 40 puertas eran literalmente imposibles.
        static let ropeLength: CGFloat = 240

        /// Al engancharse, la liana mide **lo que hay** hasta la flor (acotado a este
        /// rango) y luego se recoge sola hasta `ropeLength`.
        ///
        /// Que midiera desde el primer instante lo mismo pasara lo que pasara era
        /// justo, pero se sentía mecánico: siempre el mismo arco, siempre el mismo
        /// enganche. Así el momento de agarrarse conserva el gesto real —te enganchas
        /// donde estás— y a los pocos décimas la longitud converge a la predecible,
        /// que es la que hace que el punto bajo caiga en el hueco.
        static let ropeGrabMin: CGFloat = 200
        static let ropeGrabMax: CGFloat = 420
        /// Con qué prisa se recoge (1/s). Más alto = tirón más seco.
        static let ropeRetractRate: CGFloat = 2.6

        /// Cuánto cede la liana cuando tira. 0 sería un cable de acero — que es lo
        /// que se sentía antes. Este poco de elasticidad es lo que la convierte en
        /// algo vivo que se estira y rebota.
        static let ropeElasticity: CGFloat = 0.10
        /// Cuánta velocidad radial sobrevive al tirón. A 0 la cuerda mata el rebote
        /// de golpe; un resto pequeño devuelve el balanceo natural.
        static let ropeBounce: CGFloat = 0.25

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
        /// Bajado de 1500 a 900 tras medirlo: con el tope antiguo, cinco segundos
        /// pulsando llevaban al farolillo al máximo absoluto de velocidad. A 900 el
        /// arco sigue ganando fuerza, pero el jugador puede leer dónde va a acabar.
        static let tangentialPump: CGFloat = 900
        static let maxTangentialSpeed: CGFloat = 900

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
        ///
        /// Subido de 240/190 a 360/280 con un motivo medible: el jugador suelta en el
        /// punto bajo del arco —a la altura del hueco— pero **cae durante el vuelo**.
        /// Con media separación de muros (280 pt) a velocidad de crucero (~800 pt/s)
        /// son 0,35 s de vuelo, es decir 122 pt de caída, y el hueco de 240 solo
        /// perdonaba 94 a cada lado descontando el radio. El gesto correcto no cabía
        /// por la puerta: el juego pedía anticipar la parábola con precisión de
        /// simulador, no la sensación de un hiper-casual.
        static let gapStart: CGFloat = 360
        static let gapFloor: CGFloat = 280
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

        /// Cuánto se mantienen los faroles por debajo del techo. Su altura ya no se
        /// sortea: se deriva del hueco al que tienen que dar acceso (ver
        /// `WorldGenerator.anchorHeightRange`). Este margen solo evita que un farol
        /// quede incrustado en el techo.
        static let anchorCeilingMargin: CGFloat = 40

        /// Cuánto puede desviarse un farol de su altura ideal (`hueco + ropeLength`).
        /// Con hueco de 240 pt y farolillo de 26 de radio sobran 94 pt a cada lado,
        /// así que 40 da variedad visual sin que el punto bajo del arco deje de
        /// caer dentro del hueco.
        static let anchorHeightJitter: CGFloat = 40

        /// Cuánto puede moverse un hueco respecto al del muro anterior.
        ///
        /// Sin este límite los huecos se sorteaban independientes y aparecían saltos
        /// verticales de hasta 929 pt entre muros consecutivos, cuando el techo de
        /// subida del farolillo ronda los 560: había tramos imposibles, no difíciles.
        /// El mundo pasa a ser una **cadena**, no una lista de sorteos sueltos.
        /// Bajado de 320 a 220: el salto entre huecos se suma a la altura de la flor
        /// (una liana por encima del hueco), y la suma tiene que caber dentro del
        /// radio de agarre desde el punto de entrada. Es la otra mitad del arreglo
        /// de las puertas imposibles.
        static let maxGapStep: CGFloat = 220

        /// Franja histórica de altura de las anclas. Ya NO decide dónde van —eso lo
        /// decide el hueco—; se conserva como referencia del espacio de juego.
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
        /// Separación de emergencia cuando el tramo viene justo. Preferimos dos
        /// flores apretadas a una sola: sin escalón, el tramo puede ser imposible.
        static let anchorMinSeparationTight: CGFloat = 90
        static let anchorWallClearance: CGFloat = 110

        /// A qué distancia máxima del muro puede estar la flor que da acceso a él.
        ///
        /// Es geometría, no gusto. Colgado de una flor a distancia `D` del muro, el
        /// arco cruza el plano del muro a la altura `flor.y − √(L² − D²)`. Con `D`
        /// pequeño eso cae en pleno hueco; según crece, el punto de cruce sube y
        /// acaba estrellándote contra la parte maciza. Con L=320 y hueco de 360 el
        /// límite ronda los 273 pt, así que 240 deja margen.
        ///
        /// Antes las flores se repartían por todo el hueco entre muros y podían
        /// quedar a 450: desde esas, el balanceo terminaba en muerte hiciera el
        /// jugador lo que hiciera. **Cada puerta tiene que tener su llave.**
        static let anchorMaxWallDistance: CGFloat = 240

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

        /// Ventana de aviso, en separaciones de muro: el velo empieza a cerrarse
        /// cuando quedan `telegraphWalls` muros para llegar al de entrada, no de
        /// golpe al cruzarlo. En distancia, no en tiempo, para que se telegrafíe
        /// igual se vaya rápido o lento.
        static let telegraphWalls: CGFloat = 1

        /// Cuánto late el agujero de luz del velo, en proporción sobre su tamaño
        /// base (±5 % ≈ el punto medio del rango 4-6 % que pide el GDD).
        static let breatheAmplitude: CGFloat = 0.05

        /// Cuántos muros a ciegas hay que cruzar con éxito antes de que el cartel
        /// deje de repetirse en cada zona nueva.
        static let noticeThreshold: Int = 6
    }

    // MARK: - Aprendizaje de la mecánica a ciegas
    //
    // El eco: en las primeras zonas a ciegas que vive el jugador, los muros
    // invisibles dejan una silueta tenue y fría que late con el pulso háptico de
    // proximidad. Ver el muro latir mientras se siente el pulso es lo que enseña
    // la correlación; después se retira y la zona vuelve a ser a ciegas de verdad.

    enum BlindTeaching {
        /// Opacidad del eco en la primera zona a ciegas de la vida del jugador.
        /// Alta para que se vea sin buscarlo, baja para que siga leyéndose como
        /// eco y no como "muro visible" (un muro normal va a 1,0).
        static let initialAlpha: CGFloat = 0.35

        /// Cuántas zonas a ciegas dura la enseñanza. El eco decae linealmente
        /// desde `initialAlpha` a lo largo de estas zonas; a partir de la nº
        /// `teachingZones` (contando desde 0) es exactamente 0 para siempre.
        static let teachingZones: Int = 6

        /// Qué fracción de su opacidad conserva el eco en el valle del latido.
        /// Es la profundidad del pulso: a 1 no latiría, a 0 desaparecería entre
        /// pulso y pulso y se leería como parpadeo roto en vez de respiración.
        static let pulseFloor: CGFloat = 0.35
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

    // MARK: - Decorado
    //
    // Nada de esto afecta a la física ni a la colisión: es el mundo alrededor del
    // juego. Vive aquí igualmente porque son números, y los números viven aquí.

    enum Scenery {
        /// Cuánto se mueve cada capa de vegetación respecto a la cámara. Por debajo
        /// de 1 se quedan atrás, y eso es lo que se lee como distancia; a 0 parecerían
        /// pegadas al cristal.
        static let parallaxFar: CGFloat = 0.20
        static let parallaxNear: CGFloat = 0.45
        /// La luna, mucho más lejos que el dosel: apenas se mueve, pero se mueve.
        /// Antes clavada a la cámara — ahora el run deja memoria visual (F6).
        static let parallaxMoon: CGFloat = 0.05

        static let canopyFarHeight: CGFloat = 460
        static let canopyNearHeight: CGFloat = 320
        static let canopyBumps: Int = 14

        /// Motas de polen suspendidas. Suficientes para que el aire exista, pocas
        /// para no competir con las luces que sí informan.
        static let moonRadius: CGFloat = 62

        /// Anchura típica de cada mata de maleza y de cada hoja del dosel.
        static let undergrowthSpacing: CGFloat = 70

        /// Cuánto y cómo de rápido ondula el tallo de las flores. Amplitud pequeña a
        /// propósito: es aire, no viento, y compite con lo que sí informa.
        static let stemSwayAmplitude: CGFloat = 26
        static let stemSwaySpeed: CGFloat = 1.1

        static let pollenCount: Int = 22
        /// Radio por partícula, sorteado en este rango: discos idénticos se leían
        /// como confeti, no como bokeh a distintas profundidades.
        static let pollenRadiusMin: CGFloat = 2
        static let pollenRadiusMax: CGFloat = 6.5
        static let pollenDriftDuration: CGFloat = 6
        /// Ciclo de fundido (aparecer/desaparecer) de cada mota, con desfase por
        /// partícula, y a qué fracción de su alpha pico baja en el valle.
        static let pollenFadeDuration: CGFloat = 3.2
        static let pollenFadeFloor: CGFloat = 0.15

        /// Hasta dónde llega la luz de la luciérnaga en las zonas a ciegas.
        static let lightHoleRadius: CGFloat = 230

        /// Silueta tallada del tronco (F5): cada cuánto aparece una muesca de
        /// corteza a lo largo del canto vertical, y cuánto muerde hacia dentro.
        /// Todo el rango cabe con holgura dentro de `World.wallThickness` (46),
        /// para que la muesca más profunda + el canto lunar nunca se crucen.
        static let trunkNotchSpacing: CGFloat = 70
        static let trunkNotchDepthMin: CGFloat = 3
        static let trunkNotchDepthMax: CGFloat = 7
        /// Fracción del grosor del tronco que ocupa el canto lunar.
        static let trunkLitWidthFraction: CGFloat = 0.32
        /// Nudos de corteza por tronco: pura decoración, jamás toca el borde.
        static let trunkKnotCount: Int = 1
        /// Cuánto se aleja el muñón de rama del canto que da al hueco.
        static let trunkStumpMargin: CGFloat = 34

        /// Silueta tallada de las losas de suelo y techo (F6): mismo principio que
        /// el tronco —el borde que mira al área jugable muerde hacia dentro de la
        /// losa, nunca cruza `floorY`/`ceilingY`—, pero con una separación mayor y
        /// mordiscos más profundos: aquí lee como hierba y raíces vistas de lejos,
        /// no como corteza de cerca.
        static let boundsEdgeSpacing: CGFloat = 160
        static let boundsEdgeDepthMin: CGFloat = 20
        static let boundsEdgeDepthMax: CGFloat = 60

        /// Cuánto tarda el cielo del menú en completar un ciclo. En partida el
        /// ciclo lo marca el nº de muro (`Feel.paletteCycleWalls`); en el menú no
        /// hay muros que contar, así que aquí manda el tiempo real (F6).
        static let menuSkyCycleDuration: CGFloat = 40

        /// La flor: corola, núcleo y el tallo del que cuelga.
        static let flowerPetalCount: Int = 5
        static let flowerPetalLength: CGFloat = 17
        static let flowerCoreRadius: CGFloat = 7
        /// Cuánto se abre y brilla la flor cuando está al alcance. Es lo que enseña
        /// el radio de agarre sin un solo cartel.
        static let flowerReadyScale: CGFloat = 1.35

        /// Lumi en tres trazos: la bola de luz (que **es** el cuerpo), los ojazos
        /// y la cola de cometa. Ni cabeza, ni tórax, ni alas, ni antenas:
        /// a 36 px de alto tiene que leerse «mota de luz con carita», y cada pieza de
        /// anatomía que se añade resta legibilidad a ese tamaño.
        ///
        /// El radio de la bola sale de una cuenta, no del gusto: es toda la masa que
        /// se dibuja, y se deforma dos veces —el squash del agarre (`Feel.squashScale`)
        /// y el stretch por velocidad (`stretchAtMaxSpeed`)—, así que
        /// 20 × 1,18 × 1,10 = 26,0 = `Player.radius` exacto. Subir cualquiera de los
        /// tres saca masa encendida fuera del círculo que mata, que es lo único que
        /// el GDD no permite negociar (hay un test que vigila el producto).
        static let bodyRadius: CGFloat = 20
        /// Sobremuestreo de la textura de la bola. Se genera **una vez**; a 1× el
        /// degradado se escalona en pantalla Retina.
        static let bodyTextureScale: CGFloat = 6
        /// Hasta qué fracción del radio de la textura llega la luz sólida: el resto
        /// se desvanece hasta alpha 0 **antes** del canto. Ese último tramo
        /// transparente es lo que hace que el cuerpo no tenga filo — un círculo
        /// recortado, por bonito que sea el color, siempre acaba en un canto duro.
        static let bodyEdgeFade: CGFloat = 0.78
        /// Ruido (± fracción por canal) horneado en la textura de la bola: 1-2%
        /// basta para matar el banding del degradado radial sin verse como grano.
        static let lightTextureNoise: CGFloat = 0.015
        /// Bloom: capas aditivas concéntricas de la misma textura suave detrás de la
        /// bola. Varias capas tenues y no una opaca, porque una sola vuelve a dejar
        /// un borde que se lee como pegatina.
        static let bodyGlowLayers: Int = 3
        static let bodyGlowScale: CGFloat = 1.75
        static let bodyGlowAlpha: CGFloat = 0.42

        /// Ojazos: enormes a propósito sobre una bola de 20 de radio. Son TODA la
        /// cara (vía Limbo/Sein: el flequillo oscuro leía como eclipse y se quitó
        /// — Lumi es luminosa hasta el núcleo) y toda la legibilidad a 36 px.
        /// Sin el flequillo conservan su tamaño (subirlos devolvía la masa oscura
        /// por otra vía) y se recentran en vertical: la mirada ocupa el centro de
        /// la bola en vez de flotar en su mitad baja, y entre ambos queda franja
        /// de luz — el test es que a 36 px siga leyéndose «mota de luz con carita».
        static let eyeRadius: CGFloat = 8.1
        static let eyeOffsetX: CGFloat = 10.2
        static let eyeOffsetY: CGFloat = 0
        /// El brillo blanco dentro del ojo, arriba y hacia dentro: es lo que
        /// convierte un agujero negro en una mirada. Se hornea SIN blur (nítido):
        /// a 26 px el brillo es lo único del ojo que sobrevive, y es lo que sigue
        /// diciendo «mirada» y no «agujero».
        static let eyeHighlightRadius: CGFloat = 3.45
        static let eyeHighlightOffset: CGFloat = 3.0

        /// Parpadeo de ojos: cada cuánto (con jitter determinista) y cuánto se
        /// aplastan verticalmente al cerrarse. Se queda incluso con Reduce Motion.
        static let eyeBlinkIntervalMin: CGFloat = 3
        static let eyeBlinkIntervalMax: CGFloat = 5
        /// Fracción de alto del ojo que queda al cerrar: 0,12 se lee cerrado sin
        /// desaparecer del todo.
        static let eyeBlinkSquash: CGFloat = 0.12
        static let eyeBlinkCloseDuration: CGFloat = 0.06
        static let eyeBlinkOpenDuration: CGFloat = 0.09

        /// Squash & stretch continuo: cuánto se estira el cuerpo en la dirección en
        /// la que va, a `Pendulum.maxSpeed`. Solo sobre el dibujo, y acotado por la
        /// cuenta de `bodyRadius`: el círculo de colisión no se estira, así que un
        /// valor mayor haría que la silueta mintiera sobre lo que mata.
        static let stretchAtMaxSpeed: CGFloat = 0.10

        /// Qué fracción del ángulo de la liana adopta el cuerpo mientras cuelga. A 1
        /// se cuelga rígido como el badajo de una campana; con 0,30 se queda casi
        /// erguido —como quien se agarra a una rama— y el balanceo solo se insinúa.
        static let uprightBias: CGFloat = 0.30
        /// Muelle amortiguado de la pose: rigidez (1/s²) y amortiguación (1/s). La
        /// amortiguación va por debajo de la crítica (2·√rigidez ≈ 21) a propósito:
        /// ese resto es el rebote que se ve al cambiar de sentido y al soltar. Más
        /// rigidez = el giro persigue antes; más amortiguación = menos rebote.
        static let poseStiffness: CGFloat = 110
        static let poseDamping: CGFloat = 12

        /// Chispas que suelta en vuelo libre por encima de esta fracción de la
        /// velocidad máxima. No informan de nada que la estela no diga ya: son el
        /// premio de ir rápido, y por eso se apagan con Reduce Motion.
        static let sparkSpeedThreshold: CGFloat = 0.45
        static let sparkInterval: CGFloat = 0.09
        static let sparkLifetime: CGFloat = 0.40
        static let sparkRadius: CGFloat = 3

        /// Motas cálidas orbitando cerca. Cuelgan del jugador pero no del cuerpo:
        /// ni rotan ni se estiran con él, porque son aire iluminado, no anatomía.
        /// Tamaño, alpha, ángulo y órbita llevan jitter (nada de puntos uniformes
        /// alineados) y todas derivan además en órbita lenta (`moteOrbitDuration`).
        static let moteCount: Int = 4
        static let moteRadius: CGFloat = 2.6
        static let moteOrbit: CGFloat = 1.5
        static let moteDriftDuration: CGFloat = 1.9
        /// Una vuelta completa del corro de motas. Con Reduce Motion no gira.
        static let moteOrbitDuration: CGFloat = 16

        /// Desenfoque horneado de la cara (ojos; los brillos van nítidos), en puntos a
        /// escala de juego. Se aplica UNA vez al generar la textura: ninguna
        /// frontera del personaje queda con canto duro, tampoco las oscuras.
        static let faceBlurSigma: CGFloat = 1.2
        /// Margen de la textura de la cara para que la cola del blur no se recorte.
        static let facePadding: CGFloat = 6

        /// Qué fracción del giro de la pose adopta la cara: el cuerpo es radialmente
        /// simétrico, y sin este ladeo parcial el giro físico era invisible.
        static let faceLeanFactor: CGFloat = 0.4

        /// Luz ambiente: el halo más ancho y tenue de todos, el que aclara la selva
        /// alrededor de Lumi. Radio en múltiplos de `Player.radius`.
        static let ambientRadiusScale: CGFloat = 4.6
        static let ambientAlpha: CGFloat = 0.13
        /// Halo puente entre el halo del cuerpo (1,8·r) y el ambiente (4,6·r):
        /// sin él, la luz caía a saltos y el canto del bloom se veía como un aro.
        static let midHaloRadiusScale: CGFloat = 2.9
        static let midHaloAlpha: CGFloat = 0.09

        /// Microvida del cuerpo: pulso de respiración de la bola (±5% cada ~1,2 s,
        /// con jitter determinista de duración para que no sea un metrónomo)
        /// y parpadeo aditivo del núcleo (nunca resta alpha al cuerpo: F4 prohíbe
        /// que se transparente). Con Reduce Motion el pulso se reduce a la mitad y
        /// el parpadeo del núcleo se apaga.
        static let corePulseScale: CGFloat = 1.05
        static let corePulseDuration: CGFloat = 1.2
        /// Jitter (± fracción) sobre la duración de cada medio pulso: lo que lo
        /// hace irregular en vez de píxel-idéntico entre ciclos.
        static let corePulseJitter: CGFloat = 0.25
        static let coreFlickerAlphaLow: CGFloat = 0.25
        static let coreFlickerAlphaHigh: CGFloat = 0.55

        /// El halo detrás de todo late al ritmo del háptico de proximidad — el
        /// parpadeo ya no toca el cuerpo (F4: eso era lo que lo hacía "transparentar").
        /// Radio en múltiplos de `Player.radius`; alpha y escala oscilan entre estos
        /// límites cada latido.
        static let haloRadiusScale: CGFloat = 1.8
        static let haloDimAlpha: CGFloat = 0.20
        static let haloBrightAlpha: CGFloat = 0.55
        static let haloDimScale: CGFloat = 0.85
        static let haloBrightScale: CGFloat = 1.05
        /// Cadencia del parpadeo ocioso, cuando no hay muro del que avisar.
        static let idleBlinkInterval: CGFloat = 1.6
    }

    // MARK: - HUD dentro de la escena
    //
    // El marcador es parte del juego, no del shell: vive en la escena y viaja con
    // la cámara. Los menús de SwiftUI llegan en S6.

    enum HUD {
        static let scoreFontSize: CGFloat = 120
        static let deathFontSize: CGFloat = 64
        /// Desplazamientos respecto al centro de la cámara.
        /// Bajado de 760 tras verlo en pantalla: a esa altura la Dynamic Island se
        /// comía el marcador.
        static let scoreOffsetY: CGFloat = 600
        static let deathOffsetY: CGFloat = -160
        static let blindNoticeOffsetY: CGFloat = 420
        /// Cuánto salta el marcador al puntuar. El doble a ciegas salta más: es la
        /// diferencia entre contabilizar el riesgo y celebrarlo.
        static let scorePop: CGFloat = 1.18
        static let scorePopDoubled: CGFloat = 1.34
        /// Cuánto dura el cartel que explica las zonas a ciegas la primera vez.
        static let blindNoticeDuration: CGFloat = 2.2
    }

    // MARK: - Game feel

    enum Feel {
        /// Al agarrarse, el farolillo se estira en la dirección del tirón y vuelve.
        /// Es lo que convierte un cambio de estado en un golpe de masa.
        ///
        /// Se multiplica con el stretch por velocidad, así que este número **no es
        /// libre**: `Scenery.bodyRadius` × este × (1 + `Scenery.stretchAtMaxSpeed`)
        /// tiene que caber en `Player.radius`.
        static let squashScale: CGFloat = 1.18
        static let squashDuration: CGFloat = 0.12

        /// Menos marcas y más separadas que al principio: con 14 muy juntas la
        /// estela se pegaba al cuerpo y la luciérnaga parecía una oruga. Ahora es un
        /// rastro de luz que se apaga, que es lo que deja una luciérnaga al pasar.
        static let trailNodeCount: Int = 9
        static let trailFadeDuration: CGFloat = 0.45
        /// Opacidad de la primera marca. Por encima de ~0,3 la estela compite con el
        /// cuerpo y deja de leerse quién es quién.
        static let trailPeakAlpha: CGFloat = 0.22
        /// Cuánto se estrecha la estela hacia el final.
        static let trailTailScale: CGFloat = 0.18

        /// Cada cuántos muros completa el cielo un ciclo entero. 24 es algo más que
        /// una partida buena: el jugador nota que el mundo respira, pero no ve el
        /// bucle repetirse dentro de un mismo run.
        static let paletteCycleWalls: Int = 24
        static let paletteTransitionDuration: CGFloat = 1.2

        /// Presupuesto del brief: del toque al nuevo run. Se mide, no se supone.
        static let restartBudget: CGFloat = 0.30
    }

    // MARK: - Unidades

    enum Units {
        /// Puntos de física por metro mostrado. Constante de presentación, no de
        /// simulación: no calibra nada del juego, solo convierte el ritmo
        /// sostenido (ver `Pace`), en pt/s, a un m/s legible en la pantalla de fin
        /// de partida. A `Pendulum.maxSpeed` (1500 pt/s) equivale a 15,0 m/s.
        static let pointsPerMeter: CGFloat = 100
    }

    // MARK: - Ritmo (métrica de "una vez más")

    enum Pace {
        /// Ventana de la media móvil que define el **ritmo sostenido**: la mejor
        /// media de 10 s de `|velocidad|` en toda la partida. Sustituye al pico
        /// como métrica de leaderboard — el pico satura en `Pendulum.maxSpeed` en
        /// cualquier caída y empataría a todo el mundo; una media de 10 s solo
        /// premia mantener el ritmo, no un instante de caída libre.
        static let windowSeconds: CGFloat = 10

        /// En cuántos cubos se trocea la ventana para promediarla sin guardar una
        /// muestra por frame: cada cubo acumula tiempo y velocidad de forma
        /// incremental, y se resetea solo cuando el reloj vuelve a pisarlo una
        /// vuelta después — así el coste de memoria es fijo, pase lo que pase el
        /// framerate.
        static let bucketCount: Int = 20
    }
}
