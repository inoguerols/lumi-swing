import CoreGraphics
import Testing
@testable import LumiSwing

/// Pausa real al volver de segundo plano en plena partida (fondo, notificación a
/// pantalla completa, llamada, App Switcher). La decisión de fase vive en
/// `AppModel`, pura y sin SpriteKit — lo mismo que hace `GameScene.update(_:)` con
/// su guarda `model.phase == .playing` se reproduce aquí para probarlo sin
/// necesitar una `SKScene`.
@Suite("Pausa por interrupción")
@MainActor
struct PauseTests {

    @Test("En pausa, la simulación no avanza")
    func pausedSimulationDoesNotAdvance() {
        let model = AppModel()
        model.phase = .playing
        var simulation = GameSimulation(seed: 1)
        _ = simulation.advance(dt: 1.0 / 120, holding: false)

        model.pauseIfPlaying()
        #expect(model.phase == .paused)

        let frozenPosition = simulation.body.position
        let frozenScore = simulation.score

        // La guarda real de `GameScene.update(_:)`: fuera de `.playing` no se
        // llama a `advance`.
        if model.phase == .playing {
            _ = simulation.advance(dt: 1.0 / 120, holding: true)
        }

        #expect(simulation.body.position == frozenPosition)
        #expect(simulation.score == frozenScore)
    }

    @Test("Reanudar no resetea nada de la partida")
    func resumeKeepsState() {
        let model = AppModel()
        model.phase = .playing
        model.score = 12
        model.bestPaceMetersPerSecond = 3.4

        model.pauseIfPlaying()
        #expect(model.phase == .paused)

        model.resumeIfPaused()
        #expect(model.phase == .playing)
        #expect(model.score == 12)
        #expect(model.bestPaceMetersPerSecond == 3.4)
    }

    @Test("Fondo en plena partida termina en pausa, y volver a activo no la levanta sola")
    func backgroundDuringPlayEndsPaused() {
        let model = AppModel()
        model.phase = .playing

        // Ir a segundo plano.
        model.pauseIfPlaying()
        #expect(model.phase == .paused)

        // Volver a activo: nada en `AppModel` reanuda por su cuenta — eso
        // solo lo hace el botón «Continuar» (`resumeIfPaused`), nunca la
        // transición de `scenePhase` en sí misma.
        #expect(model.phase == .paused)
    }

    @Test("Pausar fuera de una partida en curso no hace nada")
    func pauseOnlyAffectsPlaying() {
        let model = AppModel()
        model.phase = .menu
        model.pauseIfPlaying()
        #expect(model.phase == .menu)

        model.phase = .dead
        model.pauseIfPlaying()
        #expect(model.phase == .dead)
    }

    @Test("Reanudar fuera de pausa no hace nada")
    func resumeOnlyAffectsPaused() {
        let model = AppModel()
        model.phase = .menu
        model.resumeIfPaused()
        #expect(model.phase == .menu)
    }
}
