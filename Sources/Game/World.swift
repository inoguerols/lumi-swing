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
                     anchors: anchors(index: index, wallX: wallX, gapCenterY: center, rng: &rng),
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
                                rng: inout SplitMix64) -> [Anchor] {
        let previousWallX = index > 1
            ? DifficultyCurve.wallX(forWall: index - 1)
            : Tuning.Player.startX
        let lower = previousWallX + Tuning.WorldGen.anchorWallClearance
        let upper = wallX - Tuning.WorldGen.anchorWallClearance
        guard upper > lower else { return [] }

        // La altura del farol la manda el hueco, no el azar: colgando de él hay que
        // poder ponerse a la altura por la que se pasa.
        let yRange = anchorHeightRange(forGapCenterY: gapCenterY)
        var count = Tuning.WorldGen.anchorsPerChunk
        if index >= Tuning.WorldGen.singleAnchorFromWall,
           rng.nextCGFloat(in: 0...1) < Tuning.WorldGen.singleAnchorChance {
            count = 1
        }
        if upper - lower < Tuning.WorldGen.anchorMinSeparationX { count = 1 }

        // El primer farol de la partida no se sortea a ciegas: se coloca donde el
        // jugador pueda alcanzarlo desde su posición inicial. Empezar sin asidero
        // no es dificultad, es una partida perdida antes de tocar la pantalla.
        if index == 1 {
            let reachableX = (Tuning.Player.startX + Tuning.WorldGen.firstAnchorMinOffsetX)
                ... (Tuning.Player.startX + Tuning.WorldGen.firstAnchorMaxOffsetX)
            // El primer farol tiene que cumplir dos cosas a la vez: estar al alcance
            // desde el punto de partida y llevar al primer hueco. Se cruza el rango
            // alcanzable con el que sirve para el hueco; si no se solapan, gana el
            // del hueco, porque llegar al farol y no poder pasar es peor que nada.
            let reachableY = (Tuning.Player.startY + Tuning.WorldGen.firstAnchorMinOffsetY)
                ... (Tuning.Player.startY + Tuning.WorldGen.firstAnchorMaxOffsetY)
            let firstY = intersection(reachableY, yRange) ?? yRange
            let x = rng.nextCGFloat(in: reachableX)
            let first = Anchor(position: CGPoint(x: x, y: rng.nextCGFloat(in: firstY)))
            let secondLower = x + Tuning.WorldGen.anchorMinSeparationX
            guard secondLower <= upper else { return [first] }
            return [first,
                    Anchor(position: CGPoint(x: rng.nextCGFloat(in: secondLower...upper),
                                             y: rng.nextCGFloat(in: yRange)))]
        }

        if count == 1 {
            return [Anchor(position: CGPoint(x: rng.nextCGFloat(in: lower...upper),
                                             y: rng.nextCGFloat(in: yRange)))]
        }

        // La primera se coloca dejando sitio para la separación mínima, así que la
        // segunda siempre cabe. Sin esto, un mal sorteo las junta y el jugador se
        // encuentra dos faroles solapados que se comportan como uno.
        let firstX = rng.nextCGFloat(in: lower...(upper - Tuning.WorldGen.anchorMinSeparationX))
        let secondX = rng.nextCGFloat(in: (firstX + Tuning.WorldGen.anchorMinSeparationX)...upper)
        return [
            Anchor(position: CGPoint(x: firstX, y: rng.nextCGFloat(in: yRange))),
            Anchor(position: CGPoint(x: secondX, y: rng.nextCGFloat(in: yRange)))
        ]
    }
}
