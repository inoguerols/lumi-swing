import SpriteKit

/// Selva nocturna. La paleta vive aparte de `Tuning.swift` a propósito: un color
/// no cambia cómo se juega, y mezclar RGB con constantes de física haría ilegible
/// el fichero que más importa del proyecto (ver D-009 en docs/decisiones.md).
///
/// La regla que ordena todo: **el jugador es cálido, los asideros son fríos**.
/// Antes todo era ámbar y el ojo tenía que separar "yo" de "de qué me agarro" por
/// el tamaño; con dos temperaturas se separan solos, también en la penumbra.
enum Palette {

    // MARK: - Cielo

    /// Los dos extremos del ciclo. Ambos son noche cerrada: el juego va de una luz
    /// pequeña en un sitio muy oscuro, y un cielo claro apagaría al personaje.
    static let night = SKColor(red: 0.04, green: 0.09, blue: 0.08, alpha: 1)
    static let deepNight = SKColor(red: 0.02, green: 0.05, blue: 0.05, alpha: 1)

    /// Las dos capas de vegetación del fondo. La lejana casi se confunde con el
    /// cielo; la cercana recorta contra él. Esa diferencia es la profundidad.
    static let canopyFar = SKColor(red: 0.05, green: 0.12, blue: 0.11, alpha: 1)
    static let canopyNear = SKColor(red: 0.03, green: 0.08, blue: 0.08, alpha: 1)
    /// Polvo luminoso lejano: no informa de nada, solo dice que el aire existe.
    static let pollen = SKColor(red: 0.60, green: 0.95, blue: 0.70, alpha: 1)

    // MARK: - El jugador (cálido)

    static let firefly = SKColor(red: 1.00, green: 0.88, blue: 0.40, alpha: 1)
    static let fireflyGlow = SKColor(red: 0.85, green: 1.00, blue: 0.45, alpha: 0.35)
    static let fireflyWing = SKColor(red: 0.80, green: 0.95, blue: 0.85, alpha: 0.50)
    static let fireflyDetail = SKColor(red: 0.15, green: 0.14, blue: 0.08, alpha: 0.85)

    // MARK: - Los asideros (fríos)

    static let moonflower = SKColor(red: 0.75, green: 0.95, blue: 0.90, alpha: 1)
    static let moonflowerCore = SKColor(red: 0.95, green: 1.00, blue: 0.98, alpha: 1)
    static let moonflowerGlow = SKColor(red: 0.45, green: 0.95, blue: 0.85, alpha: 0.40)
    /// El tallo del que cuelga la flor: la afordancia que dice «cuélgate de mí».
    static let stem = SKColor(red: 0.22, green: 0.40, blue: 0.34, alpha: 0.55)
    /// La liana tendida entre la luciérnaga y la flor cuando está agarrada.
    static let vine = SKColor(red: 0.62, green: 0.88, blue: 0.70, alpha: 0.80)

    // MARK: - El mundo sólido

    static let trunk = SKColor(red: 0.10, green: 0.16, blue: 0.14, alpha: 1)
    static let trunkEdge = SKColor(red: 0.18, green: 0.28, blue: 0.24, alpha: 1)
    /// Musgo lunar en los bordes del hueco: señala la puerta, no la pared.
    static let moss = SKColor(red: 0.42, green: 0.62, blue: 0.45, alpha: 1)
    static let ground = SKColor(red: 0.05, green: 0.10, blue: 0.09, alpha: 1)

    // MARK: - Nombres que usa el HUD

    static let lantern = firefly
    static let rope = vine

    // MARK: - Ciclo de cielo

    /// Cielo en la fase `t` (0...1) del ciclo. Coseno en vez de rampa para que ida
    /// y vuelta sean simétricas y no haya un salto al cerrar el ciclo.
    static func sky(at t: CGFloat) -> SKColor {
        let wave = (1 - cos(t * 2 * .pi)) / 2
        return blend(night, deepNight, wave)
    }

    static func blend(_ from: SKColor, _ to: SKColor, _ t: CGFloat) -> SKColor {
        var fromRed: CGFloat = 0, fromGreen: CGFloat = 0, fromBlue: CGFloat = 0, fromAlpha: CGFloat = 0
        var toRed: CGFloat = 0, toGreen: CGFloat = 0, toBlue: CGFloat = 0, toAlpha: CGFloat = 0
        from.getRed(&fromRed, green: &fromGreen, blue: &fromBlue, alpha: &fromAlpha)
        to.getRed(&toRed, green: &toGreen, blue: &toBlue, alpha: &toAlpha)
        return SKColor(red: lerp(fromRed, toRed, t),
                       green: lerp(fromGreen, toGreen, t),
                       blue: lerp(fromBlue, toBlue, t),
                       alpha: lerp(fromAlpha, toAlpha, t))
    }
}
