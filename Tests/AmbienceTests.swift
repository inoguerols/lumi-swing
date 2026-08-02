import AVFoundation
import CoreGraphics
import Testing
@testable import LumiSwing

@Suite("Ambiente sonoro")
struct AmbienceTests {

    private var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    }

    private func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    // MARK: - Generadores

    @Test("La cama dura lo que dice Tuning, en mono")
    func bedShape() throws {
        let bed = try #require(AmbienceSynth.bed(format: format))
        #expect(bed.format.channelCount == 1)
        #expect(bed.frameLength == AVAudioFrameCount(Tuning.Ambience.bedLoopDuration * 44_100))
    }

    @Test("El motivo dura lo que dice Tuning, en mono")
    func motifShape() throws {
        let motif = try #require(AmbienceSynth.motif(format: format))
        #expect(motif.format.channelCount == 1)
        #expect(motif.frameLength == AVAudioFrameCount(Tuning.Ambience.motifLoopDuration * 44_100))
    }

    /// La semilla fija no es un detalle: si el ambiente cambiara entre arranques,
    /// dejaría de ser un sitio y pasaría a ser ruido distinto cada vez.
    @Test("Misma semilla, mismas muestras")
    func generatorsAreDeterministic() throws {
        let firstBed = samples(try #require(AmbienceSynth.bed(format: format)))
        let secondBed = samples(try #require(AmbienceSynth.bed(format: format)))
        #expect(firstBed == secondBed)

        let firstMotif = samples(try #require(AmbienceSynth.motif(format: format)))
        let secondMotif = samples(try #require(AmbienceSynth.motif(format: format)))
        #expect(firstMotif == secondMotif)
    }

    @Test("Los dos bucles suenan y no saturan")
    func buffersAreAudibleAndBounded() throws {
        for buffer in [try #require(AmbienceSynth.bed(format: format)),
                       try #require(AmbienceSynth.motif(format: format))] {
            let peak = samples(buffer).reduce(0) { max($0, abs($1)) }
            #expect(peak > 0)
            #expect(peak <= Float(Tuning.Ambience.normalizedPeak) + 0.0001)
        }
    }

    /// El clic de la costura del bucle es el fallo clásico de un ambiente
    /// horneado: se oye una vez cada vuelta y delata el truco.
    @Test("Los extremos del bucle arrancan y acaban en silencio")
    func loopSeamIsSilent() throws {
        let bed = samples(try #require(AmbienceSynth.bed(format: format)))
        #expect(abs(bed[0]) < 0.001)
        #expect(abs(bed[bed.count - 1]) < 0.001)
    }

    // MARK: - Ducking

    @Test("A ciegas el ambiente llega a cero, y en el tiempo prometido")
    func duckReachesSilence() {
        var duck = AmbienceDucking()
        #expect(duck.gain == 1)

        // Un frame antes del final todavía se oye algo: la rampa no se salta pasos.
        let step: CGFloat = 1.0 / 120.0
        var elapsed: CGFloat = 0
        while elapsed < Tuning.Ambience.duckOutDuration - step {
            duck.update(blind: true, dt: step)
            elapsed += step
        }
        #expect(duck.gain > 0)

        duck.update(blind: true, dt: step * 2)
        #expect(duck.gain == 0)
        #expect(Tuning.Ambience.duckOutDuration <= 0.5)
    }

    @Test("Al salir vuelve a sonar entero y se queda ahí")
    func duckRecovers() {
        var duck = AmbienceDucking()
        duck.update(blind: true, dt: Tuning.Ambience.duckOutDuration)
        #expect(duck.gain == 0)

        duck.update(blind: false, dt: Tuning.Ambience.duckInDuration / 2)
        #expect(duck.gain > 0)
        #expect(duck.gain < 1)

        duck.update(blind: false, dt: Tuning.Ambience.duckInDuration)
        #expect(duck.gain == 1)
        duck.update(blind: false, dt: 1)
        #expect(duck.gain == 1)
    }

    @Test("El fundido nunca se sale del rango, entre y salga cuando salga")
    func duckStaysInRange() {
        var duck = AmbienceDucking()
        var blind = false
        for step in 0..<600 {
            // Alterna en tramos irregulares: entrar y salir a media rampa es lo
            // normal en partida, no la excepción.
            if step % 37 == 0 { blind.toggle() }
            duck.update(blind: blind, dt: 1.0 / 120.0)
            #expect(duck.gain >= 0)
            #expect(duck.gain <= 1)
        }
    }
}
