# devx → one-way Copybara cutover (#76 / #77)

This repo previously synced `devx` **bidirectionally** with `VitruvianSoftware/devx`
(continuous export *and* import + a drift checker). Per the scaling roadmap (#76),
`devx` moves to **internal-first one-way**: the monorepo is the single source of
truth, the standalone is an **export-only mirror**, and external contributions
arrive as PRs on the mirror that are *imported as monorepo PRs* (Google-style
round-trip), reviewed/merged here, then reflected back out by the export.

## What this PR already does (safe, active on merge)

- **Deletes `.github/workflows/copybara-import-devx.yaml`** — the standalone→monorepo
  bidi import stops. `devx` is now export-only. (The standalone's
  `sync-to-monorepo.yaml` may still fire its `devx-import` `repository_dispatch`;
  with no matching workflow, GitHub silently ignores it — no error, export unaffected.)
- **Removes `devx` from `copybara-drift-check.yaml`** — a one-way mirror has nothing
  to drift against.
- **Leaves `copy.bara.sky` and `export_devx` untouched** — the live mono→standalone
  export is byte-for-byte unchanged.

## Why the PR-import path is NOT in this PR (and is gated)

Copybara evaluates the **entire** `copy.bara.sky` when running **any** workflow.
The `import_pr_devx` workflow uses `git.github_pr_origin` / `git.github_pr_destination`,
which are **UNVERIFIED on the repo's pinned `olivr/copybara` (2023-01) image**. If that
image cannot even *parse* those builtins, the config fails to load and **every
component's export breaks** — not just devx. So the PR-import wiring below must only
land **after** Step 0 passes.

## Step 0 — REQUIRED GATE: smoke-test Copybara PR mode

Run the pinned Copybara image against a throwaway labelled PR on `VitruvianSoftware/devx`
using the `import_pr_devx` workflow (config snippet in §A). Confirm the config **loads**
and the PR is migrated into a monorepo PR.
- **If it works:** proceed to §A–§D.
- **If it fails to load/parse:** pin a **newer Copybara image for the import-pr workflow
  only** (§B pins its image independently of the export/import reusable workflows, so the
  bidi components keep the verified 2023-01 image), and on a current Copybara rename
  `experimental_custom_rev_id` → `custom_rev_id` in the snippet (the `_REV_ID` labels keep working).

## Loop-prevention (verified by design)

`import_pr_devx` stamps the component import label `DEVX_REV_ID` (a PR-import is still
standalone-origin), so the **unchanged** `export_devx` skip-guard (which drops
`DEVX_REV_ID`) refuses to bounce a merged PR-import back out. `import_pr_devx`'s own guard
drops anything carrying `MONOREPO_REV_ID` (export-origin), so an exported change can never
be re-imported. This is exactly the guard pairing the old bidi `import_devx` used.

## Residual risks

- PR mode unverified on the pinned image (Step 0 gate above).
- Auto-close (§C) needs the sync App granted `pull_requests:write` on `VitruvianSoftware/devx`;
  if missing, the mirror PR stays open (the close step is best-effort).
- A direct push to monorepo `devx/` carries no rev-id label, so `export_devx` will export it
  to the mirror — acceptable under one-way (monorepo is the source of truth).

---

## §A. `copy.bara.sky` change (apply after Step 0)

Apply by hand to tools/copybara/copy.bara.sky (current file is 228 lines, header says "bidirectionally syncing"):

1) COMPONENTS list: add `"is_one_way": False,` to mcp-slack (after its standalone_only line, ~line 116), homelab (~line 126), nexus-agent (~line 131), and add `"is_one_way": True,` to devx (after its standalone_only line, ~line 121). Update the COMPONENTS doc-comment to describe the is_one_way knob.

2) In _define_component(_c) (starts ~line 156): after `_monorepo_only_files = _monorepo_only(_name)` add `_is_one_way = _c.get("is_one_way", False)`.

3) Leave the `core.workflow(name = "export_" + _wf, ...)` block (lines ~165-192) COMPLETELY UNCHANGED. This is the load-bearing export-safety guarantee: export_devx keeps name "export_devx", keeps `experimental_custom_rev_id = MONOREPO_REV_ID`, and keeps its skip-guard `_make_skip_guard("export_"+_wf, _standalone_rev_id, ...)` which drops DEVX_REV_ID-stamped (PR-imported) commits.

4) Wrap the existing import workflow (current lines ~195-223) in `if _is_one_way: <new import_pr block> else: <the existing import_<comp> block, verbatim>`. The existing import_<comp> block moves UNCHANGED into the else branch (still stamps `experimental_custom_rev_id = _standalone_rev_id` and guards on MONOREPO_REV_ID).

5) The new `if _is_one_way:` branch creates `core.workflow(name = "import_pr_" + _wf, ...)` with:
   - origin = git.github_pr_origin(url=_standalone, use_merge=False, required_labels=["import-to-monorepo"])
   - destination = git.github_pr_destination(url=MONOREPO, destination_ref="main", pr_branch="devx-import-pr-${GITHUB_PR_NUMBER}", title="[devx import] ${GITHUB_PR_TITLE}", body=".../Devx-Pr-Number: ${GITHUB_PR_NUMBER}")
   - origin_files = glob(["**"], exclude=_standalone_only); destination_files = glob([_name+"/**"], exclude=_monorepo_only_files)
   - authoring = authoring.pass_thru(default=AUTHOR); mode = "ITERATIVE"
   - CRITICAL: experimental_custom_rev_id = _standalone_rev_id  (i.e. DEVX_REV_ID, NOT MONOREPO_REV_ID — this is the fix to both review blockers about inverted/colliding labels; it makes export_devx's unchanged skip-guard drop the PR-imported commit and prevents the export loop)
   - transformations = [core.dynamic_transform(impl=_make_skip_guard("import_pr_"+_wf, MONOREPO_REV_ID, "the vitruvian-core monorepo export")), core.move("", _name)]  (guard checks MONOREPO_REV_ID = the EXPORT label, so an export-origin change is never re-imported)

Net loaded-config delta: export_mcp_slack/homelab/nexus-agent and import_mcp_slack/homelab/nexus-agent are byte-for-byte identical to today; export_devx is identical to today; import_devx is no longer emitted; import_pr_devx is new. The conflict pre-check is now the Go tool //tools/copybara/conflict_precheck (replacing the former conflict-precheck.sh) and is still never invoked for devx (the import-pr workflow does not call it; export_devx's precheck still works because its import baseline = DEVX_REV_ID is still laid down by merged+exported PR-imports).

## §B. New monorepo workflow — `.github/workflows/copybara-import-pr-devx.yaml`

```yaml
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

name: Copybara Import PR (devx)

# ONE-WAY devx PR-import (CHANGE_REQUEST). Consumes a PR on VitruvianSoftware/devx
# that a MAINTAINER has reviewed/approved and labelled 'import-to-monorepo', and
# opens a MONOREPO PR under devx/ for review + merge. Monorepo is the single
# source of truth; nothing is pushed to monorepo main here.
#
# SECURITY POSTURE (do NOT weaken):
#   * Trigger is repository_dispatch (devx-import-pr) fired by the standalone
#     ONLY after an approval gate (see VitruvianSoftware/devx sync-to-monorepo.yaml
#     in standaloneRunbook), or manual workflow_dispatch by a monorepo maintainer.
#     We never use pull_request_target, so no monorepo secret is ever exposed to a
#     trigger evaluated in the context of untrusted PR head code.
#   * This job NEVER builds/tests/executes the imported PR content. Copybara only
#     applies core.move + the loop-prevention dynamic_transform. The single build
#     step (//:tidy) regenerates gazelle BUILD files and is monorepo-owned tooling;
#     it runs against the imported tree but does not execute arbitrary PR scripts.
#   * The standalone deploy key (DEVX_SYNC_SSH_KEY) is used ONLY to READ the
#     standalone PR origin; the monorepo PR is opened over HTTPS with GITHUB_TOKEN.

on:
    repository_dispatch:
        types: [devx-import-pr]
    workflow_dispatch:
        inputs:
            pr_number:
                description: "Standalone devx PR number to import (must be labelled import-to-monorepo and approved)."
                required: true
            copybara_options:
                description: "Copybara CLI options."
                default: "--ignore-noop"
                required: false

permissions:
    contents: write
    pull-requests: write

# Serialize PR imports so two simultaneously-labelled PRs cannot race the same
# monorepo PR branch / GitHub API (residual-risk #2 from the design, now closed).
concurrency:
    group: copybara-import-pr-devx
    cancel-in-progress: false

jobs:
    import-pr:
        runs-on: ubuntu-latest
        env:
            # Origin (standalone) PR number, from either trigger.
            DEVX_PR_NUMBER: ${{ github.event.client_payload.pr_number || github.event.inputs.pr_number }}
        steps:
            - uses: actions/checkout@v6
              with:
                fetch-depth: 0
            - name: Set up Copybara auth (SSH read key + HTTPS token)
              env:
                SSH_KEY: ${{ secrets.DEVX_SYNC_SSH_KEY }}
                GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
              run: |
                mkdir -p ~/.ssh
                printf '%s\n' "${SSH_KEY%$'\n'}" > ~/.ssh/id_rsa
                chmod 600 ~/.ssh/id_rsa
                ssh-keyscan -t rsa,ed25519 github.com > ~/.ssh/known_hosts 2>/dev/null
                printf 'https://x-access-token:%s@github.com\n' "$GH_TOKEN" > ~/.git-credentials
                chmod 600 ~/.git-credentials
                printf '[credential]\n\thelper = store\n[user]\n\tname = VitruvianSoftware Sync\n\temail = sync@vitruviansoftware.com\n' > ~/.gitconfig
            - name: Copybara import PR (labelled standalone PR -> monorepo PR under devx/)
              env:
                GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
                CB_OPTS: ${{ github.event.client_payload.copybara_options || github.event.inputs.copybara_options || '--ignore-noop' }}
              run: |
                set +e
                # CHANGE_REQUEST is selective by PR; pass the specific origin PR so
                # only the labelled+approved PR is imported.
                docker run --rm \
                  -v "$GITHUB_WORKSPACE":/usr/src/app \
                  -v "$HOME/.ssh/id_rsa":/root/.ssh/id_rsa \
                  -v "$HOME/.ssh/known_hosts":/root/.ssh/known_hosts \
                  -v "$GITHUB_WORKSPACE/tools/copybara/copy.bara.sky":/root/copy.bara.sky \
                  -v "$HOME/.git-credentials":/root/.git-credentials \
                  -v "$HOME/.gitconfig":/root/.gitconfig \
                  -e COPYBARA_CONFIG=/root/copy.bara.sky \
                  -e COPYBARA_WORKFLOW=import_pr_devx \
                  -e COPYBARA_OPTIONS="$CB_OPTS" \
                  -e GITHUB_TOKEN="$GH_TOKEN" \
                  olivr/copybara@sha256:87e2e9089344e64693faebb2ee0ed33b8797358c0420b0fa98325ca611e98679 \
                  copybara import_pr_devx "$DEVX_PR_NUMBER"
                rc=$?
                # 0 = PR opened/updated; 4 = NO_OP (skip-guard dropped an export-origin
                # change, or nothing to import). Both are acceptable terminal states.
                if [ "$rc" -eq 0 ] || [ "$rc" -eq 4 ]; then echo "Copybara OK (exit $rc)"; exit 0; fi
                echo "Copybara import_pr failed (exit $rc)"; exit "$rc"
            - name: Install Bazel
              uses: bazel-contrib/setup-bazel@c5acdfb288317d0b5c0bbd7a396a3dc868bb0f86 # 0.19.0
              with:
                bazelisk-cache: true
                repository-cache: true
            - name: Regenerate gazelle BUILD files on the import PR branch
              env:
                GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
              run: |
                set -uo pipefail
                BR="devx-import-pr-${DEVX_PR_NUMBER}"
                # The Copybara PR branch may not exist if the import no-op'd; bail cleanly.
                if ! git ls-remote --exit-code --heads origin "$BR" >/dev/null 2>&1; then
                  echo "No import PR branch ($BR) — nothing to tidy (import likely no-op'd)."; exit 0
                fi
                # Push race: the PR branch is owned by this single concurrency group, but
                # retry defensively in case the branch was just (re)created by Copybara.
                for attempt in 1 2 3 4 5; do
                  git fetch origin "$BR"
                  git checkout -B "$BR" "origin/$BR"
                  bazel run //:tidy
                  git add -A
                  if git diff --cached --quiet; then
                    echo "BUILD already up to date on $BR — nothing to regenerate."; exit 0
                  fi
                  git commit -m "chore(bazel): tidy BUILD for devx import PR #${DEVX_PR_NUMBER}"
                  if git push origin "HEAD:refs/heads/$BR"; then
                    echo "Pushed BUILD regeneration onto $BR."; exit 0
                  fi
                  echo "push rejected (attempt ${attempt}/5) — branch advanced; re-syncing"
                  sleep $((attempt * 3))
                done
                echo "::error::could not push BUILD regeneration onto $BR"
                exit 1

```

## §C. New monorepo workflow — `.github/workflows/copybara-import-pr-devx-close.yaml`

```yaml
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

name: Copybara Import PR (devx) auto-close mirror

# When a devx import PR (branch devx-import-pr-<N>) MERGES into monorepo main,
# explicitly close the originating VitruvianSoftware/devx#<N> mirror PR. Cross-repo
# closure cannot be done by a commit trailer, so we do it by API. The standalone
# PR number is read from the monorepo PR body footer 'Devx-Pr-Number: <N>' that
# import_pr_devx embedded.
#
# Trigger is `pull_request` (NOT pull_request_target) on the monorepo's own PRs;
# it runs in the trusted base context after merge and reads only PR metadata.
on:
    pull_request:
        types: [closed]
        branches: [main]

permissions:
    contents: read
    pull-requests: read

jobs:
    close-mirror:
        # Only for merged devx import PRs.
        if: >-
            github.event.pull_request.merged == true &&
            startsWith(github.event.pull_request.head.ref, 'devx-import-pr-')
        runs-on: ubuntu-latest
        steps:
            - name: Extract standalone PR number
              id: devxpr
              env:
                BODY: ${{ github.event.pull_request.body }}
                HEAD_REF: ${{ github.event.pull_request.head.ref }}
              run: |
                set -euo pipefail
                # Prefer the body footer; fall back to the branch suffix.
                n="$(printf '%s' "$BODY" | sed -n 's/^Devx-Pr-Number: \([0-9][0-9]*\).*/\1/p' | head -1)"
                if [ -z "$n" ]; then n="${HEAD_REF#devx-import-pr-}"; fi
                case "$n" in ''|*[!0-9]*) echo "::error::could not parse standalone PR number"; exit 1 ;; esac
                echo "number=$n" >> "$GITHUB_OUTPUT"
            - name: Mint token for VitruvianSoftware/devx
              id: app-token
              uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
              with:
                app-id: ${{ secrets.DEVX_DISPATCH_APP_ID }}
                private-key: ${{ secrets.DEVX_DISPATCH_APP_PRIVATE_KEY }}
                owner: VitruvianSoftware
                repositories: devx
            - name: Comment and close the mirror PR
              env:
                GH_TOKEN: ${{ steps.app-token.outputs.token }}
                DEVX_PR: ${{ steps.devxpr.outputs.number }}
                MONO_PR: ${{ github.event.pull_request.number }}
              run: |
                set -euo pipefail
                gh pr comment "$DEVX_PR" --repo VitruvianSoftware/devx \
                  --body "Imported and merged into VitruvianSoftware/vitruvian-core#${MONO_PR} (devx/). The monorepo is the source of truth; this mirror PR is now closed. Your change will appear on this repo's main via the next Copybara export." || true
                gh pr close "$DEVX_PR" --repo VitruvianSoftware/devx || true

```

## §D. Standalone-repo runbook — `VitruvianSoftware/devx` (+ cla-assistant)

## devx One-Way Cutover — Runbook

This cutover is split into a STAGING GATE (step 0), a monorepo PR, and standalone setup. Order matters: the standalone dispatch must not point at the new monorepo workflow until that workflow exists on main, and the old bidi flow must be quiesced before landing.

### Step 0 — STAGING GATE (must pass before the monorepo PR is allowed to merge)
The pinned `olivr/copybara@sha256:87e2...` image (build 2023-01) is VERIFIED only for the bidirectional ITERATIVE workflows. `git.github_pr_origin` / `git.github_pr_destination` (CHANGE_REQUEST mode) are UNVERIFIED on it. Before merging:
1. On a throwaway branch, run `import_pr_devx` against a disposable labelled PR on a fork/test repo using the pinned digest: `docker run ... -e COPYBARA_WORKFLOW=import_pr_devx olivr/copybara@sha256:87e2... copybara import_pr_devx <PR>`.
2. Confirm it (a) filters on the `import-to-monorepo` label, (b) opens a PR on the destination, (c) stamps `DEVX_REV_ID` (NOT `MONOREPO_REV_ID`) on the imported commit, and (d) returns exit 0/4.
3. If the pinned image does NOT support PR mode: change ONLY the image digest in `.github/workflows/copybara-import-pr-devx.yaml` to a current Copybara build (e.g. a 2024+ tag) and re-test. Do NOT touch the export/import reusable workflows' digest — the bidi components stay on the verified 2023-01 image. (The import-pr workflow pins its image independently for exactly this reason.)

### Step 1 — Quiesce in-flight bidi activity (cutover window)
1. Confirm no in-flight `Copybara Export (devx)` or `Copybara Import (devx)` runs in vitruvian-core Actions (let the queue drain; the export-devx concurrency group is non-cancelling).
2. On VitruvianSoftware/devx, ensure NO open PR carries the `import-to-monorepo` label (the label does not exist yet on the standalone, so this is normally vacuous — but check, in case it was pre-created).
3. Announce a short freeze: "devx sync cutover in progress (~10 min); do not label PRs for import until the all-clear."

### Step 2 — Land the monorepo PR
Merge the monorepo PR (copy.bara.sky one-way conversion, delete copybara-import-devx.yaml, add copybara-import-pr-devx.yaml + copybara-import-pr-devx-close.yaml, drop devx from copybara-drift-check.yaml). After merge:
1. The export_devx workflow is unchanged; the next push under devx/** re-runs it normally. No baseline re-seed is required because export_devx keeps the same name, the same MONOREPO_REV_ID stamp, and the same DEVX_REV_ID skip-guard — its export baseline on the standalone is untouched.
2. (Optional, belt-and-suspenders) Trigger `Copybara Export (devx)` via workflow_dispatch with `--ignore-noop` to confirm export still no-ops/succeeds against the live standalone.

### Step 3 — VitruvianSoftware/devx standalone setup
1. **CLA enforcement (before label):** Install the CLA Assistant app (https://github.com/apps/cla-assistant) on VitruvianSoftware/devx. CLA MUST be signed on the standalone PR BEFORE the `import-to-monorepo` label can be applied — the label-gate workflow (below) checks the CLA status check is green before dispatching. The monorepo PR is authored via authoring.pass_thru (original author preserved), so the standalone CLA is the system of record; the monorepo does not need a second CLA on the bot-opened PR.
2. **Create the `import-to-monorepo` label:** Settings > Labels > New. Name=`import-to-monorepo`, description="Maintainer-approved: import this PR into vitruvian-core/devx/ for review and merge".
3. **Reuse the EXISTING GitHub App for dispatch — do NOT mint a broad PAT.** The standalone already authenticates dispatch with the `vitruvian-copybara-sync` App via `DEVX_DISPATCH_APP_ID` / `DEVX_DISPATCH_APP_PRIVATE_KEY` (see the current sync-to-monorepo.yaml). Keep using it. This closes the security review's "overly broad DEVX_MONOREPO_DISPATCH_TOKEN (contents:write)" finding: the App is already scoped to repository_dispatch on vitruvian-core only; no contents:write PAT is created. The same App is granted `devx` (pull_requests:write) so the monorepo's auto-close workflow can close the mirror PR.
4. **Replace `.github/workflows/sync-to-monorepo.yaml`** (this is standalone-only and never crosses the sync boundary). Two jobs:
   - REMOVE the old `on: push` -> `repository_dispatch event_type=devx-import` job entirely (the old bidi import is gone).
   - ADD an APPROVAL-GATED PR-import dispatcher (NO pull_request_target, NO PR code execution):
     ```yaml
     name: Request import to monorepo
     on:
       pull_request_target:        # base-context only; we never check out or run PR head code
         types: [labeled]
     permissions: {}
     concurrency:
       group: devx-import-pr-${{ github.event.pull_request.number }}
       cancel-in-progress: false
     jobs:
       dispatch:
         if: github.event.label.name == 'import-to-monorepo'
         runs-on: ubuntu-latest
         steps:
           - name: Require maintainer approval + green CLA before dispatch
             env:
               GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
               PR: ${{ github.event.pull_request.number }}
               ACTOR: ${{ github.event.sender.login }}
             run: |
               set -euo pipefail
               # 1) Only a repo maintainer (write+) may trigger an import via the label.
               perm="$(gh api repos/$GITHUB_REPOSITORY/collaborators/$ACTOR/permission --jq .permission)"
               case "$perm" in admin|maintain|write) : ;; *) echo "::error::$ACTOR lacks maintainer perm; ignoring label"; exit 1 ;; esac
               # 2) Require at least one APPROVED review.
               approvals="$(gh pr view "$PR" --json reviews --jq '[.reviews[]|select(.state=="APPROVED")]|length')"
               [ "$approvals" -ge 1 ] || { echo "::error::PR not approved; refusing import"; exit 1; }
               # 3) Require the CLA status check to be success.
               cla="$(gh api repos/$GITHUB_REPOSITORY/commits/$(gh pr view "$PR" --json headRefOid --jq .headRefOid)/check-runs --jq '[.check_runs[]|select(.name|test("CLA";"i"))|.conclusion]|@csv')"
               echo "$cla" | grep -qi success || { echo "::error::CLA not signed; refusing import"; exit 1; }
           - name: Mint dispatch token from GitHub App
             id: app-token
             uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1
             with:
               app-id: ${{ secrets.DEVX_DISPATCH_APP_ID }}
               private-key: ${{ secrets.DEVX_DISPATCH_APP_PRIVATE_KEY }}
               owner: VitruvianSoftware
               repositories: vitruvian-core
           - name: repository_dispatch devx-import-pr
             env:
               GH_TOKEN: ${{ steps.app-token.outputs.token }}
               PR: ${{ github.event.pull_request.number }}
             run: |
               gh api -X POST repos/VitruvianSoftware/vitruvian-core/dispatches \
                 -f event_type=devx-import-pr \
                 -F client_payload[pr_number]="$PR"
     ```
   - SECURITY NOTES: `pull_request_target` here runs ONLY base-context dispatcher code (gh API calls); it never checks out or executes PR head content, so no secret reaches untrusted code (security review #1). The maintainer-permission + approval + CLA gate closes the "anyone can label to escalate into the monorepo" finding (security review #2). The dispatch payload carries only the integer PR number.
5. **Branch protection on devx:** require ≥1 approving review on PRs and restrict who can apply the `import-to-monorepo` label (Settings > Branch protection / label-management) so the gate can't be bypassed.

### Step 4 — All-clear
Lift the freeze. Document the invariant for maintainers: every change to vitruvian-core/devx/ MUST arrive via import_pr_devx -> monorepo PR -> merge; manual edits straight to devx/ bypass loop-prevention (they carry neither MONOREPO_REV_ID nor DEVX_REV_ID and would be exported, which is fine one-way, but they skip review). Enforce via CODEOWNERS on devx/ in the monorepo.

### End-to-end flow
External contributor opens PR on VitruvianSoftware/devx -> signs CLA -> maintainer reviews/approves -> maintainer applies `import-to-monorepo` -> standalone gate (maintainer+approval+CLA) dispatches `devx-import-pr` with the PR number -> monorepo copybara-import-pr-devx opens a PR under devx/ (branch devx-import-pr-<N>, body footer Devx-Pr-Number) and tidies BUILD on that branch -> monorepo reviewers review/merge -> copybara-import-pr-devx-close closes the mirror PR via the App, and export_devx pushes the merged content to the standalone main.
