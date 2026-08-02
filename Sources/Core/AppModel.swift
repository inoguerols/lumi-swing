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
}
