# Vitruvian on Android — Jetpack Compose (`//packages/design-system-android`)

The web package (`packages/design-system`) is React + CSS and does not run on
Android. What transfers is the language: `src/tokens.json` (W3C Design Tokens
format, synchronized with `tokens.css`) plus the rules in `foundations/mobile.html`.
`packages/design-system-android` is the Jetpack Compose implementation of that
language, with zero app dependencies.

## Tokens → Compose

`bazel run //packages/design-system-android/tools:gen_tokens` reads `tokens.json` and
emits `VitruvianTokens.kt` (the exact command is in `packages/design-system-android/README.md`). `bazel test //packages/design-system-android:tokens_are_current`
diffs the generated output in CI so Web and Android cannot drift. Read `px` as
`dp`; font sizes as `sp`.

| tokens.json | Compose |
| --- | --- |
| `color.*` (dark = default), `light.color.*` | `VitruvianColors` data class, `darkColors()` / `lightColors()` (including `accent100..900`, `sanguine100..900`, `neutral100..900`); expose via `LocalVitruvianColors`. Do **not** map onto `MaterialTheme.colorScheme` — Material's roles (primaryContainer, tertiary…) don't match the language. |
| `color.*` with 8-digit hex | `Color(0x…)` — alpha is in the value; these are the `color-mix` tints. |
| `font.family.display/mono` | JetBrains Mono, bundled `res/font/` (400, 500, 700). `font.family.body` → IBM Plex Sans (400, 500, 600). |
| `font.size.*` | `TextStyle(fontSize = N.sp)`; the `mobile-*` sizes are the phone ramp (h1 29 / h2 22 / h3 17 / body 15). |
| `space.1…8` | `object Space { val s1 = 3.dp … val s8 = 89.dp }`. Nothing else is used for padding or gaps. |
| `hit.1`, `hit.2` | `Modifier.defaultMinSize(minHeight = 44.dp)` on every clickable; rows/bars 55.dp. |
| `radius.*` | Square corners everywhere — all radius tokens are `0.dp`. |
| `shadow.*` | `Modifier.shadow(elevation)` only on things that float (menu, dialog, sheet, toast). Board content is flat. |
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

One Kotlin file per family in `packages/design-system-android/src/main/kotlin/dev/vitruvian/design/`,
enforced by `bazel test //packages/design-system-android:parity_test`:

- **Plate (`Plate.kt`)** — `Plate`, `Rule`, `VMark`, `Modifier.bottomHairline`.
- **Card (`Card.kt`)** — `Card` (`CardSurface.Plate / Fill / Glass`, `kicker`, `title`, `meta`, `marks`, `dashed`, `live`).
- **Button (`Button.kt`)** — `VButton` (`ButtonVariant.Primary / Secondary / Ghost / Danger`).
- **Tag (`Tag.kt`)** — `Tag` (`TagTone`), `Kbd`; `Label` and `VText` live in `Text.kt`.
- **Form (`Form.kt`)** — `Field` (with `hint` / `error`), `VInput`, `VTextarea`, `VSwitch`, `VCheckbox`, `VRadio`, `VSelect`, `VSlider`, `CopyButton`, `Segmented`.
- **Nav (`Nav.kt`)** — `TopBar`, `HostChip`, `TabBar`, `Rail`, `Section`, `SectionHeader`, `Crumbs`, `Tabs`, `Pagination`, `Avatar`.
- **Layout (`Layout.kt`, `ListItem.kt`)** — `ListItem`, `AutoGrid`, `KeyValue`, `Accordion`.
- **DataDisplay (`DataDisplay.kt`)** — `Status`, `Metric`, `Meter`, `SegBar`, `Spark`, `LogStream`, `VTable`.
- **Terminal (`Terminal.kt`)** — `Terminal`, `Code`, `BlinkingCursor`.
- **Overlay (`Overlay.kt`)** — `VDialog`, `BottomSheet`, `MenuSurface`, `MenuItem`, `MenuDivider`, `Toast`.
- **States (`States.kt`)** — `Banner`, `EmptyState`, `Skeleton`, `Spinner`.
- **Icons (`Icons.kt`)** — `VIcon` and `VitruvianIcons` (all 28 24×24 outline glyphs matching Web).
- **Illustrations (`Illustrations.kt`)** — `VitruvianPlateKind`, `VitruvianPlate`, and `PlateFigure` (all 8 codex vector plates).

## Rules that are easy to break on Android

- No Material ripple — `LocalIndication` provides a flat `accentQuiet` tint.
- No rounded corners, no elevation on board content, no gradients.
- Headings never above weight 500. Mono 700 is for terminal emphasis only.
- Destructive actions are never swipe gestures.
- `LocalContentColor` defaults to `color.text`; accent body copy uses
  `color.accentText`, never `color.accent`.
- Respect the system's reduce-motion setting: durations collapse to 0 and
  every entering element lands at full opacity.
