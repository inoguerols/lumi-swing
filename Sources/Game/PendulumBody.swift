import CoreGraphics

/// El farolillo. Tipo puro: ni SpriteKit ni actores, solo aritmética. Es lo que
/// permite testear el game feel sin abrir el simulador.
struct PendulumBody: Sendable {

    struct Attachment: Sendable, Equatable {
        let anchor: CGPoint
        let ropeLength: CGFloat
    }

    var position: CGPoint
    var velocity: CGVector
    private(set) var attachment: Attachment?

    /// Tiempo sobrante que no llegó a completar un subpaso. Guardarlo es lo que
    /// hace que la simulación avance exactamente igual a 60 y a 120 Hz.
    private var leftover: CGFloat = 0

    init(position: CGPoint, velocity: CGVector) {
        self.position = position
        self.velocity = velocity
    }

    var isAttached: Bool { attachment != nil }

    // MARK: - Integración

    mutating func advance(dt: CGFloat, holding: Bool) {
        leftover += min(dt, Tuning.Pendulum.maxFrameDelta)
        let step = Tuning.Pendulum.physicsStep
        while leftover >= step {
            integrate(step, holding: holding)
            leftover -= step
        }
    }

    private mutating func integrate(_ step: CGFloat, holding: Bool) {
        velocity = CGVector(dx: velocity.dx, dy: velocity.dy - Tuning.Pendulum.gravity * step)

        if let attachment {
            if holding { pump(step, attachment: attachment) }
            velocity = velocity * exponentialDecay(rate: Tuning.Pendulum.ropeDrag, dt: step)
            position = position + velocity * step
            applyRopeConstraint(attachment)
        } else {
            velocity = velocity * exponentialDecay(rate: Tuning.Pendulum.airDrag, dt: step)
            position = position + velocity * step
        }

        clampSpeed()
    }

    /// Bombeo: acelera en la dirección en la que ya se mueve. Es la única forma de
    /// ganar energía, y por eso mantener pulsado tiene coste — te da velocidad,
    /// pero te obliga a seguir el arco hasta el final.
    private mutating func pump(_ step: CGFloat, attachment: Attachment) {
        // Solo se bombea por debajo del ancla, como en un columpio de verdad.
        //
        // Sin esta condición, mantener pulsado añadía energía en TODO el arco: el
        // farolillo pasaba de 200 a 1500 pt/s en cuatro segundos y daba vueltas
        // completas alrededor del farol. Eso no es un péndulo, es una honda — y
        // traiciona el pilar 4 del GDD, porque un movimiento que se acelera solo no
        // se puede anticipar. Ahora el arco tiene un techo natural: al subir se
        // pierde impulso, y el jugador siempre sabe dónde va a acabar.
        guard position.y < attachment.anchor.y else { return }

        let radial = (position - attachment.anchor).normalized
        let tangent = radial.perpendicular
        let along = velocity.dot(tangent)
        guard along != 0, abs(along) < Tuning.Pendulum.maxTangentialSpeed else { return }
        let direction: CGFloat = along > 0 ? 1 : -1
        velocity = velocity + tangent * (direction * Tuning.Pendulum.tangentialPump * step)
    }

    /// La cuerda SOLO TIRA. Si el farolillo está más cerca que la longitud de
    /// cuerda, cae libre; la cuerda no lo empuja hacia fuera.
    ///
    /// Es deliberado y es lo que da el peso del pilar 4 del GDD: al agarrarse en
    /// el aire hay una caída breve hasta que la cuerda se tensa, y ese tirón es
    /// exactamente la sensación de masa. Convertirlo en varilla rígida hace el
    /// juego más "limpio" y mucho peor.
    private mutating func applyRopeConstraint(_ attachment: Attachment) {
        let offset = position - attachment.anchor
        let distance = offset.length
        guard distance > attachment.ropeLength, distance > 0 else { return }

        let radial = offset * (1 / distance)
        position = attachment.anchor + radial * attachment.ropeLength
        velocity = velocity - radial * velocity.dot(radial)
    }

    private mutating func clampSpeed() {
        let speed = velocity.length
        guard speed > Tuning.Pendulum.maxSpeed else { return }
        velocity = velocity * (Tuning.Pendulum.maxSpeed / speed)
    }

    // MARK: - Input

    /// Engancha al ancla más cercana, penalizando las que quedan detrás. Sin esa
    /// penalización el jugador se queda colgado hacia atrás y pierde el avance:
    /// es el fallo de game feel más común en juegos de swing.
    @discardableResult
    mutating func grab(anchors: [Anchor]) -> Bool {
        var best: (anchor: CGPoint, distance: CGFloat, cost: CGFloat)?

        for candidate in anchors {
            let distance = position.distance(to: candidate.position)
            guard distance <= Tuning.Pendulum.grabRadius else { continue }
            let penalty: CGFloat = candidate.position.x >= position.x
                ? 1
                : 1 + Tuning.Pendulum.backwardAnchorPenalty
            let cost = distance * penalty
            if let current = best, cost >= current.cost { continue }
            best = (candidate.position, distance, cost)
        }

        guard let best else { return false }
        // Longitud fija, no la distancia a la que estabas al pulsar: así el punto más
        // bajo del arco cae siempre en el hueco y el gesto se puede aprender en vez
        // de sufrirlo.
        attachment = Attachment(anchor: best.anchor, ropeLength: Tuning.Pendulum.ropeLength)
        return true
    }

    mutating func release() {
        guard attachment != nil else { return }
        attachment = nil
        velocity = velocity * Tuning.Pendulum.releaseBoost
        clampSpeed()
    }
}
