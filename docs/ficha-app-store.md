# Lumi Swing — Ficha de App Store

Todo lo que hay que pegar en App Store Connect. Copiar tal cual.

## Datos básicos

| Campo | Valor |
|---|---|
| **Nombre** (máx. 30) | `Lumi Swing` |
| **Subtítulo** (máx. 30) | `Columpia la luz en la noche` |
| **Bundle ID** | `com.noguerol.lumiswing` |
| **SKU** | `lumiswing-001` |
| **Categoría principal** | Juegos › Arcade |
| **Categoría secundaria** | Juegos › Acción |
| **Precio** | Gratis, sin compras dentro de la app |
| **Clasificación por edades** | 4+ |
| **Idioma principal** | Español (España) |

## Palabras clave (máx. 100 caracteres, separadas por comas, sin espacios)

```
columpio,liana,luciernaga,arcade,un dedo,reflejos,haptico,vibracion,noche,selva,records,casual
```

Van sin tilde a propósito: la App Store no normaliza acentos al buscar, y quien
teclea rápido en el móvil escribe «luciernaga».

## Descripción

```
Eres una luciérnaga en una selva de noche.

Mantén pulsado para engancharte con una liana a la flor de luna más cercana.
Suelta y sal despedido con la inercia. Un solo dedo, nada más.

ZONAS A CIEGAS
Cada pocas puertas, la espesura traga la luz y los troncos desaparecen. Ahí solo
te queda el tacto: el ritmo de las vibraciones te dice a qué distancia está el
muro, y una textura continua te avisa de que estás a la altura del hueco.

Se puede pasar con la pantalla boca abajo. Y esas puertas valen el doble.

QUÉ NO VAS A ENCONTRAR
· Sin anuncios
· Sin compras dentro de la app
· Sin vidas ni esperas
· Sin registro
· Funciona sin conexión

ACCESIBLE
Si no percibes los hápticos, activa «Ver los muros a ciegas» en Ajustes: las
zonas a ciegas mantienen la penumbra y la puntuación doble, pero los troncos
conservan un contorno tenue. El juego se puede terminar sin depender del tacto.

Clasificación mundial en Game Center, con ranking semanal: cada lunes vuelve a
empezar y todos tenéis una oportunidad.
```

## Novedades de esta versión (1.0)

```
Primera versión. Suéltate.
```

## Texto para el equipo de revisión de Apple

```
Juego de un solo input, sin cuentas ni compras. No requiere inicio de sesión.

Sobre Game Center: la clasificación es opcional; si el revisor no tiene sesión
iniciada, el juego funciona igual y guarda el récord localmente.

La mecánica distintiva son las "zonas a ciegas": tramos donde los obstáculos se
vuelven invisibles y el jugador se guía por Core Haptics. Si se prueba en
simulador no hay Taptic Engine y la app cae automáticamente a un sustituto de
audio más un contorno tenue de los obstáculos, así que sigue siendo jugable.
Para valorarlo como está diseñado hace falta un dispositivo físico.

No se recopila ningún dato del usuario.
```

## Privacidad

En el cuestionario de App Store Connect: **«No se recopilan datos»**.

- El juego no tiene analítica, ni SDK de terceros, ni red propia.
- Lo único que se guarda es el récord y cuatro ajustes, en `UserDefaults`, en el
  dispositivo.
- Game Center lo gestiona Apple con la cuenta del propio usuario; nosotros solo
  enviamos una puntuación a una leaderboard.

Aun así, App Store Connect exige una **URL de política de privacidad**. Hay un
texto listo en `docs/privacidad.md` para publicar donde sea (una página de GitHub
Pages sirve).

## Capturas

En `capturas/`, a 1320×2868 (iPhone 6,9"), que es el único tamaño de iPhone que
Apple exige hoy. Se regeneran con:

```bash
xcrun simctl launch "iPhone 17 Pro Max" com.noguerol.lumiswing -autoplay -demo
xcrun simctl io "iPhone 17 Pro Max" screenshot capturas/nombre.png
```

`-demo` hace que el juego se pilote solo: capturar un juego de reflejos a mano da
fotos torcidas, y en una ficha la pose importa — la luciérnaga colgando de una
flor con la liana tensa cuenta el juego en una sola imagen.

Orden recomendado (Apple muestra las tres primeras en los resultados de búsqueda):

1. **La luciérnaga colgando con la liana tensa** — cuenta la mecánica sin texto.
2. **Una zona a ciegas** — el gancho del juego.
3. **El menú** — marca e identidad.
4. Game over con récord.

Conviene añadirles un rótulo corto encima (Apple lo permite y sube la conversión):
«Un dedo», «A ciegas, solo con el tacto», «Ranking semanal».
