# @vitruviansoftware/design-system

Vitruvian — the Vitruvian Software design language. A CSS token layer, a React
component library built on top of it, and the Storybook that documents both.

Unlike the per-app packages under `tabula/`, `devx/` and friends, this one is
platform-level: every app is meant to depend on it, so it lives in `packages/`
and its targets are `//visibility:public` by default.

## Using it from an app

Add the workspace dependency and import the stylesheet once, at the app's entry
point:

```jsonc
// <app>/package.json
{ "dependencies": { "@vitruviansoftware/design-system": "workspace:*" } }
```

```ts
import "@vitruviansoftware/design-system/vitruvian.css";
import { Card, Button, Tag } from "@vitruviansoftware/design-system";
```

`vitruvian.css` pulls in Tailwind v4 plus `tokens.css`; import `tokens.css`
alone if the app only wants the custom properties and not the component layer.
Both stylesheets ship from `src/` — they are not compiled, and the package's
`exports` map points straight at them. Only the JS and `.d.ts` live in `dist/`.

Themes are driven by `data-theme` on `<html>` (`dark` is the default board,
`light` the parchment alternate).

## Layout

| Path                | What it is                                            |
| ------------------- | ----------------------------------------------------- |
| `src/tokens.css`    | The token layer: colour, type, space, motion          |
| `src/vitruvian.css` | The single stylesheet an app imports                  |
| `src/*.tsx`         | Components, one file per family (`Plate`, `Form`, …)  |
| `src/*.stories.tsx` | Stories — dev-only, never built into `dist/`          |
| `.storybook/`       | Storybook config (framework, addons, theme decorator) |

## Working on it

```sh
bazel run //packages/design-system:storybook   # devserver on :6006
bazel run //packages/design-system:doctor      # check the local toolchain
bazel build //packages/design-system:lib       # compile + typecheck the library
```

Or straight through pnpm from this directory:

```sh
pnpm storybook         # devserver
pnpm build-storybook   # static export to dist-storybook/
pnpm typecheck         # typecheck the library AND the stories
```

The static Storybook export is deliberately left to pnpm rather than modelled
in Bazel: Storybook's vite pipeline is a dev tool, and nothing in CI consumes
the export yet. `//packages/design-system:storybook` is a `js_binary` for the
same reason — it is run, never built into anything.

Two constraints are worth knowing before editing the build files:

- **`.storybook/main.ts` names its framework and addons by absolute path.** The
  repo sets `hoist=false` in `.npmrc` (rules_js needs pnpm's on-disk layout to
  match Bazel's), so the `storybook` CLI — which resolves from the root virtual
  store — cannot find this package's framework by bare name. Resolving through
  `require.resolve(...)` is Storybook's documented answer for strict layouts.
- **The BUILD file is hand-authored and `# gazelle:ignore`d,** like
  `//mcp-slack` and `//tabula/shared`: gazelle would rewrite it with a broken
  empty `src` glob, split out a `src/BUILD`, and try to generate targets for
  `.storybook/`.

Stories are excluded from the `ts_project` — they must not land in `dist/` or
in the published package, so they are typechecked by `tsconfig.stories.json`
(and by Storybook itself) rather than by the library target.
