import CoreGraphics
import Foundation

func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat { from + (to - from) * t }

func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
    min(max(value, lower), upper)
}

/// Decaimiento exponencial estable e independiente del frame rate.
/// Se usa para el arrastre de la física y para el suavizado de la cámara.
func exponentialDecay(rate: CGFloat, dt: CGFloat) -> CGFloat {
    CGFloat(exp(-Double(rate) * Double(dt)))
}

extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
        CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }

    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }

    func distance(to other: CGPoint) -> CGFloat { (self - other).length }
}

extension CGVector {
    static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

    static func - (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy)
    }

    static func * (vector: CGVector, scale: CGFloat) -> CGVector {
        CGVector(dx: vector.dx * scale, dy: vector.dy * scale)
    }

    var length: CGFloat { (dx * dx + dy * dy).squareRoot() }

    var normalized: CGVector {
        let length = self.length
        return length > 0 ? self * (1 / length) : CGVector(dx: 0, dy: 0)
    }

    /// Girada 90° a la izquierda: es la dirección tangencial del péndulo.
    var perpendicular: CGVector { CGVector(dx: -dy, dy: dx) }

    func dot(_ other: CGVector) -> CGFloat { dx * other.dx + dy * other.dy }
}
