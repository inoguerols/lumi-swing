import SwiftUI

/// Tipografía del juego: SF Rounded. Los textos del HUD llevan tamaño fijo porque
/// son parte de la escena; los del menú y los ajustes escalan con Dynamic Type,
/// que es donde de verdad importa poder leerlos.
private extension View {
    func gameTitle() -> some View {
        font(.system(size: 64, weight: .heavy, design: .rounded))
    }
}

/// El ámbar de la luciérnaga y el cian de las flores, para que la interfaz
/// pertenezca al mismo mundo que el juego en vez de parecer una capa de sistema
/// pegada encima.
private let fireflyAmber = Color(red: 1.00, green: 0.78, blue: 0.32)
private let flowerCyan = Color(red: 0.55, green: 0.92, blue: 0.86)

/// Tarjeta sobre la escena. Se usa material y no el cristal de iOS 26 a propósito
/// (ver D-017 en docs/decisiones.md), pero con halo cálido y borde tenue: el
/// material a secas se leía como un rectángulo gris apagado sobre la noche.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.vertical, 36)
            .padding(.horizontal, 32)
            .background {
                RoundedRectangle(cornerRadius: 32)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        // Resplandor cálido detrás del contenido, como si la
                        // luciérnaga iluminara la tarjeta desde dentro.
                        RadialGradient(colors: [fireflyAmber.opacity(0.16), .clear],
                                       center: .top,
                                       startRadius: 0,
                                       endRadius: 320)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 32)
                            .strokeBorder(fireflyAmber.opacity(0.30), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
            .padding(.horizontal, 24)
    }
}

/// Botón principal: relleno cálido con degradado y halo, en vez del azul de
/// sistema. Es el único elemento que pide ser pulsado, y tiene que notarse.
private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(Color(red: 0.10, green: 0.09, blue: 0.05))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    Capsule().fill(
                        LinearGradient(colors: [fireflyAmber,
                                                Color(red: 0.98, green: 0.65, blue: 0.22)],
                                       startPoint: .top,
                                       endPoint: .bottom))
                }
                .shadow(color: fireflyAmber.opacity(0.45), radius: 18, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menú

struct MenuView: View {
    let settings: GameSettings
    let onPlay: () -> Void
    let onSettings: () -> Void
    let onLeaderboard: () -> Void
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

                Text("Mantén pulsado para agarrarte a una flor.\nSuelta para salir volando.")
                    .font(.system(.body, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))

                if settings.best > 0 {
                    Label("\(settings.best)", systemImage: "trophy.fill")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(fireflyAmber)
                }

                PrimaryButton(title: "Jugar", action: onPlay)

                HStack(spacing: 28) {
                    Button(action: onLeaderboard) {
                        Label("Clasificación", systemImage: "list.number")
                    }
                    Button(action: onSettings) {
                        Label("Ajustes", systemImage: "slider.horizontal.3")
                    }
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(flowerCyan.opacity(0.85))
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
    let onLeaderboard: () -> Void

    var body: some View {
        Card {
            VStack(spacing: 20) {
                Text("\(score)")
                    .gameTitle()
                    .foregroundStyle(fireflyAmber)
                    .shadow(color: fireflyAmber.opacity(0.5), radius: 24)
                    .contentTransition(.numericText())

                if isNewRecord {
                    Label("¡tu mejor marca!", systemImage: "sparkles")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(fireflyAmber)
                } else {
                    Label("\(best)", systemImage: "trophy.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }

                PrimaryButton(title: "Otra vez", action: onRetry)

                HStack(spacing: 28) {
                    Button(action: onLeaderboard) {
                        Label("Clasificación", systemImage: "list.number")
                    }
                    Button(action: onMenu) {
                        Label("Menú", systemImage: "house.fill")
                    }
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(flowerCyan.opacity(0.85))
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
