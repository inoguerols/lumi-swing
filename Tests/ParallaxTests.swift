import CoreGraphics
import Testing
@testable import LumiSwing

/// El bug de la 1.2 en iPad: con el módulo simple, el strip de 3 losetas
/// quedaba corto por la derecha (+675 en el peor caso) y el iPad ve ±731.
@Suite("Parallax: cobertura y continuidad del módulo centrado")
struct ParallaxTests {

    private let tile = Tuning.World.sceneWidth * 1.5           // 1350
    private let halfSpan = Tuning.World.sceneWidth * 1.5 * 1.5 // 3 losetas: ±2025
    private let visibleHalf = Tuning.World.maxSceneWidth / 2   // iPad 4:3: 731

    /// Peor caso del strip en TODO el recorrido de un run largo, con los tres
    /// factores reales: los bordes deben cubrir siempre el semiancho de iPad.
    @Test("Las 3 losetas cubren el ancho visible de iPad en todo el recorrido")
    func stripCoversPadWidth() {
        for factor in [Tuning.Scenery.parallaxFar,
                       Tuning.Scenery.parallaxNear,
                       Tuning.Scenery.parallaxVines] {
            for step in 0...4000 {
                let cameraX = CGFloat(step) * 50   // hasta 200 000 pt (worldLength)
                let offset = Tuning.Scenery.parallaxOffset(
                    cameraX: cameraX, factor: factor, tile: tile)
                #expect(offset + halfSpan >= visibleHalf,
                        "borde derecho corto en cameraX \(cameraX), factor \(factor)")
                #expect(offset - halfSpan <= -visibleHalf,
                        "borde izquierdo corto en cameraX \(cameraX), factor \(factor)")
            }
        }
    }

    @Test("El offset vive en el rango centrado [-tile/2, tile/2]")
    func offsetIsCentered() {
        for step in 0...2000 {
            let offset = Tuning.Scenery.parallaxOffset(
                cameraX: CGFloat(step) * 97, factor: 0.58, tile: tile)
            #expect(abs(offset) <= tile / 2 + 0.0001)
        }
    }

    /// La envolvente salta exactamente una loseta: para un strip periódico
    /// (misma textura en las 3 copias) el salto es invisible. Si el paso entre
    /// dos frames consecutivos no es ~continuo o un múltiplo exacto de tile,
    /// habría un pop visible.
    @Test("Entre frames consecutivos el offset es continuo módulo una loseta")
    func offsetIsContinuousModuloTile() {
        let factor = Tuning.Scenery.parallaxVines
        var previous = Tuning.Scenery.parallaxOffset(cameraX: 0, factor: factor, tile: tile)
        for step in 1...5000 {
            let cameraX = CGFloat(step) * 12   // ~12 pt/frame a velocidad de crucero
            let offset = Tuning.Scenery.parallaxOffset(
                cameraX: cameraX, factor: factor, tile: tile)
            let delta = (offset - previous).truncatingRemainder(dividingBy: tile)
            let wrappedDelta = min(abs(delta), tile - abs(delta))
            #expect(wrappedDelta < 13, "salto no periódico en cameraX \(cameraX)")
            previous = offset
        }
    }
}
