# Pitch de featuring a Apple — Lumi Swing

**Dónde se envía:** formulario oficial «Promote your app» →
<https://developer.apple.com/contact/app-store/promote/>
(sesión con el Apple ID de desarrollador de Nacho; no hay API, es manual).

**Cuándo:** en cuanto la v1.1 esté aprobada. Apple recomienda 6-8 semanas de
antelación para fechas concretas, pero para una app nueva sin fecha de evento
lo correcto es enviarlo con el lanzamiento y marcar disponibilidad inmediata.
Se puede reenviar en cada update mayor (no spamear: 1 pitch por hito real).

**Datos que pide el formulario:**

| Campo | Valor |
|---|---|
| App name | Lumi Swing |
| Apple ID de la app | 6796959896 |
| Bundle ID | com.noguerol.lumiswing |
| Categoría | Games (Arcade / Casual) |
| Disponibilidad | Worldwide, gratis, sin IAP ni anuncios |
| Dispositivos | Universal: iPhone, iPad (portrait; D-023) |
| Idiomas | Español, English |
| Requisitos | iOS 18+, sin cuenta, sin red obligatoria |

---

## Texto principal (pegar en "Tell us about your app")

> **Lumi Swing is a one-finger swinging game where the Taptic Engine isn't
> feedback — it's the level.**
>
> You guide Lumi, a small being of light, through a night jungle: hold to grab
> a moonflower and swing, release to fly. Every few gates, the jungle goes
> dark. In these *blind zones* you navigate by touch alone: the haptic rhythm
> tells you how far the next wall is, the texture tells you whether you're
> aligned with the gap. Sound reinforces; it never substitutes. We believe
> it's one of the first games where Core Haptics carries the core mechanic
> rather than decorating it — you can literally clear sections of the game
> with your eyes closed.
>
> The whole game is built on Apple technologies, with no third-party SDKs:
> SpriteKit at 120 Hz on ProMotion, Core Haptics with a closed six-signal
> vocabulary, a fully procedural ambient soundtrack synthesized in
> AVAudioEngine (crickets, filtered wind and a kalimba — zero audio assets),
> SwiftUI for the shell, and Game Center with recurring leaderboards. Every
> day the jungle reshuffles from the date itself: the whole world plays the
> same daily layout and competes on "Today's World", with a crown for
> yesterday's winner.
>
> Accessibility is the design, not a checkbox: the blind-zone mechanic ships
> with an assisted mode (faint wall outlines) for players who can't perceive
> haptics, an independent audio-reinforcement channel, full Dynamic Type and
> Reduce Motion support — and because the game teaches through touch, it is
> genuinely playable without looking at the screen.
>
> There are no ads, no in-app purchases, no accounts and no data collection
> of any kind. One finger, one score, localized in English and Spanish, made
> by a solo indie developer in Spain.

## Párrafo corto alternativo (si el campo es pequeño)

> A one-finger swinging game where the Taptic Engine is the level: in its
> signature "blind zones" you navigate by haptic rhythm and texture alone.
> 120 Hz SpriteKit, fully procedural audio, daily shared world via Game
> Center recurring leaderboards, deep accessibility (assisted mode, audio
> reinforcement, Dynamic Type, Reduce Motion), no ads, no IAP, no tracking.
> Universal for iPhone and iPad, in English and Spanish.

## "What makes your app unique?" (bullets)

- **Haptics as gameplay, not garnish**: distance = rhythm, alignment =
  texture. A closed vocabulary of six signals the player learns like a
  language; sections are clearable with eyes closed.
- **A daily world from the calendar**: the level layout derives from the UTC
  date — everyone on Earth plays the same jungle today, competes on a
  24-hour recurring Game Center leaderboard, and yesterday's #1 earns a crown.
- **Zero-asset audio**: the entire soundscape is synthesized at runtime in
  AVAudioEngine; it ducks into silence inside blind zones because silence is
  information.
- **Accessibility-first signature mechanic**: assisted outlines, independent
  audio channel, Dynamic Type, Reduce Motion — the game's core idea was
  designed together with its fallbacks, not patched later.
- **Radically clean**: no ads, no IAP, no accounts, no analytics, no
  third-party code. Privacy nutrition label: "Data Not Collected".
- **120 Hz ProMotion** with fixed-timestep physics (identical gameplay at 60
  and 120 Hz).

## Tecnologías Apple (campo "Which Apple technologies…")

Core Haptics · SpriteKit (120 Hz ProMotion) · AVAudioEngine (procedural
audio) · SwiftUI · Game Center (classic + recurring leaderboards) · Swift 6
strict concurrency · Xcode Cloud (CI/CD) · SF Rounded / HIG-native UI ·
Dynamic Type · Reduce Motion.

## Notas para rellenar el formulario (ES)

1. **Momento**: enviar el pitch el día que Apple apruebe la v1.1 (la versión
   en revisión ya ES la 1.1 con el mundo diario). Marcar «app is available
   now».
2. **Ángulo editorial**: la historia es «el juego que se juega por el tacto»
   — encaja con las colecciones de accesibilidad de App Store (Global
   Accessibility Awareness Day, principios de mayo, es una ventana editorial
   natural para un segundo empujón) y con «Great on ProMotion».
3. **Material de apoyo**: la ficha ya tiene 4 capturas (la estrella es la
   zona a ciegas con eco) y app preview de 22,7 s. Si piden assets extra,
   los generamos del pipeline de capturas existente (`docs/APPSTORE.md`).
4. **No mencionar**: fechas comprometidas que no controlamos, ni métricas
   que no tenemos. El pitch vende el diseño, no números.
5. **Reenvíos**: un pitch nuevo por hito real (lanzamiento v1.1 ahora;
   después, p. ej., un update de contenido gordo o la ventana GAAD de mayo).
