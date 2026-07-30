import SwiftUI

/// Tipografía del juego: SF Rounded. Los textos del HUD llevan tamaño fijo porque
/// son parte de la escena; los del menú y los ajustes escalan con Dynamic Type,
/// que es donde de verdad importa poder leerlos.
private extension View {
    func gameTitle() -> some View {
        font(.system(size: 64, weight: .heavy, design: .rounded))
    }
}

/// Tarjeta translúcida sobre la escena. Se usa material y no el cristal de iOS 26
/// a propósito (ver D-017 en docs/decisiones.md).
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(32)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 28))
            .shadow(radius: 30)
            .padding(.horizontal, 24)
    }
}

// MARK: - Menú

struct MenuView: View {
    let settings: GameSettings
    let onPlay: () -> Void
    let onSettings: () -> Void
    /// Cinco toques en el título abren la pantalla de hápticos, como manda el brief.
    let onSecretDebug: () -> Void

    @State private var titleTaps = 0

    var body: some View {
        Card {
            VStack(spacing: 24) {
                Text("Péndulo")
                    .gameTitle()
                    .foregroundStyle(.orange)
                    .onTapGesture {
                        titleTaps += 1
                        guard titleTaps >= 5 else { return }
                        titleTaps = 0
                        onSecretDebug()
                    }
                    .accessibilityAddTraits(.isHeader)

                Text("Mantén pulsado para agarrarte.\nSuelta para salir volando.")
                    .font(.system(.body, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if settings.best > 0 {
                    Text("récord \(settings.best)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.9))
                }

                Button(action: onPlay) {
                    Text("Jugar")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button("Ajustes", action: onSettings)
                    .font(.system(.body, design: .rounded))
                    .tint(.secondary)
            }
        }
    }
}

// MARK: - Game over

struct GameOverView: View {
    let score: Int
    let best: Int
    let isNewRecord: Bool
    let onRetry: () -> Void
    let onMenu: () -> Void

    var body: some View {
        Card {
            VStack(spacing: 20) {
                Text("\(score)")
                    .gameTitle()
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())

                if isNewRecord {
                    Text("¡récord!")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.orange)
                } else {
                    Text("récord \(best)")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Button(action: onRetry) {
                    Text("Otra vez")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button("Menú", action: onMenu)
                    .font(.system(.body, design: .rounded))
                    .tint(.secondary)
            }
        }
    }
}

// MARK: - Ajustes

struct SettingsView: View {
    @Bindable var settings: GameSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Hápticos", isOn: $settings.hapticsEnabled)
                    Toggle("Sonido", isOn: $settings.audioEnabled)
                } footer: {
                    Text("En las zonas a ciegas los muros no se ven: el ritmo de las "
                         + "vibraciones dice a qué distancia está el muro, y una "
                         + "textura continua avisa de que pasas por el hueco.")
                }

                Section {
                    Toggle("Ver los muros a ciegas", isOn: $settings.visibleBlindZones)
                    Toggle("Reducir parpadeos", isOn: $settings.reduceFlashing)
                } header: {
                    Text("Accesibilidad")
                } footer: {
                    // El juego tiene que poder terminarse sin depender del tacto.
                    Text("«Ver los muros a ciegas» mantiene la penumbra y la "
                         + "puntuación doble, pero deja los muros con un contorno "
                         + "tenue. Si apagas los hápticos se activa solo.")
                }

                Section {
                    Text("Récord: \(settings.best)")
                        .font(.system(.body, design: .rounded))
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}
