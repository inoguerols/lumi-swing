import SwiftUI
import SpriteKit

@main
struct PenduloApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// El shell: la escena de juego siempre debajo, y encima el menú o el game over
/// según la fase. La escena no se destruye nunca — reconstruirla se comería el
/// presupuesto entero de 300 ms para volver a jugar.
@MainActor
struct RootView: View {

    @State private var engine: CoreHapticsEngine
    @State private var settings: GameSettings
    @State private var model: AppModel
    @State private var scene: GameScene
    @State private var showingDebug = false
    @State private var showingSettings = false

    init() {
        // Un único motor háptico para toda la app, compartido por la escena y por la
        // pantalla de debug: dos motores pelearían por el mismo Taptic Engine.
        let engine = CoreHapticsEngine()
        let settings = GameSettings()
        let model = AppModel()
        model.best = settings.best

        _engine = State(initialValue: engine)
        _settings = State(initialValue: settings)
        _model = State(initialValue: model)
        _scene = State(initialValue: GameScene(
            size: CGSize(width: Tuning.World.sceneWidth, height: Tuning.World.sceneHeight),
            haptics: engine,
            model: model,
            settings: settings))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene, preferredFramesPerSecond: 120)
                .ignoresSafeArea()

            switch model.phase {
            case .menu:
                MenuView(settings: settings,
                         onPlay: startRun,
                         onSettings: { showingSettings = true },
                         onLeaderboard: GameCenter.showLeaderboard,
                         onSecretDebug: { showingDebug = true })
                    .transition(.opacity)

            case .playing:
                EmptyView()

            case .dead:
                GameOverView(score: model.score,
                             best: model.best,
                             isNewRecord: model.isNewRecord,
                             onRetry: startRun,
                             onMenu: showMenu,
                             onLeaderboard: GameCenter.showLeaderboard)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showingDebug) { HapticsDebugView(engine: engine) }
        .sheet(isPresented: $showingSettings) { SettingsView(settings: settings) }
        .task {
            GameCenter.authenticate()
            scene.showMenuBackdrop()

            // Para capturas y depuración: `xcrun simctl launch ... -autoplay` entra
            // directo a jugar, sin atravesar el menú a mano.
            if ProcessInfo.processInfo.arguments.contains("-autoplay") {
                startRun()
            }
        }
    }

    private func startRun() {
        model.score = 0
        model.isNewRecord = false
        model.phase = .playing
        scene.startRun()
    }

    private func showMenu() {
        model.phase = .menu
        scene.showMenuBackdrop()
    }
}
