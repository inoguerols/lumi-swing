# Rediseño de Lumi + velocidad máxima + ranking automático

Fecha: 2026-08-02 · Aprobado por Nacho en sesión de brainstorming visual
(mockups en `.superpowers/brainstorm/78836-1785665227/content/`, elegida
fusión C1 «Acróbata» + C3 «Linterna viva»).

## 1 · Personaje (fusión C1+C3)

Sigue siendo procedural (SKShapeNode en `GameScene.buildFirefly()`), sin assets.

- **Anatomía en tres cuerpos**: cabeza (círculo) + tórax (elipse) + abdomen,
  sustituyendo el óvalo único actual. Todo el caparazón en `fireflyDetail`.
- **Abdomen = farol real**: relleno con degradado radial de núcleo blanco
  caliente → ámbar (SpriteKit no degrada `SKShapeNode`: usar `SKTexture` de
  degradado generada por código o capas concéntricas). Las **franjas oscuras se
  dibujan por encima de la luz**, no al revés. Punta de luz blanca en la cola.
- **Rim light**: arco cálido fino perfilando cabeza y tórax por el lado del farol.
- **Cuatro alas** en barrido (dos por lado, la trasera más tumbada y tenue).
- **Antenas** con puntita encendida (círculo `firefly` pequeño en el extremo).
- **Motas**: 2-3 partículas cálidas flotando cerca (SKEmitter o nodos animados).
- **Paleta**: 3 colores nuevos en `Palette` — `fireflyCore` (blanco cálido),
  `fireflyAmber` (ámbar profundo), `fireflyRim` (cálido translúcido).
- **Se conserva**: halo aditivo que late con el háptico de proximidad
  (`updateBlink`), regla del GDD «jugador cálido / asideros fríos», y el test
  del icono de 1 cm² (a tamaño mini se lee: masa oscura + farol encendido).

## 2 · Animación

- **Colgada**: el cuerpo pivota alineado con la liana; antenas y alas barridas
  por inercia (rotación función de la velocidad angular).
- **Al soltar**: estiramiento del abdomen con la velocidad y compresión al
  enganchar (squash & stretch continuo, escala función de `|v|`, con tope).
- **Estela** cálida que se desvanece + chispas ocasionales detrás en vuelo libre.
- El aleteo actual (`startWingFlap`) se adapta a las cuatro alas.
- Respetar Reduce Motion donde aplique (estela/chispas se atenúan, no la pose).

## 3 · Velocidad máxima

- `GameSimulation` registra el pico de `|velocidad|` de la partida (ya calcula
  la velocidad del cuerpo; solo hay que retener el máximo y exponerlo).
- Se muestra **solo al morir**, junto al score. Sin velocímetro en vivo (la
  estela ya comunica velocidad). Unidad presentada: m/s con un decimal
  (conversión puntos→metros con constante en `Tuning`).
- Persistir el récord personal junto al resto de persistencia existente.

## 4 · Ranking automático

- **Nuevo leaderboard** de velocidad máxima (`pendulo.maxspeed`) junto al
  existente `pendulo.highscore`. Envío de ambos al terminar la partida
  (Game Center ya integrado en `Sources/Core/GameCenter.swift`).
- **Al morir, el ranking aparece automáticamente**: mini-ranking integrado en
  la pantalla de fin (tu posición + vecinos, vía `GKLeaderboard.loadEntries`),
  NO el modal completo de Game Center (morir es frecuente; el modal sería un
  castigo). Botón para abrir el Game Center completo. Con Game Center no
  autenticado o sin red: la pantalla de fin degrada en silencio a lo actual.
- Alta del leaderboard `pendulo.maxspeed` en App Store Connect vía API
  (clave ya configurada) — paso final, tras verificar el código.

## 5 · Icono, launch y ficha

- Icono y launch regenerados con la silueta nueva (misma masa oscura + farol).
- Capturas nuevas de la ficha cuando el personaje esté integrado.
- La build 7 sigue en revisión: todo esto va en la **siguiente** versión; no se
  toca la revisión en curso. Rama `feat/rediseno-lumi`, sin push a `main`
  hasta validar (cada push a main dispara build de Xcode Cloud).

## 6 · Tests

- Unit tests para: pico de velocidad (retención y reset por partida),
  conversión de unidades, lógica de envío a dos leaderboards, y degradación
  sin Game Center. La parte visual se valida con build + capturas de simulador.
