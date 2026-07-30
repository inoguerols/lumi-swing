import SpriteKit

/// La paleta vive aparte de `Tuning.swift` a propósito: un color no cambia cómo
/// se juega, y mezclar RGB con constantes de física haría ilegible el fichero que
/// más importa del proyecto (ver D-009 en docs/decisiones.md).
enum Palette {
    static let night = SKColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1)
    static let lantern = SKColor(red: 1.00, green: 0.78, blue: 0.42, alpha: 1)
    static let lanternGlow = SKColor(red: 1.00, green: 0.60, blue: 0.25, alpha: 0.35)
    static let anchorIdle = SKColor(red: 0.95, green: 0.72, blue: 0.38, alpha: 0.55)
    static let rope = SKColor(red: 1.00, green: 0.85, blue: 0.60, alpha: 0.75)
    static let wall = SKColor(red: 0.13, green: 0.16, blue: 0.26, alpha: 1)
    static let wallEdge = SKColor(red: 0.35, green: 0.42, blue: 0.60, alpha: 1)
    static let bounds = SKColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1)

    /// Los dos extremos del ciclo de cielo. Ambos son noche: el juego va de
    /// farolillos, y un cielo diurno apagaría lo único que ilumina la escena. Lo que
    /// cambia es la profundidad de esa noche.
    static let deepNight = SKColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1)

    /// Cielo en la fase `t` (0...1) del ciclo. Coseno en vez de rampa para que ida y
    /// vuelta sean simétricas y no haya un salto al cerrar el ciclo.
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
