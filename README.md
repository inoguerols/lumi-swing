# Péndulo

Juego hiper-casual para iPhone. Un dedo, partidas de 15–60 segundos, muerte
instantánea. Eres un farolillo: **mantén pulsado** para engancharte al farol más
cercano y balancearte, **suelta** para salir despedido con la inercia.

Cada pocos muros llega una **zona a ciegas**: los muros desaparecen y solo quedan
los hápticos. El ritmo de las vibraciones dice a qué distancia está el muro; una
textura continua avisa de que estás a la altura del hueco. Se puede pasar con la
pantalla boca abajo.

## Empezar

```bash
xcodegen generate
open Pendulo.xcodeproj
```

Requisitos: Xcode 26+, iOS 18 mínimo, `brew install xcodegen`. Sin dependencias de
terceros: solo frameworks de Apple.

`Pendulo.xcodeproj` no está en git — la fuente de verdad es `project.yml`.

## Probar

```bash
xcodebuild test -project Pendulo.xcodeproj -scheme Pendulo \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

43 tests: 40 unitarios que corren sin simulador (física, generación, colisiones,
mapeo háptico, persistencia) y 3 de interfaz que conducen la app real.

Dos de ellos son los que de verdad importan:

- **`GameplayTests.generatedWorldIsTraversable`** — busca entre 400 políticas por
  mundo si existe *alguna* forma de pasar. En un procedural de un solo input, esa
  es la frontera entre «difícil» e «injusto».
- **`BlindZoneTests.blindZoneIsSolvableFromHapticsAlone`** — un agente que solo
  recibe el ritmo de proximidad y si la textura está presente, sin ver la
  geometría, cruza el primer muro invisible. Es la prueba de aceptación de la
  mecánica firma.

## Tunear los hápticos

**Cinco toques en el título del menú** abren la pantalla de debug: dispara cada
señal, corre el tren de proximidad a una distancia simulada y vuelca los valores
vigentes. Los hápticos solo se pueden validar en un iPhone real — el simulador no
tiene Taptic Engine y cae al sustituto de audio.

## Documentación

| Documento | Qué contiene |
|---|---|
| [docs/gdd.md](docs/gdd.md) | Pilares, loop, scoring, curva de dificultad, y qué **no** es este juego |
| [docs/lenguaje-haptico.md](docs/lenguaje-haptico.md) | El vocabulario háptico como idioma: seis señales, la tabla ritmo↔distancia y los fallbacks |
| [docs/arquitectura.md](docs/arquitectura.md) | SpriteKit sin `SKPhysicsWorld`, capas, chunks deterministas, concurrencia |
| [docs/decisiones.md](docs/decisiones.md) | Registro append-only: qué se decidió, qué se descartó y por qué |
| [docs/APPSTORE.md](docs/APPSTORE.md) | Lo que falta para publicar |

## Estado

Los seis slices están completos y el juego es jugable de principio a fin.

**Sin validar todavía:** cómo se *sienten* los hápticos y el balanceo. Los valores
de `Tuning.swift` son un diseño razonado, no una medición — no hubo prototipo del
que sacarlos (D-001). Eso se arregla con un iPhone y un rato, no con más código.
