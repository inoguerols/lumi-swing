import AVFoundation
import CoreGraphics
import Foundation

/// Cuánto ambiente se oye. A ciegas el juego se queda mudo: el silencio refuerza
/// la mecánica firma y deja los hápticos solos, que es lo único que informa ahí.
///
/// Rampa lineal y no exponencial a propósito: así llega **exactamente** a 0 en
/// `duckOutDuration` — un decaimiento exponencial deja siempre una cola audible,
/// y aquí lo que cuenta es que el silencio esté completo al cruzar el muro.
struct AmbienceDucking: Equatable, Sendable {

    private(set) var gain: CGFloat = 1

    mutating func update(blind: Bool, dt: CGFloat) {
        let target: CGFloat = blind ? 0 : 1
        let duration = blind ? Tuning.Ambience.duckOutDuration : Tuning.Ambience.duckInDuration
        guard duration > 0 else {
            gain = target
            return
        }
        let step = max(dt, 0) / duration
        gain = gain < target ? min(target, gain + step) : max(target, gain - step)
    }
}

/// La selva, horneada por código: dos bucles largos que se generan una vez al
/// arrancar y luego solo se reproducen. Sin ficheros de audio en el bundle y sin
/// nada que decodificar en tiempo real.
///
/// Todo es determinista (SplitMix64 con semilla fija): el ambiente suena igual en
/// cada partida y en los tests.
enum AmbienceSynth {

    /// Grillos + aire entre las hojas. Se mezclan en un solo bucle porque suenan
    /// siempre juntos: dos players para lo mismo serían dos relojes que sincronizar.
    static func bed(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let count = frameCount(duration: Tuning.Ambience.bedLoopDuration, sampleRate: sampleRate)
        guard count > 0 else { return nil }

        var rng = SplitMix64(seed: Tuning.Ambience.bedSeed)
        let air = normalized(renderAir(count: count, sampleRate: sampleRate, rng: &rng))
        let crickets = normalized(renderCrickets(count: count, sampleRate: sampleRate, rng: &rng))

        var mixed = [Float](repeating: 0, count: count)
        for frame in 0..<count {
            mixed[frame] = air[frame] * Float(Tuning.Ambience.airLevel)
                + crickets[frame] * Float(Tuning.Ambience.cricketLevel)
        }
        return buffer(format: format, samples: seamFaded(normalized(mixed, peak: Tuning.Ambience.normalizedPeak),
                                                        sampleRate: sampleRate))
    }

    /// El motivo: dos frases cortas de kalimba en 25 s de silencio. La escasez es
    /// el diseño — una nota que llega cada mucho se escucha; un arpegio continuo
    /// se convierte en papel pintado.
    static func motif(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let count = frameCount(duration: Tuning.Ambience.motifLoopDuration, sampleRate: sampleRate)
        guard count > 0 else { return nil }

        var samples = [Float](repeating: 0, count: count)
        var rng = SplitMix64(seed: Tuning.Ambience.motifSeed)
        let scale = Tuning.Ambience.pentatonicFrequencies
        let slot = Tuning.Ambience.motifLoopDuration / CGFloat(max(Tuning.Ambience.motifPhrasesPerLoop, 1))

        for phrase in 0..<Tuning.Ambience.motifPhrasesPerLoop {
            let noteCount = Int.random(in: Tuning.Ambience.motifNoteCountMin...Tuning.Ambience.motifNoteCountMax,
                                       using: &rng)
            let spacings = (0..<noteCount).map { _ in
                rng.nextCGFloat(in: Tuning.Ambience.motifNoteSpacingMin...Tuning.Ambience.motifNoteSpacingMax)
            }
            // La frase entera cabe dentro de su hueco, cola incluida: si una nota
            // cruzara el final del bucle, el bucle sonaría cortado.
            let span = spacings.reduce(0, +) + Tuning.Ambience.pluckDuration
            let start = CGFloat(phrase) * slot + rng.nextCGFloat(in: 0...max(slot - span, 0))

            var degree = Int.random(in: 0..<scale.count, using: &rng)
            var offset = start
            for note in 0..<noteCount {
                render(pluck: scale[degree],
                       level: 1 - rng.nextCGFloat(in: 0...Tuning.Ambience.motifLevelJitter),
                       at: Int(offset * CGFloat(sampleRate)),
                       into: &samples,
                       sampleRate: sampleRate)
                offset += spacings[note]
                // Melodía por grados contiguos, no saltos al azar: es lo que hace
                // que tres notas suenen a frase y no a tres notas.
                let step = Int.random(in: -Tuning.Ambience.motifStepRange...Tuning.Ambience.motifStepRange,
                                      using: &rng)
                degree = min(max(degree + step, 0), scale.count - 1)
            }
        }
        return buffer(format: format, samples: seamFaded(normalized(samples, peak: Tuning.Ambience.normalizedPeak),
                                                         sampleRate: sampleRate))
    }

    // MARK: - Capas

    /// Ruido blanco por un paso-bajo de un polo cuyo corte respira. El corte y la
    /// ganancia se modulan a frecuencias distintas para que el ciclo compuesto no
    /// se deje contar.
    private static func renderAir(count: Int,
                                  sampleRate: Double,
                                  rng: inout SplitMix64) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        var lowpass = 0.0
        for frame in 0..<count {
            let t = Double(frame) / sampleRate
            let sweep = 0.5 + 0.5 * sin(2 * .pi * Double(Tuning.Ambience.airCutoffModHz) * t)
            let cutoff = Double(Tuning.Ambience.airCutoffMin)
                + (Double(Tuning.Ambience.airCutoffMax) - Double(Tuning.Ambience.airCutoffMin)) * sweep
            let coefficient = 1 - exp(-2 * .pi * cutoff / sampleRate)
            let white = Double(rng.nextCGFloat(in: -1...1))
            lowpass += coefficient * (white - lowpass)

            let floorLevel = Double(Tuning.Ambience.airGainFloor)
            let breath = floorLevel + (1 - floorLevel)
                * (0.5 + 0.5 * sin(2 * .pi * Double(Tuning.Ambience.airGainModHz) * t))
            samples[frame] = Float(lowpass * breath)
        }
        return samples
    }

    private static func renderCrickets(count: Int,
                                       sampleRate: Double,
                                       rng: inout SplitMix64) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        let pulseSpan = Tuning.Ambience.cricketPulseDuration + Tuning.Ambience.cricketPulseGap
        let chirpSpan = pulseSpan * CGFloat(Tuning.Ambience.cricketPulseCount)
        let chirps = Int(Tuning.Ambience.bedLoopDuration * Tuning.Ambience.cricketChirpsPerSecond)
        let lastStart = max(Tuning.Ambience.bedLoopDuration - chirpSpan, 0)

        for _ in 0..<chirps {
            let start = rng.nextCGFloat(in: 0...lastStart)
            let jitter = rng.nextCGFloat(in: -Tuning.Ambience.cricketPitchJitter...Tuning.Ambience.cricketPitchJitter)
            let carrier = Double(Tuning.Ambience.cricketCarrierFrequency * (1 + jitter))
            let level = Double(1 - rng.nextCGFloat(in: 0...Tuning.Ambience.cricketLevelJitter))
            render(chirp: carrier,
                   level: level,
                   at: Int(start * CGFloat(sampleRate)),
                   into: &samples,
                   sampleRate: sampleRate)
        }
        return samples
    }

    /// Un canto = varios pulsos cortos seguidos. El patrón de pulsos es lo que el
    /// oído reconoce como grillo; el timbre FM solo lo hace creíble.
    private static func render(chirp carrier: Double,
                               level: Double,
                               at startFrame: Int,
                               into samples: inout [Float],
                               sampleRate: Double) {
        let pulseFrames = Int(Double(Tuning.Ambience.cricketPulseDuration) * sampleRate)
        let strideFrames = Int(Double(Tuning.Ambience.cricketPulseDuration
            + Tuning.Ambience.cricketPulseGap) * sampleRate)
        guard pulseFrames > 0 else { return }

        for pulse in 0..<Tuning.Ambience.cricketPulseCount {
            let base = startFrame + pulse * strideFrames
            for frame in 0..<pulseFrames where base + frame < samples.count {
                let t = Double(frame) / sampleRate
                // Ventana de seno: entra y sale a cero, así que ningún pulso deja
                // un clic en los extremos.
                let envelope = sin(.pi * Double(frame) / Double(pulseFrames))
                let modulator = Double(Tuning.Ambience.cricketModulationIndex)
                    * sin(2 * .pi * Double(Tuning.Ambience.cricketModulatorFrequency) * t)
                let value = sin(2 * .pi * carrier * t + modulator) * envelope * level
                samples[base + frame] += Float(value)
            }
        }
    }

    /// Lengüeta de kalimba: fundamental con decay exponencial más la octava, que
    /// se apaga mucho antes. Ese desfase entre los dos decays es todo el brillo
    /// metálico del ataque.
    private static func render(pluck frequency: CGFloat,
                               level: CGFloat,
                               at startFrame: Int,
                               into samples: inout [Float],
                               sampleRate: Double) {
        let frames = Int(Double(Tuning.Ambience.pluckDuration) * sampleRate)
        let attackFrames = max(Int(Double(Tuning.Ambience.pluckAttack) * sampleRate), 1)
        let decay = Double(Tuning.Ambience.pluckDecay)
        guard frames > 0, decay > 0 else { return }

        for frame in 0..<frames where startFrame + frame < samples.count && startFrame + frame >= 0 {
            let t = Double(frame) / sampleRate
            let attack = min(Double(frame) / Double(attackFrames), 1)
            let fundamental = sin(2 * .pi * Double(frequency) * t) * exp(-t / decay)
            let partial = sin(2 * .pi * Double(frequency * Tuning.Ambience.pluckPartialRatio) * t)
                * exp(-t / (decay * Double(Tuning.Ambience.pluckPartialDecayFactor)))
                * Double(Tuning.Ambience.pluckPartialLevel)
            samples[startFrame + frame] += Float((fundamental + partial) * attack * Double(level))
        }
    }

    // MARK: - Utilidades

    private static func frameCount(duration: CGFloat, sampleRate: Double) -> Int {
        Int(Double(duration) * sampleRate)
    }

    private static func normalized(_ samples: [Float], peak: CGFloat = 1) -> [Float] {
        let maximum = samples.reduce(0) { max($0, abs($1)) }
        guard maximum > 0 else { return samples }
        let scale = Float(peak) / maximum
        return samples.map { $0 * scale }
    }

    /// Fundido corto en los dos extremos: sin él, el salto del último sample al
    /// primero se oye como un clic en cada vuelta del bucle.
    private static func seamFaded(_ samples: [Float], sampleRate: Double) -> [Float] {
        let fade = min(Int(Double(Tuning.Ambience.loopSeamFade) * sampleRate), samples.count / 2)
        guard fade > 0 else { return samples }
        var faded = samples
        for frame in 0..<fade {
            let ramp = Float(frame) / Float(fade)
            faded[frame] *= ramp
            faded[samples.count - 1 - frame] *= ramp
        }
        return faded
    }

    private static func buffer(format: AVAudioFormat, samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}
