import AVFoundation
import CoreGraphics

/// El audio del juego: refuerzo cuando hay Taptic Engine, sustituto cuando no.
///
/// Categoría `.ambient` a propósito: respeta el interruptor de silencio y la
/// música del jugador. Forzar `.playback` para colar nuestros pitidos en modo
/// silencio sería hostil, y el diseño no lo necesita — el mapa es táctil, el
/// audio solo acompaña (docs/lenguaje-haptico.md §6.2).
actor AudioCueEngine {

    private let engine = AVAudioEngine()
    private let cuePlayer = AVAudioPlayerNode()
    private let tonePlayer = AVAudioPlayerNode()

    private var buffers: [HapticSignal: AVAudioPCMBuffer] = [:]
    private var proximityClick: AVAudioPCMBuffer?
    private var alignmentTone: AVAudioPCMBuffer?

    private var gain: CGFloat = Tuning.Audio.reinforcementGain
    private var running = false
    private var toneActive = false

    private static let sampleRate = 44_100.0

    func prepare(substituting: Bool) {
        gain = substituting ? Tuning.Audio.substituteGain : Tuning.Audio.reinforcementGain

        guard !running else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate,
                                             channels: 1) else { return }
            engine.attach(cuePlayer)
            engine.attach(tonePlayer)
            engine.connect(cuePlayer, to: engine.mainMixerNode, format: format)
            engine.connect(tonePlayer, to: engine.mainMixerNode, format: format)

            buildBuffers(format: format)
            try engine.start()
            cuePlayer.play()
            tonePlayer.play()
            running = true
        } catch {
            // Sin audio el juego sigue siendo jugable con hápticos. No es fatal.
            running = false
        }
    }

    /// Una llamada o Siri desactivan la sesión y paran el `AVAudioEngine`; volver a
    /// primer plano no lo revive solo. Barato cuando no hace falta.
    ///
    /// ponytail: se fía de `engine.isRunning` como síntoma de la interrupción. Si
    /// apareciera un caso con sesión caída y motor "corriendo", habría que
    /// suscribirse a `AVAudioSession.interruptionNotification`.
    func reactivate(substituting: Bool) {
        guard running else {
            prepare(substituting: substituting)
            return
        }
        guard !engine.isRunning else { return }

        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
        // Si el arranque falló (p. ej. sesión aún secuestrada), tocar los players
        // lanzaría NSException — el mismo crash de abajo, en el otro sentido.
        guard engine.isRunning else { return }
        cuePlayer.play()
        tonePlayer.play()
        toneActive = false
    }

    /// `stop()` + `play()` deja el nodo armado para el siguiente `scheduleBuffer`.
    /// Pero `play()` con el `AVAudioEngine` parado lanza NSException (no un Error):
    /// al suspender la app el sistema para el motor, y el `stopContinuous()` del
    /// observador de scenePhase crasheaba en background (TestFlight, 2026-08-02).
    private func rearm(_ player: AVAudioPlayerNode) {
        player.stop()
        guard engine.isRunning else { return }
        player.play()
    }

    func enableSubstitution() {
        gain = Tuning.Audio.substituteGain
    }

    func play(_ signal: HapticSignal) {
        guard running, let buffer = buffers[signal] else { return }
        cuePlayer.volume = Float(gain)
        cuePlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    /// Un click por pulso, con la misma cadencia que los hápticos: el ritmo es la
    /// información, así que el sustituto tiene que respetarlo exactamente.
    func playProximityClick(intensity: CGFloat) {
        guard running, let click = proximityClick else { return }
        cuePlayer.volume = Float(gain * intensity)
        cuePlayer.scheduleBuffer(click, at: nil, options: [], completionHandler: nil)
    }

    func updateAlignment(intensity: CGFloat?) {
        guard running, let tone = alignmentTone else { return }
        if let intensity {
            tonePlayer.volume = Float(gain * intensity * Tuning.Audio.alignToneGain * 16)
            if !toneActive {
                tonePlayer.scheduleBuffer(tone, at: nil, options: [.loops], completionHandler: nil)
                toneActive = true
            }
        } else if toneActive {
            rearm(tonePlayer)
            toneActive = false
        }
    }

    func stopContinuous() {
        guard running else { return }
        rearm(tonePlayer)
        toneActive = false
    }

    // MARK: - Síntesis

    private func buildBuffers(format: AVAudioFormat) {
        proximityClick = tone(format: format,
                              frequency: Tuning.Audio.proximityClickFrequency,
                              duration: Tuning.Audio.proximityClickDuration)
        alignmentTone = tone(format: format,
                             frequency: Tuning.Audio.alignToneFrequency,
                             duration: 0.25,
                             fade: false)

        buffers[.grab] = tone(format: format, frequency: Tuning.Audio.grabClickFrequency, duration: 0.03)
        buffers[.release] = tone(format: format, frequency: Tuning.Audio.releaseThudFrequency, duration: 0.09)
        buffers[.score] = tone(format: format, frequency: Tuning.Audio.scoreBlipFrequency, duration: 0.07)
        buffers[.blindEnter] = tone(format: format,
                                    frequency: Tuning.Audio.releaseThudFrequency * 2,
                                    duration: 0.12)
        buffers[.blindExit] = tone(format: format,
                                   frequency: Tuning.Audio.scoreBlipFrequency,
                                   duration: 0.14)
        buffers[.death] = sweep(format: format,
                                from: Tuning.Audio.scoreBlipFrequency,
                                to: Tuning.Audio.releaseThudFrequency * 0.5,
                                duration: Tuning.Audio.deathSweepDuration)
    }

    private func tone(format: AVAudioFormat,
                      frequency: CGFloat,
                      duration: CGFloat,
                      fade: Bool = true) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(Double(duration) * Self.sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        for frame in 0..<Int(frames) {
            let phase = 2 * Double.pi * Double(frequency) * Double(frame) / Self.sampleRate
            // Sin envolvente, cortar la onda a media oscilación produce un clic que
            // se oye más que el propio tono.
            let envelope = fade ? 1 - Double(frame) / Double(frames) : 1
            samples[frame] = Float(sin(phase) * envelope)
        }
        return buffer
    }

    private func sweep(format: AVAudioFormat,
                       from start: CGFloat,
                       to end: CGFloat,
                       duration: CGFloat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(Double(duration) * Self.sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        var phase = 0.0
        for frame in 0..<Int(frames) {
            let t = Double(frame) / Double(frames)
            let frequency = Double(start) + (Double(end) - Double(start)) * t
            phase += 2 * Double.pi * frequency / Self.sampleRate
            samples[frame] = Float(sin(phase) * (1 - t))
        }
        return buffer
    }
}
