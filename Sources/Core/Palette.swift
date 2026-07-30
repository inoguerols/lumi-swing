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
}
