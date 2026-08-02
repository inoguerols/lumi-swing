# Subir Lumi Swing a App Store Connect

Paso a paso, en orden. Los textos que hay que pegar están en
[ficha-app-store.md](ficha-app-store.md); esto es el procedimiento.

Cuenta necesaria: **Apple Developer Program**, 99 €/año. Sin ella no hay envío
posible, y tarda entre unas horas y un par de días en activarse.

---

## 0. Antes de tocar App Store Connect

**Decide el ID de la leaderboard.** Ahora mismo el código usa `pendulo.highscore`
(`Sources/Core/GameCenter.swift`). En cuanto la crees, **ese identificador no se
puede cambiar nunca**. Si lo quieres como `lumiswing.highscore`, cámbialo en el
código antes de seguir.

**Comprueba que el nombre está libre.** Busca «Lumi Swing» en la App Store. Si
existe una app con ese nombre exacto, Apple rechazará el tuyo y tendrás que
repetir la ficha entera.

---

## 1. Registrar el Bundle ID

En [developer.apple.com](https://developer.apple.com/account) →
**Certificates, Identifiers & Profiles** → **Identifiers** → **+**:

- Tipo: **App IDs** → **App**
- Description: `Lumi Swing`
- Bundle ID: **Explicit** → `com.noguerol.lumiswing`
- Capabilities: marca **Game Center**

> Atajo: si en Xcode marcas *Automatically manage signing* y eliges tu equipo, él
> registra el Bundle ID solo. Pero la capacidad de Game Center la tendrás que
> añadir igualmente desde Xcode (**+ Capability → Game Center**).

---

## 2. Crear la app en App Store Connect

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+**
→ **Nueva app**:

| Campo | Valor |
|---|---|
| Plataformas | iOS |
| Nombre | `Lumi Swing` |
| Idioma principal | Español (España) |
| Bundle ID | `com.noguerol.lumiswing` |
| SKU | `lumiswing-001` |
| Acceso de usuario | Acceso completo |

El **SKU** es un identificador interno tuyo: no lo ve nadie y no se puede cambiar.

---

## 3. Rellenar la ficha

En la versión **1.0**, pestañas **Información de la app** y **Preparar para
enviar**. Todo el texto sale de `ficha-app-store.md`:

- Subtítulo, descripción, palabras clave, novedades.
- **Categoría**: Juegos › Arcade (secundaria: Acción).
- **Copyright**: `2026 Ignacio Noguerol`.
- **URL de soporte**: obligatoria. Si no tienes web, sirve un repositorio público
  de GitHub o una página sencilla.
- **URL de política de privacidad**: obligatoria. Publica `privacidad.md` donde
  sea (GitHub Pages vale y es gratis) y pega la URL.

### Clasificación por edades

**Información de la app → Clasificación por edades → Editar.** Responde **Ninguno**
a todo: no hay violencia, ni sustancias, ni contenido sexual, ni juego de azar, ni
contenido generado por usuarios, ni acceso web sin restricciones. Resultado
esperado: **4+**.

### Privacidad de la app

**Privacidad de la app → Empezar** → **«No, no recopilamos datos de esta app»**.

Es literalmente cierto: el juego no tiene analítica, ni SDK de terceros, ni red
propia. Game Center lo gestiona Apple con la cuenta del propio usuario. Si algún
día añades cualquier SDK, esto hay que revisarlo — declarar de menos aquí es de
las pocas cosas por las que Apple retira apps.

---

## 4. Capturas

**Preparar para enviar → Capturas de pantalla del iPhone.**

Sube las de `capturas/` (1320×2868). Apple solo exige hoy el tamaño de 6,9"; el
resto los deduce. Mínimo 3, máximo 10, y **las tres primeras son las que se ven en
los resultados de búsqueda** — pon primero la de la luciérnaga colgando con la
liana tensa.

---

## 5. Game Center

**Servicios → Game Center → Clasificaciones → +** → *Clasificación única*:

| Campo | Valor |
|---|---|
| ID de clasificación | `pendulo.highscore` (¡el mismo que el código!) |
| Nombre de referencia | Mejor puntuación |
| Formato de puntuación | Entero |
| Orden | De mayor a menor |
| Intervalo de puntuación | 0 – 100000 |

Y añade una **localización** en español: nombre visible «Mejor puntuación»,
formato «puntos».

El ranking semanal y el diario los mantiene Apple automáticamente sobre esta misma
clasificación: no hay que crear nada más. El juego abre el semanal por defecto.

---

## 6. Precio

**Precios y disponibilidad** → **Gratis**, todos los territorios.

---

## 7. Subir la compilación desde Xcode

1. Destino: **Any iOS Device (arm64)** (con un simulador seleccionado, *Archive*
   está en gris).
2. **Product → Archive**.
3. En el Organizer: **Distribute App → App Store Connect → Upload**.
4. Firma automática: deja que Xcode gestione los certificados.

La compilación tarda entre 5 y 30 minutos en aparecer en App Store Connect
(«procesando»). Cuando aparezca, selecciónala en **Preparar para enviar →
Compilación**.

No te preguntará por el cumplimiento de exportación: ya va declarado en el
Info.plist (`ITSAppUsesNonExemptEncryption: false`), porque el juego no usa
cifrado propio.

---

## 8. Enviar a revisión

**Añadir para revisión → Enviar**.

En **Notas para el revisor**, pega el texto de `ficha-app-store.md`. La parte
importante es avisar de que **la mecánica firma son los hápticos** y de que en el
simulador no existen: sin ese aviso, un revisor que lo pruebe en simulador verá un
juego al que le falta la mitad.

Versión de lanzamiento: **publicar manualmente** es lo sensato para una primera
app — así decides tú el día en que aparece.

---

## Lo que suele hacer que rechacen un juego así

- **Capturas que no son del juego.** Las nuestras lo son.
- **Ficha que promete algo que la app no hace.** Cuidado si algún día quitas el
  ranking o metes anuncios: hay que actualizar la descripción.
- **Privacidad mal declarada.** Con «no se recopilan datos» y sin SDK, cubierto.
- **Crash en la revisión.** Prueba el archive en tu iPhone antes de enviar, no
  solo en simulador.
- **Guideline 4.3 (spam / clon).** Es el riesgo real de un hiper-casual de swing:
  Apple rechaza clones sin identidad propia. Nuestra defensa son las zonas a
  ciegas guiadas por hápticos, así que **menciónalas en las notas del revisor y en
  la descripción** — no las escondas.

---

## Después de publicar

- Los primeros números tardan 24 h en aparecer en **Analíticas**.
- Las valoraciones son el motor de descubrimiento. El sitio natural para pedirlas
  con `SKStoreReviewController` sería tras un récord nuevo, y no está implementado:
  dilo si lo quieres.
- Para actualizar: sube la versión en `project.yml` (`MARKETING_VERSION`), archiva
  y crea una versión nueva en App Store Connect.

## 9. Release automatizado (desde 2026-08-02)

El camino manual de arriba (§7) ya no hace falta:

1. **Merge/push a `main`** → Xcode Cloud compila, firma y sube la build a
   TestFlight él solo (workflow "Default", distribución `APP_STORE_ELIGIBLE`;
   `ci_scripts/ci_post_clone.sh` genera el proyecto con XcodeGen).
2. **Enviar a revisión** (cuando la versión en ASC está editable):

   ```bash
   python3 "$(pwd)/scripts/asc-release.py" --whats-new "Novedades en español" --whats-new-en "What's new"
   ```

   Engancha la última build VALID, la asegura en los grupos internos de
   TestFlight, actualiza las novedades (es+en) y crea+envía el reviewSubmission.
   `--status` para mirar sin tocar. Credenciales: `~/.appstoreconnect/asc-api-key.json`.

Para una versión nueva (p. ej. 1.1) hay que crear antes la versión en ASC
(POST appStoreVersions o desde la web) y subir capturas si cambiaron.
