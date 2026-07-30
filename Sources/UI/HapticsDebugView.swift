import CoreGraphics
import SwiftUI

/// Los hápticos solo se validan en dispositivo físico, así que esta pantalla no
/// es un extra: es el instrumento de medida del proyecto.
///
/// Acceso oculto: cinco toques en la esquina superior izquierda (en S6 pasará al
/// título del menú). Sin botón visible.
@MainActor
struct HapticsDebugView: View {

    let engine: CoreHapticsEngine

    @State private var distance: CGFloat = 450
    @State private var aligned = false
    @State private var clearance: CGFloat = 45
    @State private var diagnostics = "midiendo…"
    @Environment(\.dismiss) private var dismiss

    private let signals: [(HapticSignal, String)] = [
        (.grab, "Agarre — clic seco"),
        (.release, "Suelta — golpe sordo"),
        (.score, "Punto — discreto"),
        (.death, "Muerte — impacto y resonancia"),
        (.blindEnter, "Entrada a ciegas — dos golpes"),
        (.blindExit, "Salida — el único ascendente")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Estado del motor") {
                    Text(diagnostics)
                        .font(.system(.footnote, design: .monospaced))
                }

                Section("Las seis señales") {
                    ForEach(signals, id: \.0) { signal, label in
                        Button(label) {
                            Task { await engine.play(signal) }
                        }
                    }
                }

                Section("Proximidad — el ritmo es la distancia") {
                    VStack(alignment: .leading) {
                        Text("Distancia simulada: \(Int(distance)) pt")
                        Slider(value: $distance, in: 0...1000, step: 10)
                        if let cue = ProximityMapping.cue(forDistance: distance) {
                            Text(String(format: "cada %.2f s · int %.2f · sharp %.2f",
                                        Double(cue.interval),
                                        Double(cue.intensity),
                                        Double(cue.sharpness)))
                                .font(.system(.caption, design: .monospaced))
                        } else {
                            Text("silencio — nada inminente")
                                .font(.caption)
                        }
                    }
                    Button("Arrancar el tren de pulsos") {
                        Task { await engine.updateProximity(distance: distance) }
                    }
                    Button("Silencio") {
                        Task { await engine.updateProximity(distance: nil) }
                    }
                }

                Section("Alineación — la presencia es el sí") {
                    Toggle("Cabe por el hueco", isOn: $aligned)
                    VStack(alignment: .leading) {
                        Text("Margen libre: \(Int(clearance)) pt")
                        Slider(value: $clearance, in: 0...120, step: 5)
                        if let intensity = ProximityMapping.alignmentIntensity(clearance: clearance) {
                            Text(String(format: "textura int %.2f · sharp %.2f",
                                        Double(intensity),
                                        Double(Tuning.Haptics.alignSharpness)))
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }

                Section {
                    Button("Parar todo lo continuo") {
                        Task { await engine.stopContinuous() }
                    }
                    Button("Volcar valores actuales a la consola") {
                        dumpTuning()
                    }
                }
            }
            .navigationTitle("Hápticos")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        Task { await engine.stopContinuous() }
                        dismiss()
                    }
                }
            }
            .onChange(of: clearance) { _, _ in sendAlignment() }
            .onChange(of: aligned) { _, _ in sendAlignment() }
        }
        .task { await refreshDiagnostics() }
    }

    private func sendAlignment() {
        let value: CGFloat? = aligned ? clearance : nil
        Task { await engine.updateAlignment(clearance: value) }
    }

    private func refreshDiagnostics() async {
        let info = await engine.diagnostics
        diagnostics = """
        Taptic Engine: \(info.supportsHaptics ? "sí" : "NO — se usa el sustituto de audio")
        motor arrancado: \(info.running ? "sí" : "no")
        resets: \(info.resets)
        bajo consumo: \(info.lowPower ? "sí" : "no")
        """
    }

    /// El tuning háptico se hace con el pulgar en el iPhone, no razonándolo en un
    /// fichero. Esto imprime los valores vigentes listos para pegar en Tuning.swift.
    private func dumpTuning() {
        print("""
        // Háptica vigente (volcado desde la pantalla de debug)
        proximityRange           = \(Tuning.Haptics.proximityRange)
        proximityIntervalNear    = \(Tuning.Haptics.proximityIntervalNear)
        proximityIntervalFar     = \(Tuning.Haptics.proximityIntervalFar)
        proximityCurveExponent   = \(Tuning.Haptics.proximityCurveExponent)
        alignSharpness           = \(Tuning.Haptics.alignSharpness)
        alignIntensityLow        = \(Tuning.Haptics.alignIntensityLow)
        alignIntensityHigh       = \(Tuning.Haptics.alignIntensityHigh)
        alignClearanceSpan       = \(Tuning.Haptics.alignClearanceSpan)
        grabIntensity/sharpness  = \(Tuning.Haptics.grabIntensity) / \(Tuning.Haptics.grabSharpness)
        releaseIntensity/sharp   = \(Tuning.Haptics.releaseIntensity) / \(Tuning.Haptics.releaseSharpness)
        """)
    }
}
