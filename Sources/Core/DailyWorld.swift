import Foundation

/// El mundo del día: la fecha (en UTC) decide la semilla, así que todo el
/// mundo juega el mismo trazado el mismo día y el leaderboard diario compara
/// manzanas con manzanas. Mañana, mundo nuevo — la memorización caduca a
/// medianoche. La demo y los tests NO pasan por aquí: usan la semilla fija
/// de `Tuning.WorldGen.initialSeed` (el plan de DemoPilot depende de ella).
enum DailyWorld {
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Días de calendario UTC desde el epoch. Es el mismo reloj que usa la
    /// racha: «volví hoy» significa lo mismo en el mundo y en la racha.
    static func dayOrdinal(on date: Date = Date(),
                           calendar: Calendar = DailyWorld.utcCalendar) -> Int {
        calendar.dateComponents([.day],
                                from: Date(timeIntervalSince1970: 0),
                                to: date).day ?? 0
    }

    static func seed(on date: Date = Date(),
                     calendar: Calendar = DailyWorld.utcCalendar) -> UInt64 {
        // SplitMix64 sobre el ordinal del día: días consecutivos → semillas
        // sin correlación. El +1 evita el día 0 → estado 0.
        var rng = SplitMix64(seed: UInt64(dayOrdinal(on: date, calendar: calendar) + 1)
            &* 0x9E37_79B9_7F4A_7C15)
        var seed = rng.next()
        if seed == Tuning.WorldGen.initialSeed { seed &+= 1 }  // jamás el mundo de la demo
        return seed
    }
}
