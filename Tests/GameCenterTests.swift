import Testing
@testable import LumiSwing

/// Sin invocar `GameCenter.authenticate()`, `isAuthenticated` se queda en su
/// valor inicial (`false`) durante todo el proceso de test — es exactamente el
/// escenario "sin sesión" que hay que degradar en silencio (spec §4), y no
/// requiere ningún doble ni protocolo para provocarlo.
@Suite("Game Center: degradación sin sesión")
@MainActor
struct GameCenterTests {

    @Test("Los dos leaderboards son distintos y el nuevo es el documentado")
    func leaderboardIDsAreDistinct() {
        #expect(GameCenter.leaderboardID == "pendulo.highscore")
        #expect(GameCenter.paceLeaderboardID == "pendulo.ritmo")
        #expect(GameCenter.leaderboardID != GameCenter.paceLeaderboardID)
    }

    @Test("Sin sesión, enviar puntuación y ritmo no revienta")
    func submitWithoutSessionIsANoOp() {
        #expect(!GameCenter.isAuthenticated)
        // No hay nada que comprobar salvo que esto no lance ni cuelgue: sin
        // sesión, `submit` debe volver de inmediato.
        GameCenter.submit(score: 42, paceMetersPerSecond: 12.3)
    }

    @Test("Sin sesión, el mini-ranking degrada a lista vacía")
    func rankingWithoutSessionIsEmpty() async {
        #expect(!GameCenter.isAuthenticated)
        let rows = await GameCenter.loadRankingAroundLocalPlayer(
            leaderboardID: GameCenter.leaderboardID)
        #expect(rows.isEmpty)
    }

    /// El leaderboard de ritmo viaja en décimas (Game Center solo guarda
    /// enteros): 123 son 12,3 m/s, y quien lo deshace es quien construye la fila,
    /// no la vista.
    @Test("Las décimas del leaderboard de ritmo se pintan ya como m/s")
    func speedRowsAreFormattedAsMetersPerSecond() {
        let speed = GameCenter.displayValue(score: 123,
                                            leaderboardID: GameCenter.paceLeaderboardID)
        #expect(speed.contains("12"))
        #expect(speed.contains("m/s"))
        #expect(speed != "123")

        // El de puntuación no lleva unidad: son muros cruzados.
        let score = GameCenter.displayValue(score: 123,
                                            leaderboardID: GameCenter.leaderboardID)
        #expect(!score.contains("m/s"))
    }
}

@Suite("Leaderboard diario")
@MainActor
struct DailyLeaderboardTests {

    @Test("El leaderboard diario tiene ID propio")
    func dailyLeaderboardHasOwnID() {
        #expect(GameCenter.dailyLeaderboardID == "pendulo.diario")
        #expect(GameCenter.dailyLeaderboardID != GameCenter.leaderboardID)
        #expect(GameCenter.dailyLeaderboardID != GameCenter.paceLeaderboardID)
    }

    @Test("El valor del diario se muestra como puntos enteros")
    func dailyDisplayValueIsPlainScore() {
        #expect(GameCenter.displayValue(score: 17,
                                        leaderboardID: GameCenter.dailyLeaderboardID) == "17")
    }
}
