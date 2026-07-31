import CoreGraphics
import Testing
@testable import Pendulo

@Suite("Física del péndulo")
struct PendulumBodyTests {

    /// Farolillo colgando justo debajo del ancla y moviéndose en horizontal: la
    /// cuerda está tensa y la gravedad es puramente radial. Es el estado limpio
    /// para medir invariantes.
    private func attachedBody(rope: CGFloat = 300, tangentialSpeed: CGFloat = 400) -> PendulumBody {
        let anchor = CGPoint(x: 500, y: 1400)
        var body = PendulumBody(position: CGPoint(x: anchor.x, y: anchor.y - rope),
                                velocity: CGVector(dx: tangentialSpeed, dy: 0))
        body.grab(anchors: [Anchor(position: anchor)])
        return body
    }

    private func mechanicalEnergy(of body: PendulumBody) -> CGFloat {
        let speed = body.velocity.length
        return 0.5 * speed * speed + Tuning.Pendulum.gravity * body.position.y
    }

    @Test("La liana se estira, pero solo lo justo")
    func ropeStretchesWithinItsElasticity() throws {
        var body = attachedBody()
        let anchor = try #require(body.attachment).anchor

        // La liana cede un poco al tirar: no es un cable de acero. Lo que no puede
        // hacer es dar de sí sin freno, porque entonces el arco dejaría de ser
        // predecible y el punto bajo ya no caería en el hueco.
        let ceiling = Tuning.Pendulum.ropeGrabMax * (1 + Tuning.Pendulum.ropeElasticity) + 1

        for _ in 0..<600 {
            body.advance(dt: Tuning.Pendulum.physicsStep, holding: false)
            #expect(body.position.distance(to: anchor) <= ceiling)
        }
    }

    @Test("La liana se recoge hasta su longitud de reposo")
    func ropeRetractsToRestLength() throws {
        // Enganchada larga: debe acabar midiendo lo de siempre, que es lo que hace
        // que el punto bajo del arco caiga en el hueco.
        var body = attachedBody(rope: Tuning.Pendulum.ropeGrabMax)
        #expect(try #require(body.attachment).ropeLength > Tuning.Pendulum.ropeLength)

        for _ in 0..<600 {
            body.advance(dt: Tuning.Pendulum.physicsStep, holding: false)
        }

        let settled = try #require(body.attachment).ropeLength
        #expect(abs(settled - Tuning.Pendulum.ropeLength) < 5)
    }

    @Test("Sin bombeo, la energía mecánica nunca crece")
    func energyNeverGrowsWithoutPumping() {
        var body = attachedBody()
        var previous = mechanicalEnergy(of: body)

        for _ in 0..<600 {
            body.advance(dt: Tuning.Pendulum.physicsStep, holding: false)
            let current = mechanicalEnergy(of: body)
            #expect(current <= previous + abs(previous) * 1e-3)
            previous = current
        }
    }

    @Test("Al soltar, la velocidad es tangente a la cuerda")
    func releaseIsTangential() throws {
        var body = attachedBody()
        let anchor = try #require(body.attachment).anchor

        for _ in 0..<120 {
            body.advance(dt: Tuning.Pendulum.physicsStep, holding: false)
        }

        let radial = (body.position - anchor).normalized
        body.release()

        let speed = body.velocity.length
        #expect(speed > 0)
        // Casi tangente, no exactamente: la liana cede y rebota, así que queda un
        // resto radial. Ese resto ES la sensación de liana — con tolerancia cero
        // estaríamos exigiendo un cable de acero, que es justo lo que se sentía
        // mecánico. Lo que sí importa es que la salida siga dominada por el arco.
        #expect(abs(body.velocity.dot(radial)) / speed < 0.15)
    }

    @Test("Ante dos anclas equidistantes gana la de delante")
    func forwardAnchorWins() {
        var body = PendulumBody(position: CGPoint(x: 1000, y: 1000),
                                velocity: CGVector(dx: 0, dy: 0))
        let forward = Anchor(position: CGPoint(x: 1300, y: 1000))
        let backward = Anchor(position: CGPoint(x: 700, y: 1000))

        // El orden de la lista no debe importar: la de delante gana igual.
        // (La llamada va fuera de #expect: la macro captura la expresión en un
        // closure inmutable y `grab` es mutating.)
        let grabbed = body.grab(anchors: [backward, forward])
        #expect(grabbed)
        #expect(body.attachment?.anchor == forward.position)
    }

    @Test("Fuera del radio de agarre no engancha")
    func grabFailsBeyondRadius() {
        var body = PendulumBody(position: .zero, velocity: CGVector(dx: 0, dy: 0))
        let far = Anchor(position: CGPoint(x: Tuning.Pendulum.grabRadius + 1, y: 0))
        let grabbed = body.grab(anchors: [far])
        #expect(grabbed == false)
        #expect(body.attachment == nil)
    }

    @Test("La simulación no depende del frame rate")
    func frameRateIndependence() {
        var atSixty = attachedBody()
        var atOneTwenty = attachedBody()

        for _ in 0..<60 { atSixty.advance(dt: 1.0 / 60, holding: true) }
        for _ in 0..<120 { atOneTwenty.advance(dt: 1.0 / 120, holding: true) }

        #expect(abs(atSixty.position.x - atOneTwenty.position.x) < 1)
        #expect(abs(atSixty.position.y - atOneTwenty.position.y) < 1)
    }
}
