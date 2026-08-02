import Observation

/// Estado que la UI de SwiftUI observa. `GameScene` escribe aquí desde
/// `update(_:)`, que ya corre en el hilo principal: sin saltos de actor por frame.
@Observable
@MainActor
final class AppModel {
    enum Phase {
        case intro, menu, playing, dead
    }

    /// Arranca en `.intro` (el plano de apertura); el shell lo baja a `.menu` en
    /// cuanto la cámara termina — o directamente si Reduce Motion o `-skip-intro`.
    var phase: Phase = .intro
    var score = 0
    var best = 0
    var isNewRecord = false
    /// Ritmo sostenido de la última partida (mejor media de 10 s de
    /// `|velocidad|`), ya en m/s (spec de ritmo). 0 si la partida no llegó a
    /// durar la ventana completa. Solo se enseña al morir: no hay velocímetro
    /// en vivo.
    var bestPaceMetersPerSecond: Double = 0

    /// Cierre de partida: resultado a la pantalla de fin, al récord persistido y a
    /// Game Center, en un único sitio.
    ///
    /// Vive aquí y no en `GameScene` porque es lo único del camino de muerte que se
    /// puede ejercitar sin un `SKScene`: si esto se queda en el bucle de la escena,
    /// que el ritmo sostenido llegue a la pantalla de fin no lo comprueba nadie.
    func endRun(score: Int, bestPaceMetersPerSecond pace: Double, settings: GameSettings) {
        self.score = score
        bestPaceMetersPerSecond = pace
        isNewRecord = settings.record(score: score)
        best = settings.best
        settings.record(paceMetersPerSecond: pace)
        GameCenter.submit(score: score, paceMetersPerSecond: pace)
        phase = .dead
    }
}
