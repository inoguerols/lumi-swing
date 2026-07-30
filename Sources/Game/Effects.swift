import CoreGraphics
import SpriteKit

/// La parte del game feel que se puede razonar sin mirar la pantalla: cuánto
/// tiembla la cámara, de qué color es el cielo, cada cuánto se muestrea la estela.
/// Funciones puras, para poder cambiarlas sin abrir el simulador.
enum Effects {

    /// Temblor de muerte: la amplitud decae con lo que queda de sacudida. Decae y no
    /// se corta de golpe, porque un corte seco se lee como un fallo de render en vez
    /// de como un impacto.
    static func shakeOffset(remaining: CGFloat, rng: inout SplitMix64) -> CGPoint {
        guard remaining > 0 else { return .zero }
        let strength = Tuning.Camera.deathShakeAmplitude
            * clamp(remaining / Tuning.Camera.deathShakeDuration, 0, 1)
        return CGPoint(x: rng.nextCGFloat(in: -strength...strength),
                       y: rng.nextCGFloat(in: -strength...strength))
    }

    /// Cada cuánto se deja una marca de estela. Fijarlo en tiempo y no en frames hace
    /// que la estela mida lo mismo a 60 y a 120 Hz — si no, en un iPhone con ProMotion
    /// sería la mitad de larga.
    static var trailSampleInterval: CGFloat {
        Tuning.Feel.trailFadeDuration / CGFloat(Tuning.Feel.trailNodeCount)
    }

    /// Opacidad de la marca número `index` de la estela.
    static func trailAlpha(index: Int) -> CGFloat {
        let t = CGFloat(index) / CGFloat(Tuning.Feel.trailNodeCount)
        return (1 - t) * Tuning.Feel.trailPeakAlpha
    }

    /// Radio de la marca número `index`: la estela se estrecha hacia atrás.
    static func trailRadius(index: Int) -> CGFloat {
        let t = CGFloat(index) / CGFloat(Tuning.Feel.trailNodeCount)
        return Tuning.Player.radius * lerp(1, Tuning.Feel.trailTailScale, t)
    }

    /// Fase del ciclo de cielo para un muro dado, en 0...1.
    static func skyPhase(forWall wall: Int) -> CGFloat {
        CGFloat(wall % Tuning.Feel.paletteCycleWalls) / CGFloat(Tuning.Feel.paletteCycleWalls)
    }
}
