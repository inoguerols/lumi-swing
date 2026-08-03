import Foundation
import Testing
@testable import LumiSwing

@Suite("Mundo diario")
struct DailyWorldTests {

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = hour
        return DailyWorld.utcCalendar.date(from: c)!
    }

    @Test("El mismo día UTC da la misma semilla, a cualquier hora")
    func sameDaySameSeed() {
        #expect(DailyWorld.seed(on: date(2026, 8, 3, hour: 0))
            == DailyWorld.seed(on: date(2026, 8, 3, hour: 23)))
    }

    @Test("Días distintos dan semillas distintas")
    func differentDaysDifferentSeeds() {
        let seeds = (1...30).map { DailyWorld.seed(on: date(2026, 8, $0)) }
        #expect(Set(seeds).count == 30)
    }

    @Test("Días consecutivos dan ordinales consecutivos")
    func ordinalsAreConsecutive() {
        #expect(DailyWorld.dayOrdinal(on: date(2026, 8, 4))
            == DailyWorld.dayOrdinal(on: date(2026, 8, 3)) + 1)
    }

    @Test("La semilla diaria nunca colisiona con la de demo/tests")
    func neverCollidesWithFixedSeed() {
        for offset in 0..<3653 {  // 10 años de días
            let day = DailyWorld.utcCalendar.date(byAdding: .day, value: offset,
                                                  to: date(2026, 1, 1))!
            #expect(DailyWorld.seed(on: day) != Tuning.WorldGen.initialSeed)
        }
    }
}
