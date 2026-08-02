import CoreGraphics
import Testing
@testable import LumiSwing

@Suite("Aura viva")
struct AuraTests {

    private func makeSeed() -> Effects.AuraLayerSeed {
        var rng = SplitMix64(seed: 0xA0_9A)
        return Effects.AuraLayerSeed(rng: &rng)
    }

    @Test("El parpadeo es determinista y queda acotado entre suelo y techo")
    func flickerBoundedAndDeterministic() {
        let seed = makeSeed()
        for step in 0..<2000 {
            let time = CGFloat(step) * 0.016
            let flicker = Effects.auraFlicker(time: time, seed: seed, amplitudeScale: 1)
            #expect(flicker >= Tuning.Scenery.auraFlickerMin)
            #expect(flicker <= Tuning.Scenery.auraFlickerMax)
            #expect(flicker == Effects.auraFlicker(time: time, seed: seed, amplitudeScale: 1))
        }
    }

    @Test("El aura vive de verdad: el parpadeo varía a lo largo del tiempo")
    func flickerActuallyMoves() {
        let seed = makeSeed()
        var low = CGFloat.greatestFiniteMagnitude
        var high = -CGFloat.greatestFiniteMagnitude
        for step in 0..<2000 {
            let flicker = Effects.auraFlicker(time: CGFloat(step) * 0.016,
                                              seed: seed,
                                              amplitudeScale: 1)
            low = min(low, flicker)
            high = max(high, flicker)
        }
        #expect(high - low > 0.05)
    }

    @Test("Reduce Motion nunca desvía el aura más que el modo normal")
    func reduceMotionShrinksDeviation() {
        let seed = makeSeed()
        for step in 0..<400 {
            let time = CGFloat(step) * 0.13
            let full = Effects.auraFlicker(time: time, seed: seed, amplitudeScale: 1)
            let reduced = Effects.auraFlicker(
                time: time, seed: seed,
                amplitudeScale: Tuning.Scenery.auraReduceMotionFactor)
            #expect(abs(reduced - 1) <= abs(full - 1) + 1e-9)
        }
    }

    @Test("La deriva del centro luminoso queda dentro de su amplitud")
    func driftBounded() {
        for step in 0..<2000 {
            let drift = Effects.auraDrift(time: CGFloat(step) * 0.016, amplitudeScale: 1)
            #expect(abs(drift.x) <= Tuning.Scenery.auraDriftAmplitude)
            #expect(abs(drift.y) <= Tuning.Scenery.auraDriftAmplitude)
        }
    }

    @Test("Dos capas sorteadas del mismo generador no comparten fase")
    func layersOutOfPhase() {
        var rng = SplitMix64(seed: 0xA0_9A)
        let first = Effects.AuraLayerSeed(rng: &rng)
        let second = Effects.AuraLayerSeed(rng: &rng)
        #expect(first.breathPhase != second.breathPhase)
        #expect(first.tremorPhase != second.tremorPhase)
        #expect(first.dipPhase != second.dipPhase)
    }
}
