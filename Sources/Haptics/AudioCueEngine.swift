import AVFoundation
import CoreGraphics

/// El audio del juego: refuerzo cuando hay Taptic Engine, sustituto cuando no.
///
/// Categoría `.ambient` a propósito: respeta el interruptor de silencio y la
/// música del jugador. Forzar `.playback` para colar nuestros pitidos en modo
/// silencio sería hostil, y el diseño no lo necesita — el mapa es táctil, el
/// audio solo acompaña (docs/lenguaje-haptico.md §6.2).
///
/// **Regla del actor**: `AVAudioPlayerNode.play()` con el motor parado no
/// devuelve un `Error`, lanza una NSException que mata el proceso. Y
/// `engine.isRunning` no sirve como salvoconducto: tras suspender la app el
/// sistema para el motor por debajo y el flag puede seguir diciendo `true`
/// (crash de TestFlight en build 7, al volver a primer plano). Por eso `play()`
/// vive en **un solo sitio**, `ensureActive()`, justo detrás de un
/// `try engine.start()` que no ha lanzado; ninguna ruta de parada lo toca.
actor AudioCueEngine {

    private let engine = AVAudioEngine()
    private let cuePlayer = AVAudioPlayerNode()
    private let tonePlayer = AVAudioPlayerNode()

    private var buffers: [HapticSignal: AVAudioPCMBuffer] = [:]
    private var proximityClick: AVAudioPCMBuffer?
    private var alignmentTone: AVAudioPCMBuffer?

    private var gain: CGFloat = Tuning.Audio.reinforcementGain
    private var graphReady = false
    /// Motor arrancado por nosotros en esta sesión de primer plano. No es un
    /// espejo de `engine.isRunning`: es lo que sabemos con certeza.
    private(set) var isActive = false
    private var toneActive = false

    private static let sampleRate = 44_100.0

    /// Arranque en frío y vuelta de una interrupción: el mismo camino, porque el
    /// orden correcto (sesión → motor → players) es el mismo en los dos casos.
    func start(substituting: Bool) {
        gain = substituting ? Tuning.Audio.substituteGain : Tuning.Audio.reinforcementGain
        ensureActive()
    }

    /// Irse a background. Deja el audio explícitamente muerto para que la vuelta
    /// rehaga el ciclo completo en vez de fiarse de un flag que puede mentir.
    func suspend() {
        toneActive = false
        guard isActive else { return }
        isActive = false
        cuePlayer.stop()
        tonePlayer.stop()
        engine.stop()
    }

    /// La única puerta que toca `play()`. Si algo del arranque falla, devuelve
    /// `false` y no se toca ningún player: el audio se queda mudo hasta el
    /// siguiente evento (scenePhase `.active` o la siguiente señal de juego), que
    /// es infinitamente mejor que un `play()` "a ver si cuela".
    @discardableResult
    private func ensureActive() -> Bool {
        guard buildGraph() else { return false }
        if isActive, engine.isRunning { return true }

        isActive = false
        toneActive = false
        cuePlayer.stop()
        tonePlayer.stop()
        do {
            let session = AVAudioSession.sharedInstance()
            // La categoría se repite a propósito: un reset de media services la
            // devuelve a la de por defecto.
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            try engine.start()
        } catch {
            // Sin audio el juego sigue siendo jugable con hápticos. No es fatal.
            return false
        }
        guard engine.isRunning else { return false }

        cuePlayer.play()
        tonePlayer.play()
        isActive = true
        return true
    }

    /// Deja el player en condiciones de recibir `scheduleBuffer`. El `play()` que
    /// lo rearma sale de `ensureActive()`, nunca de una ruta de parada.
    private func armed(_ player: AVAudioPlayerNode) -> Bool {
        guard ensureActive() else { return false }
        if !player.isPlaying { player.play() }
        return true
    }

    private func buildGraph() -> Bool {
        if graphReady { return true }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate,
                                         channels: 1) else { return false }
        engine.attach(cuePlayer)
        engine.attach(tonePlayer)
        engine.connect(cuePlayer, to: engine.mainMixerNode, format: format)
        engine.connect(tonePlayer, to: engine.mainMixerNode, format: format)
        buildBuffers(format: format)
        graphReady = true
        return true
    }

    func enableSubstitution() {
        gain = Tuning.Audio.substituteGain
    }

    func play(_ signal: HapticSignal) {
        guard armed(cuePlayer), let buffer = buffers[signal] else { return }
        cuePlayer.volume = Float(gain)
        cuePlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    /// Un click por pulso, con la misma cadencia que los hápticos: el ritmo es la
    /// información, así que el sustituto tiene que respetarlo exactamente.
    func playProximityClick(intensity: CGFloat) {
        guard armed(cuePlayer), let click = proximityClick else { return }
        cuePlayer.volume = Float(gain * intensity)
        cuePlayer.scheduleBuffer(click, at: nil, options: [], completionHandler: nil)
    }

    func updateAlignment(intensity: CGFloat?) {
        guard let intensity else {
            stopContinuous()
            return
        }
        guard armed(tonePlayer), let tone = alignmentTone else { return }
        tonePlayer.volume = Float(gain * intensity * Tuning.Audio.alignToneGain * 16)
        if !toneActive {
            tonePlayer.scheduleBuffer(tone, at: nil, options: [.loops], completionHandler: nil)
            toneActive = true
        }
    }

    /// Callar la textura de alineación. `stop()` descarta lo programado y deja el
    /// nodo parado; volver a armarlo es cosa del siguiente `updateAlignment`.
    /// Aquí NO se llama a `play()`: esta era la ruta del crash (background →
    /// `setChannels` → `stopContinuous`).
    func stopContinuous() {
        toneActive = false
        guard isActive else { return }
        tonePlayer.stop()
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
