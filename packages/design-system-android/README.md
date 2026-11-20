# Vitruvian for Jetpack Compose

## What it gives you

The Kotlin and Jetpack Compose half of the [Vitruvian](../design-system/README.md) design language: generated design tokens (`VitruvianTokens`), `VitruvianTheme`, composition locals, flat press indication, reduce-motion helpers, and Compose UI primitives (`Plate`, `Card`, `Button`, `Tag`, `Form`, `DataDisplay`, `Terminal`, `Overlay`, `Nav`, `Icons`) backed by vendored `JetBrains Mono` and `IBM Plex Sans` fonts.

## When to use it

- Building any Android or Wear OS UI in Jetpack Compose (`apps/mobile/vitruvian-remote` or future Android apps) that follows the Vitruvian design language.

## When not to use it

- Web/React UI; use [`//packages/design-system`](../design-system/README.md) instead.
- Apps needing standard Material Design 3 components (this module intentionally avoids MaterialTheme and Material widgets).

## Example

From `apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/RemoteApp.kt:25-85`:

```kotlin
import androidx.compose.foundation.isSystemInDarkTheme
// …
import androidx.compose.runtime.Composable
// …
import dev.vitruvian.design.VitruvianTheme
// …
@Composable
public fun RemoteApp(state: RemoteState) {
  // …
  val dark = Derive.isDarkTheme(state.themeMode, isSystemInDarkTheme())
  VitruvianTheme(dark = dark) {
    SystemBarsFollowTheme(dark = dark)
    val layout = rememberDeviceLayout()
    RemoteShell(state = state, layout = layout) { screen ->
      // …
      ScreenContent(state = state, screen = screen)
    }
    // …
  }
}
```

## Depend on it

- Library: `//packages/design-system-android:lib`
- Compose compiler plugin (required for `@Composable` callers): `//packages/design-system-android:compose_compiler`

## Constraints

- **Tokens are generated (`VitruvianTokens.kt`), never hand-edited** — regenerate from `packages/design-system/src/tokens.json` with `//packages/design-system-android/tools:gen_tokens` (`tokens_are_current` enforces parity).
- **No Material, no ripple, no rounded corners, no gradients, no elevation on board content** (only floating overlays carry elevation).
- **No app dependencies** — apps depend on the design system, never the reverse.
- **No Compose visual regression screenshots yet** — ships components and token/parity tests only.

The web package next door is React + CSS and does not run on Android. What
transfers is the language: `src/tokens.json` and [`ANDROID.md`](../design-system/ANDROID.md),
which is the authoritative mapping between the two, and this module is its realisation.

## Tokens are generated

`VitruvianTokens.kt` is emitted from `packages/design-system/src/tokens.json` and
must never be hand-edited. To change a value, change the JSON and regenerate:

```sh
bazel run //packages/design-system-android/tools:gen_tokens -- \
  --tokens "$PWD/packages/design-system/src/tokens.json" \
  --header "$PWD/packages/design-system-android/tools/kt_license_header.txt" \
  --out "$PWD/packages/design-system-android/src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt"
```

`bazel test //packages/design-system-android:tokens_are_current` is the CI gate
that keeps web and Android from drifting.

## What is here

| File                                                 | Contents                                                                                                                               |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `VitruvianTokens.kt`                                 | Generated. Colours (dark + parchment), the Fibonacci space scale, hit floors, the type ramp, motion durations and easings, elevations. |
| `Theme.kt`                                           | `VitruvianTheme`, the composition locals, the type ramp as `TextStyle`s, the flat press indication, reduce-motion.                     |
| `Text.kt`, `Plate.kt`, `Layout.kt`                   | The text primitive, the plate with its registration marks and grid field, and `AutoGrid`.                                              |
| `Button.kt`, `Tag.kt`, `Form.kt`, `ListItem.kt`      | Controls.                                                                                                                              |
| `DataDisplay.kt`                                     | `Status`, `Metric`, `Meter`, `SegBar`, `Spark`, `LogStream`, `VTable`.                                                                 |
| `Terminal.kt`, `Overlay.kt`, `States.kt`, `Glass.kt` | Terminal ground, dialog and sheet, banner and empty state, the backdrop blur.                                                          |
| `Nav.kt`, `Icons.kt`                                 | Top bar, host chip, tab bar, rail, sections; the Lucide glyphs.                                                                        |

## Fonts

`src/main/res/font/` carries JetBrains Mono (400/500/700) and IBM Plex Sans
(400/500/600) as TTF — the same faces the web package ships as WOFF2, which
Android cannot read. Both are SIL Open Font License 1.1; the licence texts are
in [`fonts/`](fonts/).

## Rules this module enforces

Taken straight from ANDROID.md, and the easiest ones to break:

- **No Material.** Not `MaterialTheme`, not its colour scheme, not its `Text`.
  Everything renders through `BasicText` and this module's own locals, because
  Material's roles do not match this language.
- **No ripple.** `LocalIndication` provides a flat `accentQuiet` tint.
- **No rounded corners, no gradients, no elevation on board content.** Every
  radius token is zero; shadows exist only on things that float.
- **Headings never above weight 500.** Mono 700 is terminal emphasis only.
- **Destructive actions are never swipes.** They are dialogs, with a typed
  confirmation when the host asks for one.
- **Reduce-motion is respected.** `motion()` collapses every duration to zero and
  entering elements land at full opacity.

## Not done yet

The design system's definition of done asks for a Compose preview per component
in both modes, screenshot-tested. Those previews are not written; the module
ships the components and the token gate, not the visual regression suite.

## Subdirectories & Boundaries
- [src](./src/README.md): Subsystem blueprint grouping child modules under packages/design-system-android/src.
- [tools](./tools/README.md): Subsystem blueprint grouping child modules under packages/design-system-android/tools.

