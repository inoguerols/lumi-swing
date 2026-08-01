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
                // Panel **pintado**, no `.ultraThinMaterial`. El material del sistema
                // se lee como una hoja de ajustes de iOS puesta encima del juego: es
                // exactamente lo que hacía que la interfaz pareciera "demasiado
                // nativa". Un verde de selva con su propio degradado pertenece al
                // mundo del juego.
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.13, green: 0.27, blue: 0.24).opacity(0.97),
                                 Color(red: 0.06, green: 0.15, blue: 0.14).opacity(0.97)],
                        startPoint: .top,
                        endPoint: .bottom))
                    .overlay {
                        // Resplandor cálido arriba, como si la luciérnaga iluminara
                        // el panel desde fuera.
                        RadialGradient(colors: [fireflyAmber.opacity(0.22), .clear],
                                       center: .top,
                                       startRadius: 0,
                                       endRadius: 380)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [fireflyAmber.opacity(0.55),
                                                        flowerCyan.opacity(0.25)],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing),
                                lineWidth: 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
            .shadow(color: .black.opacity(0.6), radius: 34, y: 14)
            .padding(.horizontal, 24)
    }
}

/// Luciérnagas sueltas revoloteando por el menú. Es lo que separa una pantalla de
/// título de una pantalla de ajustes: el mundo del juego sigue vivo detrás aunque
/// no estés jugando.
///
/// Se dibujan en un único `Canvas` y no como vistas: son decenas de puntos que se
/// mueven cada frame, y treinta vistas de SwiftUI animándose costarían mucho más
/// que treinta círculos pintados de una vez.
struct FireflySwarm: View {
    let count: Int

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { drawing, size in
                let time = context.date.timeIntervalSinceReferenceDate

                for index in 0..<count {
                    let seed = Double(index)
                    // Trayectorias de Lissajous con periodos distintos: nunca vuelven
                    // a coincidir, así que el vuelo no se lee como un bucle.
                    let x = (sin(time * 0.17 + seed * 1.7) * 0.5 + 0.5) * size.width
                    let y = (cos(time * 0.13 + seed * 2.3) * 0.5 + 0.5) * size.height
                    let pulse = sin(time * 1.6 + seed * 3.1) * 0.5 + 0.5
                    let radius = 2.5 + pulse * 2.5

                    let halo = Path(ellipseIn: CGRect(x: x - radius * 3,
                                                      y: y - radius * 3,
                                                      width: radius * 6,
                                                      height: radius * 6))
                    drawing.fill(halo, with: .color(fireflyAmber.opacity(0.05 + pulse * 0.08)))

                    let core = Path(ellipseIn: CGRect(x: x - radius,
                                                      y: y - radius,
                                                      width: radius * 2,
                                                      height: radius * 2))
                    drawing.fill(core, with: .color(fireflyAmber.opacity(0.35 + pulse * 0.5)))
                }
            }
        }
        .allowsHitTesting(false)
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
    /// Latido sutil del título: el menú tiene que sentirse vivo antes de que se
    /// toque nada (F6). Con Reduce Motion se queda quieto.
    @State private var titlePulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Card {
            VStack(spacing: 24) {
                Text("Lumi Swing")
                    .gameTitle()
                    .foregroundStyle(fireflyAmber)
                    .shadow(color: fireflyAmber.opacity(0.5), radius: 24)
                    .scaleEffect(titlePulsing ? 1.03 : 1.0)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                            titlePulsing = true
                        }
                    }
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
