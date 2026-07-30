import CoreGraphics

/// Colisión propia: círculo contra rectángulos alineados a los ejes. Cuatro
/// líneas de aritmética, determinista y testeable sin simulador.
///
/// El brief pedía categorías de bitmask de SpriteKit; aquí la disciplina la pone
/// `ObstacleKind` y un `switch` exhaustivo que verifica el compilador, sin
/// arrastrar el motor de físicas (D-002 en docs/decisiones.md).
enum Collision {

    /// Los dos tramos macizos de un muro: del suelo al hueco, y del hueco al techo.
    /// Lo que se ve es exactamente lo que mata.
    static func solidRects(of wall: Wall) -> [CGRect] {
        let halfThickness = Tuning.World.wallThickness / 2
        return [
            CGRect(x: wall.x - halfThickness,
                   y: Tuning.World.floorY,
                   width: Tuning.World.wallThickness,
                   height: wall.gapBottomY - Tuning.World.floorY),
            CGRect(x: wall.x - halfThickness,
                   y: wall.gapTopY,
                   width: Tuning.World.wallThickness,
                   height: Tuning.World.ceilingY - wall.gapTopY)
        ].filter { $0.height > 0 }
    }

    static func circleIntersects(center: CGPoint, radius: CGFloat, rect: CGRect) -> Bool {
        // El punto del rectángulo más cercano al centro. Si cae dentro del radio,
        // hay contacto. Funciona igual en los lados y en las esquinas, que es donde
        // fallan las versiones "listas" de esta rutina.
        let closest = CGPoint(x: clamp(center.x, rect.minX, rect.maxX),
                              y: clamp(center.y, rect.minY, rect.maxY))
        let offset = center - closest
        return offset.dot(offset) < radius * radius
    }

    /// Contra qué ha chocado el farolillo, si es que ha chocado.
    static func hit(position: CGPoint, radius: CGFloat, chunks: [Chunk]) -> ObstacleKind? {
        if position.y - radius <= Tuning.World.floorY { return .floor }
        if position.y + radius >= Tuning.World.ceilingY { return .ceiling }

        for chunk in chunks {
            for rect in solidRects(of: chunk.wall)
            where circleIntersects(center: position, radius: radius, rect: rect) {
                return .wall
            }
        }
        return nil
    }
}
