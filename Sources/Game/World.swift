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

        var lowestCenter = Tuning.World.floorY + Tuning.WorldGen.gapEdgeMargin + gapHeight / 2
        var highestCenter = Tuning.World.ceilingY - Tuning.WorldGen.gapEdgeMargin - gapHeight / 2

        // El primer muro se abre a la altura de partida: es la puerta de entrada al
        // juego, no un sorteo.
        if index == 1 {
            let spread = Tuning.WorldGen.firstGapVerticalSpread
            lowestCenter = max(lowestCenter, Tuning.Player.startY - spread)
            highestCenter = min(highestCenter, Tuning.Player.startY + spread)
        }

        let gapCenterY = highestCenter > lowestCenter
            ? rng.nextCGFloat(in: lowestCenter...highestCenter)
            : Tuning.World.sceneHeight / 2

        let wall = Wall(x: wallX, gapCenterY: gapCenterY, gapHeight: gapHeight)
        return Chunk(index: index,
                     wall: wall,
                     anchors: anchors(index: index, wallX: wallX, rng: &rng),
                     isBlind: isBlind)
    }

    private static func anchors(index: Int, wallX: CGFloat, rng: inout SplitMix64) -> [Anchor] {
        let previousWallX = index > 1
            ? DifficultyCurve.wallX(forWall: index - 1)
            : Tuning.Player.startX
        let lower = previousWallX + Tuning.WorldGen.anchorWallClearance
        let upper = wallX - Tuning.WorldGen.anchorWallClearance
        guard upper > lower else { return [] }

        let yRange = Tuning.WorldGen.anchorMinY...Tuning.WorldGen.anchorMaxY
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
            let reachableY = (Tuning.Player.startY + Tuning.WorldGen.firstAnchorMinOffsetY)
                ... (Tuning.Player.startY + Tuning.WorldGen.firstAnchorMaxOffsetY)
            let x = rng.nextCGFloat(in: reachableX)
            let first = Anchor(position: CGPoint(x: x, y: rng.nextCGFloat(in: reachableY)))
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
