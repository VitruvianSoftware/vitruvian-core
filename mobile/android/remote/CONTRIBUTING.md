# Contributing to Vitruvian Remote

`mobile/android/remote` lives in the
[VitruvianSoftware/vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core)
monorepo and — unlike `mcp-slack`, `nexus-agent` and `devx` — is **not mirrored**
to a standalone repository. There is no Copybara export for it, so this is the
only place it is edited. That omission is deliberate, not drift: an unreleased
client with no distribution channel has nothing to mirror yet.

Work lands through the monorepo's standard flow — read the root
[Contributing SOP](../CONTRIBUTING.md) for the commit format, the merge queue and
the required checks. What follows is only what is specific to this app.

## Before you start

You need the Android SDK (API 35 platform plus build-tools) and `ANDROID_HOME`
pointing at it. Then:

```sh
bazel run //mobile/android/remote:doctor
bazel build //mobile/android/remote:app
```

## House rules for this app

**Never hardcode a design value.** No `Color(...)`, no bare `.dp` for spacing, no
font size that is not from the ramp. If a value is missing, it belongs in
`packages/design-system/src/tokens.json` and reaches Kotlin through the
generator — see [the design system's README](../packages/design-system-android/README.md).
The Fibonacci scale (`Space.s1`…`s8`) is the only source of padding and gaps.

**Never edit `VitruvianTokens.kt`.** It is generated, and
`//packages/design-system-android:tokens_are_current` will fail the build if you
do.

**Add components to the design system, not here.** If two screens want the same
shape, it is a design-system component. This app should contain screens, state
and wiring — nothing that draws a new kind of thing.

**Check all three postures.** A change is not done until it reads correctly
folded, unfolded and in tabletop. `AutoGrid` does most of the work; the trap is
assuming a width. Test on a foldable emulator with the fold controls, not just a
phone profile.

**Respect the hard rules.** No Material ripple, no rounded corners, no gradients,
no springs, no swipe-to-destroy, headings never above weight 500. These are the
language, not preferences.

## Where things are

`state/` holds one observable holder for the whole app rather than a ViewModel
per screen — the screens are views onto a single host and the dock shows two of
them at once, so splitting the state would mean plumbing most of it back
together. `MockHost.kt` is the stand-in for the Mac agent; when the real
transport arrives, it replaces that object and nothing in `screens/` should need
to change.
