# Péndulo — Game Design Document

*Versión 1 · 2026-07-29 · nombre de trabajo: Péndulo*

## Pilares

1. **Un input.** Un dedo, dos estados: pulsado (agarrado, balanceándose) y suelto (volando con la inercia). No hay swipe, no hay doble toque, no hay botones. Cualquier idea que requiera un segundo gesto se descarta.
2. **Legibilidad.** El jugador debe saber por qué murió en el instante en que muere. La física es determinista y propia (no `SKPhysicsWorld`) precisamente para que nada se sienta arbitrario.
3. **Los hápticos son un idioma.** En las zonas a ciegas el Taptic Engine no acompaña: *informa*. Ritmo = distancia, textura = alineación. El audio refuerza; nunca sustituye.
4. **Peso.** El farolillo tiene masa. El balanceo se anticipa, no se corrige a media caída. Un péndulo flotante está roto aunque los números cuadren.

## Loop

Toque en el menú → run. El farolillo entra por la izquierda con velocidad inicial. El mundo se extiende hacia la derecha: muros verticales con un hueco cada uno, y faroles (anclas) suspendidos entre ellos.

- **Mantener pulsado**: se engancha al farol más cercano dentro del radio de agarre, con preferencia hacia delante. Queda restringido a la circunferencia de la cuerda y bombea tangencialmente mientras se mantenga.
- **Soltar**: sale despedido con la velocidad tangencial acumulada. Gravedad y arrastre a partir de ahí.
- **Volver a pulsar**: engancha al siguiente farol si hay uno en radio; si no, sigue volando (y probablemente muere).

Cada muro atravesado = 1 punto. Muerte → pantalla de game over → toque → nuevo run en menos de 300 ms.

Partida objetivo: **15–60 s**. Los primeros 10 muros son un tutorial silencioso (espaciado generoso, anclas evidentes); nadie lee un tutorial en un hiper-casual. Una excepción deliberada: el muro 6 es el **anticipo** de la mecánica firma (D-021) — velo parcial, muro en penumbra visible y hápticos a plena spec, para que quien muere pronto pruebe el sabor de las zonas a ciegas antes del muro 11.

**El mundo cambia cada día** (D-020): la semilla deriva de la fecha en UTC, todo el mundo juega el mismo trazado el mismo día y la memorización caduca a medianoche. Las zonas a ciegas y el muro de anticipo caen siempre en los mismos muros, sea cual sea la semilla.

## Muerte

Instantánea, sin vidas ni escudos:

- Colisión del círculo del jugador con un muro (cualquier parte que no sea el hueco).
- Colisión con suelo o techo.

No hay muerte por tiempo, ni por quedarse quieto: el mundo nunca mata directamente al que no avanza — la única forma de puntuar es avanzar. En el tramo de aprendizaje (muros 1-13) colgarse se sostiene solo, indefinidamente. A partir del muro 14 las flores se marchitan mientras se cuelga de ellas (D-019): la flor agotada *suelta* a Lumi con su velocidad exacta, y es la física de siempre la que resuelve — si muere después, lo mata la caída que ya conocía, no un temporizador.

## Scoring

- **1 punto** por muro atravesado.
- **×2** por muro atravesado dentro de una zona a ciegas. Es la mecánica firma; el marcador debe recompensarla, no solo tolerarla.
- Récord local persistente + leaderboards de Game Center (S6): el global `pendulo.highscore` (el principal, botón «Clasificación»), el recurrente diario `pendulo.diario` («Mundo de hoy» — el game over enseña sus vecinos bajo la cabecera «Hoy») y el de ritmo `pendulo.ritmo`. Sin monedas ni divisa blanda.
- Racha de días jugados (D-020): única meta-progresión. Cuenta días UTC consecutivos con al menos una partida; una línea en el menú solo cuando ya es racha (≥2 días). No exige, no castiga, no notifica.

## Curva de dificultad

La dificultad es una **rampa lineal**, no una escalera. Un salto brusco se lee como injusticia aunque la media sea idéntica. Dos fórmulas, sin tablas escalonadas (`n` = índice de muro, empezando en 1):

```
exceso   = max(0, n − 10)
espaciado = max(440, 560 − 4,0 · exceso)     pt
hueco     = max(190, 240 − 1,3 · exceso)     pt
hueco a ciegas = hueco + 100                  pt
```

Lo que producen:

| Muro | Espaciado | Hueco | Hueco si es a ciegas |
|---|---|---|---|
| 1–10 | 560 pt | 240 pt | — |
| 11 | 556 pt | 239 pt | **339 pt — primera zona a ciegas** |
| 20 | 520 pt | 227 pt | 327 pt |
| 40 | 440 pt | 201 pt | 301 pt |
| 50+ | 440 pt (piso) | 190 pt (piso) | 290 pt |

**Zonas a ciegas.** Empiezan en el muro 11 y se repiten cada 12. La duración arranca en 3 muros y crece un muro cada dos zonas, con techo en 6:

| Zona | Empieza en el muro | Duración |
|---|---|---|
| 1.ª | 11 | 3 muros |
| 2.ª | 23 | 3 muros |
| 3.ª | 35 | 4 muros |
| 4.ª | 47 | 4 muros |
| 5.ª | 59 | 5 muros |
| 7.ª y siguientes | 83, 95, … | 6 muros (techo) |

Principios de la curva:

- **La primera zona a ciegas llega en el muro 11**, no antes: el jugador necesita haber interiorizado el balanceo para que perder la vista sea un reto y no un muro de ladrillo. Llega pronto igualmente, porque es la razón de ser del juego y no puede quedar escondida tras dos minutos de juego. Y llega en el **mismo sitio para todo el mundo**: no depende de la semilla, porque es el momento en que se enseña la mecánica.
- **A ciegas el hueco crece 100 pt.** Se compensa la pérdida de información con tolerancia espacial. La dificultad la pone la ceguera, no la precisión: exigir ambas sería sumar dos castigos.
- **La dificultad escala por espaciado y alto del hueco**, no por velocidad. Acelerar el mundo rompe el pilar de legibilidad: obliga a reaccionar en vez de anticipar.
- Todos los valores tienen piso. El juego se estabiliza en un techo de dificultad alcanzable; no se vuelve imposible por diseño, se vuelve exigente.

## Qué NO es este juego (v1)

- Sin monedas, sin gemas, sin divisa blanda.
- Sin energía, vidas ni temporizadores de espera.
- Sin anuncios, ni intersticiales ni recompensados.
- Sin compras dentro de la app.
- Sin cuentas ni registro (Game Center es opt-in del sistema).
- Sin skins ni personalización cosmética.
- Sin tutorial modal ni cartel de "pulsa para saltar".
- Sin multijugador, ni asíncrono.

Un juego, un input, un marcador.

## Accesibilidad (compromiso de diseño, se implementa en S6)

Las zonas a ciegas se apoyan en un canal (el tacto) que no todo el mundo percibe igual. El juego debe ser completable sin él:

- Ajuste **«Zonas a ciegas visibles»**: mantiene la penumbra y los ×2 pero deja los muros visibles con contorno tenue.
- Ajuste **«Refuerzo de audio»** independiente de los hápticos, activo por defecto si el hardware no tiene Taptic Engine.
- El detalle de fallbacks está en [lenguaje-haptico.md](lenguaje-haptico.md).
