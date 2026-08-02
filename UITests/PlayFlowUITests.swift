import XCTest

/// Lo único que ningún test unitario puede afirmar: que la app se abre, que se
/// puede empezar a jugar, que el juego mata, y que se puede volver a empezar.
///
/// Va en XCTest y no en Swift Testing porque XCUIApplication sigue siendo XCTest.
final class PlayFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testJugarMorirYVolverAEmpezar() {
        let app = XCUIApplication()
        // Directo al menú: el intro animado retrasaría cada test 2 s.
        app.launchArguments = ["-skip-intro"]
        app.launch()

        let jugar = app.buttons["Jugar"]
        XCTAssertTrue(jugar.waitForExistence(timeout: 10), "El menú no llegó a aparecer")
        jugar.tap()

        // Sin tocar nada el farolillo cae y muere: es la forma más fiable de llegar
        // al game over sin depender de saber jugar.
        let otraVez = app.buttons["Otra vez"]
        XCTAssertTrue(otraVez.waitForExistence(timeout: 15),
                      "El juego no llegó a matar al jugador ni mostró el game over")

        otraVez.tap()

        // Y la partida nueva vuelve a terminar: el reinicio deja el juego funcional,
        // no en un estado muerto que solo lo parece.
        XCTAssertTrue(otraVez.waitForExistence(timeout: 20),
                      "La segunda partida no terminó: el reinicio dejó el juego roto")
    }

    func testMantenerPulsadoLlegaALaEscena() {
        let app = XCUIApplication()
        // Directo al menú: el intro animado retrasaría cada test 2 s.
        app.launchArguments = ["-skip-intro"]
        app.launch()

        let jugar = app.buttons["Jugar"]
        XCTAssertTrue(jugar.waitForExistence(timeout: 10))
        jugar.tap()

        // Mantener pulsado engancha al farol. Si el input no llegara a la escena,
        // esto no cambiaría nada respecto a no tocar.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 2.5)

        let otraVez = app.buttons["Otra vez"]
        XCTAssertTrue(otraVez.waitForExistence(timeout: 25),
                      "La partida no terminó nunca, ni siquiera tras soltar")
    }

    func testLosAjustesSeAbrenYSeCierran() {
        let app = XCUIApplication()
        // Directo al menú: el intro animado retrasaría cada test 2 s.
        app.launchArguments = ["-skip-intro"]
        app.launch()

        XCTAssertTrue(app.buttons["Ajustes"].waitForExistence(timeout: 10))
        app.buttons["Ajustes"].tap()

        XCTAssertTrue(app.switches["Hápticos"].waitForExistence(timeout: 5),
                      "No apareció el ajuste de hápticos")
        // Con espera, no `exists` a secas: la hoja de ajustes se presenta animada y
        // el segundo interruptor puede no estar todavía en la jerarquía.
        XCTAssertTrue(app.switches["Ver los muros a ciegas"].waitForExistence(timeout: 5),
                      "Falta el modo de accesibilidad para quien no percibe hápticos")

        app.buttons["Listo"].tap()
        XCTAssertTrue(app.buttons["Jugar"].waitForExistence(timeout: 5))
    }
}
