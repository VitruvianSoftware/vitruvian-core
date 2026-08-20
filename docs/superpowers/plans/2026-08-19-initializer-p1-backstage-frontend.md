# Application Initializer P1 — Backstage Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stamp an application into `vitruvian-core` from the Backstage Create page, end
to end: form → the target repo's **embedded** engine → a reviewable PR. No concern flags
yet (spec §13 P1); the fully-automatic auto-merge deploy is P3.

**Architecture:** Two independent PRs. **PR-A (Task 1)** onboards `vitruvian-core` as a
valid ADR-015 target — its own engine snapshot at `tools/initializer/`, since it predates
the embedding and snapshots don't heal (ADR-026). **PR-B (Tasks 2–4)** is the Backstage
side: the `aspect` binary vendored into the image (ADR-004), a `vitruvian:app:render`
custom action that runs the **workspace's own** engine (never fetching
aspect-workflows-template — ADR-026), and a `stamp-application` template using plain RJSF
(the custom field extension is only needed when concerns arrive in P2) with existing
`fetch:plain` → our action → existing `publish:github:pull-request` steps.

**Tech Stack:** AXL engine (already shipped), TypeScript (Backstage backend module, new
backend system, `scaffolderActionsExtensionPoint` from `@backstage/plugin-scaffolder-node`
main entry — P0-era research, still installed at 4.0.2/0.13.6), ts-jest (NOT
backstage-cli's runner — `hoist=false` breaks it), Dockerfile, scaffolder template YAML.

## Global Constraints

- Repos: `vitruvian-core` (both PRs; merge queue; ALL gates green before presenting — license, conformance, tidy, prettier, jest, tsc-unchanged-in-kind, boot smoke).
- The engine snapshot is copied **verbatim** from `aspect-workflows-template@platform-v2.0` `template/tools/initializer/` — byte-identical; vitruvian-core owns it thereafter. Never edit engine files in vitruvian-core except where a Task explicitly says so.
- P1 calling convention (from `docs/application-initializer.md` in awt, authoritative): run `aspect render-app` **from the target repo root**; inside a repo with root `go.mod` (vitruvian-core has one) importpath auto-resolves; `--out` basename MUST equal `--name` (snake_case); `--out` is cleared if it exists; `--host-oci` auto-probes `bazel/oci/go_image.bzl` (absent in vitruvian-core → false → no go_image target: correct).
- Valid-target predicate (frontends must check before rendering): `tools/initializer/config.json` exists AND `MODULE.aspect` contains `use_task("tools/initializer/tasks.axl", ...)` for `render_app`.
- ADR-014: default app path `apps/<name>/`, user-overridable. vitruvian-core keeps its existing top-level apps; the first stamp introduces `apps/` (accepted in the ADR).
- ADR-018: the existing `backstage-github-token` (already in the pod env as `GITHUB_TOKEN`, repository Administration write) is the credential; no new secrets.
- Never `# gazelle:ignore`. The stamped app must be a gazelle fixed point under **vitruvian-core's** gazelle (proven in Task 1, not assumed from the starter proof).
- Commit style: conventional, why-first. Backstage work in a git worktree off origin/main; never the shared checkout.

---

### Task 1: Onboard vitruvian-core as a valid target (PR-A)

**Files:** Create `tools/initializer/**` (verbatim copy of awt `template/tools/initializer/**` — 9 files incl. `app/go/*.tmpl`); Modify `MODULE.aspect` (append the three `use_task("tools/initializer/tasks.axl", …)` lines: `render_app`, `check_metadata`, `check_renders`); Modify `.bazelignore` (append `tools/initializer` — defensive parity with starters; vitruvian-core's file currently holds only `.claude`); possibly Modify `tools/license/BUILD` `_IGNORE_GLOBS` (see step below).

- [ ] Copy the engine from `/tmp/awt/template/tools/initializer/` (branch platform-v2.0, post-#46); verify byte-identity with `diff -r`. Append the `use_task` lines; verify all three tasks register: `aspect check-metadata` → OK, `aspect check-renders` → 44/44 OK **from the vitruvian-core worktree root**.
- [ ] License gate: run `bazel run //tools/license:check` (CI's real gate, NOT verify.sh — it is looser). If it flags engine files, add `tools/initializer/**` to `_IGNORE_GLOBS` with a comment (the snapshot is upstream-owned, mirroring awt's own defensive glob). If it passes untouched, say so in the report — do not add the glob speculatively without evidence either way.
- [ ] Formatter drift: run the repo's tidy/format over the tree; if vitruvian-core's prettier rewrites `tools/initializer/config.json` (its config may differ from awt's), STOP and report — do NOT commit a drifted engine file; the fix decision (exclude from format vs accept drift) needs the controller.
- [ ] **The stamp acceptance, under vitruvian-core's own toolchain:** `aspect render-app --language=go --name=smoke_probe --out=./apps/smoke_probe` → 5 files, importpath derived from the REAL root `go.mod` module path (paste it); `bazel run //:gazelle` → **no diff under apps/smoke_probe AND nowhere else** (vitruvian-core's own gazelle config is the risk the starter proof cannot cover — if gazelle rewrites the BUILD file, record the diff verbatim, take gazelle's output as truth, and STOP for controller decision since the fix belongs in awt's template, not the snapshot); `bazel test //apps/smoke_probe:all` green; then `git clean` the probe away — it must NOT be in the commit.
- [ ] Full local gate sweep (license, conformance, tidy-check clean tree, prettier) then commit, push branch `feat/initializer-target-onboarding`, open PR-A titled `feat(initializer): onboard vitruvian-core as a stamping target`. Body: the ADR-026 snapshot trade (this copy does not heal; refresh = re-copy), the predicate now satisfied, the smoke evidence incl. the gazelle fixed-point proof, and what was/wasn't needed for license/format gates.

### Task 2: Vendor the aspect CLI into the backstage image (PR-B, first commit)

**Files:** Modify `backstage/Dockerfile` (runtime stage).

- [ ] Pin the same aspect CLI version the engine was proven with (`aspect --version` in /tmp/awt prints it; record it). Add a per-`TARGETARCH` download+install in the **runtime** stage (multi-arch build exists: amd64+arm64), `chmod +x`, and a `RUN aspect --version` build-time assertion so a bad URL fails the build not the pod. `git` is already installed in the build stage — verify it is present in the **runtime** stage (the action's workspace comes from fetch:plain, so git is likely NOT needed at runtime; if absent, note it and do not add it).
- [ ] Build the amd64 image locally (`docker build --target runtime`), run `docker run --rm <img> aspect --version`, paste output. The boot smoke (`tools/ci/backstage-boot-smoke.sh`) must still pass on the built image — run it.
- [ ] Commit (no push yet; PR-B opens in Task 4).

### Task 3: The `vitruvian:app:render` custom action (PR-B)

**Files:** Create `backstage/packages/backend/src/scaffolder/appRender.ts` + `appRender.test.ts` + `module.ts` (backend module `scaffolder-backend-module-app-render`); Modify `backstage/packages/backend/src/index.ts` (one `backend.add`).

**Interfaces:** action id `vitruvian:app:render`; input `{ name: string; language: string; targetPath?: string }` (default targetPath `apps/<name>`); it operates on `ctx.workspacePath` (the already-fetched target repo), output `{ appPath: string; catalogInfoPath: string }`.

- [ ] Action behavior, in order: (1) **validate the target predicate** on the workspace (config.json + MODULE.aspect use_task lines) and fail with an actionable message naming the onboarding PR pattern if absent; (2) validate `name` is snake_case and `basename(targetPath) === name` (the engine enforces it too — fail EARLY with the friendlier message); (3) run the workspace's own engine via `executeShellCommand` (`aspect render-app --language … --name … --out <workspace>/<targetPath>`), cwd = workspace root, streaming to `ctx.logger` (>60s-silent rule); (4) **append the new app to the root `catalog-info.yaml`'s `vitruvian-core-apps` Location targets** (one line, `./<targetPath>/catalog-info.yaml`) so the PR is catalog-complete — ADR-019's disclose-and-include pattern, and the action's log must state it edited that file; (5) support dry-run (`ctx.isDryRun`: render, log the file list, skip nothing else — rendering is side-effect-free within the workspace).
- [ ] The aspect binary path: `aspect` from PATH (Task 2 puts it there). Guard: if the binary is missing, fail with a message naming the image version requirement — do NOT silently skip.
- [ ] Tests (ts-jest, colocated): predicate-missing fails with the message; bad name/path-mismatch fails early; happy path against a **fixture workspace** = a minimal fake (config.json + MODULE.aspect + go.mod + catalog-info.yaml with the Location) where `executeShellCommand` is mocked to emit the 5 files — assert the Location append is exact and idempotent (running twice must not duplicate the line). PLUS one integration-style test gated on `process.env.ASPECT_E2E` that uses the REAL aspect binary against a REAL rendered starter (document the command to run it locally; CI skips it).
- [ ] The tsc error budget stays unchanged in kind (the `backend.add(import(...))` TS2345 class gains exactly one instance); jest suite green; prettier clean.
- [ ] Commit.

### Task 4: The `stamp-application` template + registration + PR-B ships

**Files:** Create `backstage/templates/stamp-application/template.yaml`; Modify root `catalog-info.yaml` (add the template to a Location target); Modify `gitops/argocd/platform/backstage/values.yaml` + `backstage/app-config.yaml` ONLY IF a config change is genuinely required (none is expected — document that none was needed).

- [ ] `template.yaml` (`scaffolder.backstage.io/v1beta3`): parameters page 1 = name (snake_case pattern + maxLength 30), description, owner (`OwnerPicker`), language (enum: go — single option today, the enum exists so P2 adds languages without re-shaping the form), targetPath (string, default `apps/${{ parameters.name }}`, advanced section). Steps: `fetch:plain` (url `https://github.com/VitruvianSoftware/vitruvian-core`) → `vitruvian:app:render` → `publish:github:pull-request` (repoUrl `github.com?owner=VitruvianSoftware&repo=vitruvian-core`, branch `stamp/${{ parameters.name }}`, title `feat(${{ parameters.name }}): stamp application via initializer`, description carries the disclose-and-include note about the catalog-info edit; **draft PR** so nothing lands unreviewed in P1). Output links: the created PR URL.
- [ ] Register: add `./backstage/templates/stamp-application/template.yaml` to the root `catalog-info.yaml` Location targets (same mechanism as everything else in that file).
- [ ] Verify the template renders in the scaffolder's schema: `curl` is unavailable against prod from CI — instead assert YAML validity + required fields via a unit check in the backend test dir (parse the file, assert apiVersion/steps/action ids exist and every step's action is in the known-registered set {fetch:plain, vitruvian:app:render, publish:github:pull-request}). This is the drift guard between template and registered actions.
- [ ] Full gate sweep; commit; push branch `feat/backstage-stamp-application`; open PR-B titled `feat(backstage): stamp applications from the Create page (initializer P1)`. Body: flow diagram (form → fetch → embedded engine → draft PR), ADR-026 note (the action runs the TARGET's engine; aspect-workflows-template is never fetched), image change (vendored binary version), test evidence, and the explicit statement that PR-A must merge first (the action fails with the predicate message until vitruvian-core carries its engine).

### Task 5: End-to-end verification + docs (post-merge, controller-driven)

Not a subagent dispatch — the controller (with James) drives after both PRs merge and the image deploys: create a throwaway app via the real Create page, verify the draft PR (stamped files + catalog-info Location line + gazelle gate green on the PR), then close the PR unmerged and delete the branch. Update the spec's §13 rollout table (P1 delivered) and note any discovered ADR material. This step doubles as the deferred "scaffolder end-to-end test" from the pre-initializer backlog.

## Self-Review

- Spec coverage: §7 Frontend A minus concerns (P2) and minus auto-merge (P3) — deliberate; ADR-014/015/018/026 all honored; the onboarding task closes the valid-target gap this plan itself discovered.
- Risks stated: vitruvian-core's own gazelle/prettier may disagree with the starter-proven shapes (Task 1 STOPs for controller decisions rather than improvising in the snapshot); fetch:plain workspace size (vitruvian-core tarball is large — if the scaffolder times out, the fallback is a shallow-clone variant inside the action, a scoped change); publish:github:pull-request has not been exercised against this repo (first real use — draft PR limits blast radius).
- No placeholders; interfaces named; each task independently testable.
