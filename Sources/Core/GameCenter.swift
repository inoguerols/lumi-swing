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

    /// Abre la clasificación de Game Center sobre el juego.
    ///
    /// La presenta UIKit directamente y no SwiftUI porque `GKGameCenterViewController`
    /// trae su propia navegación y su propio botón de cerrar: envolverlo en un
    /// `sheet` daría dos barras y dos formas de salir.
    static func showLeaderboard() {
        guard isAuthenticated else { return }

        let controller = GKGameCenterViewController(leaderboardID: leaderboardID,
                                                    playerScope: .global,
                                                    timeScope: .allTime)
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
