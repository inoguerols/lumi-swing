import Observation

/// Estado que la UI de SwiftUI observa. `GameScene` escribe aquí desde
/// `update(_:)`, que ya corre en el hilo principal: sin saltos de actor por frame.
@Observable
@MainActor
final class AppModel {
    enum Phase {
        case menu, playing, dead
    }

    /// En S1 se entra directo a jugar; el menú llega en S6.
    var phase: Phase = .playing
    var score = 0
    var best = 0
}
