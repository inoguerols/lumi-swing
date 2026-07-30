import Foundation
import Testing
@testable import Pendulo

@Suite("Récord y ajustes")
@MainActor
struct SettingsTests {

    /// Un `UserDefaults` propio por test: tocar el del sistema haría que un test
    /// dejara el récord del simulador cambiado y que el siguiente empezara sucio.
    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suite = "pendulo.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("En la primera ejecución, hápticos y sonido están encendidos")
    func firstLaunchDefaults() {
        let settings = GameSettings(defaults: isolatedDefaults("first"))
        // `bool(forKey:)` devuelve false para una clave que no existe: si el código
        // usara eso, el juego arrancaría mudo la primera vez que se abre.
        #expect(settings.hapticsEnabled)
        #expect(settings.audioEnabled)
        #expect(settings.best == 0)
        #expect(!settings.visibleBlindZones)
    }

    @Test("El récord solo sube")
    func recordOnlyImproves() {
        let settings = GameSettings(defaults: isolatedDefaults("record"))

        #expect(settings.record(score: 7))
        #expect(settings.best == 7)

        #expect(!settings.record(score: 3))
        #expect(settings.best == 7)

        #expect(settings.record(score: 8))
        #expect(settings.best == 8)
    }

    @Test("El récord sobrevive a cerrar la app")
    func recordPersists() {
        let defaults = isolatedDefaults("persist")
        let first = GameSettings(defaults: defaults)
        first.record(score: 42)

        let reopened = GameSettings(defaults: defaults)
        #expect(reopened.best == 42)
    }

    @Test("Apagar los hápticos activa solo el modo asistido")
    func disablingHapticsTurnsOnAssistedMode() {
        let settings = GameSettings(defaults: isolatedDefaults("assist"))
        #expect(!settings.needsAssistedBlindZones)

        // Quien apaga los hápticos se queda sin el canal que sustituía a la vista;
        // dejarle las zonas a ciegas tal cual sería hacerle el juego imposible en
        // vez de distinto.
        settings.hapticsEnabled = false
        #expect(settings.needsAssistedBlindZones)

        settings.hapticsEnabled = true
        #expect(!settings.needsAssistedBlindZones)

        // Y también se puede pedir por accesibilidad, con los hápticos encendidos.
        settings.visibleBlindZones = true
        #expect(settings.needsAssistedBlindZones)
    }
}
