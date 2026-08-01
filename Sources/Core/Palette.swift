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
    /// Aclarados respecto a la primera versión: seguía siendo noche, pero tan cerrada
    /// que la selva no se veía y la pantalla parecía apagada. Sigue siendo de noche
    /// —lo exige la mecánica— con luz suficiente para que haya un mundo alrededor del
    /// jugador y no un vacío negro.
    static let night = SKColor(red: 0.12, green: 0.24, blue: 0.22, alpha: 1)
    static let deepNight = SKColor(red: 0.07, green: 0.17, blue: 0.16, alpha: 1)

    /// Las dos capas de vegetación del fondo. La lejana casi se confunde con el
    /// cielo; la cercana recorta contra él. Esa diferencia es la profundidad.
    static let canopyFar = SKColor(red: 0.17, green: 0.34, blue: 0.29, alpha: 1)
    /// Más clara que `trunk`/`bark`: es decoración, no letal, y la regla de Alto's
    /// (silueta oscura = peligro) exige que lo que mata sea lo más oscuro de la escena.
    static let canopyNear = SKColor(red: 0.12, green: 0.26, blue: 0.23, alpha: 1)

    /// La luna: de dónde viene la luz. Sin ella el verde del cielo era un color
    /// plano sin causa; con ella hay una fuente, y la escena tiene dirección.
    static let moon = SKColor(red: 0.88, green: 0.97, blue: 0.92, alpha: 1)
    static let moonHalo = SKColor(red: 0.55, green: 0.85, blue: 0.78, alpha: 0.30)
    /// Polvo luminoso lejano: no informa de nada, solo dice que el aire existe.
    static let pollen = SKColor(red: 0.60, green: 0.95, blue: 0.70, alpha: 1)

    // MARK: - El jugador (cálido)

    static let firefly = SKColor(red: 1.00, green: 0.88, blue: 0.40, alpha: 1)
    /// Color del halo del parpadeo (aditivo, detrás de todo). Ya no es el borde del
    /// cuerpo: F4 saca el latido del propio cuerpo para que este nunca se transparente.
    static let fireflyGlow = SKColor(red: 0.85, green: 1.00, blue: 0.45, alpha: 0.35)
    static let fireflyWing = SKColor(red: 0.80, green: 0.95, blue: 0.85, alpha: 0.50)
    /// Cuerpo de la luciérnaga: opaco de verdad (antes 0.85 de alpha, que es justo lo
    /// que hacía "transparentar" el material). Ahora es el color del cuerpo entero,
    /// no solo del detalle de ojos/antenas.
    static let fireflyDetail = SKColor(red: 0.15, green: 0.14, blue: 0.08, alpha: 1)

    // MARK: - Los asideros (fríos)

    static let moonflower = SKColor(red: 0.75, green: 0.95, blue: 0.90, alpha: 1)
    static let moonflowerCore = SKColor(red: 0.95, green: 1.00, blue: 0.98, alpha: 1)
    static let moonflowerGlow = SKColor(red: 0.45, green: 0.95, blue: 0.85, alpha: 0.40)
    /// El tallo del que cuelga la flor: la afordancia que dice «cuélgate de mí».
    static let stem = SKColor(red: 0.22, green: 0.40, blue: 0.34, alpha: 0.55)
    /// La liana tendida entre la luciérnaga y la flor cuando está agarrada.
    static let vine = SKColor(red: 0.62, green: 0.88, blue: 0.70, alpha: 0.80)

    // MARK: - El mundo sólido

    /// Lo letal es lo más oscuro de la escena (regla de Alto's Odyssey: silueta
    /// oscura en primer plano = peligro). Antes contrastaba MENOS con el cielo que
    /// `canopyNear`, que es pura decoración — jerarquía tonal invertida.
    static let trunk = SKColor(red: 0.05, green: 0.09, blue: 0.08, alpha: 1)
    static let trunkEdge = SKColor(red: 0.18, green: 0.28, blue: 0.24, alpha: 1)
    /// El canto del tronco que mira a la luna. Un rectángulo de un solo color es
    /// una barra; con un lado iluminado es madera.
    static let trunkLit = SKColor(red: 0.19, green: 0.31, blue: 0.27, alpha: 1)
    /// Vetas de corteza, casi negras: apenas se notan de cerca y son justo lo que
    /// separa una superficie de un relleno.
    static let bark = SKColor(red: 0.02, green: 0.04, blue: 0.03, alpha: 1)
    static let grass = SKColor(red: 0.13, green: 0.28, blue: 0.22, alpha: 1)
    static let leaf = SKColor(red: 0.11, green: 0.24, blue: 0.20, alpha: 1)
    /// Musgo lunar en los bordes del hueco: aclarado para que señale la puerta con
    /// más fuerza frente al tronco, ahora más oscuro.
    static let moss = SKColor(red: 0.50, green: 0.72, blue: 0.52, alpha: 1)
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
