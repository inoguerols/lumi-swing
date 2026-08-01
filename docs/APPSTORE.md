# Lumi Swing — Qué falta para llegar a la App Store

> Los textos de la ficha están en [ficha-app-store.md](ficha-app-store.md) y la
> política de privacidad en [privacidad.md](privacidad.md). Las capturas, en
> `capturas/` a 1320×2868.

**Ya hecho:** nombre (Lumi Swing), Bundle ID `com.noguerol.lumiswing`, icono,
pantalla de arranque, capturas, ficha completa, política de privacidad y
cuestionario de privacidad resuelto («no se recopilan datos»).

El juego está completo y jugable (S1–S6). Lo que queda pide una cuenta de Apple
Developer, y por eso quedó fuera de esta tanda (D-006).

## 1. Lo que solo puedes hacer tú

- [ ] **Team ID** en `project.yml` → `settings.base.DEVELOPMENT_TEAM`. Ahora mismo la
      firma es automática y sin equipo: compila para simulador, no para dispositivo.
- [ ] **Bundle ID** `com.noguerol.lumiswing` registrado en el portal de Apple. Es
      irreversible una vez publicado (D-007).
- [ ] **Capacidad Game Center** activada para ese Bundle ID, y leaderboard
      `pendulo.highscore` creada en App Store Connect. Ese identificador también es
      irreversible. El código ya la usa y falla en silencio si no existe.
- [x] ~~Ficha en App Store Connect~~: los textos están en `ficha-app-store.md`, listos para pegar.
- [x] ~~Capturas~~: en `capturas/`, a 1320×2868 (6,9"), el único tamaño de iPhone que Apple exige.
- [ ] **Privacidad**: el juego no recoge absolutamente nada. En el cuestionario hay
      que marcar «no se recopilan datos» — Game Center lo gestiona Apple, no nosotros.

## 2. Antes de enviar

- [ ] **Probar los hápticos en tu iPhone.** Es lo único importante que sigue sin
      validar. Cinco toques en el título del menú abren la pantalla de debug: dispara
      cada señal, mueve el slider de distancia y siente si el ritmo se lee. Los
      valores de `Tuning.Haptics` son un diseño razonado, no una medición (D-001).
- [ ] **Jugar una zona a ciegas con la pantalla boca abajo.** Es la prueba de
      aceptación de verdad. El test automático demuestra que la información basta;
      solo un dedo puede decir si además se siente bien.
- [ ] **Perfilar en un iPhone de hace tres años** con Instruments (Time Profiler y
      Core Animation FPS). El presupuesto de S5 es cero caídas de frames y no se ha
      podido medir aquí: el simulador no dice nada útil sobre rendimiento real.
- [x] ~~Icono~~: luciérnaga sobre selva, generado por código. Se regenera con el script del scratchpad.
- [x] ~~Nombre~~: **Lumi Swing**. Queda comprobar que no está cogido en la App Store.

## 3. Compilar y archivar

```bash
cd "~/Claude Developer/Juegos/Pendulo"
xcodegen generate
open LumiSwing.xcodeproj
```

En Xcode: target `LumiSwing` → Signing & Capabilities → tu equipo → añadir Game Center
→ Product › Archive → Distribute App.

`LumiSwing.xcodeproj` **no está en git a propósito**: lo genera XcodeGen desde
`project.yml`, que es la fuente de verdad. Si lo editas a mano en Xcode, el siguiente
`xcodegen generate` se lo lleva por delante.

## 4. Lo que el juego promete y hay que poder defender en la revisión

- No recoge datos, no muestra anuncios, no tiene compras.
- Funciona sin conexión. Game Center es opcional y su fallo no afecta al juego.
- Es accesible: se puede completar sin percibir los hápticos, con el ajuste
  «Ver los muros a ciegas», que mantiene la penumbra y la puntuación doble.
