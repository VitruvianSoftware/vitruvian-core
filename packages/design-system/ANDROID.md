# Vitruvian on Android — Jetpack Compose handoff

The web package (`packages/design-system`) is React + CSS and does not run on
Android. What transfers is the language: `src/tokens.json` (W3C Design Tokens
format, generated from `tokens.css`) plus the rules in `foundations/mobile.html`.
This maps them to Compose. Build one Gradle module, `:design-system`, with no
app dependencies.

## Tokens → Compose

Generate, don't hand-copy. Style Dictionary (or a 40-line Gradle task) reads
`tokens.json` and emits `VitruvianTokens.kt`; CI diffs the output so web and
Android cannot drift. Read px as dp; font sizes as sp.

| tokens.json | Compose |
| --- | --- |
| `color.*` (dark = default), `light.color.*` | `VitruvianColors` data class, `darkColors()` / `lightColors()`; expose via `LocalVitruvianColors`. Do **not** map onto `MaterialTheme.colorScheme` — Material's roles (primaryContainer, tertiary…) don't match the language. |
| `color.*` with 8-digit hex | `Color(0x…)` — alpha is in the value; these are the `color-mix` tints. |
| `font.family.display/mono` | JetBrains Mono, bundled `res/font/` (400, 500, 700). `font.family.body` → IBM Plex Sans (400, 500, 600). |
| `font.size.*` | `TextStyle(fontSize = N.sp)`; the `mobile-*` sizes are the phone ramp (h1 29 / h2 22 / h3 17 / body 15). |
| `space.1…8` | `object Space { val s1 = 3.dp … val s8 = 89.dp }`. Nothing else is used for padding or gaps. |
| `hit.1`, `hit.2` | `Modifier.sizeIn(minHeight = 44.dp)` on every clickable; rows/bars 55.dp. |
| `radius.*` | `Shapes(RectangleShape, RectangleShape, …)` — every corner is square. |
| `shadow.*` | `Modifier.shadow(elevation)` only on things that float (menu, dialog). Board content is flat. |
| `motion.duration.1…4` | `tween(durationMillis = 90 / 140 / 220 / 340)`. |
| `motion.easing.mech/snap` | `CubicBezierEasing(0.2f, 0f, 0.3f, 1f)`, `CubicBezierEasing(0.45f, 0f, 0.15f, 1f)`. No `spring()`, ever. |
| `glass.*` | A 66%-alpha surface. The blur is of what sits BEHIND it, so it is a property of the window, not of the surface: inside a `Dialog`, API 31+ `FLAG_BLUR_BEHIND` + `blurBehindRadius = 16`. Below 31, or off a dialog window, or with cross-window blur disabled: opaque `color.surface`. **Never** `Modifier.graphicsLayer { renderEffect = createBlurEffect(...) }` on the surface — that blurs the surface's own icons and text, which is the inverse of glass. |

Theme entry point:

```kotlin
@Composable
fun VitruvianTheme(dark: Boolean = true, content: @Composable () -> Unit)
```

`dark = true` is the default (the board); light is parchment.

## Components — mirror the React set

One Kotlin file per family, same names as `src/*.tsx`, so a designer reading
the Storybook and a developer reading the module see the same vocabulary.

- **Plate** — `Box` with a 1.dp `color.divider` border and four registration
  marks drawn in `Modifier.drawBehind` (11.dp crosses, 6.dp outside each
  corner, `color.accentText`). Everything framed is a Plate.
- **Button** — `primary / secondary / ghost / danger`; mono 12–13.sp, tracked
  0.08em, uppercase; min height 44.dp; press = 1.dp translate + `accentQuiet`
  fill over `duration.1`.
- **Tag, Label, Kbd** — mono, tracked, tinted 16% + 40% border as in CSS.
- **Card** — a Plate with kicker / title / body / meta; transparent ground.
- **Field, Input, Switch, Segmented, Checkbox, Radio** — square boxes, steel
  fills, label lights to `accentText` on focus. Input height ≥ 44.dp.
- **Shell (mobile)** — `Scaffold` with `TopBar` (55.dp + status-bar inset)
  and `TabBar` (55.dp + navigation-bar inset, glass, 2.dp steel rule on the
  active tab's top edge). Use `WindowInsets.safeDrawing` on the bars only.
- **ListItem** — 55.dp row, status square, title + mono sub-line, trailing
  slot; hairline separator; press tint. Never a card per row.
- **Status, Metric, Meter, SegBar, Spark** — `Canvas` primitives; values
  animate with `tween(340, LinearEasing)`.
- **Dialog** — glass over a 55% ink scrim; destructive variant with sanguine
  kicker and a typed confirmation.
- **Menu** — glass, 200.dp min width, mono items, hairline divider, sanguine
  last item for destroy.
- **EmptyState, Skeleton, Spinner** — dashed plate; pulsing surface;
  hairline ring rotating 900ms linear.

## Rules that are easy to break on Android

- No Material ripple — `LocalIndication` provides a flat `accentQuiet` tint.
- No rounded corners, no elevation on board content, no gradients.
- Headings never above weight 500. Mono 700 is for terminal emphasis only.
- Destructive actions are never swipe gestures.
- `LocalContentColor` defaults to `color.text`; accent body copy uses
  `color.accentText`, never `color.accent`.
- Respect the system's reduce-motion setting: durations collapse to 0 and
  every entering element lands at full opacity.

## Definition of done

The `:design-system` module has a Compose preview per component in both
modes, screenshot-tested; `tokens.json` → Kotlin is generated in CI; and
`foundations/mobile.html` and the previews look like the same drawing.
