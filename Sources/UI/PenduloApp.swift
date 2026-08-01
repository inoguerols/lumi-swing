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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            // El enjambre solo fuera de la partida: durante el juego competiría con
            // las luces que sí informan, y a ciegas sería directamente ruido.
            if model.phase != .playing {
                FireflySwarm(count: 18)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            switch model.phase {
            case .menu:
                MenuView(settings: settings,
                         onPlay: startRun,
                         onSettings: { showingSettings = true },
                         onLeaderboard: { GameCenter.show(.week) },
                         onSecretDebug: { showingDebug = true })
                    .transition(menuTransition)

            case .playing:
                EmptyView()

            case .dead:
                GameOverView(score: model.score,
                             best: model.best,
                             isNewRecord: model.isNewRecord,
                             onRetry: startRun,
                             onMenu: showMenu,
                             onLeaderboard: { GameCenter.show(.week) })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // El motor háptico muere con las interrupciones (llamada, Siri, suspensión) y
        // nadie lo rearrancaba: era el "a veces no vibra" (docs/lenguaje-haptico.md §7).
        .onChange(of: scenePhase) { _, phase in
            let engine = self.engine
            if phase == .active {
                Task { await engine.ensureRunning() }
            } else {
                // Un continuous vibrando en background es un bug reportable.
                Task { await engine.stopContinuous() }
            }
        }
        // El motor filtra cada canal por su cuenta, así que hápticos OFF + sonido ON
        // da solo sonido. Aquí es donde vive el interruptor, así que aquí se empuja.
        .onChange(of: [settings.hapticsEnabled, settings.audioEnabled], initial: true) { _, channels in
            let engine = self.engine
            Task { await engine.setChannels(haptics: channels[0], audio: channels[1]) }
        }
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

    /// La tarjeta del menú entra con un golpe de muelle, no con un fundido plano:
    /// es la primera imagen del juego y un `.opacity` no cuenta nada. Con Reduce
    /// Motion se cae a un fundido corto, sin escala.
    private var menuTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .scale(scale: 0.85).combined(with: .opacity)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7)),
                removal: .opacity)
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
