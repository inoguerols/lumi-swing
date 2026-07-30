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
        static let haptics = "pendulo.haptics"
        static let audio = "pendulo.audio"
        static let visibleBlindZones = "pendulo.visibleBlindZones"
        static let reduceFlashing = "pendulo.reduceFlashing"
    }

    private let defaults: UserDefaults

    var best: Int { didSet { defaults.set(best, forKey: Key.best) } }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.best = defaults.integer(forKey: Key.best)
        // Los interruptores nacen encendidos, así que en la primera ejecución
        // (`object(forKey:) == nil`) hay que devolver `true`, no el `false` que
        // daría `bool(forKey:)`.
        self.hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        self.audioEnabled = defaults.object(forKey: Key.audio) as? Bool ?? true
        self.visibleBlindZones = defaults.bool(forKey: Key.visibleBlindZones)
        self.reduceFlashing = defaults.bool(forKey: Key.reduceFlashing)
    }

    /// Devuelve `true` si el resultado es un récord nuevo.
    @discardableResult
    func record(score: Int) -> Bool {
        guard score > best else { return false }
        best = score
        return true
    }

    /// Cuándo hay que enseñar los muros a ciegas de todos modos: porque el jugador
    /// lo ha pedido, o porque ha apagado el canal que los sustituía.
    var needsAssistedBlindZones: Bool {
        visibleBlindZones || !hapticsEnabled
    }
}
