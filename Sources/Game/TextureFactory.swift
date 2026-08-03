import CoreGraphics
import SpriteKit

/// Texturas dibujadas por código. Cero assets: el juego se sigue construyendo
/// entero desde el repositorio, sin PNG que mantener ni ilustrador que esperar.
///
/// Todas se generan **una vez** al montar la escena. Nada de esto se regenera por
/// frame; lo que cambia en vivo son el color y la posición de los nodos.
enum TextureFactory {

    /// Degradado vertical. Se genera en blanco y se tiñe con `colorBlendFactor`,
    /// así que la misma textura sirve para cualquier color de cielo.
    static func verticalGradient(size: CGSize, topAlpha: CGFloat, bottomAlpha: CGFloat) -> SKTexture {
        image(size: size) { context, rect in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [SKColor(white: 1, alpha: topAlpha).cgColor,
                         SKColor(white: 1, alpha: bottomAlpha).cgColor] as CFArray,
                locations: [0, 1]) else { return }
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: rect.midX, y: rect.maxY),
                                       end: CGPoint(x: rect.midX, y: rect.minY),
                                       options: [])
        }
    }

    /// El velo de las zonas a ciegas: negro con un **agujero suave en el centro**.
    ///
    /// Es la diferencia entre «el juego te ha apagado la pantalla» y «tu luz solo
    /// llega hasta aquí». La oscuridad se cierra alrededor del jugador en vez de
    /// caer como un telón, y de paso explica la mecánica sin un cartel.
    static func lightHole(size: CGFloat, holeRadius: CGFloat) -> SKTexture {
        image(size: CGSize(width: size, height: size)) { context, rect in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let center = CGPoint(x: rect.midX, y: rect.midY)

            context.setFillColor(SKColor.black.cgColor)
            context.fill(rect)

            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [SKColor(white: 0, alpha: 0).cgColor,
                         SKColor(white: 0, alpha: 0.35).cgColor,
                         SKColor(white: 0, alpha: 1).cgColor] as CFArray,
                locations: [0, 0.55, 1]) else { return }

            // `.copy` para que el agujero *sustituya* al negro en vez de sumarse.
            context.setBlendMode(.copy)
            context.drawRadialGradient(gradient,
                                       startCenter: center,
                                       startRadius: 0,
                                       endCenter: center,
                                       endRadius: holeRadius,
                                       options: [])
        }
    }

    /// Silueta de vegetación: una fila de copas irregulares recortadas contra el
    /// cielo. Determinista por semilla, para que dos ejecuciones den la misma selva.
    static func canopy(width: CGFloat, height: CGFloat, seed: UInt64, bumps: Int) -> SKTexture {
        image(size: CGSize(width: width, height: height)) { context, rect in
            var rng = SplitMix64(seed: seed)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: rng.nextCGFloat(in: (height * 0.3)...(height * 0.6))))

            let step = width / CGFloat(max(1, bumps))
            var x: CGFloat = 0
            for _ in 0..<max(1, bumps) {
                let peak = rng.nextCGFloat(in: (height * 0.45)...height)
                let next = x + step
                path.addQuadCurve(
                    to: CGPoint(x: next, y: rng.nextCGFloat(in: (height * 0.3)...(height * 0.7))),
                    control: CGPoint(x: x + step / 2, y: peak))
                x = next
            }

            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.closeSubpath()

            context.setFillColor(SKColor.white.cgColor)
            context.addPath(path)
            context.fillPath()
        }
    }

    /// Una loseta de lianas colgando: trazos curvos con comba desde el borde
    /// superior, grosor decreciente y alguna hoja puntual. En blanco, como el
    /// dosel: el tinte lo pone el sprite. Se hornea UNA vez por loseta — cero
    /// SKShapeNode en la escena (las lianas son decoración, no información).
    static func vines(width: CGFloat, height: CGFloat, seed: UInt64, count: Int) -> SKTexture {
        image(size: CGSize(width: width, height: height)) { context, _ in
            var rng = SplitMix64(seed: seed)
            context.setFillColor(SKColor.white.cgColor)
            context.setStrokeColor(SKColor.white.cgColor)
            context.setLineCap(.round)

            for index in 0..<max(1, count) {
                // Reparto con jitter: ni equidistantes (cortina) ni a saco (grumos).
                let slot = width / CGFloat(max(1, count))
                let x = slot * (CGFloat(index) + 0.5) + rng.nextCGFloat(in: -slot * 0.3...slot * 0.3)
                let length = height * rng.nextCGFloat(in: 0.35...0.9)
                let sway = rng.nextCGFloat(in: -34...34)

                let path = CGMutablePath()
                path.move(to: CGPoint(x: x, y: height))
                path.addCurve(to: CGPoint(x: x + sway, y: height - length),
                              control1: CGPoint(x: x + sway * 0.2, y: height - length * 0.35),
                              control2: CGPoint(x: x + sway * 0.85, y: height - length * 0.7))
                context.setLineWidth(rng.nextCGFloat(in: 3.5...6))
                context.addPath(path)
                context.strokePath()

                // 2-3 hojas por liana, gotas orientadas hacia abajo.
                for _ in 0..<Int(rng.nextCGFloat(in: 2...3.99)) {
                    let t = rng.nextCGFloat(in: 0.3...0.95)
                    let leafX = x + sway * t + rng.nextCGFloat(in: -3...3)
                    let leafY = height - length * t
                    let leafSize = rng.nextCGFloat(in: 5...9)
                    context.fillEllipse(in: CGRect(x: leafX - leafSize / 2,
                                                   y: leafY - leafSize,
                                                   width: leafSize,
                                                   height: leafSize * 1.8))
                }
            }
        }
    }

    // MARK: - Utilidad

    private static func image(size: CGSize, draw: (CGContext, CGRect) -> Void) -> SKTexture {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))

        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return SKTexture()
        }

        draw(context, rect)
        guard let cgImage = context.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: cgImage)
    }
}
