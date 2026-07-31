import CoreGraphics

/// Qué es cada cosa con la que se puede chocar. Sustituye a las categorías de
/// bitmask de SpriteKit: al ser un enum, el `switch` de resolución de colisión
/// lo verifica el compilador (ver D-002 en docs/decisiones.md).
enum ObstacleKind: Sendable, Equatable {
    case wall, floor, ceiling
}

struct Wall: Sendable, Equatable {
    let x: CGFloat
    let gapCenterY: CGFloat
    let gapHeight: CGFloat

    var gapBottomY: CGFloat { gapCenterY - gapHeight / 2 }
    var gapTopY: CGFloat { gapCenterY + gapHeight / 2 }
}

struct Anchor: Sendable, Equatable {
    let position: CGPoint
}

struct Chunk: Sendable, Equatable {
    /// Índice del muro, empezando en 1.
    let index: Int
    let wall: Wall
    let anchors: [Anchor]
    let isBlind: Bool
}

/// La curva del GDD, como fórmula. Rampa lineal con piso: sin escalones, porque
/// un salto brusco de dificultad se lee como injusticia aunque la media no cambie.
enum DifficultyCurve {
    static func spacing(forWall wall: Int) -> CGFloat {
        let excess = CGFloat(max(0, wall - Tuning.WorldGen.rampStartWall))
        return max(Tuning.WorldGen.spacingFloor,
                   Tuning.WorldGen.spacingStart - excess * Tuning.WorldGen.spacingDecayPerWall)
    }

    static func gapHeight(forWall wall: Int) -> CGFloat {
        let excess = CGFloat(max(0, wall - Tuning.WorldGen.rampStartWall))
        return max(Tuning.WorldGen.gapFloor,
                   Tuning.WorldGen.gapStart - excess * Tuning.WorldGen.gapDecayPerWall)
    }

    /// ponytail: acumula en bucle en vez de resolver la suma en cerrado. Solo hay
    /// cuatro chunks vivos a la vez, así que el coste es invisible; si algún día
    /// se materializa el chunk 10.000, se cachea.
    static func wallX(forWall wall: Int) -> CGFloat {
        var x = Tuning.WorldGen.firstWallX
        guard wall > 1 else { return x }
        for previous in 1..<wall {
            x += spacing(forWall: previous)
        }
        return x
    }
}

/// Qué muros son a ciegas. Función pura y sin azar a propósito: la primera zona
/// a ciegas debe caer en el mismo muro para todo el mundo, porque es el momento
/// en el que el juego enseña su mecánica firma.
enum BlindZones {
    static func isBlind(wall: Int) -> Bool {
        guard wall >= Tuning.BlindZone.firstWall else { return false }
        let zone = (wall - Tuning.BlindZone.firstWall) / Tuning.BlindZone.period
        let start = Tuning.BlindZone.firstWall + zone * Tuning.BlindZone.period
        let duration = min(Tuning.BlindZone.durationMax,
                           Tuning.BlindZone.durationStart + zone / Tuning.BlindZone.durationGrowthEvery)
        return wall < start + duration
    }
}

enum WorldGenerator {
    static func chunk(index: Int, seed: UInt64) -> Chunk {
        // La semilla se deriva del índice, no de un generador que avanza: el chunk
        // 47 es idéntico se haya pedido antes o después que el 46.
        var rng = SplitMix64(seed: seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15)

        let isBlind = BlindZones.isBlind(wall: index)
        let gapHeight = DifficultyCurve.gapHeight(forWall: index)
            + (isBlind ? Tuning.WorldGen.blindGapBonus : 0)
        let wallX = DifficultyCurve.wallX(forWall: index)

        let center = gapCenterY(forWall: index, seed: seed)
        let wall = Wall(x: wallX, gapCenterY: center, gapHeight: gapHeight)
        return Chunk(index: index,
                     wall: wall,
                     anchors: anchors(index: index,
                                      wallX: wallX,
                                      gapCenterY: center,
                                      gapHeight: gapHeight,
                                      rng: &rng),
                     isBlind: isBlind)
    }

    /// A qué altura tiene que estar un farol para que, **colgando de él**, el
    /// jugador pueda ponerse a la altura del hueco.
    ///
    /// Con la cuerda tensa el farolillo vive entre `ancla − maxRope` y
    /// `ancla − minRope`. Para que ese tramo cruce el hueco, el ancla tiene que
    /// estar entre `hueco + minRope` y `hueco + maxRope`. Antes las anclas y los
    /// huecos se sorteaban por separado y el 45 % de los huecos no se alcanzaba
    /// balanceándose: había que soltarse y acertar una parábola a ciegas.
    /// Entre qué alturas puede abrirse el hueco del muro `wall`.
    ///
    /// El techo no lo pone la pared, lo pone la cuerda: un hueco tan alto que su
    /// farol tuviera que ir empotrado en el techo dejaría de alcanzarse
    /// balanceándose, porque ese farol se quedaría corto.
    static func gapBand(forWall wall: Int) -> ClosedRange<CGFloat> {
        let gapHeight = DifficultyCurve.gapHeight(forWall: wall)
            + (BlindZones.isBlind(wall: wall) ? Tuning.WorldGen.blindGapBonus : 0)

        let lowest = Tuning.World.floorY + Tuning.WorldGen.gapEdgeMargin + gapHeight / 2
        var highest = Tuning.World.ceilingY - Tuning.WorldGen.gapEdgeMargin - gapHeight / 2
        highest = min(highest,
                      Tuning.World.ceilingY
                          - Tuning.WorldGen.anchorCeilingMargin
                          - Tuning.Pendulum.ropeLength
                          + Tuning.WorldGen.anchorHeightJitter)

        return lowest...max(lowest, highest)
    }

    /// Altura del hueco del muro `wall`, como **cadena**: cada hueco se aparta del
    /// anterior como mucho `maxGapStep`, de modo que dos muros seguidos nunca piden
    /// un salto que el farolillo no pueda dar.
    ///
    /// Antes cada hueco se sorteaba libre dentro de su banda y aparecían escalones
    /// de hasta 929 pt entre muros consecutivos —imposibles, no difíciles—. Sigue
    /// siendo determinista: el mismo `(wall, seed)` da siempre el mismo resultado,
    /// se pida en el orden que se pida.
    ///
    /// ponytail: recorre la cadena desde el principio, igual que `wallX`. Con cuatro
    /// chunks vivos y un chunk nuevo por segundo, el coste es invisible.
    static func gapCenterY(forWall wall: Int, seed: UInt64) -> CGFloat {
        // El primero se abre a la altura de salida y con su farol al alcance: es la
        // puerta de entrada al juego, no un sorteo.
        let firstBand = gapBand(forWall: 1)
        let spread = Tuning.WorldGen.firstGapVerticalSpread
        let rope = Tuning.Pendulum.ropeLength
        let jitter = Tuning.WorldGen.anchorHeightJitter
        let reachableLow = Tuning.Player.startY + Tuning.WorldGen.firstAnchorMinOffsetY - rope - jitter
        let reachableHigh = Tuning.Player.startY + Tuning.WorldGen.firstAnchorMaxOffsetY - rope + jitter

        var current = clamp(Tuning.Player.startY,
                            max(firstBand.lowerBound, max(Tuning.Player.startY - spread, reachableLow)),
                            max(firstBand.lowerBound, min(firstBand.upperBound,
                                                          min(Tuning.Player.startY + spread, reachableHigh))))
        guard wall > 1 else { return current }

        for index in 2...wall {
            // Semilla propia para la cadena: así generar anclas no desplaza el
            // sorteo de los huecos ni al revés.
            var rng = SplitMix64(seed: seed
                &+ UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15
                &+ 0xA5A5_5A5A_C3C3_3C3C)
            let step = rng.nextCGFloat(in: -Tuning.WorldGen.maxGapStep...Tuning.WorldGen.maxGapStep)
            let band = gapBand(forWall: index)
            current = clamp(current + step, band.lowerBound, band.upperBound)
        }
        return current
    }

    private static func intersection(_ a: ClosedRange<CGFloat>,
                                     _ b: ClosedRange<CGFloat>) -> ClosedRange<CGFloat>? {
        let lower = max(a.lowerBound, b.lowerBound)
        let upper = min(a.upperBound, b.upperBound)
        return lower <= upper ? lower...upper : nil
    }

    /// A qué distancia máxima del muro puede estar la flor que lo abre.
    ///
    /// Colgado a distancia `D`, el arco cruza el plano del muro `L − √(L² − D²)` por
    /// debajo de la flor. Para que ese cruce caiga dentro del hueco, esa caída tiene
    /// que ser menor que el margen del hueco — y como la flor puede estar hasta
    /// `anchorHeightJitter` desplazada, el margen se cuenta descontándolo.
    ///
    /// Se calcula por puerta, no con una constante: el hueco se estrecha con la
    /// dificultad, y una distancia segura en el muro 10 es una trampa en el 125.
    static func maxWallDistance(forGapHeight gapHeight: CGFloat) -> CGFloat {
        let rope = Tuning.Pendulum.ropeLength
        let margin = gapHeight / 2
            - Tuning.Player.radius
            - Tuning.WorldGen.anchorHeightJitter
        guard margin > 0 else { return Tuning.WorldGen.anchorWallClearance }

        let vertical = max(0, rope - margin)
        let maximum = (rope * rope - vertical * vertical).squareRoot()
        return max(Tuning.WorldGen.anchorWallClearance,
                   min(maximum, Tuning.WorldGen.anchorMaxWallDistance))
    }

    static func anchorHeightRange(forGapCenterY gapCenterY: CGFloat) -> ClosedRange<CGFloat> {
        let ideal = gapCenterY + Tuning.Pendulum.ropeLength
        let ceiling = Tuning.World.ceilingY - Tuning.WorldGen.anchorCeilingMargin
        let jitter = Tuning.WorldGen.anchorHeightJitter
        let lowest = min(ideal - jitter, ceiling)
        let highest = min(ideal + jitter, ceiling)
        return lowest...max(lowest, highest)
    }

    private static func anchors(index: Int,
                                wallX: CGFloat,
                                gapCenterY: CGFloat,
                                gapHeight: CGFloat,
                                rng: inout SplitMix64) -> [Anchor] {
        let previousWallX = index > 1
            ? DifficultyCurve.wallX(forWall: index - 1)
            : Tuning.Player.startX
        let lower = previousWallX + Tuning.WorldGen.anchorWallClearance
        let upper = wallX - Tuning.WorldGen.anchorWallClearance
        guard upper > lower else { return [] }

        // La altura de la flor la manda el hueco, no el azar: colgando de ella hay
        // que poder ponerse a la altura por la que se pasa.
        let yRange = anchorHeightRange(forGapCenterY: gapCenterY)

        // LA LLAVE: la flor que abre esta puerta. Va lo bastante cerca del muro como
        // para que el arco lo cruce por dentro del hueco (ver `anchorMaxWallDistance`).
        let keyLow = min(max(lower, wallX - maxWallDistance(forGapHeight: gapHeight)), upper)
        let keyX = rng.nextCGFloat(in: keyLow...upper)

        var keyY = rng.nextCGFloat(in: yRange)
        if index == 1 {
            // La primera flor cumple dos cosas a la vez: está al alcance desde el
            // punto de partida y abre el primer hueco. Se cruzan los dos rangos; si
            // no se solapan gana el del hueco, porque llegar a la flor y no poder
            // pasar es peor que no llegar.
            let reachableY = (Tuning.Player.startY + Tuning.WorldGen.firstAnchorMinOffsetY)
                ... (Tuning.Player.startY + Tuning.WorldGen.firstAnchorMaxOffsetY)
            keyY = rng.nextCGFloat(in: intersection(reachableY, yRange) ?? yRange)
        }
        let key = Anchor(position: CGPoint(x: keyX, y: keyY))

        var wantsSecond = index < Tuning.WorldGen.singleAnchorFromWall
            || rng.nextCGFloat(in: 0...1) >= Tuning.WorldGen.singleAnchorChance
        if index == 1 { wantsSecond = true }
        guard wantsSecond else { return [key] }

        // LA DE PASO: sirve para encadenar hasta la llave, no para cruzar. Va tan
        // atrás que su propio arco ni siquiera alcanza el muro — si quedara a media
        // distancia, columpiarse desde ella acabaría estampándote contra la parte
        // maciza sin que el jugador pudiera hacer nada por evitarlo.
        let outOfReachOfWall = wallX - Tuning.Pendulum.ropeLength - Tuning.Player.radius
        let secondUpper = min(keyX - Tuning.WorldGen.anchorMinSeparationX, outOfReachOfWall)
        guard secondUpper > lower else { return [key] }

        let second = Anchor(position: CGPoint(x: rng.nextCGFloat(in: lower...secondUpper),
                                              y: rng.nextCGFloat(in: yRange)))
        return [key, second]
    }
}
