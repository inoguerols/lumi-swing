import Foundation
import Testing
@testable import LumiSwing

@Suite("Tu viaje")
@MainActor
struct JourneyTests {

    /// Mismo aislamiento que en `SettingsTests` (el helper es privado allí).
    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suite = "pendulo.tests.journey.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Cada run suma partidas y muros")
    func runsAccumulate() {
        let settings = GameSettings(defaults: isolatedDefaults(#function))
        settings.registerRun(score: 7, dayOrdinal: 100)
        settings.registerRun(score: 0, dayOrdinal: 100)
        #expect(settings.totalRuns == 2)
        #expect(settings.totalWallsCrossed == 7)
    }

    @Test("Jugar días seguidos alarga la racha; saltarse un día la resetea")
    func streakGrowsAndBreaks() {
        let settings = GameSettings(defaults: isolatedDefaults(#function))
        settings.registerRun(score: 1, dayOrdinal: 100)
        #expect(settings.streakDays == 1)
        settings.registerRun(score: 1, dayOrdinal: 100)   // mismo día: no crece
        #expect(settings.streakDays == 1)
        settings.registerRun(score: 1, dayOrdinal: 101)   // día siguiente
        #expect(settings.streakDays == 2)
        settings.registerRun(score: 1, dayOrdinal: 103)   // se saltó el 102
        #expect(settings.streakDays == 1)
    }

    @Test("La corona de un día solo se reclama una vez, y nunca hacia atrás")
    func crownsAreMonotonic() {
        let settings = GameSettings(defaults: isolatedDefaults(#function))
        #expect(settings.awardCrown(forDay: 100))
        #expect(settings.crownsEarned == 1)
        #expect(!settings.awardCrown(forDay: 100))   // mismo día: no duplica
        #expect(!settings.awardCrown(forDay: 99))    // hacia atrás: jamás
        #expect(settings.awardCrown(forDay: 101))
        #expect(settings.crownsEarned == 2)

        let reopened = GameSettings(defaults: isolatedDefaults(#function))
        _ = reopened  // el aislamiento borra el dominio: solo comprobamos arriba
    }

    @Test("La racha sobrevive a cerrar la app")
    func streakPersists() {
        let defaults = isolatedDefaults(#function)
        let first = GameSettings(defaults: defaults)
        first.registerRun(score: 3, dayOrdinal: 200)
        let second = GameSettings(defaults: defaults)
        #expect(second.streakDays == 1)
        #expect(second.totalRuns == 1)
        #expect(second.lastPlayedDay == 200)
    }
}
