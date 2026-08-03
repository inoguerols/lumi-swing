import GameKit

/// Game Center, tratado como lo que es: un extra. Si el jugador no ha iniciado
/// sesión, si está sin red o si Apple devuelve un error, **no pasa nada** — el
/// récord local es la fuente de verdad y la partida no se entera.
///
/// El identificador de la leaderboard es irreversible una vez publicado
/// (ver D-007 en docs/decisiones.md).
@MainActor
enum GameCenter {

    static let leaderboardID = "pendulo.highscore"
    /// Ritmo sostenido de la partida (mejor media de 10 s de `|velocidad|`), en
    /// m/s ×10 (un entero con un decimal implícito — los leaderboards de Game
    /// Center solo aceptan enteros). Renombrado desde `pendulo.maxspeed`: ese ID
    /// medía el pico, que saturaba en el tope físico y empataba a todo el mundo.
    /// Alta en App Store Connect pendiente, ver spec §4 (aún no existe, sin
    /// migración de puntuaciones previas).
    static let paceLeaderboardID = "pendulo.ritmo"

    /// El mundo de hoy: leaderboard **recurrente** de 24 h (medianoche UTC, el
    /// mismo reloj que rota la semilla de `DailyWorld`). Es la cita diaria: tus
    /// vecinos jugaron exactamente el mismo trazado que tú.
    static let dailyLeaderboardID = "pendulo.diario"

    /// Coronas: cuántos días se terminó nº1 del «Mundo de hoy». Acumulado
    /// clásico; la corona se reclama al abrir la app consultando la ocurrencia
    /// **anterior** del diario (ver `claimDailyCrownIfWon`).
    static let crownsLeaderboardID = "pendulo.coronas"

    /// Las tres vistas del ranking, en el idioma del juego y no en el de GameKit:
    /// así la interfaz no tiene que importar GameKit para hablar de clasificaciones.
    enum Scope: String, CaseIterable, Identifiable {
        case week, allTime, friends

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: "Semana"
            case .allTime: "Histórico"
            case .friends: "Amigos"
            }
        }
    }

    static func show(_ scope: Scope) {
        switch scope {
        case .week: showLeaderboard(timeScope: .week, playerScope: .global)
        case .allTime: showLeaderboard(timeScope: .allTime, playerScope: .global)
        case .friends: showLeaderboard(timeScope: .allTime, playerScope: .friendsOnly)
        }
    }

    private(set) static var isAuthenticated = false

    /// Se llama una vez al arrancar. La pantalla de inicio de sesión la presenta el
    /// sistema si hace falta; aquí no se fuerza nada ni se interrumpe al jugador.
    static func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { _, _ in
            isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    /// Abre la clasificación de Game Center sobre el juego.
    ///
    /// La presenta UIKit directamente y no SwiftUI porque `GKGameCenterViewController`
    /// trae su propia navegación y su propio botón de cerrar: envolverlo en un
    /// `sheet` daría dos barras y dos formas de salir.
    /// Apple mantiene gratis, sobre la misma leaderboard, un ranking de hoy, uno de
    /// la semana y el histórico. En un juego de «una vez más» el semanal importa más
    /// que el histórico: en el de siempre están los diez de siempre y nadie más se
    /// molesta en competir, mientras que el semanal se resetea y todo el mundo tiene
    /// una oportunidad cada lunes. Por eso es el que se abre por defecto.
    static func showLeaderboard(id: String = GameCenter.leaderboardID,
                                timeScope: GKLeaderboard.TimeScope = .week,
                                playerScope: GKLeaderboard.PlayerScope = .global) {
        guard isAuthenticated else { return }

        let controller = GKGameCenterViewController(leaderboardID: id,
                                                    playerScope: playerScope,
                                                    timeScope: timeScope)
        controller.gameCenterDelegate = delegate

        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else { return }

        root.present(controller, animated: true)
    }

    private static let delegate = LeaderboardDelegate()

    private final class LeaderboardDelegate: NSObject, GKGameCenterControllerDelegate {
        func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
            controller.dismiss(animated: true)
        }
    }

    /// Envía la puntuación y, si la partida trajo uno, el ritmo sostenido (en
    /// m/s). Una partida que no llega a durar la ventana de 10 s no genera ritmo
    /// (llega en 0) y ese envío se omite. Los dos leaderboards son
    /// independientes: el fallo de uno no debe impedir el envío del otro, así
    /// que van en tareas separadas.
    static func submit(score: Int, paceMetersPerSecond: Double) {
        guard isAuthenticated else { return }
        if score > 0 {
            Task {
                // Un fallo aquí es irrelevante para la partida: se ignora a propósito
                // y sin ruido. Lo que no puede pasar es que una leaderboard caída
                // interrumpa el "otra vez".
                try? await GKLeaderboard.submitScore(score,
                                                     context: 0,
                                                     player: GKLocalPlayer.local,
                                                     leaderboardIDs: [leaderboardID])
            }
            Task {
                try? await GKLeaderboard.submitScore(score,
                                                     context: 0,
                                                     player: GKLocalPlayer.local,
                                                     leaderboardIDs: [dailyLeaderboardID])
            }
        }
        if paceMetersPerSecond > 0 {
            let tenths = Int((paceMetersPerSecond * 10).rounded())
            Task {
                try? await GKLeaderboard.submitScore(tenths,
                                                     context: 0,
                                                     player: GKLocalPlayer.local,
                                                     leaderboardIDs: [paceLeaderboardID])
            }
        }
    }

    /// ¿Ganaste el mundo de ayer? Se comprueba al arrancar: la ocurrencia
    /// anterior del leaderboard recurrente guarda el podio final del día ya
    /// cerrado. Si el jugador local quedó nº1 y esa corona no estaba reclamada
    /// (`GameSettings.awardCrown` es monótona por día), se suma y se publica el
    /// total en `pendulo.coronas`. Todo fallo degrada en silencio, como el
    /// resto de Game Center: una corona jamás bloquea el juego.
    static func claimDailyCrownIfWon(settings: GameSettings) async {
        guard isAuthenticated else { return }
        guard let board = try? await GKLeaderboard.loadLeaderboards(IDs: [dailyLeaderboardID]).first,
              let previous = try? await board.loadPreviousOccurrence(),
              let startDate = previous.startDate,
              let local = try? await previous.loadEntries(for: [GKLocalPlayer.local],
                                                          timeScope: .allTime).0,
              local.rank == 1
        else { return }

        let day = DailyWorld.dayOrdinal(on: startDate)
        guard settings.awardCrown(forDay: day) else { return }
        let total = settings.crownsEarned
        Task {
            try? await GKLeaderboard.submitScore(total,
                                                 context: 0,
                                                 player: GKLocalPlayer.local,
                                                 leaderboardIDs: [crownsLeaderboardID])
        }
    }

    // MARK: - Mini-ranking de la pantalla de fin

    /// Una fila del mini-ranking: solo lo que `GameOverView` necesita para
    /// pintarla, sin que la vista tenga que importar GameKit.
    struct RankingRow: Identifiable, Sendable {
        let id: String
        let rank: Int
        let displayName: String
        /// Ya formateado para pintar. La vista no descifra unidades: el leaderboard
        /// de velocidad viaja en décimas de m/s y volverlas a m/s es trabajo de
        /// quien conoce el leaderboard, no de quien lo dibuja.
        let value: String
        let isLocalPlayer: Bool
    }

    /// Cuánto vale un mini-ranking ya cargado. Morir es frecuente y la pantalla de
    /// fin lo pide en cada muerte: sin caché son dos viajes a Game Center por
    /// partida, y Apple acaba estrangulando a quien pregunta tanto. Medio minuto es
    /// más que una partida y menos que una sesión.
    static let rankingCacheDuration: TimeInterval = 30

    /// El `GKLeaderboard` resuelto se cachea aparte y sin caducar: el objeto no
    /// cambia nunca, solo sus entradas, y resolverlo era la mitad de las llamadas.
    private static var leaderboards: [String: GKLeaderboard] = [:]
    private static var cachedRanking: [String: (rows: [RankingRow], loadedAt: Date)] = [:]

    private static func leaderboard(id: String) async throws -> GKLeaderboard? {
        if let cached = leaderboards[id] { return cached }
        let loaded = try await GKLeaderboard.loadLeaderboards(IDs: [id]).first
        leaderboards[id] = loaded
        return loaded
    }

    /// El líder y tus vecinos inmediatos (tú ±1), para el mini-ranking automático al
    /// morir (spec §4): cuando acabas de estrellarte, lo que mueve a repetir es a
    /// quién tienes justo delante, no un top absoluto inalcanzable.
    ///
    /// Ámbito **semanal**, el mismo que abre el botón «Clasificación»: dos ámbitos
    /// distintos en la misma pantalla harían que los números no cuadraran.
    ///
    /// Sin sesión, sin red o si Apple devuelve un error: lista vacía, en silencio —
    /// la misma degradación que ya usa `submit`.
    static func loadRankingAroundLocalPlayer(leaderboardID: String) async -> [RankingRow] {
        guard isAuthenticated else { return [] }
        if let cached = cachedRanking[leaderboardID],
           Date().timeIntervalSince(cached.loadedAt) < rankingCacheDuration {
            return cached.rows
        }

        do {
            guard let leaderboard = try await leaderboard(id: leaderboardID) else { return [] }

            // Game Center devuelve tu entrada pidas el rango que pidas, así que la
            // primera llamada trae al líder y, de paso, tu puesto.
            let (localEntry, leaders, _) = try await leaderboard.loadEntries(
                for: .global, timeScope: .week, range: NSRange(location: 1, length: 1))

            // Sin marca propia todavía, «tus vecinos» es la cabeza de la tabla.
            let start = max(1, (localEntry?.rank ?? 2) - 1)
            let (_, neighbours, _) = try await leaderboard.loadEntries(
                for: .global, timeScope: .week, range: NSRange(location: start, length: 3))

            var seen = Set<String>()
            let rows = (leaders + neighbours)
                .sorted { $0.rank < $1.rank }
                .filter { seen.insert($0.player.gamePlayerID).inserted }
                .map { Self.row(from: $0, leaderboardID: leaderboardID) }

            cachedRanking[leaderboardID] = (rows, Date())
            return rows
        } catch {
            return []
        }
    }

    private static func row(from entry: GKLeaderboard.Entry, leaderboardID: String) -> RankingRow {
        RankingRow(id: entry.player.gamePlayerID,
                   rank: entry.rank,
                   displayName: entry.player.displayName,
                   value: displayValue(score: entry.score, leaderboardID: leaderboardID),
                   isLocalPlayer: entry.player.gamePlayerID == GKLocalPlayer.local.gamePlayerID)
    }

    /// Los leaderboards de Game Center solo guardan enteros, así que el de ritmo
    /// viaja en décimas de m/s (ver `submit`). Deshacer esa multiplicación es cosa
    /// de aquí: la vista pinta el texto que se le da.
    static func displayValue(score: Int, leaderboardID: String) -> String {
        switch leaderboardID {
        case paceLeaderboardID: return speedText(metersPerSecond: Double(score) / 10)
        default: return score.formatted()
        }
    }

    /// «12,3 m/s» con el separador decimal del idioma del jugador (en inglés es un
    /// punto, no una coma) y la unidad traducida.
    static func speedText(metersPerSecond speed: Double) -> String {
        let number = speed.formatted(.number.precision(.fractionLength(1)))
        return "\(number) \(String(localized: "m/s"))"
    }
}
