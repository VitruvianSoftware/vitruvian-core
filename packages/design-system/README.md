# @vitruviansoftware/design-system

Vitruvian — the Vitruvian Software design language. A CSS token layer with
self-hosted variable fonts, a React component library built on top of it,
codex-inspired technical vector illustrations, and the Storybook that documents
all of them.

Unlike the per-app packages under `apps/suites/tabula/`, `apps/cli/devx/` and friends, this one is
platform-level: every app is meant to depend on it, so it lives in `packages/`
and its default visibility is `//:__subpackages__` — the whole monorepo, rather
than a single app. Only `:pkg` is `//visibility:public`, because rules_js roots
the virtual store at `//:node_modules` and the generated link targets reach it
from outside this package.

## Using it from an app

Add the workspace dependency and import the stylesheet once, at the app's entry
point:

```jsonc
// <app>/package.json
{ "dependencies": { "@vitruviansoftware/design-system": "workspace:*" } }
```

```ts
import "@vitruviansoftware/design-system/vitruvian.css";
import {
  Card,
  Button,
  Tag,
  VIcon,
  VitruvianIcons,
  PlateFigure,
  VitruvianTokens,
} from "@vitruviansoftware/design-system";
```

`vitruvian.css` pulls in Tailwind v4 plus `tokens.css` (which declares local
`@font-face` rules for the vendored `IBM Plex Sans` and `JetBrains Mono`
`.woff2` fonts in `src/fonts/`, with zero external CDN requests); import
`tokens.css` alone if the app only wants the custom properties and not the
component layer. Both stylesheets and `src/fonts/**` ship from `src/` — they
are not compiled, and the package's `exports` map points straight at them. Only
the JS and `.d.ts` live in `dist/`.

Themes are driven by `data-theme` on `<html>` (`dark` is the default board,
`light` the parchment alternate).

## Component families

| File                    | Exports                                                                                             |
| ----------------------- | --------------------------------------------------------------------------------------------------- |
| `src/tokens.ts`         | `VitruvianTokens` / `tokens` — typed programmatic access to colors, fonts, spacing, and motion      |
| `src/Plate.tsx`         | `Plate`, `Rule`, `VMark`, `RegistrationMarks`                                                       |
| `src/Card.tsx`          | `Card` (`plate` / `fill` / `glass` surfaces, `live` indicator, `marks`, `dashed`)                   |
| `src/Button.tsx`        | `Button` (`primary` / `secondary` / `ghost` / `danger`, `sm` / `md` / `touch`)                      |
| `src/Tag.tsx`           | `Tag`, `Label`, `Kbd`                                                                               |
| `src/Form.tsx`          | `Field`, `Input`, `Textarea`, `Select`, `Checkbox`, `Radio`, `Switch`, `Segmented`, `Slider`, `CopyButton` |
| `src/DataDisplay.tsx`   | `Status`, `Metric`, `Meter`, `SegBar`, `Spark`, `BarChart`, `LogStream`, `Table`                    |
| `src/Terminal.tsx`      | `Terminal`, `Code`, `BlinkingCursor`                                                                |
| `src/Layout.tsx`        | `ListItem`, `AutoGrid`, `KeyValue`, `Accordion`                                                     |
| `src/Nav.tsx`           | `Crumbs`, `Tabs`, `TopBar`, `HostChip`, `TabBar`, `Rail`, `Section`, `SectionHeader`, `MobileShell`, `Pagination`, `Avatar` |
| `src/Overlay.tsx`       | `Dialog`, `BottomSheet`, `Menu`, `MenuItem`, `MenuDivider`, `Tooltip`, `Popover`, `Toast`, `Drawer`, `CommandPalette` |
| `src/States.tsx`        | `Banner`, `EmptyState`, `Skeleton`, `Spinner`                                                       |
| `src/Icons.tsx`         | `VIcon`, `VitruvianIcons` (28 technical 1.5px stroke icons on a 24×24 grid)                         |
| `src/Illustrations.tsx` | `VitruvianPlate` (8 codex plates), `PlateFigure`, `VitruvianStockImages`, `DuotoneImage`            |

## Layout

| Path                | What it is                                              |
| ------------------- | ------------------------------------------------------- |
| `src/tokens.css`    | The token layer: colour, type, space, motion, `@font-face` |
| `src/tokens.json`   | The same tokens in W3C Design Tokens format, for native |
| `src/tokens.ts`     | Typed TypeScript token constants (`VitruvianTokens`)    |
| `src/fonts/`        | Vendored `IBM Plex Sans` & `JetBrains Mono` `.woff2`    |
| `src/vitruvian.css` | The single stylesheet an app imports                    |
| `src/*.tsx`         | Components, one file per family (`Plate`, `Form`, …)    |
| `src/*.stories.tsx` | Stories — dev-only, never built into `dist/`            |
| `.storybook/`       | Storybook config (framework, addons, theme decorator)   |
| `ANDROID.md`        | Mapping the tokens and components onto Jetpack Compose  |

## Working on it

```sh
bazel run //packages/design-system:storybook          # devserver on :6006
bazel run //packages/design-system:doctor             # check the local toolchain
bazel build //packages/design-system:lib              # compile + typecheck the library
bazel build //packages/design-system:stories_typecheck # typecheck library + stories
bazel test //packages/design-system:tokens_sync_test  # verify tokens.css / tokens.json / tokens.ts / fonts parity
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
  `//apps/mcp/slack` and `//apps/suites/tabula/shared`: gazelle would rewrite it with a broken
  empty `src` glob, split out a `src/BUILD`, and try to generate targets for
  `.storybook/`.

Stories are excluded from `:lib` — they must not land in `dist/` or in the
published package — and are typechecked in CI by `:stories_typecheck`
(`tsconfig.stories.json`).
