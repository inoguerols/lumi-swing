#!/usr/bin/env swift
// Genera el icono, el launch logo y la copia de docs con la Lumi «Cometa»
// ACTUAL del juego (GameScene.buildFirefly + makeLightTexture + makeEyesTexture):
// bola de luz con matiz desplazado (blanco cálido → amarillo → naranja →
// rescoldo), bloom aditivo multicapa y SOLO los ojazos con brillo — sin
// flequillo: Lumi es luz hasta el núcleo (vía Limbo/Sein). El glow es blando;
// la cara es el plano de foco (borde nítido) y los brillos de los ojos van sin
// blur ninguno. Sin cola ni texto: icono.
// Ejecutar con:  swift scripts/generate-icon.swift

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Paleta (copiada de Sources/Core/Palette.swift; el fondo es el mismo
// verde noche que LaunchBackground.colorset).

typealias RGBA = (r: Double, g: Double, b: Double, a: Double)

let night: RGBA = (0.12, 0.24, 0.22, 1)
let fireflyCore: RGBA = (1.00, 0.973, 0.878, 1)
let firefly: RGBA = (1.00, 0.82, 0.30, 1)
let fireflyAmber: RGBA = (1.00, 0.616, 0.239, 1)
let fireflyEmber: RGBA = (1.00, 0.42, 0.22, 1)
let fireflyGlow: RGBA = (0.85, 1.00, 0.45, 0.35)
let fireflyEye: RGBA = (0.06, 0.04, 0.03, 1)
// Matiz exterior de los halos, desplazado hacia rosáceo (solo icono): el
// amarillo-verdoso fundiendo con el teal del fondo pasaba por un oliva sucio.
let fireflyRose: RGBA = (1.00, 0.48, 0.52, 1)

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

func blend(_ from: RGBA, _ to: RGBA, _ t: Double) -> RGBA {
    (lerp(from.r, to.r, t), lerp(from.g, to.g, t), lerp(from.b, to.b, t), lerp(from.a, to.a, t))
}

func cg(_ c: RGBA, _ alpha: Double = 1) -> CGColor {
    CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a * alpha)
}

// MARK: - Constantes del juego (Tuning.Scenery / Tuning.Player), en unidades de
// juego donde bodyRadius = 20 y Player.radius = 26.

let bodyRadius = 20.0
let playerRadius = 26.0
let bodyEdgeFade = 0.78          // la luz sólida llega hasta aquí; el resto muere en alpha 0
let bodyGlowLayers = 3
let bodyGlowScale = 1.75
let bodyGlowAlpha = 0.42
// Ojos = valores del juego (Tuning.Scenery): sin flequillo son toda la cara,
// y el icono debe leer igual que el personaje en pantalla.
let eyeRadius = 8.1
let eyeOffsetX = 10.2
let eyeOffsetY = 0.0
let eyeHighlightRadius = 3.45
let eyeHighlightOffset = 3.0
let faceBlurSigma = 1.2
let facePadding = 6.0
let ambientRadiusScale = 4.6     // × Player.radius
let ambientAlpha = 0.13
let midHaloRadiusScale = 2.9
let midHaloAlpha = 0.09
let haloRadiusScale = 1.8
let haloDimAlpha = 0.20
let tiltDeg = -10.0              // ligera inclinación de icono

// MARK: - Contextos y PNG

func makeContext(size: Int, opaque: Bool) -> CGContext {
    let space = CGColorSpaceCreateDeviceRGB()
    let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space, bitmapInfo: alphaInfo.rawValue)
    else { fatalError("No se pudo crear el contexto \(size)x\(size)") }
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("No se pudo crear el destino PNG en \(path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("No se pudo escribir \(path)") }
    print("Escrito \(path)")
}

// MARK: - La bola de luz (calco de GameScene.makeLightTexture)

/// Degradado radial con el matiz desplazado a lo largo de TODO el recorrido:
/// blanco cálido → amarillo → ámbar → rescoldo rojizo que muere en alpha 0
/// antes del canto. `texRadius` es el radio de la textura (bodyRadius/0.78).
func drawLightGradient(_ ctx: CGContext, center: CGPoint, texRadius: CGFloat,
                       alpha: Double, additive: Bool) {
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [cg(fireflyCore, alpha),
                  cg(blend(fireflyCore, firefly, 0.5), alpha),
                  cg(firefly, alpha),
                  cg(fireflyAmber, alpha),
                  cg(blend(fireflyAmber, fireflyEmber, 0.7), 0.28 * alpha),
                  cg(fireflyEmber, 0)] as CFArray
    let locations: [CGFloat] = [0, 0.30, 0.55, CGFloat(bodyEdgeFade), 0.88, 1]
    guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)
    else { fatalError("gradient") }
    ctx.saveGState()
    ctx.setBlendMode(additive ? .plusLighter : .normal)
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: texRadius, options: [])
    ctx.restoreGState()
}

/// Halo tintado con caída continua de centro a borde: en el juego la suma de
/// sprites en radios distintos hace la caída; aquí, ya horneada en un solo
/// degradado monótono — un plateau con canto se leería como un aro.
/// El matiz también viaja de `inner` a `outer`: el tramo que muere sobre el
/// fondo teal debe llegar ya cálido (naranja→rosáceo) para no pasar por oliva.
func drawTintHalo(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                  inner: RGBA, outer: RGBA, alpha: Double) {
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [cg(inner, alpha),
                  cg(blend(inner, outer, 0.6), alpha * 0.35),
                  cg(outer, 0)] as CFArray
    guard let gradient = CGGradient(colorsSpace: space, colors: colors,
                                    locations: [0, 0.5, 1])
    else { fatalError("gradient") }
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
    ctx.restoreGState()
}

// MARK: - La cara (calco de GameScene.makeEyesTexture)

/// Hornea la cara —solo los ojazos con brillo. La cara es el plano de foco
/// del icono: ojos con borde nítido (blur ≤2 px a 1024, solo para
/// quitar el aliasing duro) y los brillos SIN blur ninguno — el
/// glow puede ser blando, pero algo tiene que estar enfocado.
/// `unit` = píxeles por unidad de juego; la cara ya sale rotada `tiltDeg`.
func makeFaceImage(canvas: Int, center: CGPoint, unit: CGFloat) -> CGImage {
    func faceContext() -> CGContext {
        let ctx = makeContext(size: canvas, opaque: false)
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: CGFloat(tiltDeg) * .pi / 180)
        ctx.scaleBy(x: unit, y: unit)
        return ctx
    }

    let ctx = faceContext()
    for eyeSide in [-1.0, 1.0] {
        let eye = CGPoint(x: eyeSide * eyeOffsetX, y: eyeOffsetY)
        ctx.setFillColor(cg(fireflyEye))
        ctx.fillEllipse(in: CGRect(x: eye.x - eyeRadius, y: eye.y - eyeRadius,
                                   width: eyeRadius * 2, height: eyeRadius * 2))
    }

    guard let sharp = ctx.makeImage() else { fatalError("face sharp") }
    // 1,5 px a 1024 (proporcional en los demás tamaños): ablanda el canto sin
    // sacar la cara del plano de foco.
    let sigma = 1.5 * Double(canvas) / 1024.0
    let blurred = CIImage(cgImage: sharp)
        .applyingGaussianBlur(sigma: sigma)
        .cropped(to: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    guard let soft = CIContext().createCGImage(blurred, from: blurred.extent)
    else { fatalError("face blur") }

    // Los brillos, encima y nítidos del todo: el elemento crisp del icono.
    let out = faceContext()
    out.saveGState()
    out.concatenate(out.ctm.inverted())
    out.draw(soft, in: CGRect(x: 0, y: 0, width: CGFloat(canvas), height: CGFloat(canvas)))
    out.restoreGState()
    for eyeSide in [-1.0, 1.0] {
        // Los dos brillos hacia dentro y arriba: la mirada converge en algo.
        let highlight = CGPoint(x: eyeSide * eyeOffsetX - eyeSide * eyeHighlightOffset,
                                y: eyeOffsetY + eyeHighlightOffset)
        out.setFillColor(cg(fireflyCore))
        out.fillEllipse(in: CGRect(x: highlight.x - eyeHighlightRadius,
                                   y: highlight.y - eyeHighlightRadius,
                                   width: eyeHighlightRadius * 2, height: eyeHighlightRadius * 2))
    }
    guard let image = out.makeImage() else { fatalError("face out") }
    return image
}

// MARK: - Lumi entera

/// Mismo orden de dibujo que GameScene.buildFirefly: luz ambiente → halo puente
/// → halo → bloom multicapa → bola → núcleo → cara. Sin cola ni motas: icono.
func drawLumi(_ ctx: CGContext, canvas: Int, bodyR: CGFloat) {
    let s = CGFloat(canvas)
    let center = CGPoint(x: s / 2, y: s / 2)
    let unit = bodyR / CGFloat(bodyRadius)          // px por unidad de juego
    let playerR = CGFloat(playerRadius) * unit
    let texR = bodyR / CGFloat(bodyEdgeFade)        // radio de la textura difusa

    // El fondo se OSCURECE bajo el halo antes de sumar luz: el teal a plena
    // luminancia más amarillo aditivo daba justo el verde oliva intermedio.
    let duskSpace = CGColorSpaceCreateDeviceRGB()
    let dusk: RGBA = (night.r * 0.35, night.g * 0.35, night.b * 0.35, 1)
    if let duskGradient = CGGradient(colorsSpace: duskSpace,
                                     colors: [cg(dusk), cg(dusk, 0)] as CFArray,
                                     locations: [0, 1]) {
        ctx.drawRadialGradient(duskGradient, startCenter: center, startRadius: 0,
                               endCenter: center,
                               endRadius: playerR * CGFloat(ambientRadiusScale),
                               options: [])
    }

    // Luz ambiente: el halo más ancho. Nace ámbar y muere ROSÁCEO sobre el teal:
    // el amarillo-verdoso antiguo fundía en una banda oliva sucia.
    drawTintHalo(ctx, center: center, radius: playerR * CGFloat(ambientRadiusScale),
                 inner: fireflyAmber, outer: fireflyRose, alpha: ambientAlpha)
    // Halo puente cálido: la caída de luz es continua, no a saltos.
    drawTintHalo(ctx, center: center, radius: playerR * CGFloat(midHaloRadiusScale),
                 inner: firefly, outer: fireflyRose, alpha: midHaloAlpha)
    // Halo pegado al cuerpo, también cálido en el icono: su tramo exterior cae
    // sobre el fondo, y el verdoso del juego es lo que fabricaba el oliva.
    drawTintHalo(ctx, center: center, radius: playerR * CGFloat(haloRadiusScale),
                 inner: firefly, outer: fireflyAmber, alpha: haloDimAlpha * fireflyGlow.a)

    // Bloom multicapa: la misma textura difusa, aditiva, en radios crecientes.
    for step in 0..<bodyGlowLayers {
        let t = Double(step + 1) / Double(bodyGlowLayers)
        let scale = CGFloat(lerp(1.15, bodyGlowScale, t))
        drawLightGradient(ctx, center: center, texRadius: texR * scale,
                          alpha: bodyGlowAlpha / Double(bodyGlowLayers), additive: true)
    }

    // La bola sólida (blend normal) y el núcleo caliente por encima (aditivo).
    drawLightGradient(ctx, center: center, texRadius: texR, alpha: 1, additive: false)
    drawLightGradient(ctx, center: center, texRadius: texR * 0.6, alpha: 0.4, additive: true)

    // La cara, horneada con blur real y con la inclinación del icono.
    let face = makeFaceImage(canvas: canvas, center: center, unit: unit)
    ctx.draw(face, in: CGRect(x: 0, y: 0, width: s, height: s))
}

// MARK: - Render de cada asset

func renderIcon(size: Int) -> CGImage {
    let ctx = makeContext(size: size, opaque: true)
    let s = CGFloat(size)
    ctx.setFillColor(cg(night))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    drawLumi(ctx, canvas: size, bodyR: s * 0.28)    // diámetro ≈ 56% del lienzo
    guard let image = ctx.makeImage() else { fatalError("icon") }
    return image
}

func renderLaunchLogo(size: Int) -> CGImage {
    // Fondo transparente: el color de arranque lo pone LaunchBackground.
    let ctx = makeContext(size: size, opaque: false)
    drawLumi(ctx, canvas: size, bodyR: CGFloat(size) * 0.28)
    guard let image = ctx.makeImage() else { fatalError("launch") }
    return image
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

writePNG(renderIcon(size: 1024),
         to: root.appendingPathComponent("Sources/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png").path)
writePNG(renderLaunchLogo(size: 512),
         to: root.appendingPathComponent("Sources/Resources/Assets.xcassets/LaunchLogo.imageset/launch-logo.png").path)
writePNG(renderIcon(size: 512),
         to: root.appendingPathComponent("docs/img/icono.png").path)
