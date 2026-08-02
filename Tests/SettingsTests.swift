import Foundation
import Testing
@testable import LumiSwing

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

    @Test("El cartel de aviso se repite hasta cruzar N muros a ciegas, y luego calla")
    func blindNoticeStopsAfterThreshold() {
        let settings = GameSettings(defaults: isolatedDefaults("notice"))
        #expect(settings.blindWallsCrossed == 0)
        #expect(settings.needsBlindNotice)

        for _ in 0..<(Tuning.BlindZone.noticeThreshold - 1) {
            settings.blindWallsCrossed += 1
            #expect(settings.needsBlindNotice)
        }

        settings.blindWallsCrossed += 1
        #expect(!settings.needsBlindNotice)
    }

    @Test("Las zonas a ciegas vividas se cuentan entre partidas, no dentro de una")
    func blindZonesEnteredPersists() {
        let defaults = isolatedDefaults("blindZones")
        let first = GameSettings(defaults: defaults)
        // Clave nueva: nadie ha gastado la enseñanza todavía, así que todo el
        // mundo arranca con el eco al máximo.
        #expect(first.blindZonesEntered == 0)
        #expect(BlindZones.ghostAlpha(zonesExperienced: first.blindZonesEntered)
                == Tuning.BlindTeaching.initialAlpha)

        first.blindZonesEntered += 1
        first.blindZonesEntered += 1

        let reopened = GameSettings(defaults: defaults)
        #expect(reopened.blindZonesEntered == 2)
        #expect(BlindZones.ghostAlpha(zonesExperienced: reopened.blindZonesEntered)
                < Tuning.BlindTeaching.initialAlpha)
    }
}
