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

/// En S1 el shell es solo la escena a pantalla completa. El menú, el marcador y
/// el game over llegan en S6.
@MainActor
struct RootView: View {
    @State private var scene = GameScene(size: CGSize(width: Tuning.World.sceneWidth,
                                                      height: Tuning.World.sceneHeight))

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 120)
            .ignoresSafeArea()
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
    }
}
