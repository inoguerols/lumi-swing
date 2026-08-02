import Foundation
import Observation

/// Lo único que el juego recuerda entre partidas: un número y cuatro
/// interruptores. `UserDefaults` es exactamente del tamaño del problema; montar
/// SwiftData para esto sería construir un almacén y llenarlo con una postal.
@Observable
@MainActor
final class GameSettings {

    private enum Key {
        static let best = "pendulo.best"
        static let bestPace = "pendulo.bestPace"
        static let haptics = "pendulo.haptics"
        static let audio = "pendulo.audio"
        static let visibleBlindZones = "pendulo.visibleBlindZones"
        static let reduceFlashing = "pendulo.reduceFlashing"
        static let blindWallsCrossed = "pendulo.blindWallsCrossed"
        static let blindZonesEntered = "pendulo.blindZonesEntered"
    }

    private let defaults: UserDefaults

    var best: Int { didSet { defaults.set(best, forKey: Key.best) } }
    /// Récord personal de ritmo sostenido (mejor media de 10 s de `|velocidad|`),
    /// en m/s. Sustituye al antiguo récord de pico, que saturaba en el tope
    /// físico del péndulo — clave nueva a propósito, sin migrar el valor viejo:
    /// medían cosas distintas.
    var bestPace: Double { didSet { defaults.set(bestPace, forKey: Key.bestPace) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    var audioEnabled: Bool { didSet { defaults.set(audioEnabled, forKey: Key.audio) } }

    /// Accesibilidad: mantiene la penumbra y el ×2, pero deja los muros con un
    /// contorno tenue. Para quien no percibe los hápticos y no quiere depender del
    /// audio. Cambia el canal, no la mecánica.
    var visibleBlindZones: Bool {
        didSet { defaults.set(visibleBlindZones, forKey: Key.visibleBlindZones) }
    }

    /// Reduce los cambios bruscos de luminancia al entrar y salir de las zonas a
    /// ciegas.
    var reduceFlashing: Bool {
        didSet { defaults.set(reduceFlashing, forKey: Key.reduceFlashing) }
    }

    /// Muros a ciegas cruzados con éxito en toda la vida de la instalación. No es
    /// un bool de "ya lo vio una vez": el cartel se repite hasta que el jugador
    /// haya demostrado que sabe cruzar a ciegas varias veces, no solo que abrió
    /// la app una vez.
    var blindWallsCrossed: Int {
        didSet { defaults.set(blindWallsCrossed, forKey: Key.blindWallsCrossed) }
    }

    /// Zonas a ciegas en las que el jugador ha entrado en toda la vida de la
    /// instalación. Gobierna el eco de aprendizaje (`BlindZones.ghostAlpha`), y
    /// se cuenta por zonas y no por muros porque lo que se aprende es el paso
    /// completo, no cada tronco. Clave nueva a propósito: nadie ha tenido la
    /// enseñanza todavía, así que todo el mundo empieza en 0.
    var blindZonesEntered: Int {
        didSet { defaults.set(blindZonesEntered, forKey: Key.blindZonesEntered) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.best = defaults.integer(forKey: Key.best)
        self.bestPace = defaults.double(forKey: Key.bestPace)
        // Los interruptores nacen encendidos, así que en la primera ejecución
        // (`object(forKey:) == nil`) hay que devolver `true`, no el `false` que
        // daría `bool(forKey:)`.
        self.hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        self.audioEnabled = defaults.object(forKey: Key.audio) as? Bool ?? true
        self.visibleBlindZones = defaults.bool(forKey: Key.visibleBlindZones)
        self.reduceFlashing = defaults.bool(forKey: Key.reduceFlashing)
        self.blindWallsCrossed = defaults.integer(forKey: Key.blindWallsCrossed)
        self.blindZonesEntered = defaults.integer(forKey: Key.blindZonesEntered)
    }

    /// Devuelve `true` si el resultado es un récord nuevo.
    @discardableResult
    func record(score: Int) -> Bool {
        guard score > best else { return false }
        best = score
        return true
    }

    /// Igual que `record(score:)`, para el récord de ritmo sostenido.
    @discardableResult
    func record(paceMetersPerSecond pace: Double) -> Bool {
        guard pace > bestPace else { return false }
        bestPace = pace
        return true
    }

    /// Cuándo hay que enseñar los muros a ciegas de todos modos: porque el jugador
    /// lo ha pedido, o porque ha apagado el canal que los sustituía.
    var needsAssistedBlindZones: Bool {
        visibleBlindZones || !hapticsEnabled
    }

    /// Mientras no se hayan cruzado `Tuning.BlindZone.noticeThreshold` muros a
    /// ciegas, el cartel explicativo se sigue enseñando en cada zona nueva.
    var needsBlindNotice: Bool {
        blindWallsCrossed < Tuning.BlindZone.noticeThreshold
    }
}
