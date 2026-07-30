# Péndulo — Registro de decisiones

Append-only. Cada entrada: fecha, decisión, alternativas descartadas, y por qué. No se edita el pasado; si una decisión se revierte, se añade una entrada nueva que lo diga.

---

## 2026-07-29 · D-001 · Sin prototipo web de referencia

**Decisión:** se desarrolla directamente en nativo, derivando las constantes de física desde cero y tuneándolas en simulador y dispositivo.

**Contexto:** el brief daba `pendulo-a-ciegas.html` como fuente de verdad del game feel. Ese fichero **no existe en el Mac** (verificado: `find` en todo el home hasta profundidad 4, más Spotlight `mdfind` — cero resultados). Se ofreció al usuario generarlo primero o esperar a que lo aportara; eligió saltarlo.

**Consecuencia asumida:** cada iteración de game feel cuesta un build de Xcode en vez de un refresh de navegador. Los valores iniciales de `Tuning.swift` son un punto de partida razonado, no medido: **están sin validar perceptualmente hasta que se juegue**. Es el riesgo principal del proyecto y hay que atacarlo pronto, en S1.

**Descartado:** (a) escribir el prototipo web antes; (b) esperar a que llegue el HTML original.

---

## 2026-07-29 · D-002 · SpriteKit sí, `SKPhysicsWorld` no

**Decisión:** SpriteKit como renderer, input y bucle de juego. La física del péndulo y las colisiones son código propio en tipos puros.

**Por qué:** legibilidad (un solver propio es predecible y el jugador puede anticiparlo), testabilidad sin simulador, tuning directo, y colisiones círculo-vs-AABB que son cuatro líneas de aritmética.

**Discrepancia con la skill de SpriteKit registrada aquí a propósito:** el brief pedía "categorías de bitmask disciplinadas" siguiendo la skill. Se sustituyen por un `enum ObstacleKind` en el modelo puro, con resolución por `switch` exhaustivo verificado por el compilador. Es la misma disciplina — declarar qué es cada cosa y tratarla explícitamente — sin arrastrar el motor de físicas. Gana el criterio de diseño, como autoriza el brief.

**Descartado:** Metal a mano, SwiftUI `Canvas`, Unity/Godot (dependencia prohibida), SpriteKit con físicas integradas.

---

## 2026-07-29 · D-003 · Orientación portrait, bloqueada

**Decisión:** portrait exclusivo.

**Por qué:** un pulgar, una mano, sesiones de 15–60 s. El coste es menos anticipación visual horizontal, y se mitiga con cámara adelantada. En zonas a ciegas ese coste es cero por definición: el juego está diseñado para no depender de la vista en su mecánica firma.

**Descartado:** landscape (más campo visual, pero exige dos manos y rompe el gesto de «otra vez» con el móvil en una mano); orientación libre (duplica el trabajo de layout y de tuning de cámara por cero beneficio).

---

## 2026-07-29 · D-004 · iOS 18 como mínimo

**Decisión:** deployment target iOS 18.0. Liquid Glass tras `if #available(iOS 26, *)`.

**Por qué:** ninguna API necesaria exige más. Core Haptics es de iOS 13; `@Observable` y Swift Testing, de iOS 17. Subir el mínimo a 26 por un efecto de material en los menús sacrificaría parque instalado a cambio de estética.

---

## 2026-07-29 · D-005 · Alineación háptica por presencia/ausencia, no por contraste de textura

**Decisión:** en zona a ciegas, la señal de alineación es un `continuous` sordo que **solo existe cuando el jugador cabe por el hueco**. Desalineado = silencio táctil.

**Por qué:** dos texturas continuas distintas (suave vs. áspera) son casi indistinguibles en el Taptic Engine, y más aún con los transients de proximidad encima. Presencia/ausencia es binario e instantáneo, no exige comparar. El matiz fino («pasas rozando» vs. «vas centrado») se obtiene escalando la `intensity` con el margen libre: un parámetro, tres niveles de información, cero señales nuevas.

**Descartado:** textura áspera para desalineado (canal saturado, lectura ambigua); un tercer estado discreto "casi alineado" (vocabulario más grande sin más información).

---

## 2026-07-29 · D-006 · Alcance de esta tanda: el juego, no el envío a App Store

**Decisión:** se construye el juego completo (S1–S6) jugable en simulador y en dispositivo. La firma, App Store Connect, capturas de la ficha y el envío quedan fuera de esta tanda.

**Por qué:** requieren la cuenta de Apple Developer del usuario, que lo ha aplazado explícitamente.

---

## 2026-07-29 · D-007 · Bundle ID y leaderboard (irreversibles)

- **Bundle ID:** `com.noguerol.pendulo`
- **Leaderboard de Game Center:** `pendulo.highscore`

Ambos son irreversibles una vez publicados en App Store Connect. Se fijan ahora para que el proyecto sea coherente, y se confirman con el usuario antes de cualquier envío.

---

## 2026-07-29 · D-008 · Test de resolubilidad como puerta de calidad

**Decisión:** `SolvabilityTests` hace búsqueda en anchura sobre un espacio de estados discretizado para demostrar que los primeros 60 muros generados son superables con la física de `Tuning.swift`.

**Por qué:** en un procedural de un solo input, la frontera entre "difícil" e "injusto" es exactamente esta. Un tramo imposible es una reseña de una estrella. Ningún test de unidad convencional lo detecta.

**Coste asumido:** es el test más lento de la suite y hay que acotarle el presupuesto de nodos para que no se dispare.

---

## 2026-07-30 · D-009 · La paleta vive fuera de `Tuning.swift`

**Decisión:** los colores están en `Sources/Core/Palette.swift`, no en `Tuning.swift`.

**Por qué:** la regla del brief es «ningún número mágico fuera de `Tuning.swift`», y su propósito es que ningún valor que afecte al juego esté escondido en el código. Un componente RGB no afecta a cómo se juega. Meter treinta floats de color en el fichero que contiene la gravedad y el radio de agarre haría ilegible justo el fichero que más se consulta. La regla se respeta en su intención: cero literales sueltos, todos los valores con nombre y en un único sitio por dominio.

---

## 2026-07-30 · D-010 · Sin routing a subagentes: se implementa en la sesión principal

**Decisión:** los cinco subagentes de la sección 2.2 del brief están creados y versionados en `.claude/agents/`, pero la implementación la hace la sesión principal.

**Por qué:** el clasificador de permisos del entorno bloquea la invocación de subagentes (`Permission for this action was denied by the Claude Code auto mode classifier`). Se intentó con `ios-engineer` para S1 y fue denegado. Insistir habría sido dar vueltas a un muro.

**Consecuencia:** se pierde el ahorro de coste del routing (código mecánico en modelos más baratos), no la calidad. Los ficheros de agente quedan en el repo y funcionarán en cuanto el entorno lo permita; también se copiaron a `~/.claude/agents/` para que estén en el registro global.

---

## 2026-07-30 · D-011 · Menos ficheros que los previstos en la arquitectura

**Decisión:** `Chunk`, `Wall`, `Anchor`, `ObstacleKind`, `DifficultyCurve`, `BlindZones` y `WorldGenerator` viven juntos en `Sources/Game/World.swift`. `GameEvent`, `GameSimulation` y `CameraController`, en `Sources/Game/GameSimulation.swift`.

**Por qué:** son tipos pequeños, puros y que solo se usan entre sí. Siete ficheros de veinte líneas no son más navegables que uno de ciento cincuenta con secciones; son siete cabeceras de importación y un salto de fichero por cada lectura. Si alguno crece, se parte entonces.

**Consecuencia:** `docs/arquitectura.md` §4 describe una estructura más granular que la real.

---

## 2026-07-30 · S1 completado — qué queda por validar

S1 compila, corre en simulador y pasa 15 tests. Pero **el game feel sigue sin validar**: una captura estática no dice si el balanceo se siente pesado o de gelatina, y sin el prototipo web (D-001) no hay referencia contra la que comparar.

Señal ya observada en la primera captura: con `gravity = 2800` el farolillo recorre el alto entero del playfield en caída libre en poco más de un segundo. Es coherente con el periodo de péndulo que buscábamos (~1 s por medio arco), pero deja **muy poco margen de reacción antes del primer agarre**. Es el candidato número uno a ajuste en cuanto se juegue de verdad; no se toca antes, porque cambiar constantes a ciegas es exactamente lo que produce un juego sin carácter.

La herramienta que sí puede pronunciarse sin un humano delante es el test de resolubilidad (D-008), que llega en S2 con las colisiones.

---

## 2026-07-30 · D-012 · Tres arreglos de diseño que encontró el test de resolubilidad

El test de D-008 falló nada más existir, y encontró tres cosas que ningún test de unidad habría visto. Las tres eran fallos de diseño, no del test:

1. **`gravity` 2800 → 2000.** Con 2800 el farolillo recorría los 1500 pt del playfield en 0,73 s: tocaba suelo antes de llegar al primer muro (x = 900). A 2000 la caída completa dura 1,22 s y el medio arco con cuerda de 320 pt queda en 1,26 s. Sigue teniendo masa; ahora deja tiempo para leer el mundo.

2. **Franja de anclas [900, 1600] → [1050, 1450].** Un ancla a y = 1600 queda a más de `grabRadius` (430 pt) de la altura a la que vuela el jugador: era decorado inalcanzable, y el generador producía tramos sin un solo asidero válido.

3. **El arranque no se sortea.** El primer farol se coloca ahora dentro del radio de agarre desde el punto de partida (397 pt como máximo), y el hueco del primer muro se abre a la altura de partida ±120 pt. Antes, ese hueco podía caer 700 pt más arriba o más abajo con 0,7 s para llegar. El GDD promete diez muros de tutorial silencioso; sortear la primera puerta en todo el alto del playfield es exactamente lo contrario.

**Y un arreglo del propio test:** la primera versión usaba un bot con una política fija. Murió con 0 puntos en las ocho semillas — pero contra el muro, no contra el suelo, y tras agarrarse hasta nueve veces. Es decir: el bot se columpiaba bien y no sabía apuntar al hueco. Un test así mide la calidad de mi bot, no la del mundo. Se sustituyó por **búsqueda aleatoria** (400 políticas por mundo, decisiones cada 0,05–0,35 s), que es lo que pedía D-008 desde el principio y responde la única pregunta que importa: ¿existe alguna forma de pasar?

Lección para el resto del proyecto: un test de jugabilidad no debe contener una estrategia. Debe buscar una.
