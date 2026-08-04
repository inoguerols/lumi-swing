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
    /// Si el hardware tiene Taptic Engine: decide el texto del aviso del menú
    /// («juega con el móvil en la mano» vs «el audio te guía»). Optimista hasta
    /// que el motor responda: el aviso equivocado un frame no se llega a ver.
    @State private var hapticsSupported = true
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
            // 60 Hz fijo: a 120 el iPhone se calentaba en sesiones largas y el
            // péndulo no gana suavidad apreciable con el doble de frames.
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .ignoresSafeArea()
                // Altura fija, ancho según el aspecto de la vista (D-023): en
                // iPad/Mac la escena se ensancha en vez de recortarse en
                // vertical, que escondería suelo, techo y la flor llave. Nadie
                // lee `scene.size` después del init, así que mutarlo es seguro.
                .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize in
                    scene.size = Tuning.World.sceneSize(for: viewSize)
                }

            // El enjambre solo fuera de la partida: durante el juego competiría con
            // las luces que sí informan, y a ciegas sería directamente ruido.
            if model.phase != .playing {
                FireflySwarm(count: 18)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            switch model.phase {
            case .intro:
                // El plano de apertura corre en la escena; un toque lo salta.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { scene.skipIntro() }

            case .menu:
                MenuView(settings: settings,
                         hapticsSupported: hapticsSupported,
                         onPlay: startRun,
                         onSettings: { showingSettings = true },
                         onLeaderboard: { GameCenter.show(.week) },
                         onSecretDebug: { showingDebug = true })
                    .transition(menuTransition)

            case .playing:
                EmptyView()

            case .paused:
                // El juego congelado se ve detrás (la escena ya está en
                // `isPaused`, ver `GameScene.pauseForInterruption`): esta capa solo
                // oscurece y ofrece la única salida — sin cuenta atrás, sin más
                // botones (chocarías igual si reanudara sola).
                PauseOverlayView(onResume: resumeRun)
                    .transition(.opacity)

            case .dead:
                GameOverView(score: model.score,
                             best: model.best,
                             isNewRecord: model.isNewRecord,
                             onRetry: startRun,
                             onMenu: showMenu,
                             onLeaderboard: { GameCenter.show(.week) },
                             bestPaceMetersPerSecond: model.bestPaceMetersPerSecond)
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
                // Hipótesis del "framerate reducido tras una notificación": el
                // display link renegocia a 60 Hz con la interrupción y nadie
                // vuelve a pedir 120. Re-pedirlo es gratis; validar en device.
                scene.refreshFrameRate()
                // SKView se reanuda solo al volver a primer plano — si la partida
                // se quedó en pausa, hay que reafirmar `isPaused` aquí mismo o el
                // jugador se encontraría el mundo moviéndose otra vez detrás del
                // overlay, o peor, chocando antes de poder pulsar «Continuar».
                if model.phase == .paused { scene.pauseForInterruption() }
            } else {
                // Un continuous vibrando en background es un bug reportable, y un
                // AVAudioEngine que creemos vivo mientras el sistema lo para es el
                // crash de la build 7: se apagan los dos canales a la vez.
                Task { await engine.suspend() }
                // La pausa real (spec «pausa-background»): una partida en curso no
                // puede seguir corriendo sin pantalla, y no debe reanudarse sola al
                // volver — solo el botón «Continuar» la libera.
                model.pauseIfPlaying()
                scene.pauseForInterruption()
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
            hapticsSupported = await !engine.capabilities.needsFullSubstitution
            // La corona de ayer se reclama al arrancar, con un margen para que
            // la autenticación de Game Center termine. Si aún no hay sesión, se
            // reintentará en el próximo arranque — una corona puede esperar.
            Task {
                try? await Task.sleep(for: .seconds(3))
                await GameCenter.claimDailyCrownIfWon(settings: settings)
            }

            // Para capturas y depuración: `xcrun simctl launch ... -autoplay` entra
            // directo a jugar, sin atravesar el menú a mano.
            if ProcessInfo.processInfo.arguments.contains("-autoplay") {
                startRun()
            } else if reduceMotion || ProcessInfo.processInfo.arguments.contains("-skip-intro") {
                model.phase = .menu
            } else {
                scene.playIntro { model.phase = .menu }
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
        model.bestPaceMetersPerSecond = 0
        model.phase = .playing
        scene.startRun()
    }

    private func showMenu() {
        model.phase = .menu
        scene.showMenuBackdrop()
    }

    private func resumeRun() {
        scene.resumeFromPause()
        model.resumeIfPaused()
    }
}
