import CoreGraphics
import Testing
@testable import LumiSwing

/// D-023: altura fija, ancho variable. La geometría vertical (suelo, techo,
/// HUD, flor llave) es idéntica en todos los dispositivos; solo cambia cuánto
/// mundo se ve a los lados.
@Suite("Tamaño de escena por aspecto")
struct SceneSizingTests {

    @Test("iPhone moderno queda en el diseño base 900×1950")
    func modernPhoneKeepsDesignWidth() {
        let size = Tuning.World.sceneSize(for: CGSize(width: 393, height: 852))
        // 1950·393/852 ≈ 899,5 < 900 → clamp inferior: mismo encuadre de siempre.
        #expect(size.width == Tuning.World.sceneWidth)
        #expect(size.height == Tuning.World.sceneHeight)
    }

    @Test("iPad 13\" 4:3 llega exactamente al tope")
    func bigPadHitsMaxWidth() {
        let size = Tuning.World.sceneSize(for: CGSize(width: 1024, height: 1366))
        #expect(abs(size.width - Tuning.World.maxSceneWidth) < 1)
        #expect(size.height == Tuning.World.sceneHeight)
    }

    @Test("iPad 11\" queda entre el diseño base y el tope")
    func midPadSitsBetweenBounds() {
        let size = Tuning.World.sceneSize(for: CGSize(width: 834, height: 1210))
        #expect(size.width > Tuning.World.sceneWidth)
        #expect(size.width < Tuning.World.maxSceneWidth)
    }

    @Test("Una ventana apaisada absurda no pasa del tope")
    func landscapeWindowIsClamped() {
        let size = Tuning.World.sceneSize(for: CGSize(width: 2000, height: 1000))
        #expect(size.width == Tuning.World.maxSceneWidth)
    }

    @Test("Altura cero cae al diseño base, sin dividir por cero")
    func zeroHeightFallsBackToDesign() {
        let size = Tuning.World.sceneSize(for: .zero)
        #expect(size.width == Tuning.World.sceneWidth)
        #expect(size.height == Tuning.World.sceneHeight)
    }

    @Test("La altura es siempre 1950, para cualquier aspecto")
    func heightIsInvariant() {
        for aspect: CGFloat in [0.3, 0.4615, 0.6, 0.75, 1.5, 3] {
            let size = Tuning.World.sceneSize(for: CGSize(width: 1000 * aspect, height: 1000))
            #expect(size.height == Tuning.World.sceneHeight)
        }
    }
}
