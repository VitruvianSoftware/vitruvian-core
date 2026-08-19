# Application Initializer P0.5 — Embed the Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every rendered starter repo carries its own working initializer (ADR-026): a
developer in a generated monorepo runs `aspect render-app` with no dependency on
`aspect-workflows-template` existing, being reachable, or being version-compatible.

**Architecture:** All work in `aspect-workflows-template`, branch base `platform-v2.0`
(P0 merged as #44). The engine moves INSIDE `template/` at
`template/tools/initializer/` so repo stamping delivers it; the repo-root task files
become thin wrappers over the same embedded source (one engine, two mount points). The
`app-contract` CI gate flips to exercising the embedded path — render a starter, run
*its* engine — which is the product now.

**Tech Stack:** AXL/Starlark (aspect CLI), minijinja, JSON contract, GitHub Actions.

## Global Constraints

- Repo `VitruvianSoftware/aspect-workflows-template`, base **`platform-v2.0`**. Branch: `feat/app-embed-engine`.
- Starlark: no recursion, no `while`; same AXL primitives as P0 (see `render.axl`/`app.axl`/`dev.axl` — invent nothing).
- Repo stamping for NON-initializer content must stay byte-identical; the ONLY diff in a rendered starter vs. base is the new `tools/initializer/**`, `MODULE.aspect`, and (backstage presets) their `skeleton/` copies + `template.yaml` `copyWithoutTemplating` addition.
- `aspect check-metadata`, `aspect check-renders` (44), `aspect render-app` must keep working FROM THE AWT ROOT after every task (the development flow), and additionally FROM A RENDERED STARTER after Task 2 (the product flow).
- Never `# gazelle:ignore` in app templates. Never break the P0 destination-property failures (module-root refusal, no-go.mod fail, basename==name).
- Target layout inside a rendered starter (and, source-side, under `template/`):
  ```
  tools/initializer/
    engine/render.axl      # THE renderer lib (moved, single source)
    engine/app.axl         # THE app lib (moved, single source)
    config.json            # the app contract (MOVED out of template-config.json's "app" key)
    tasks.axl              # render_app/check_metadata/check_renders task defs (shared shape)
    app/go/...             # the app templates (moved from template/app/go)
  MODULE.aspect            # use_task lines for the embedded tasks
  ```
  AWT's root `dev.axl` keeps `render_preset` (repo stamping, loads the engine from the
  new path) and re-exports the app tasks by loading `template/tools/initializer/tasks.axl`
  with a base-dir knob (see Task 1) — root `app.axl` and root `render.axl` are DELETED
  (moved, not copied; a copy is drift).
- Commit style: conventional, why-first bodies.

---

### Task 1: Move the engine into template/ and re-point both mount points

**Files:** Create `template/tools/initializer/{engine/render.axl,engine/app.axl,config.json,tasks.axl}` (moves of root `render.axl`, `app.axl`, the `app` key of `template-config.json`, and the app-task defs from `dev.axl`); move `template/app/go/**` → `template/tools/initializer/app/go/**`; Modify root `dev.axl`, `MODULE.aspect`, `template-config.json`.

**Interfaces produced:** `tasks.axl` must define tasks whose implementations resolve paths from a single `_base(ctx)` helper: in AWT the engine root is `<repo>/template/tools/initializer`, in a rendered starter it is `<repo>/tools/initializer`. Determine which by probing which exists (`ctx.std.fs.exists`); fail loudly if both or neither. The contract's `languages.go.template_dir` becomes `"app/go"` **relative to the engine root**.

Key mechanics (all verified in P0 — do not rediscover):
- `render()` globs are relative to its `template_dir` argument, so moving the app templates only changes the path handed in, not the contract's own `rules/no_render/executable`.
- The Task-2 (P0) exclusion rule `{"flag":"app_template","globs":["app/**"]}` is now WRONG twice over: the path moved, and the files must now SHIP. Replace it with `no_render` entries (verbatim copy, jinja preserved): `tools/initializer/app/**`, `tools/initializer/engine/*.axl`, `tools/initializer/tasks.axl`, `tools/initializer/config.json`. NO exclusion rule — every starter gets the engine.
- `template-config.json` loses its `app` key entirely (single source is `config.json`); AWT-side `check-metadata`/`render-app` load the contract from the engine root. `validate_app_config` keeps its signature but reads the new shape (the file IS the app section).

**Steps:**
- [ ] Move files with `git mv` (history follows); adjust `load()` paths (`tasks.axl` loads `./engine/render.axl`, `./engine/app.axl`); root `dev.axl` loads `./template/tools/initializer/engine/render.axl` for `render_preset` and `./template/tools/initializer/tasks.axl` for the app tasks; root `MODULE.aspect` use_task lines unchanged in name.
- [ ] Run from AWT root: `aspect check-metadata` (OK), `aspect check-renders` (44/44 OK), `aspect render-app --language=go --name=payments --out=/tmp/t1 ...` (5 files, substituted). Paste outputs.
- [ ] Render the `go` preset; assert the rendered tree now CONTAINS `tools/initializer/**` with jinja intact (`grep -l 'project_snake' <out>/tools/initializer/app/go/main.go` — braces preserved) and engine axl byte-identical to source; assert everything OUTSIDE `tools/initializer/` and `MODULE.aspect` is byte-identical to a base-commit render (the P0 stash/worktree diff method, ignoring the two new paths).
- [ ] Falsify the no_render coverage: temporarily remove the `tools/initializer/app/**` no_render entry, re-render, show `main.go` arrives with `{{ project_snake }}` EXPANDED (i.e. broken for later app-stamping); revert. This proves the entry is load-bearing.
- [ ] Commit.

### Task 2: The embedded task surface + the Nunjucks hazard

**Files:** Create `template/MODULE.aspect`; Modify `template/template.yaml`; possibly `dev.axl`'s `_populate_skeleton`.

- [ ] `template/MODULE.aspect` (rendered verbatim — add to `no_render`): `use_task("tools/initializer/tasks.axl", "render_app")` + the two check tasks. NOTE: verify the aspect CLI accepts a subdirectory path in `use_task` — AWT's own root uses `"dev.axl"`. If it does not, `tasks.axl` moves to repo-root-relative `initializer.axl` inside the starter (adjust layout; document).
- [ ] **The Nunjucks hazard:** backstage-preset starters copy the rendered tree into `skeleton/`, and Backstage's `fetch:template` Nunjucks-renders `skeleton/**` at repo-create time — it would eat the app templates' `{{ project_snake }}`. Add `copyWithoutTemplating: ["tools/initializer/**"]` (verify exact key name against the installed scaffolder's fetch:template schema — `copyWithoutTemplating` vs `copyWithoutRender`, cite which) to `template/template.yaml`'s fetch step.
- [ ] Verify: render `backstage-go`; inspect `skeleton/tools/initializer/app/go/main.go` — jinja intact; `template.yaml` carries the new key; non-backstage `go` render has NO skeleton and needs nothing.
- [ ] E2E the embedded engine for real: render the `go` preset to `$T/host`, `cd $T/host`, run `aspect render-app --language=go --name=payments --out=$T/host/app/payments` **from inside the rendered repo**, assert 5 substituted files + `aspect check-metadata`/`check-renders` work there too. This is ADR-026's acceptance criterion.
- [ ] Falsify: in the rendered host, delete `tools/initializer/config.json`, re-run render-app, assert it fails loudly (not silently); restore.
- [ ] Commit.

### Task 3: Flip app-contract CI to the embedded path

**Files:** Modify `.github/workflows/ci.yaml` (app-contract job); `docs/application-initializer.md`.

- [ ] check-metadata/check-renders steps stay AWT-root (they gate the source). The fixed-point step changes: after rendering each host, run `aspect render-app` **from within the host** (its embedded engine) instead of from AWT root — same stampings (payments, payments_api, services/billing on `go`; billing on `copybara-go`), same lockfile-materialization baseline, same staged `git diff --cached --exit-code` verdict, same refusal-guard and explicit-flags steps but invoked embedded.
- [ ] Keep one AWT-root `render-app` smoke (one render) so the development mount point stays gated too.
- [ ] Local run of the full step script for both hosts (the Task-5/P0 method, CI=1 for lockfile parity); actionlint clean.
- [ ] Rewrite `docs/application-initializer.md` for the embedded model: "your repo carries its own initializer" as the primary usage, AWT-root as the development flow, the P1 calling convention updated (frontends clone the TARGET and run its engine), ADR-026 trade documented (snapshots don't heal; our starters refresh on deliver).
- [ ] Commit, push branch, open PR to `platform-v2.0` titled `feat(app): embed the initializer in every starter (P0.5, ADR-026)`; body: what moved, the Nunjucks fix, the CI flip, verification evidence, and that starters change by exactly `tools/initializer/** + MODULE.aspect (+ skeleton copies)`.

## Self-Review
- Coverage: layout move (T1), starter delivery + skeleton safety + embedded E2E (T2), CI proving the product + docs (T3). ADR-026 consequences all land; ADR-013 unification is NOT in scope (follow-up).
- Known risks stated: `use_task` subdirectory support (T2 has the fallback); `copyWithoutTemplating` exact key name (T2 verifies against the installed scaffolder); deliver.yaml needs no change (it renders `template/`, which now includes the engine) — T3's PR body must confirm by reading deliver.yaml once.
