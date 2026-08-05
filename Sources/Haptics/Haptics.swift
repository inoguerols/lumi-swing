import CoreGraphics
import Foundation

/// El vocabulario completo del idioma háptico. Seis señales de evento, ni una
/// más: añadir una séptima obliga a demostrar que no se confunde con las que ya
/// hay (ver docs/lenguaje-haptico.md §1).
enum HapticSignal: Sendable, Equatable, CaseIterable {
    case grab
    case release
    case score
    case death
    case blindEnter
    case blindExit
}

struct HapticsCapabilities: Sendable, Equatable {
    let supportsHaptics: Bool
    let lowPowerMode: Bool

    /// Cuándo hay que sustituir el mapa táctil por otro canal, no solo reforzarlo.
    /// Sin Taptic Engine la ceguera total no es un reto: es un muro.
    var needsFullSubstitution: Bool { !supportsHaptics }
}

/// La escena habla con esto, nunca con Core Haptics. Así el juego se puede
/// testear y correr en simulador sin tocar hardware (docs/arquitectura.md §7).
protocol HapticsEngine: Sendable {
    var capabilities: HapticsCapabilities { get async }

    func prepare() async
    func play(_ signal: HapticSignal) async

    /// Ritmo de proximidad. `nil` = silencio, que también es información:
    /// «no hay nada inminente».
    func updateProximity(distance: CGFloat?) async

    /// Textura de alineación. `nil` = desalineado, y el desalineado se dice
    /// callando (decisión D-005).
    func updateAlignment(clearance: CGFloat?) async

    /// Volumen del ambiente de selva: 1 = suena entero, 0 = silencio total, que
    /// es lo que pide una zona a ciegas.
    func setAmbience(gain: CGFloat) async

    /// Al salir de una zona a ciegas, al morir y al irse a background.
    func stopContinuous() async

    /// Al armar mundo nuevo (partida o menú): silencia lo que suene y levanta la
    /// mordaza que puso la muerte sobre el mapa continuo.
    func resetForRun() async
}

// MARK: - Mapeo (puro y testeable)

struct ProximityCue: Sendable, Equatable {
    let interval: CGFloat
    let intensity: CGFloat
    let sharpness: CGFloat
}

/// La traducción de geometría a idioma háptico. Es el núcleo de la mecánica
/// firma, así que vive en un tipo puro y tiene tests propios: si alguien cambia
/// el exponente de la curva sin actualizar el documento, un test lo caza.
enum ProximityMapping {

    static func cue(forDistance distance: CGFloat) -> ProximityCue? {
        guard distance <= Tuning.Haptics.proximityRange else { return nil }

        let t = clamp(distance / Tuning.Haptics.proximityRange, 0, 1)
        let curved = CGFloat(pow(Double(t), Double(Tuning.Haptics.proximityCurveExponent)))

        return ProximityCue(
            interval: lerp(Tuning.Haptics.proximityIntervalNear,
                           Tuning.Haptics.proximityIntervalFar,
                           curved),
            intensity: lerp(Tuning.Haptics.proximityIntensityNear,
                            Tuning.Haptics.proximityIntensityFar,
                            t),
            sharpness: lerp(Tuning.Haptics.proximitySharpnessNear,
                            Tuning.Haptics.proximitySharpnessFar,
                            t))
    }

    /// Intensidad de la textura de alineación, o `nil` si el farolillo no cabe.
    /// El matiz («pasas rozando» vs. «vas centrado») sale de escalar un único
    /// parámetro con el margen libre: tres niveles de información, cero señales
    /// nuevas.
    static func alignmentIntensity(clearance: CGFloat) -> CGFloat? {
        guard clearance > 0 else { return nil }
        let t = clamp(clearance / Tuning.Haptics.alignClearanceSpan, 0, 1)
        return lerp(Tuning.Haptics.alignIntensityLow, Tuning.Haptics.alignIntensityHigh, t)
    }

    /// Cuánto le sobra al farolillo para pasar por el hueco. Negativo = no cabe.
    static func clearance(playerY: CGFloat, wall: Wall) -> CGFloat {
        wall.gapHeight / 2 - Tuning.Player.radius - abs(playerY - wall.gapCenterY)
    }
}

// MARK: - Mock

/// Registra lo que se le pide sin tocar hardware. Se usa en tests y es lo que
/// corre en simulador, donde no hay Taptic Engine que valga.
actor MockHapticsEngine: HapticsEngine {

    private(set) var played: [HapticSignal] = []
    private(set) var proximity: [CGFloat?] = []
    private(set) var alignment: [CGFloat?] = []
    private(set) var ambience: [CGFloat] = []
    private(set) var stops = 0
    private(set) var prepared = false

    var capabilities: HapticsCapabilities {
        HapticsCapabilities(supportsHaptics: false, lowPowerMode: false)
    }

    func prepare() { prepared = true }
    func play(_ signal: HapticSignal) { played.append(signal) }
    func updateProximity(distance: CGFloat?) { proximity.append(distance) }
    func updateAlignment(clearance: CGFloat?) { alignment.append(clearance) }
    func setAmbience(gain: CGFloat) { ambience.append(gain) }
    func stopContinuous() { stops += 1 }
    func resetForRun() { stops += 1 }
}
