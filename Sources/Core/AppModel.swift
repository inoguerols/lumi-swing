import Observation

/// Estado que la UI de SwiftUI observa. `GameScene` escribe aquí desde
/// `update(_:)`, que ya corre en el hilo principal: sin saltos de actor por frame.
@Observable
@MainActor
final class AppModel {
    enum Phase {
        case menu, playing, dead
    }

    var phase: Phase = .menu
    var score = 0
    var best = 0
    var isNewRecord = false
}
