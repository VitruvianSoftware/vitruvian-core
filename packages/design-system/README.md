# Vitruvian design system

## What it gives you

The Vitruvian Software design language, in two halves that share one set of tokens:

- [`web/`](./web/README.md): CSS tokens, self-hosted fonts, a Tailwind v4 theme and React components, documented in Storybook.
- [`android/`](./android/README.md): the same tokens generated for Kotlin, plus `VitruvianTheme` and Jetpack Compose primitives.

`web/src/tokens.json` is the single source of truth. The Android tokens are generated from it.

## When to use it

- Any web or Android UI in the monorepo that should look like Vitruvian.

## When not to use it

- Apps that must use standard Material Design 3 widgets; the Android half deliberately avoids them.
- Standalone-exported apps whose mirror build cannot resolve monorepo packages (for example `oauth-user-inspector`, which vendors its copy).

## Example

See the example in each half: [web](./web/README.md#example) and [android](./android/README.md#example).

## Depend on it

- Web: `//packages/design-system/web:pkg`, or `"@vitruviansoftware/design-system": "workspace:*"` in `package.json`.
- Android: `//packages/design-system/android:lib`.

## Constraints

- Change tokens in `web/src/tokens.json` only, then regenerate the Android tokens; never edit the generated Kotlin by hand.
