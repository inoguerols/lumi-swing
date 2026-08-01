import Foundation
import Testing
@testable import LumiSwing

/// Nada de tests contra la UI en inglés (no hay locale switch en swift-testing):
/// basta con leer el propio catálogo y comprobar que ninguna clave se quedó sin
/// su traducción al inglés. Mismo patrón que Legion.
@Suite("Catálogo de localización")
struct LocalizationTests {

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct StringUnit: Decodable {
                    let state: String
                    let value: String
                }
                let stringUnit: StringUnit?
            }
            let localizations: [String: Localization]?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func loadCatalog() throws -> Catalog {
        // El catálogo vive junto a los fuentes, no en el bundle de test: leerlo por
        // ruta de archivo evita tener que declararlo como recurso del target de test.
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    @Test("Todas las claves tienen traducción al inglés")
    func everyKeyHasEnglishTranslation() throws {
        let catalog = try loadCatalog()
        #expect(catalog.sourceLanguage == "es")
        #expect(!catalog.strings.isEmpty)

        for (key, entry) in catalog.strings {
            let english = entry.localizations?["en"]?.stringUnit
            #expect(english != nil, "«\(key)» no tiene entrada en inglés")
            #expect(english?.state == "translated", "«\(key)» en inglés no está marcada como traducida")
            #expect(!(english?.value.isEmpty ?? true), "«\(key)» en inglés está vacía")
        }
    }
}
