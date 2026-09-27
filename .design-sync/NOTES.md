# design-sync notes — @vitruviansoftware/design-system

Source of truth for syncing `packages/design-system` to claude.ai/design.
Read this **and** `config.json` before doing anything; both carry fixes that
cost real debugging to find.

## Shape and layout

- `shape: "storybook"` — the repo's own Storybook is the fidelity oracle.
  `.storybook/` lives in the package (`packages/design-system/.storybook`),
  not at the repo root, so `storybookConfigDir` is pinned in config.
- Build the DS with `tsc -p tsconfig.json` from the package (`buildCmd`), and
  the reference with
  `npx storybook build -c .storybook -o <repo-root>/.design-sync/sb-reference`
  run **from `packages/design-system`**. Do not use the package's own
  `build-storybook` script — it writes to `dist-storybook/`, where nothing
  looks for it.
- pnpm workspace with `hoist=false` (`.npmrc`, required by rules_js). Deps
  were already installed on disk; `--node-modules` is the **package's own**
  `node_modules`, which has react/react-dom symlinked. `node_modules/<pkg>`
  does not exist in the DS's own source repo, hence `--entry dist/index.js`.

## [GENERAL] Fixes — symptom → cause → fix

- **Only 4 of 12 components synced; `[TITLE_UNMAPPED]` dropped 8 titles.**
  Story titles are prose ("Components/Status & metrics"), not export names.
  In this shape the roster is `storybook titles ∩ package exports`, so an
  unmapped title is a dropped component. → `cfg.titleMap` maps each title's
  last segment (whitespace-stripped) to the export that title is really
  about. `Foundations/Motion` is mapped to `null` (excluded) deliberately —
  see "Deliberate exclusions" below.

- **[GENERAL] Every preview rendered on a WHITE ground; secondary and ghost
  variants were invisible.** Vitruvian is dark-first: `:root` carries the
  board tokens and only `[data-theme="light"]` is the alternate. Storybook
  gets its ground from the `withTheme` decorator in `.storybook/preview.tsx`,
  but that decorator **cannot be bundled** — it side-effect-imports
  `../src/vitruvian.css`, whose `@import "tailwindcss"` esbuild cannot
  resolve (`! preview decorator bundle failed: Could not resolve
  "tailwindcss"`). The generated card page then hardcodes
  `body{margin:0;padding:24px;background:#fff}`, which is app-contract
  surface and must not be forked. → `.design-sync/preview-ground.mjs` exports
  `VitruvianGround`, merged into the bundle via `cfg.extraEntries` and wired
  as `cfg.provider`. It mirrors the decorator exactly: `data-theme`, the
  board background/text colour, and the 21px Fibonacci gutter.
  **Do not "fix" this per-component** — it is global by construction.

- **[GENERAL] `[FONT_MISSING]`: IBM Plex Sans / JetBrains Mono were named by
  the CSS but shipped by nobody — and the compare oracle could not see it.**
  `tokens.css` pulls both from the Google Fonts CDN with
  `@import url('https://fonts.googleapis.com/...')`. Vite + lightningcss
  **drop that remote `@import`** from the compiled stylesheet, so neither the
  shipped bundle CSS *nor the reference storybook itself* loads the real
  typefaces — both panels fell back to system fonts identically and graded
  "matching" while every claude.ai/design user would have got the wrong type.
  → Latin + latin-ext subsets vendored to `.design-sync/fonts/` (12 faces,
  336 KB, both families are OFL 1.1) with `.design-sync/fonts.css`, wired via
  `cfg.extraFonts`. The **same** faces are injected into the reference by
  `.design-sync/inject-reference-fonts.sh`, so the oracle verifies against
  the real type on both sides.
  **Correction (2026-09-26 re-sync): until then it did NOT.** The script wrote
  `url('./ds-fonts/x.woff2')` into a stylesheet that itself lives in
  `ds-fonts/`, so every face 404'd and the reference rendered on system
  fallback fonts (`document.fonts` showed every face `error`) — the exact
  blind spot this bullet describes. The 2026-09-05 grades were therefore made
  against a fallback-font oracle. Fixed (sibling `./x.woff2` paths + a guard
  that fails when a named face is missing), and all 10 carried components were
  re-captured against the corrected reference: every one still grades `match`.
  To confirm it works, check `document.fonts` in the reference, not the
  script's exit code.
  ⚠ **Re-run that script after every `storybook build`** — `sb-reference/` is
  regenerated and gitignored, so the injection does not survive a rebuild.

- **6 × `[GRID_OVERFLOW]`.** Batched into `cfg.overrides` in one cycle:
  `Card`, `Nav`, `Status`, `Plate`, `Shell` → `cardMode: "column"` (their
  stories are wider than a grid cell and were being cropped);
  `Dialog` → `cardMode: "single"` + `primaryStory: "DestructiveDialog"`
  (the dialog is `position: fixed` and painted over sibling cells).

- **[GENERAL] The scraped storybook CSS shipped only a THIRD of the design
  language.** A rendered claude.ai/design page gets **static CSS — there is no
  Tailwind compiler at render time** — so `[CSS_FROM_STORYBOOK]` shipped only
  the utilities the DS's own stories happened to use. Of the whole colour
  vocabulary `@theme inline` defines (`bg-ink`, `text-steel`,
  `border-hairline`, the steel-100..900 ramp), exactly **three** colour
  utilities survived: `text-paper-dim`, `text-steel-text`, `text-sanguine-text`.
  Documenting the design language would have told the design agent to write
  classes that resolve to nothing — silently unstyled output.
  → `.design-sync/tailwind-entry.css` re-compiles `vitruvian.css` with
  `@source inline(...)` safelists for the colour families, the Fibonacci
  spacing ramp on every axis, the grid/type utilities, fonts and shadows.
  `.design-sync/prepare.sh` (wired as `cfg.buildCmd`) emits it to
  `packages/design-system/dist/vitruvian.built.css`, and `cfg.cssEntry` points
  there. Shipped CSS went **260 → 783 class selectors, 122 → 241 tokens**, and
  the `[CSS_FROM_STORYBOOK]` fallback no longer fires.
  Verified non-regressive: Button, Plate, Status, Field and Terminal were
  re-captured against the reference after the swap and all still grade `match`.
  ⚠ `cfg.cssEntry` is bounded to the **package** (unlike `extraFonts` /
  `extraEntries`, which are workspace-bounded), which is why the built file
  lands in the package's gitignored `dist/` rather than under `.design-sync/`.

- **[GENERAL] The stylesheet carried ~270 utilities from OTHER monorepo apps
  (found 2026-09-26 via Claude Design's own stylesheet check).** `prepare.sh`
  ran the Tailwind CLI from the repo root, and Tailwind v4 auto-scans the
  working directory, so stock `bg-slate-800`/`bg-blue-600` (56 palette
  tokens), `rounded-xl`, `pr-9999` etc. shipped — contradicting
  conventions.md ("stock colours are not in this build") and bloating the
  design project's token/theme lists with Tailwind internals. → the CLI now
  runs from `packages/design-system` (what the package's own Vite build scans),
  neutral layout helpers (`hidden`, `text-center`, `md:grid-cols-*`...) are
  safelisted explicitly in `tailwind-entry.css`, and `prepare.sh` fails if a
  stock palette token appears. 813 → 597 classes, 64 → 39 `--tw-*` vars.
  Previews unchanged (Shell/Status/Nav re-captured to confirm).
  **Deliberately NOT done:** stripping all Tailwind utilities, which that
  check also suggested. Designs get static CSS with no Tailwind compiler, so
  the utilities ARE the styling vocabulary conventions.md teaches; removing
  them is the 2026-09-05 "three colour utilities survived" failure again.
  The remaining `--tw-*` variables and `.space-y-*` scopes are the cost of
  shipping utilities, not leakage.

## Deliberate exclusions

- `Foundations/Motion` → `titleMap: null`. It is a motion **showcase**, not a
  component: its five stories animate Button, Meter, Status, LogStream and
  Tabs. Every other title maps onto an export whose identity its stories
  genuinely demonstrate; Motion does not, and mapping it onto some export
  would have shipped a card whose name promised one component and whose
  preview showed five — teaching the design agent a wrong contract. The
  motion vocabulary belongs in `conventions.md` instead. Nothing is lost from
  the bundle: all 44 exports ship regardless.

## Grading notes carried forward

- `Dialog / Destructive Dialog` — the **reference** is the clipped side: the
  storybook canvas cuts the dialog off at the confirm input while the preview
  renders it whole. Graded `match`; rendering more than a gated reference is
  not a defect.
- `Shell / Authentication Portal` — preview canvas is wider than storybook's,
  so the centred card renders wider. Framing only.
- `Shell` (Patterns/Page Layouts, 8 stories since #2514) — **4 `match`, 4
  `close`**. The stories are `layout: "fullscreen"`, and since #2521 the
  storybook decorator drops its 21px gutter for fullscreen stories.
  `VitruvianGround` still pads every story (provider props are global; there is
  no per-component provider knob), and the card page adds a fixed 24px white
  body margin (app contract). So the preview canvas is ~90px narrower than the
  reference and the wider layouts reflow: KPI labels wrap (Operations Console,
  Agent Transcript), the JSON block/claims table overflow (O Auth Inspector),
  the title butts against its badges (Data Catalog). Content, components,
  colour and fonts are identical. Owning `previews/Shell.tsx` to cancel the
  gutter was rejected: it can't remove the 48px body margin, and it would need
  hand-updating on every Patterns story edit. The design agent never sees the
  gutter (conventions forbid `VitruvianGround` in designs). Separately worth
  knowing: those layouts get tight below ~850px — a DS finding, not a sync one.
- **Harness framing for fullscreen stories:** compare photographs the preview
  side at the 900x700 viewport only, while the storybook side is an element
  shot that grows (up to 1228px). Everything below 700px on the preview is
  unphotographed — grade those stories from a full-page shot of
  `components/patterns/Shell/Shell.html?story=<ExportName>` (export names,
  e.g. `OAuthInspector`, not the display label).
- `Shell` has 8 stories; compare's default cap is 6 — pass `--max-stories 8`
  or Cast Controller / Situational HUD go unverified.

## The target project is SHARED — merge semantics, not replace

`cfg.projectId` = `689e5ee5-09c2-4968-a008-b75b2e2c9ac7` ("Vitruvian"). That
project is **not** owned by this sync: it already held ~22 hand-authored cards
(`components/*.html`, `foundations/*.html`), four template sets, handoff docs
and its own `readme.md`/`demo.css`. The sync was merged in alongside them.

**Rules for every future sync of this project:**
- **Upload `deletes` MUST stay `[]`.** The generated components live at nested
  paths (`components/<group>/<Name>/...`) that do not collide with the flat
  `components/*.html` pages. A reconciliation delete over `components/**` —
  which the incremental path does automatically — would wipe those pages.
  This is why the run took the ATOMIC path; keep it that way.
  On an **anchored** re-sync, pass `.sync-diff.json`'s `upload.deletePaths`
  verbatim instead of `[]`: the diff only lists paths the previous
  `_ds_sync.json` recorded (this sync's own output), never the hand-authored
  pages. Never hand-derive a delete list or glob over `components/**`.
- **`styles.css` and `_ds_bundle.js` ARE overwritten**, and that is only safe
  because the built stylesheet is a verified SUPERSET of the project's
  original one: 137/137 classes and 84/84 tokens from its `_ds_manifest.json`
  were checked present before upload. **Re-run that check** if the DS's CSS
  ever loses rules. Overwriting the bundle is safe because the project's
  manifest carries `"components": []` — its cards are static HTML and nothing
  resolves against `window.Industry_indust`.
- `readme.md` (theirs) was edited once by hand on 2026-09-26, at James's
  request. It now says the tokens live in
  `packages/design-system/src/tokens.css` and that `styles.css` is generated
  by the sync. If the token source ever moves, that line goes stale. The
  sync never writes `readme.md`; update it via a separate one-file plan.
  Claude Design's own agent wrongly treats it as sync output.
- Root `README.md` (ours) and `readme.md` (theirs) are distinct paths — the
  store is case-sensitive; `get_file README.md` 404'd before the first upload.

## Components with no story are invisible to this sync

The oracle is the repo's own Storybook, so an export with no story gets no card
and cannot be verified. That currently includes `Menu`, `MenuItem`,
`MenuDivider`, `Skeleton`, `Spinner`, `Banner`, `Code`, `Kbd`, `Meter` and
`SegBar`. They still ship in `_ds_bundle.js` and are importable by the design
agent — they are just unverified and undocumented by a preview card.

This blind spot is not theoretical: `Menu`/`MenuItem`/`MenuDivider` rendered
`.dropdown-*` classes that did not exist in `tokens.css` at all, so all three
were completely unstyled — and because no story renders them, neither Storybook
nor this sync could see it. That gap was closed upstream in **#2193**
("style Menu, add mobile foundation and tokens.json"), which ported the menu
layer, the mobile shell and the `--hit-*` / `--glass-border` /
`--color-accent-danger` tokens back into `tokens.css`.

`tokens.css` describes itself as a mirror of the design project's canonical
`styles.css`. **Treat that mirror as drift-prone**: check it against the
project's `styles.css` on each sync (the manifest at `_ds_manifest.json` lists
every token the project expects). Adding stories for the unstoried components
is what would bring them under the oracle for good.

## Re-sync risks — what to watch

- **Fresh worktree / clone setup (learned 2026-09-26).** Use Node 22 (`.nvmrc`;
  Node 26 is the machine default). `pnpm i --frozen-lockfile --filter
  "@vitruviansoftware/design-system..."` creates the package's own
  `node_modules`. `prepare.sh` calls `.ds-sync/node_modules/.bin/tailwindcss`,
  so the converter-deps install must include `@tailwindcss/cli` and
  `tailwindcss` at the package's version (4.3.3). `--entry` is resolved from
  the repo root: `packages/design-system/dist/index.js`, not `dist/index.js`.
  Prior grades live in the main checkout's gitignored
  `.design-sync/.cache/compare/`; copying them into a worktree lets unchanged
  components carry forward instead of re-grading.
- **DesignSync needs a one-time `/design-login`** from an interactive terminal
  session; headless/desktop sessions can't run it, and without it the anchor
  (`_ds_sync.json`) can't be fetched, so no upload can be planned.

- **The full-vocabulary CSS depends on `prepare.sh` running.** If
  `dist/vitruvian.built.css` is absent the build prints
  `! cssEntry: ... not found — skipped`, falls back to `[CSS_FROM_STORYBOOK]`,
  and silently ships the impoverished 260-selector stylesheet again — every
  documented colour utility in `conventions.md` would stop resolving while
  every gate stays green. Treat a `[CSS_FROM_STORYBOOK]` line in the build log
  as a failure, not a note.
- **`conventions.md` enumerates real class and prop names.** Three props in its
  first draft were wrong (`Shell` takes the sidebar as a `side` prop not as
  children; `SideGroup` is a group *heading* with no `label` prop; `Crumbs`
  wraps anchors rather than taking an `items` array) and were caught only by
  checking each name against the shipped `.d.ts`. Re-validate the file against
  the fresh build on every re-sync — a conventions file that names things which
  do not exist is worse than no file at all.

- **The reference-font injection is the fragile one.** Rebuild the reference
  and `[FONT_MISSING]` silently comes back on the oracle side only, where no
  screenshot can show it. Always run `inject-reference-fonts.sh` after a
  storybook build, and treat a clean `package-validate.mjs` **without** a
  `fonts: N @font-face rule(s)` line in the build log as a red flag.
- **The vendored fonts are pinned copies** of Google Fonts v23 subsets. They
  do not track upstream, and the unicode-ranges cover latin + latin-ext only.
  Non-latin copy in a story will fall back.
- **`cfg.provider` replaced the decorators**, so `.storybook/preview.tsx` and
  `preview-ground.mjs` can now drift apart. If the decorator gains real
  context (a provider, a locale, a router), previews will NOT get it until
  `preview-ground.mjs` is updated to match.
- **`titleMap` is keyed on story titles.** Renaming a story title in a
  `*.stories.tsx` silently drops that component from the sync with a
  `[TITLE_UNMAPPED]` warning — check that warning on every re-sync.
- **Upstream repo bug worth fixing separately:** the design system references
  two typefaces it does not ship, and its own Storybook renders on fallback
  fonts today. The right long-term fix is to vendor the woff2 into
  `packages/design-system` and replace the CDN `@import` with local
  `@font-face`; this sync works around it without touching the package.
