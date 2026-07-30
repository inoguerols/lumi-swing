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

    private(set) static var isAuthenticated = false

    /// Se llama una vez al arrancar. La pantalla de inicio de sesión la presenta el
    /// sistema si hace falta; aquí no se fuerza nada ni se interrumpe al jugador.
    static func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { _, _ in
            isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    static func submit(score: Int) {
        guard isAuthenticated, score > 0 else { return }
        Task {
            // Un fallo aquí es irrelevante para la partida: se ignora a propósito y
            // sin ruido. Lo que no puede pasar es que una leaderboard caída
            // interrumpa el "otra vez".
            try? await GKLeaderboard.submitScore(score,
                                                 context: 0,
                                                 player: GKLocalPlayer.local,
                                                 leaderboardIDs: [leaderboardID])
        }
    }
}
