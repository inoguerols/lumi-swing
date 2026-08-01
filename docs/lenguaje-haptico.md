# Péndulo — El lenguaje háptico

*Versión 1 · 2026-07-29*

Este documento define los hápticos de Péndulo como un idioma: un vocabulario cerrado de señales, cada una con un significado único e inequívoco. La regla que gobierna todo el sistema:

> **Dos señales no pueden competir por el mismo canal perceptual.** Si el jugador tiene que decidir *cuál* de dos vibraciones parecidas está sintiendo, el idioma ha fallado.

De ahí sale la decisión central del sistema: **la proximidad habla por ritmo, la alineación habla por presencia/ausencia de textura.** Son dos ejes perceptuales ortogonales (tiempo vs. continuidad), así que se pueden sentir simultáneamente sin enmascararse.

---

## 1. Vocabulario

Seis señales. No hay una séptima.

| Señal | Tipo | Significado | Cuándo |
|---|---|---|---|
| **Proximidad** | transients repetidos | «hay un muro a esta distancia» | continuo en zona a ciegas |
| **Alineación** | continuous | «estás a la altura del hueco» | continuo en zona a ciegas, solo si alineado |
| **Agarre** | transient seco | «te has enganchado» | al pulsar con ancla en radio |
| **Suelta** | transient blando | «te has soltado» | al levantar el dedo estando agarrado |
| **Punto** | transient corto | «has pasado un muro» | al cruzar el plano del muro |
| **Muerte** | transient + decay | «se ha acabado» | en la colisión |

Más dos marcadores estructurales (frontera de zona, no estado continuo):

| Señal | Tipo | Significado |
|---|---|---|
| **Entrada a ciegas** | dos transients | «pierdes la vista ahora» |
| **Salida de ciegas** | transient ascendente | «has salido» |

---

## 2. Proximidad — el ritmo es la distancia

Un tren de `hapticTransient` cuya **cadencia** codifica la distancia horizontal al siguiente muro. Cerca = rápido y fuerte. Lejos = lento y suave. Más allá de 900 pt: **silencio** (el silencio también es información: «no hay nada inminente»).

### Tabla ritmo ↔ distancia

| Distancia al muro | Intervalo entre pulsos | `intensity` | `sharpness` | Sensación |
|---|---|---|---|---|
| > 900 pt | — (silencio) | — | — | vía libre |
| 900 pt | 0,60 s | 0,35 | 0,75 | latido lejano |
| 700 pt | 0,45 s | 0,45 | 0,79 | se acerca |
| 500 pt | 0,32 s | 0,58 | 0,83 | atención |
| 350 pt | 0,23 s | 0,70 | 0,87 | inminente |
| 200 pt | 0,15 s | 0,82 | 0,91 | ya |
| 100 pt | 0,09 s | 0,92 | 0,96 | urgencia |
| ≤ 40 pt | 0,06 s | 1,00 | 1,00 | ráfaga |

### Fórmula (es esto lo que se implementa; la tabla es su lectura)

```
t = clamp(distance / proximityRange, 0, 1)          // proximityRange = 900 pt
interval  = lerp(0.06, 0.60, pow(t, 1.35))          // s
intensity = lerp(1.00, 0.35, t)
sharpness = lerp(1.00, 0.75, t)
```

El exponente **1,35** es lo que hace legible el sistema: comprime los cambios lejanos y expande los cercanos, de modo que la aceleración del ritmo se percibe justo cuando importa (los últimos 300 pt). Con exponente 1,0 la rampa es lineal y el jugador no siente la urgencia hasta que ya ha chocado.

`sharpness` alta (0,75–1,0) en todo el rango: el pulso de proximidad debe ser **seco y puntual**, un golpecito, para no confundirse nunca con la textura continua de alineación.

---

## 3. Alineación — la presencia es el sí

Un `hapticContinuous` de baja intensidad y **sharpness muy baja** (textura sorda, redonda, tipo zumbido lejano) que **suena solo cuando el jugador cabe por el hueco**.

```
clearance = (gapHeight / 2) - playerRadius - abs(playerY - gapCenterY)
alineado  = clearance > 0
intensity = lerp(alignLowIntensity, alignHighIntensity, clamp(clearance / alignClearanceSpan, 0, 1))
            // 0,16 → 0,34
sharpness = 0.12   (constante)
```

**Desalineado = ausencia total de textura.** Esta es una decisión deliberada y es la más importante del documento. La alternativa obvia era «textura suave si alineado, textura áspera si desalineado», y se descarta: dos continuous simultáneamente distintos son casi indistinguibles en el Taptic Engine cuando además hay transients encima. Presencia/ausencia es binario, instantáneo y no requiere comparación. El jugador aprende en dos segundos: *si zumba, pasas*.

La `intensity` escalada por `clearance` da el matiz gratis: un zumbido apenas perceptible significa «pasas rozando», uno pleno significa «vas centrado». Un solo parámetro, tres niveles de información, cero señales nuevas.

---

## 4. Las cuatro señales de evento

| Señal | Patrón | Por qué así |
|---|---|---|
| **Agarre** | 1 transient · `intensity 0,85` · `sharpness 1,00` | Máxima sharpness = chasquido metálico. Es un enganche mecánico; debe sentirse como un clic, no como un empujón. |
| **Suelta** | 1 transient · `intensity 0,45` · `sharpness 0,25` | Sharpness baja = golpe sordo y difuso. La liberación es lo contrario del enganche, y el contraste tímbrico lo hace inconfundible incluso a ciegas. |
| **Punto** | 1 transient · `intensity 0,40` · `sharpness 0,65` | Discreto. Ocurre muchas veces por partida; si fuese fuerte, saturaría y enmascararía los pulsos de proximidad. |
| **Muerte** | 1 transient · `intensity 1,00` · `sharpness 0,90`, seguido de continuous 0,28 s con `intensity 0,60 → 0` y `sharpness 0,30` | Impacto y resonancia. El decay es lo que da la sensación de "se apaga" y cierra la partida sin necesidad de mirar la pantalla. |

### Marcadores de zona

- **Entrada a ciegas**: dos transients (`intensity 0,70` · `sharpness 0,40`) separados **0,12 s**. Un patrón rítmico de dos golpes no existe en ninguna otra señal del vocabulario, así que es imposible confundirlo con proximidad (que es un tren regular) o con agarre (que es único y seco).
- **Salida de ciegas**: 1 transient (`intensity 0,60` · `sharpness 0,70`) + continuous 0,18 s con `intensity 0,15 → 0,40` (ascendente). El único patrón *ascendente* del idioma: alivio.

---

## 5. Convivencia en zona a ciegas

Durante una zona a ciegas hay dos señales activas a la vez, más eventos puntuales encima:

```
proximidad   ·  ·  ·  · · · ·· ····     (transients, sharp, ritmo creciente)
alineación   ~~~~~~~~      ~~~~~~~~~~   (continuous, sordo, on/off)
eventos                ▲        ▲       (agarre, punto)
```

Reglas de mezcla:

1. La suma de intensidades simultáneas se mantiene por debajo de **1,3** en `CHHapticEngine`. Si un evento coincide con proximidad a máxima intensidad, **el evento gana** y el pulso de proximidad de ese instante se omite (no se atenúa: se salta, para no romper la lectura del ritmo).
2. **Muerte cancela todo**: detiene el player de proximidad y el de alineación antes de disparar su patrón.
3. La alineación se recalcula por frame pero su `CHHapticAdvancedPatternPlayer` se **actualiza con parámetros dinámicos** (`sendParameters`), no se recrea. Recrear players a 60 Hz agota el motor y produce cortes audibles.

---

## 6. Fallbacks

El lenguaje háptico es el mapa. Si el mapa no se puede entregar, el juego debe entregar otro — nunca dejar al jugador sin información.

### 6.1 Hardware sin Taptic Engine (iPad, simulador, iPod)

Detección: `CHHapticEngine.capabilitiesForHardware().supportsHaptics == false`.

Sustitución **completa y automática**, sin preguntar:

| Señal háptica | Sustituto |
|---|---|
| Proximidad | click de audio corto (1,2 kHz, 18 ms) con la misma cadencia de la tabla |
| Alineación | tono continuo 660 Hz a −24 dB cuando alineado; silencio si no |
| Agarre / suelta | click agudo / thud grave |
| Punto | blip 880 Hz |
| Muerte | ruido descendente 0,3 s |

**Y además** se activa el *refuerzo visual asistido*: en zona a ciegas los muros no desaparecen del todo, se dibujan con un contorno al 12 % de opacidad y aparecen anillos de proximidad concéntricos. Sin Taptic, la ceguera total no es un reto: es un muro.

### 6.2 Modo silencio (interruptor lateral)

Core Haptics **no** depende del interruptor de silencio: los hápticos siguen funcionando. El audio sí se calla, porque la sesión de audio usa la categoría `.ambient` (respetamos la música del jugador y el interruptor; forzar `.playback` para colar nuestros pitidos en modo silencio sería hostil).

Consecuencia asumida y correcta: **en silencio, con un iPhone con Taptic, el juego es plenamente jugable** — el audio era refuerzo. Es exactamente el escenario para el que está diseñado el sistema.

En silencio **y** sin Taptic (iPad silenciado): se activa el refuerzo visual asistido de 6.1, que no depende de ningún canal desactivable.

### 6.3 Modo de bajo consumo

`ProcessInfo.processInfo.isLowPowerModeEnabled` — iOS atenúa los hápticos del sistema y no garantiza fidelidad. Se activa el refuerzo de audio (si no está en silencio) además de los hápticos. No se activa el refuerzo visual: los hápticos siguen ahí, solo se les añade una red.

### 6.4 Hápticos desactivados por el jugador (ajuste de la app)

Ajuste **«Hápticos»** en S6. Al apagarlo se aplica el paquete completo de 6.1: audio sustitutivo + refuerzo visual asistido. Apagar los hápticos no debe hacer el juego más difícil, solo distinto.

### 6.5 Accesibilidad

Ajuste **«Zonas a ciegas visibles»**: penumbra y ×2 se mantienen, los muros se ven con contorno tenue permanente. Para quien no percibe hápticos ni quiere depender del audio. Preserva la mecánica y el marcador; cambia el canal.

---

## 7. Gestión del motor

- **Un único `CHHapticEngine`** para toda la app, tras el protocolo `HapticsEngine` (ver [arquitectura.md](arquitectura.md)).
- Patrones de evento **precargados** como `CHHapticPatternPlayer` al arrancar. Crear el patrón en el instante del evento introduce latencia perceptible (~10-20 ms) y en el agarre eso rompe la sensación de causa-efecto.
- Proximidad y alineación usan `CHHapticAdvancedPatternPlayer` con `loopEnabled` y parámetros dinámicos.
- `resetHandler`: el motor puede morir (llamada entrante, presión de memoria). Al resetear, se rearranca y se **recargan los players**; si el juego estaba en zona a ciegas, se reanudan proximidad y alineación en el estado actual.
- `stoppedHandler`: si la razón es `.audioSessionInterrupt` o `.applicationSuspended`, no se rearranca hasta volver a foreground. Cualquier otra razón se rearranca en el acto.
- **`ensureRunning()` es quien cumple ese "hasta volver a foreground"**: `RootView` observa `scenePhase` y en `.active` lo llama. Rearranca el motor si está parado, reintenta entero el `prepare()` si el arranque en frío había fallado y reactiva la `AVAudioSession` y el `AVAudioEngine` del canal de audio, que la interrupción también se lleva. Es idempotente y barato, así que además se usa como guard perezoso al principio de `play()` y en cada vuelta del bucle de proximidad: eso cubre el `isAutoShutdownEnabled` y la carrera con el `stoppedHandler`. Sin esto, una llamada entrante dejaba el juego mudo el resto de la sesión.
- `engine.start()` es asíncrono y puede lanzar. Un fallo de arranque **no es fatal**: se cae al fallback de 6.1 y el juego sigue.
- Fuera de `.active` (`.inactive`/`.background`): parar los players continuos. Un continuous huérfano vibrando en background es un bug reportable.
- **Los interruptores de Ajustes se filtran por canal, dentro del motor** (`setChannels(haptics:audio:)`, empujado desde `RootView` en cuanto cambian). Hápticos OFF + sonido ON = solo sonido, y apagar los hápticos calla la textura de alineación en el acto. La escena solo decide si merece la pena cruzar al actor cuando los dos canales están apagados.

---

## 8. Pantalla de debug (S3)

Los hápticos **solo se validan en dispositivo físico**, así que la herramienta de validación es parte del producto interno, no un extra.

Acceso oculto: **cinco toques en el título del menú principal**. Sin botón visible en release.

Contiene:

- Un botón por cada una de las 8 señales del vocabulario, que la dispara aislada.
- Sliders de `intensity` y `sharpness` en vivo para el patrón seleccionado, para tunear sobre el dispositivo.
- Un slider de **distancia simulada** (0–1000 pt) que hace correr el tren de proximidad con el ritmo correspondiente, para calibrar la tabla del punto 2 con el pulgar en vez de con la intuición.
- Un interruptor de alineación, para sentir la textura del punto 3 y ajustar el par intensity/sharpness.
- Lectura del estado del motor: `supportsHaptics`, si arrancó, cuántos resets ha habido, si hay low power mode.
- Un botón **«volcar valores»** que imprime las constantes actuales en formato Swift, listas para pegar en `Tuning.swift`. El tuning se hace con el dedo en el iPhone; el fichero solo lo registra.
