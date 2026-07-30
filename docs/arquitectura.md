# Péndulo — Arquitectura

*Versión 1 · 2026-07-29 · iOS 18+ · Swift 6 strict concurrency · cero dependencias de terceros*

## 1. La decisión central: SpriteKit como renderer, física propia

**SpriteKit sí. `SKPhysicsWorld` no.**

SpriteKit aporta lo que necesitamos y no tenemos gratis en otro sitio: bucle de juego con `update(_:)` sincronizado al display, batching de sprites, sistema de partículas (`SKEmitterNode`), cámara (`SKCameraNode`), gestión de texturas y soporte nativo de 120 Hz en ProMotion. Todo del sistema, cero bytes de dependencia.

Pero la física del péndulo la escribimos nosotros. Motivos, en orden de peso:

1. **Legibilidad (pilar 2 del GDD).** Un `SKPhysicsJointLimit` con un `SKPhysicsBody` dinámico produce un péndulo que casi funciona: rebota raro en los extremos, pierde energía de forma no documentada y varía con el frame rate. Un jugador no puede anticipar un solver que no entiende. Nosotros necesitamos que el arco sea *exactamente* el mismo cada vez.
2. **Testabilidad.** `SKPhysicsWorld` exige una `SKScene` viva, y eso exige simulador. La física propia es un `struct` puro: se testea en milisegundos desde la línea de comandos.
3. **Tuning.** Ajustar el game feel de un péndulo propio es cambiar un número en `Tuning.swift`. Ajustar el de Box2D (que es lo que hay debajo de SpriteKit) es pelearse con restitución, damping y masa para conseguir un efecto de segundo orden.
4. **Colisiones triviales.** El jugador es un círculo; los muros, suelo y techo son rectángulos alineados a los ejes. Círculo-vs-AABB son cuatro líneas de aritmética. Traer un motor de colisiones completo para eso es desproporcionado.

De `SKPhysicsBody` no usamos nada. Las categorías de bitmask que pedía el brief se sustituyen por un `enum ObstacleKind { wall, floor, ceiling }` en el modelo puro, que es la misma disciplina sin el motor: cada obstáculo declara qué es y la resolución de colisión es un `switch` exhaustivo que el compilador verifica. Queda registrado como discrepancia con la skill de SpriteKit en [decisiones.md](decisiones.md).

### Alternativas descartadas

| Opción | Por qué no |
|---|---|
| **Metal a mano** | Coste de escribir pipeline, batching y texto propio, para un juego de formas geométricas simples. Cero beneficio observable a 120 Hz con esta carga. |
| **SwiftUI `Canvas` / `TimelineView`** | No hay bucle de juego de verdad: el timing es del sistema de layout, no del display link. Sin partículas, sin batching. Un juego de reflejos no puede depender del programador de vistas. |
| **Unity / Godot / LÖVE** | Dependencia externa prohibida por el brief. Además: binario 40× mayor, arranque más lento, hápticos por plugin de terceros. |
| **SpriteKit *con* `SKPhysicsWorld`** | Ver los cuatro motivos de arriba. Es la opción "por defecto" y es la que más cuesta a largo plazo. |

## 2. Capas

```
┌─────────────────────────────────────────────┐
│  UI (SwiftUI)                               │
│  RootView · MenuView · GameOverView          │
│  SettingsView · HapticsDebugView             │
└───────────────┬─────────────────────────────┘
                │ AppModel (@Observable, @MainActor)
                │ estado: .menu / .playing / .dead
┌───────────────▼─────────────────────────────┐
│  SpriteView { GameScene }                   │
│  GameScene: input, nodos, cámara, FX         │
└───────────────┬─────────────────────────────┘
                │ posee y hace avanzar
┌───────────────▼─────────────────────────────┐
│  Core / Game — TIPOS PUROS, SIN SPRITEKIT   │
│  GameSimulation                              │
│   ├── PendulumBody   (integración, agarre)  │
│   ├── WorldGenerator (chunks deterministas) │
│   ├── Collision      (círculo vs AABB)      │
│   └── BlindZones     (activación, ×2)       │
│  → emite [GameEvent] por frame              │
└───────────────┬─────────────────────────────┘
                │ eventos
┌───────────────▼─────────────────────────────┐
│  Haptics — protocolo HapticsEngine          │
│  CoreHapticsEngine · AudioCueEngine · Mock  │
└─────────────────────────────────────────────┘
```

**La regla de oro del flujo:** `GameSimulation` no sabe que existen SpriteKit ni Core Haptics. Avanza con `advance(dt:input:)` y devuelve un array de `GameEvent` (`.grabbed`, `.released`, `.scored`, `.died`, `.enteredBlindZone`, `.exitedBlindZone`) más su estado. `GameScene` lee ese estado para colocar nodos y reenvía los eventos al motor háptico. Un flujo de datos, una dirección.

Esto hace que la mecánica sea reproducible: dada una semilla y una secuencia de inputs con dt fijo, el resultado es idéntico. Es lo que permite tener un test que demuestre que un tramo generado es superable.

## 3. Comunicación SwiftUI ↔ SpriteKit

`SpriteView(scene:)` con una `GameScene` cuya vida es la de la sesión de juego. `AppModel` es `@Observable` y `@MainActor`:

```swift
@Observable @MainActor
final class AppModel {
    enum Phase { case menu, playing, dead }
    var phase: Phase = .menu
    var score = 0
    var best = 0
}
```

`GameScene` recibe una referencia a `AppModel` y escribe en él desde `update(_:)`, que ya corre en el hilo principal — sin saltos de actor y sin `Task { @MainActor in }` por frame. La UI de SwiftUI (marcador, game over) se reconstruye por observación.

Al morir: `phase = .dead`, la escena se **pausa** pero no se destruye. Al reiniciar: `simulation.reset(seed:)` y `scene.rebuild()`. **No se instancia una escena nueva.** Esto es lo que da el reinicio en menos de 300 ms del brief: crear una `SKScene` y sus texturas desde cero cuesta bastante más que resetear structs y reposicionar nodos ya existentes.

## 4. Estructura de carpetas

```
Sources/
  Core/
    Tuning.swift            ← TODOS los números del juego. Sin excepciones.
    Geometry.swift           ← lerp, clamp, círculo-vs-AABB
    RandomGenerator.swift    ← SplitMix64 determinista (Sendable)
    Persistence.swift        ← récord y ajustes (UserDefaults)
  Game/
    GameSimulation.swift     ← orquestador puro; advance(dt:input:) -> [GameEvent]
    PendulumBody.swift       ← estado e integración del farolillo
    WorldGenerator.swift     ← chunks deterministas por índice
    Chunk.swift              ← Wall, Anchor, Chunk (modelos de valor)
    Collision.swift          ← detección pura
    BlindZones.swift          ← qué chunks son a ciegas, según la curva del GDD
    GameScene.swift          ← SpriteKit: nodos, input, cámara
    CameraController.swift    ← look-ahead, shake
    Effects.swift            ← estela, partículas, squash & stretch (S5)
  Haptics/
    HapticsEngine.swift      ← protocolo + HapticSignal (el vocabulario)
    CoreHapticsEngine.swift  ← implementación real
    MockHapticsEngine.swift  ← registra señales; para tests y simulador
    HapticPatterns.swift     ← construcción de CHHapticPattern
    ProximityMapping.swift   ← distancia → (intervalo, intensity, sharpness). PURO.
    AudioCueEngine.swift     ← AVAudioEngine, refuerzo y sustitución
  UI/
    PenduloApp.swift
    RootView.swift
    MenuView.swift
    GameOverView.swift
    SettingsView.swift
    HapticsDebugView.swift
Tests/
  PendulumBodyTests.swift
  WorldGeneratorTests.swift
  CollisionTests.swift
  ProximityMappingTests.swift
  SolvabilityTests.swift      ← el test que importa (ver §6)
```

## 5. Generación procedural por chunks

Un **chunk** es una unidad de mundo de ancho fijo que contiene un muro con su hueco y una o dos anclas.

```swift
struct Chunk: Sendable {
    let index: Int
    let originX: CGFloat
    let wall: Wall          // x, gapCenterY, gapHeight
    let anchors: [Anchor]   // posiciones de los faroles
    let isBlind: Bool
}
```

**Determinismo por índice.** Cada chunk se genera desde `SplitMix64(seed &+ UInt64(index) &* 0x9E3779B97F4A7C15)`. No hay generador con estado que avance: el chunk 47 es el mismo se haya generado antes o después que el 46. Consecuencias buenas: se puede generar hacia atrás si la cámara retrocede, se puede testear cualquier chunk aislado, y un récord se puede reproducir con su semilla.

**Ventana viva de 4 chunks.** Se mantienen materializados el actual y tres por delante; los que quedan a más de un chunk por detrás se desmontan y sus nodos vuelven a un pool. Con `SKNode` reutilizados el coste por chunk nuevo es reposicionar, no instanciar.

**Los parámetros salen de la curva del GDD**, implementada como función pura `DifficultyCurve.parameters(forWallIndex:) -> (spacing, gapHeight, anchorCount)`. La tabla del GDD y esta función deben coincidir; hay un test que lo comprueba.

**Zonas a ciegas** (`BlindZones`): función pura `isBlind(wallIndex:) -> Bool` que implementa la cadencia del GDD (primera en el muro 11, luego cada ~12 con duración creciente hasta 6). Ningún estado mutable, ningún azar: la primera zona a ciegas cae siempre en el mismo sitio para todos los jugadores, lo cual importa porque es el momento de enseñar la mecánica.

## 6. Testing

Swift Testing (`import Testing`), todo sin simulador, todo sin `SKScene`.

**Invariantes de física** (`PendulumBodyTests`):
- Agarrado, la distancia al ancla se mantiene constante (±0,5 pt) durante 600 frames.
- Sin bombeo, la energía mecánica no crece nunca (permitido decrecer por arrastre).
- Al soltar, la velocidad resultante es tangente a la cuerda (producto escalar con el radio ≈ 0).
- El agarre elige el ancla más cercana **con preferencia hacia delante**: dos anclas equidistantes, una delante y una detrás → gana la de delante.
- `dt` fijo vs. `dt` variable acumulando el mismo tiempo total → misma posición final (±1 pt). Blinda contra bugs de integración dependientes del frame rate.

**Generación** (`WorldGeneratorTests`):
- Misma semilla y mismo índice → chunk idéntico, generado en cualquier orden.
- El hueco siempre cabe dentro de suelo/techo con margen.
- `DifficultyCurve` coincide con la tabla del GDD en los muros frontera (10, 11, 13, 14, 24, 25, 46).
- `BlindZones.isBlind(11) == true`, `isBlind(10) == false`.

**Colisiones** (`CollisionTests`): círculo dentro del hueco no colisiona; rozando el borde sí; suelo y techo; el caso de esquina del hueco (que es donde fallan estas rutinas).

**Mapeo háptico** (`ProximityMappingTests`): monotonía estricta — a menor distancia, intervalo menor e intensity mayor. Los valores de la tabla de `lenguaje-haptico.md` se reproducen con tolerancia 0,01. Si alguien cambia el exponente sin actualizar el doc, el test lo caza.

**`SolvabilityTests` — el test que de verdad importa.** Un solver por fuerza bruta: para cada uno de los primeros 60 muros, con la geometría generada por la semilla, comprueba que existe *al menos una* secuencia de agarre/suelta que lleva al jugador desde la entrada del chunk hasta el hueco, dada la velocidad máxima y la gravedad de `Tuning.swift`. Búsqueda en anchura sobre un espacio discretizado de estados, con presupuesto de nodos acotado.

Es el único test que puede afirmar que el juego no genera situaciones imposibles. En un procedural de un input, eso es la diferencia entre difícil e injusto — y "injusto" es la reseña de una estrella que hunde un hiper-casual.

## 7. Concurrencia (Swift 6 estricto)

- `GameScene`, `AppModel` y toda la UI: **`@MainActor`**. `SKScene.update(_:)` ya corre ahí; no hay saltos de actor en el bucle de juego, que es exactamente lo que queremos a 120 Hz.
- Los tipos puros (`Chunk`, `Wall`, `GameEvent`, `PendulumBody`, `Tuning`) son `struct`/`enum` de valores: **`Sendable`** de forma trivial y sin anotaciones forzadas.
- `CoreHapticsEngine`: `CHHapticEngine` invoca `resetHandler` y `stoppedHandler` **fuera del actor principal**. Se aísla en un **`actor HapticsActor`** propio que posee el engine y los players; los handlers hacen `Task { await self.handleReset() }`. La escena le habla con llamadas `async` fire-and-forget (`Task { await haptics.play(.grab) }`), que no bloquean el frame.
- **Prohibido `@unchecked Sendable`** en este proyecto. Si aparece uno, es que el diseño está mal; se corrige el diseño.
- `AVAudioEngine` (refuerzo de audio) vive dentro del mismo actor háptico: comparten ciclo de vida, interrupciones y sesión de audio. Dos actores gestionando la misma `AVAudioSession` es una carrera esperando a ocurrir.

## 8. Decisiones de plataforma

| Decisión | Valor | Justificación |
|---|---|---|
| **Orientación** | **Portrait, bloqueado** | Un solo pulgar, sesiones de 15–60 s, uso en el metro. El mundo avanza en horizontal, así que portrait recorta anticipación visual: se compensa con cámara adelantada (`lookAhead`) y velocidad moderada. Y en las zonas a ciegas ese coste es cero por definición — el juego está diseñado para no depender de la vista en su mecánica firma. Landscape daría más campo pero exige dos manos y rompe el gesto de "una mano, una vez más". |
| **iOS mínimo** | **18.0** | Nada del juego necesita API más nueva: Core Haptics es de iOS 13, Swift Testing y `@Observable` van en 17. Subir a 26 para usar Liquid Glass nativo dejaría fuera parque instalado por un efecto de menú. Liquid Glass se usa tras `if #available(iOS 26, *)`. |
| **Bundle ID** | `com.noguerol.pendulo` | Decisión irreversible una vez publicado. Registrada en decisiones.md. |
| **Nombre en pantalla** | Péndulo | Nombre de trabajo; el definitivo se decide antes del envío. |
| **Persistencia** | `UserDefaults` | Se guardan un `Int` (récord) y cuatro `Bool` (ajustes). Un contenedor SwiftData para eso sería absurdo. |
| **Game Center** | leaderboard única, `pendulo.highscore` | ID irreversible una vez creado en App Store Connect. |
