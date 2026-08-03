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

---

## 2026-07-30 · D-013 · El ritmo de proximidad lo lleva el motor, no un player en loop

**Decisión:** los pulsos de proximidad se disparan uno a uno desde un bucle propio dentro del `actor`, con `Task.sleep` entre ellos y parámetros dinámicos por pulso. No se usa un `CHHapticAdvancedPatternPlayer` con `loopEnabled` para el tren de pulsos.

**Discrepancia consciente con `docs/lenguaje-haptico.md` §7**, que proponía el player en loop.

**Por qué:** la cadencia *es* la información. Un player en loop repite un patrón de duración fija: para cambiar el ritmo hay que regenerar el patrón o manipular la tasa de reproducción, y en ambos casos el intervalo real deja de ser exactamente el que dice la tabla. Con un bucle propio, el intervalo entre pulsos es literalmente el valor calculado, pulso a pulso, y responde al frame siguiente cuando cambia la distancia.

La alineación **sí** usa un advanced player con `loopEnabled` y `sendParameters`, como decía el documento: ahí la señal es continua por naturaleza y lo que se modula es su intensidad, no su tiempo.

**Coste asumido:** un `Task.sleep` no es un temporizador de tiempo real y puede desviarse unos milisegundos bajo carga. Para un ritmo cuyo rango va de 60 a 600 ms esa deriva es imperceptible — y sigue siendo más fiel que un loop cuya duración de patrón no coincide con el intervalo deseado.

---

## 2026-07-30 · S3 completado — lo que sigue sin poder validarse aquí

El motor háptico está implementado, aislado tras el protocolo, con mock, con manejo de reset e interrupciones, y con 10 tests que atan el código a la tabla del documento (incluido uno que compara los siete valores de la tabla §2 uno a uno).

## 2026-07-30 · D-017 · Material translúcido, no Liquid Glass

**Decisión:** las tarjetas del menú y del game over usan `.ultraThinMaterial`, no el cristal de iOS 26.

**Discrepancia consciente con el brief**, que pedía «Liquid Glass donde aporte». La respuesta honesta es: aquí no aporta. El cristal está diseñado para superponerse a contenido rico y variado; nuestro fondo es una escena oscura casi monocroma, sobre la que el efecto es indistinguible de un material translúcido normal. A cambio ataría parte de la UI a iOS 26 y obligaría a mantener dos caminos de código para el mismo resultado visual.

Si el día de mañana el fondo del menú se vuelve más vistoso, el sitio donde cambiarlo es una sola `struct Card` en `Sources/UI/Shell.swift`.

**Lo que sí se ha tomado de la estética actual:** SF Rounded en todo el shell, Dynamic Type en los textos de menú y ajustes (no en el HUD, que es parte de la escena), safe areas respetadas y `contentTransition(.numericText())` en el marcador del game over.

---

## 2026-07-30 · D-018 · La escena no corre si no se está jugando

**Decisión:** `GameScene.update(_:)` sale inmediatamente si `model.phase != .playing`.

**Por qué:** lo encontró la primera captura de S6. La escena empieza a correr en cuanto aparece, y entre ese instante y el momento en que el shell la pausa pasan varios frames: los suficientes para que el farolillo cayera, muriera, y el jugador se encontrara la pantalla de game over antes de haber tocado nada. Pausar desde fuera era una carrera; la guarda es un invariante.

---

## 2026-07-30 · D-014 · A ciegas se apagan los muros, no las luces

**Decisión:** en zona a ciegas desaparecen los muros, pero los faroles y el propio farolillo siguen viéndose: se dibujan por encima del velo oscuro.

**Por qué:** temáticamente es lo coherente — un farol es una luz, y una luz es justo lo que sí se ve en la oscuridad. Y en jugabilidad es lo que hace la zona posible en vez de imposible: sin asideros visibles el jugador no puede columpiarse y quedaría flotando a oscuras esperando la muerte. Lo que se le quita es la información sobre *dónde está el hueco*, que es exactamente lo que los hápticos vienen a sustituir. Quitarle también los asideros no sería más difícil: sería otro juego.

**Descartado:** oscurecerlo todo (injugable); dejar los muros con contorno tenue siempre (anula la mecánica — eso es el modo asistido de quien no tiene Taptic Engine).

---

## 2026-07-30 · D-015 · La ventana de chunks sigue al jugador, no a un contador

**Decisión:** si el jugador queda por delante de todo el mundo materializado, el índice de generación salta hasta alcanzarlo en vez de seguir emitiendo muros consecutivos.

**Por qué:** lo destapó un test de S4 al colocar el farolillo lejos. La versión anterior generaba siempre "los cuatro siguientes por índice", así que un salto grande dejaba la ventana permanentemente a la espalda del jugador: `nextChunk` devolvía `nil`, no había proximidad que sentir y las zonas a ciegas no se anunciaban nunca. En juego normal no ocurre —nadie avanza 3.000 pt en un frame—, pero era una fragilidad real disfrazada de invariante.

---

## 2026-07-30 · D-016 · La prueba de aceptación a ciegas se hace dentro de la zona

**Decisión:** el test que demuestra que una zona a ciegas es superable coloca al agente a la entrada de la primera zona, en vez de exigirle llegar vivo hasta el muro 11.

**Por qué:** la primera versión pedía las dos cosas a la vez y medía la equivocada. Un agente guiado por hápticos llegaba a 2 puntos de 11 — no porque el idioma háptico fallara, sino porque una política aleatoria no sobrevive diez muros seguidos: la probabilidad decae exponencialmente, y el resultado hablaba de habilidad general con el péndulo, no de la mecánica firma. Colocado a la entrada de la zona, el test responde la pregunta del slice — *¿basta el ritmo y la textura para cruzar un muro invisible?* — y la respuesta es sí, con 400 políticas por mundo.

El agente de ese test no ve la geometría: recibe exactamente lo mismo que un dedo.

**Y un fallo del test, no del juego:** colocaba el farolillo en `wallX + 1`, es decir *dentro* del muro (grosor 46, radio 26). Moría en el primer frame y todos los eventos posteriores eran silencio. Corregido con un margen calculado a partir de las constantes en vez de un número inventado.

---

## 2026-07-30 · S3 completado — lo que sigue sin poder validarse aquí

Lo que **no** se puede verificar en este entorno: cómo se sienten. El simulador no tiene Taptic Engine — `supportsHaptics` devuelve `false` y todo cae al sustituto de audio. La pantalla de debug (cinco toques en la esquina superior izquierda) existe precisamente para eso: es el instrumento con el que hay que sentarse con el iPhone y ajustar. Hasta entonces, los valores de `Tuning.Haptics` son un diseño razonado, no una medición.

---

## 2026-08-03 · D-019 · Flores marchitas: colgarse consume la flor (muro 14+)

**Decisión:** a partir del muro 14, toda flor se marchita mientras se cuelga de ella: 4 s de presupuesto de agarre **acumulativo por flor** (un pétalo cada 0,8 s — la flor de 5 pétalos ES el temporizador, sin HUD), y al agotarse la flor cae, suelta a Lumi **con su velocidad exacta** (sin `releaseBoost`: el impulso es el premio de una suelta elegida) y no se puede volver a agarrar. Regla global sin zonas ni excepciones; tutorial (1-10) y primera zona a ciegas (11-13) intactos.

**Por qué:** impedir el descanso infinito colgado, con el mismo contrato que ya vende el bombeo — energía a cambio de compromiso. Acumulativo porque reiniciar al soltar permite descansar a base de micro-toques (derrota el propósito) y porque los pétalos caídos son el estado hecho visible: lo que se ve es lo que hay. Sin zonas porque el juego ya tiene UN vocabulario de zona (la ceguera es la firma); sin excepción para la flor de paso porque una regla con excepciones invisibles es ilegible. El muro 14 estrena la mecánica en aislamiento y deja el tramo con vista 14-22 para interiorizarla antes de que conviva con la ceguera (muro 23).

**Enmienda al GDD:** la línea «si el jugador se queda colgando, el mundo no lo mata — se sostiene solo» era literalmente falsa con esta mecánica. Reescrita: el mundo sigue sin matar por tiempo — la flor te *suelta*, y es la física de siempre la que resuelve. Si mueres después, te mata la caída que ya conocías, no un temporizador.

**Hápticos:** ni pétalo ni caída estrenan señal (el vocabulario es cerrado: seis señales). La caída reutiliza el transient de Suelta — significa «estás desenganchado», y es verdad.

**Puerta de calidad:** `WitherTests` extiende D-008 con el bot de búsqueda aleatoria soltado tras el muro 13: el tramo marchito debe seguir siendo superable.

---

## 2026-08-03 · D-020 · El mundo cambia cada día; los récords, no

**Decisión:** la semilla del mundo deriva de la fecha en UTC (`DailyWorld.seed`): todo el mundo juega el mismo trazado el mismo día, y a medianoche UTC el mundo rota. Leaderboard **recurrente** de 24 h `pendulo.diario` («Mundo de hoy»), con el mismo reloj. El global `pendulo.highscore` se mantiene como leaderboard principal del menú, y la demo y los tests conservan la semilla fija `initialSeed` — el plan pre-buscado de DemoPilot solo vale para ella.

**Por qué:** con semilla fija el juego entero era un único nivel estático: el meta degeneraba en memorizar el trazado — la habilidad contraria a la que el juego celebra — y no había ninguna razón para volver mañana. La semilla diaria arregla ambas de un golpe sin tocar ningún pilar: la memorización caduca a medianoche y la cita diaria existe sin misiones, monedas ni notificaciones. Las zonas a ciegas y el muro de anticipo son funciones puras del índice de muro, independientes de la semilla: los momentos que enseñan no se sortean.

**Fleco asumido:** hay días más amables que otros (la semilla sortea centros de hueco y jitter de anclas), así que el global premia parcialmente «quién jugó el día bueno». Varianza modesta y aceptada — cada puerta tiene su llave por construcción —; que quede escrito para que nadie lo «descubra» como bug.

**Racha:** única meta-progresión añadida (`streakDays`, días UTC consecutivos con al menos una partida, mismo reloj que el mundo). Cuenta días, no exige nada: sin misiones, sin castigo, una línea en el menú solo cuando ya es racha (≥2). El game over enseña el mini-ranking del DÍA con cabecera «Hoy» — tus vecinos jugaron tus mismas puertas; el global sigue en «Clasificación».

**Candidato v1.2 (no implementar aún):** coronas de días ganados vía `loadPreviousOccurrence` del recurrente. Con pocos jugadores, el mismo ganaría todo y desmotivaría; esperar a que el diario tenga competencia real.

---

## 2026-08-03 · D-021 · El anticipo de la firma y el aviso del canal

**Decisión:** el muro 6 es el **anticipo** de la mecánica firma: velo parcial (`previewVeilPeak` 0,6 frente al 0,96 real), muro en penumbra visible (`previewWallAlpha` 0,5, sin latir — el latido de silueta es vocabulario del eco de las zonas reales), hápticos de proximidad y alineación a plena spec, sin ×2, sin cartel, sin bonus de hueco, sin contar en `blindZonesEntered`. Un solo muro, fijo e independiente de la semilla. Y el menú avisa del canal («Lumi habla por el tacto: juega con el móvil en la mano», o su variante de audio si no hay Taptic Engine) hasta 3 veces o hasta la primera zona a ciegas vivida.

**Por qué:** la mecánica firma llegaba en el muro 11 y buena parte de los jugadores muere en los muros 3-8 sin verla jamás — el juego se dejaba juzgar por lo que no es. El anticipo es una cata (~1,3 s): entrada, tren de proximidad, salida — el vocabulario completo una vez, con los ojos aún puestos. La escalera de opacidades queda 1,0 normal > 0,5 anticipo > 0,35 eco > 0,12 asistido; por debajo de ~0,4 la visión periférica pierde el muro y mataría a quien aún no habla háptico. El aviso existe porque la firma depende de un canal que el jugador puede tener apagado sin saberlo: degradar en silencio era regalar la primera impresión.
