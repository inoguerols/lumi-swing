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

    /// Fases y jitter de periodo de una capa del aura, sorteados UNA vez por capa
    /// con SplitMix64: cada capa respira desfasada de las demás y con periodos
    /// ligeramente distintos, que es lo que evita que el aura lata al unísono.
    struct AuraLayerSeed {
        let breathPhase: CGFloat
        let tremorPhase: CGFloat
        let dipPhase: CGFloat
        let periodScale: CGFloat

        init(rng: inout SplitMix64) {
            breathPhase = rng.nextCGFloat(in: 0...(2 * .pi))
            tremorPhase = rng.nextCGFloat(in: 0...(2 * .pi))
            dipPhase = rng.nextCGFloat(in: 0...(2 * .pi))
            let jitter = Tuning.Scenery.auraLayerPeriodJitter
            periodScale = rng.nextCGFloat(in: (1 - jitter)...(1 + jitter))
        }
    }

    /// Parpadeo orgánico del aura: factor multiplicativo alrededor de 1, suma de
    /// tres osciladores deterministas — respiración lenta, temblor rápido y una
    /// caída ocasional más profunda tipo vela (seno estrechado por potencia, así
    /// solo muerde cerca de su pico). Acotado para que el aura viva sin
    /// estroboscopear ni apagarse.
    static func auraFlicker(time: CGFloat,
                            seed: AuraLayerSeed,
                            amplitudeScale: CGFloat) -> CGFloat {
        let twoPi = 2 * CGFloat.pi
        let breath = sin(time * twoPi / (Tuning.Scenery.auraBreathPeriod * seed.periodScale)
                         + seed.breathPhase) * Tuning.Scenery.auraBreathAmplitude
        let tremor = sin(time * twoPi / (Tuning.Scenery.auraTremorPeriod * seed.periodScale)
                         + seed.tremorPhase) * Tuning.Scenery.auraTremorAmplitude
        let dipWave = sin(time * twoPi / (Tuning.Scenery.auraDipPeriod * seed.periodScale)
                          + seed.dipPhase)
        let dip = -pow(max(0, dipWave), Tuning.Scenery.auraDipExponent)
            * Tuning.Scenery.auraDipDepth
        return clamp(1 + (breath + tremor + dip) * amplitudeScale,
                     Tuning.Scenery.auraFlickerMin,
                     Tuning.Scenery.auraFlickerMax)
    }

    /// Deriva lenta del centro luminoso respecto al cuerpo: Lissajous de periodos
    /// inconmensurables, 1-2 pt — la luz de una llama no está clavada a su mecha.
    static func auraDrift(time: CGFloat, amplitudeScale: CGFloat) -> CGPoint {
        let twoPi = 2 * CGFloat.pi
        let amplitude = Tuning.Scenery.auraDriftAmplitude * amplitudeScale
        return CGPoint(x: sin(time * twoPi / Tuning.Scenery.auraDriftPeriodX) * amplitude,
                       y: sin(time * twoPi / Tuning.Scenery.auraDriftPeriodY) * amplitude)
    }
}
