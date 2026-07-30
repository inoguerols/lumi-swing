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

/// El shell es la escena a pantalla completa. El menú y el game over llegan en S6.
@MainActor
struct RootView: View {

    @State private var engine: CoreHapticsEngine
    @State private var scene: GameScene
    @State private var showingDebug = false
    @State private var secretTaps = 0

    init() {
        // Un único motor háptico para toda la app, compartido por la escena y por la
        // pantalla de debug: dos motores pelearían por el mismo Taptic Engine.
        let engine = CoreHapticsEngine()
        _engine = State(initialValue: engine)
        _scene = State(initialValue: GameScene(
            size: CGSize(width: Tuning.World.sceneWidth, height: Tuning.World.sceneHeight),
            haptics: engine))
    }

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 120)
            .ignoresSafeArea()
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .overlay(alignment: .topLeading) { debugTrigger }
            .sheet(isPresented: $showingDebug) {
                HapticsDebugView(engine: engine)
            }
    }

    /// Cinco toques en la esquina superior izquierda abren la pantalla de hápticos.
    /// Esa zona se come los toques del juego, y es un precio aceptable mientras el
    /// pulgar juega desde abajo: en S6 el acceso se muda al título del menú y esto
    /// desaparece.
    private var debugTrigger: some View {
        Color.clear
            .frame(width: 70, height: 70)
            .contentShape(Rectangle())
            .onTapGesture {
                secretTaps += 1
                guard secretTaps >= 5 else { return }
                secretTaps = 0
                showingDebug = true
            }
    }
}
