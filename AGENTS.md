# Agent guide — vitruvian-core

> **This file is the single, vendor-neutral agent guide for this repo.** It follows the
> [AGENTS.md](https://agents.md) convention, which Antigravity/Gemini, Copilot, Cursor,
> opencode and others read. Claude Code reads `CLAUDE.md` instead, so the root `CLAUDE.md`
> is a single `@AGENTS.md` import and nothing else (#3418). There is deliberately **no other
> per-tool file** (`.cursorrules`, `copilot-instructions.md`) — one guide, so it cannot drift
> per tool. Never add guidance to `CLAUDE.md`; it goes here.
>
> Keep it that way when editing:
> - **Write for any agent.** Don't assume a specific tool's commands, file layout or
>   capabilities. Prefer the repo's own `bazel run …` entrypoints, which work everywhere.
> - **No tool-specific instructions in this file.** If setup only applies to one vendor,
>   it goes in `docs/` and is linked from here (as the homelab access section does) —
>   everything in this guide should be actionable by every agent that reads it.
> - **Nested `AGENTS.md` files scope to their subtree** (`apps/cli/devx/`, `apps/suites/tabula/`,
>   `apps/web/oauth-user-inspector/`, `apps/web/vitruviansoftware-dev/`, `apps/mobile/android-remote/`, `apps/desktop/`, `apps/desktop/home-speaker/`,
>   `apps/desktop/vitruvian/`, `apps/embedded/esp32-s3/`) — put per-component detail there, not here. Note that an
>   `AGENTS.md` only applies to the directory it sits in and below, so one in a
>   non-source directory silently never applies.

## Orient first: principles, SDLC, docs hub

Before shaping any non-trivial change, read the
[Guiding Principles](docs/engineering/application-development-principles.md) — they
are the authoritative standard and exist precisely to steer agents toward the right
shape: everything-as-code (never click-ops or imperative one-offs), the pipeline as
the only trigger, secrets never in git, bazel-wrapped tooling, expand/contract
sequencing, and "every fix ships with the check that would catch it again". The
[SDLC walkthrough](docs/concepts/sdlc.md) explains how a change reaches production;
the [docs hub](docs/README.md) routes everything else, and the
[Bazel targets catalog](docs/reference/bazel-targets.md) lists the sanctioned tool
surface. When an app's own docs conflict with `CONTRIBUTING.md`, CONTRIBUTING wins.

## GitHub identity: act as yourself, not as James

Every agent has its own GitHub App. **Set up your identity at the start of any
session that will touch GitHub**, so commits, PRs and reviews are attributed to
you rather than to the repository owner:

```sh
eval "$(bazel run //tools/agent-app -- env <your-agent-name>)"
```

That sets `GH_TOKEN` **and** the git author/committer identity. Both are needed
and they are separate mechanisms: `GH_TOKEN` changes who **pushes**, the
`GIT_AUTHOR_*` variables change who **authored** the commit. With only the token,
a commit pushed by your bot still carries the machine owner's name in the history
— the PR looks right and the commit log is wrong.

`gh` prefers `GH_TOKEN` over the stored keyring credential, and git already
delegates to `gh` (`credential.https://github.com.helper = !gh auth
git-credential`), so the token covers API calls and pushes alike.

Names and ids are in [`tools/agent-app/agents.tsv`](tools/agent-app/agents.tsv).
If the key is missing, run `bazel run //tools/sync-env-secrets:agent-keys-pull`
(needs the Bitwarden vault unlocked).

**Use your own name.** The keys sit in one directory readable by every agent, so
nothing stops you minting someone else's token — which makes attribution a
convention we keep, not a control that holds. Minting as another agent puts their
name on your work.

**Tokens expire after one hour.** Re-run the command rather than caching it.

Without this you are `ipv1337`, and you cannot approve another agent's PR:
GitHub blocks self-approval, and every PR is self-authored from its point of view.
See [docs/guides/agent-github-identities.md](docs/guides/agent-github-identities.md).

## GCP identity is pinned per-infrastructure

This repo manages cloud infrastructure under multiple Google accounts (personal,
nocentre, Vitruvian). Today every first-party app here deploys under the personal
account `james.nguyen@gmail.com`. **Never assume the ambient `gcloud` account is correct.**

The mapping of infrastructure → GCP account is in
[`infrastructure/gcp-identities.tsv`](infrastructure/gcp-identities.tsv).

- **Pulumi:** the Bazel wrappers
  (`bazel run //infrastructure/pulumi/<project>:{preview,up,refresh,destroy,config,setup}`)
  read that file and automatically inject an access token for the declared
  account — you do not touch `gcloud config`. If the declared account isn't
  logged in, the wrapper fails fast and tells you which `gcloud auth login` to run.
- **Ad-hoc GCP commands** (`gcloud`, `gsutil`, …): look up the account (and project) in the map, then:

  ```bash
  export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token --account=<account>)"
  # if the map declares a project (3rd column), also:
  export GOOGLE_CLOUD_PROJECT=<gcp_project>
  ```

- **GCP Project IDs:** Never infer or hardcode GCP Project IDs. They are generated with random 4-character suffixes (e.g., `prj-d-bu1-oss-floating-648a`). Always look up the exact project ID from `<app>/infra/app/Pulumi.<env>.yaml` (field `gcp:project`).

> Adding a new Pulumi project that uses GCP? Add a row to the map **first** — the
> wrapper silently skips injection (and falls back to the ambient account) for
> projects not listed.

## Applying infrastructure: where `pulumi up` may run

Infrastructure changes reach live systems through their pipeline, not from
your checkout. Previews are always fine; applies are not.

- **Cloud stacks** (GCP, GitHub, Cloudflare, anything with a CI deploy job):
  **never run `:up` locally.** Merge the change; CI applies it through its
  GitHub Environment.
- **dev-local** (the homelab stack, `infrastructure/pulumi/platform/dev-local`)
  has no CI deploy job, so it is applied by hand, and only like this:
  1. from the **main checkout**, on `main`, with a **clean tree**, after the
     change has merged;
  2. through the wrapper (`bazel run //infrastructure/pulumi/platform/dev-local:preview`,
     then `:up`), never raw `pulumi`;
  3. only after reading the preview. If it shows **any delete or replace**
     you did not intend, stop.
- **Never apply from a git worktree.** The stack config (`Pulumi.local.yaml`)
  is gitignored, so worktrees don't have it, and every component then reads as
  disabled. On 2026-09-23 a `pulumi up` from a worktree with a dirty tree
  uninstalled Argo CD this way, taking the `argocd` namespace and all
  Applications with it. The program now refuses to run without that config
  (`stackguard.go`, #2448), but the rule stands on its own: a guard is the last
  line, not the process.

## Build, test, run
- Dev environment: `bazel run //tools:bazel_env` (with [direnv](https://direnv.net); `direnv allow`).
- Build / test everything: `bazel build //...` and `bazel test //...`.
- Lint / format: `aspect lint //...` and `format`.
- Watch loop: `ibazel run //<target>`.
- Regenerate `BUILD` files after adding/moving code: `bazel run //:gazelle`.
- macOS app (nexus-agent): `bazel build --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgent`.

## Repo and dev operations go through Bazel targets
**Use these targets for every git write.** Raw git writes (`git commit`, `git push`,
`git rebase`, `git worktree add/remove`, `git stash`, …) are blocked by agent-guard
in agent sessions (below); reads (`git status`, `log`, `diff`, `show`, `fetch`) stay allowed.
Each target does the write plus the checks that belong with it, and every refusal
prints the command to use instead. If no target fits, stop and say which one is missing.

| To | Run |
|---|---|
| Start work on a branch | `bazel run //tools/worktree -- <branch>`, then work inside it |
| Look at a commit without a branch | `bazel run //tools/worktree -- --detach <ref> <name>` |
| Keep a worktree safe from pruners | `bazel run //tools/worktree -- --lock [reason]` (and `--unlock`) |
| Commit | `bazel run //tools/git:commit -- --agent <you> -m "fix(scope): …" <paths>` (or `--all`; `--fixup <sha>`) |
| Push | `bazel run //tools/git:push` (`--agent <you>`; `--force-with-lease` after a rebase) |
| Catch up with main | `bazel run //tools/git:sync` (`--autosquash [--keep-base]`; `--merge` for a pushed branch; `--abort`) |
| Finish a merge | `bazel run //tools/git:commit -- <fixed files>` |
| Scan for secrets | `bazel run //tools/secret-scan` (`--staged`, `--range a..b`) |
| Lint workflows | `bazel run //tools/ci:actionlint` |
| Remove a worktree | `bazel run //tools/worktree -- --remove <branch\|name> [--delete-branch]` |
| Delete a branch on GitHub | `bazel run //tools/agent-app -- branch-delete --agent <you> <branch>...` (only branches already on `main`) |
| Open, comment on or close an issue | `bazel run //tools/agent-app -- issue-create --agent <you> --title "…" --body-file <f>` (`issue-comment <n>`, `issue-close <n>`) |

Pass `--agent <you>` to commit and push: it makes your agent's bot the author,
committer and pusher (via `//tools/agent-app`), so nothing lands as James.
Commit refuses on `main` and in the main checkout, and secret-scans what it records.
Push never writes `main` and never plain-forces. Sync never stashes: the stash is
shared by every worktree. See [`tools/git/README.md`](tools/git/README.md).
Pull requests are not here: open one with `bazel run //tools/agent-app -- pr-create`
(below). The other PR commands (edit, comment, enqueue) are coming separately as
more `//tools/agent-app` `pr-*` commands; until then, use `gh pr …` as below.

The same goes for toolchains and `gh` writes: `bazel test //...` instead of `go test`,
`swift test`, `pnpm test` or `cargo test`; `bazel run //tools/format` and `aspect lint`
instead of running linters; `bazel run //tools/agent-app -- pr-create` instead of
`gh pr create`. Read-only commands (`git status/log/diff`, `gh pr view`, `kubectl get`)
stay fine. Where this guide still names a raw command, use the target if it exists; if it
does not, stop and tell James which one is missing.

In Claude Code and Antigravity (agy) this is enforced by **agent-guard**, a hook that refuses the raw command and
names the target ([tools/agent-guard](tools/agent-guard/README.md)). It reads command text,
so it stops habits, not determined workarounds: do not route around it. It runs from the repo, so
every checkout and worktree is guarded with nothing to install: `.claude/settings.json` and
`.agents/hooks.json` run `tools/agent-guard/hook.sh`, which runs the guard **as it is on
`origin/main`**. You may change `agent_guard.py` and `policy.json` like any code (your edit takes
effect once merged); you may not change those two hook files or `hook.sh`, which take effect
before review: that is James's call. **A pull request that changes agent-guard's rules cannot
merge until James approves it on GitHub:** anything under `tools/agent-guard/`, the hook wiring
(`.claude/settings.json`, `.claude/settings.local.json`, `.claude/*.sh`, `.agents/hooks.json`), or
the ruleset that enforces this (`infrastructure/pulumi/platform/repo-config/guard_review.go`,
its `main.go`, `Pulumi.yaml`, `Pulumi.dev.yaml`). Any later push makes his approval stale. Open the
PR, say why in its description, and wait; never approve it yourself as `ipv1337`. Other PRs are
unaffected. See "Who may do what" in the agent-guard README. `bazel run //tools/agent-guard:install -- --check` shows
whether the wiring works. Sessions started outside the repo are covered by a one-time per-user
backstop that runs the main checkout's `hook.sh` (`bazel run //tools/agent-guard:install`, James's step).

## Finishing work: PR, checks, land, clean up
Run every change to completion — an unmerged branch is unfinished work, not a deliverable.
1. **Open a PR.** When the work is done, push and open one unless an open, related PR already
   covers it. Open it with `bazel run //tools/agent-app -- pr-create [gh pr create args]`, not
   bare `gh pr create`: that opens it as the agent app with the `agent-fast-lane` label, so the
   PR skips the heavy tests (#3418). The merge queue still tests everything before it lands. Never merge locally. PR bodies are self-contained: what
   changed, why, how it was verified.
   **Act as your own app.** Every `//tools/agent-app` PR command acts as **wren** unless you pass
   `--agent <your agent name>` as its first argument (`pr-create --agent atlas --title ...`), so
   pass it, or your work shows up as wren's. The run commands (`run-rerun`, `run-cancel`,
   `workflow-run`) are the exception: they work **only as wren**, the one app allowed to start
   or stop workflow runs, so leave `--agent` off for those.
2. **Drive the checks green & monitor landing autonomously.** Run `bazel run //tools/watch-pr -- <pr#>`
   (or delegate to subagent `scout`). This hermetic tool monitors PR CI checks to completion,
   extracts failure logs if a check goes red, tracks merge queue progression, confirms squash landing,
   and verifies post-merge push workflows on `main` (`//tools/pipeline-status`) with a hard timeout
   to prevent spinning or infinite loops.
   Edit, comment on, review, mark ready or close it the same way: `pr-edit`, `pr-comment`, `pr-review`,
   `pr-ready`, `pr-close` (`bazel run //tools/agent-app -- <command> [--agent <you>] <pr#> ...`). To re-run or cancel a CI
   run use `run-rerun <run-id> [--failed]` / `run-cancel <run-id>`; to start a workflow,
   `workflow-run <file.yaml>`, which only starts the ones in
   `tools/agent-app/workflow-allowlist.txt`, from `main`. No raw `gh pr`, `gh run` or
   `gh workflow` writes.
3. **Land it.** Once approved, arm auto-merge with `bazel run //tools/agent-app -- pr-enqueue <pr#>`
   (not `gh pr merge --auto`). It arms auto-merge as the agent app, then checks on GitHub that
   the PR has auto-merge armed or is in the merge queue, and says which. Let `watch-pr` monitor
   until it lands. To hold a PR, `pr-hold <pr#> [--reason "..."]`: it adds `do-not-automerge`,
   turns auto-merge off and takes the PR out of the queue, since the label alone stops nothing.
   `pr-enqueue` refuses a held PR, including one a release gate holds (`dev-deploy-red`,
   `beta-not-built`): that gate re-arms it itself once its condition clears. `pr-unhold <pr#>` removes the label only; run `pr-enqueue`
   again when it should land.
   **Never merge past the merge queue.** No `gh pr merge --admin`, no direct merge through the
   API, no push to `main`. If the queue removes your PR, a check failed on the queue's trial
   commit (your change plus the latest `main`); that run is under Actions, not on the PR's Checks
   tab. Fix what failed and queue it again. Skipping the queue is the human maintainer's
   break-glass, not yours: on 2026-10-08 a PR the queue had just rejected was merged directly
   and turned `main` red. Claude Code sessions are stopped by `.claude/block-queue-bypass.sh`;
   every other agent is bound by this rule. A direct merge also raises an alert.
4. **Clean up & verify post-merge health.** After `watch-pr` confirms the squash commit has landed
   and the post-merge pipeline is green, remove the worktree and branch (`bazel run //tools/worktree -- --remove <branch> --delete-branch`).
   **Verify it landed first**, and note that `git merge-base --is-ancestor <branch-sha>
   origin/main` is always false here — `main` is squash-only, so your branch's SHAs are
   never ancestors of it. Check by PR number instead (`git log --grep "(#N)" origin/main`,
   or `bazel run //tools/landed -- <pr#|branch|sha>`), or verify the content directly.
   **Verify post-merge health**: Run `bazel run //tools/pipeline-status -- <pr#|sha>`
   and confirm all push workflows on `main` (CI, delivery, image builds) have finished green
   (exit code 0) before reporting the work complete.

## Rigor & validation
- **Never assume configuration parity.** When touching monorepo-wide config (matrices,
  package lists, `release-please-config.json`, workspaces), do not hand-identify the set.
  Diff the physical directory structure against the config to prove 100% parity.
- **Check sibling ecosystems.** A change for one language usually has a counterpart in
  another (Go → TypeScript, and vice versa). Confirm before declaring the task done.
- **Verify before claiming success.** Don't report a bug fixed until a test or script you
  actually ran proves it — and prove the check fails against the broken state, or it is
  not evidence. For infrastructure, assert the **live effect**, not a green apply log: a
  provider reporting `updated` does not mean the setting took.

## Conventions & landmines
- **`main` is squash-only, so branch SHAs NEVER become ancestors of `main`.** Do not verify
  "did it land?" with `git merge-base --is-ancestor <branch-sha> origin/main` — it returns
  false for *every* merged PR. That is a false negative on the dangerous side: it claims
  landed work is missing, which can lead you to redo it, or to hesitate over deleting a
  branch that is perfectly safe to delete. **Before cleaning up worktrees/branches, or
  claiming anything is in `main`, use `bazel run //tools/landed -- <pr#|branch|sha>`**,
  which resolves to the *squashed* commit and checks that. Fallbacks: `git log --grep
  "(#N)" origin/main` (GitHub appends `(#N)` to squash titles), or verify the content
  directly with `git show origin/main:<path>`. See CONTRIBUTING.md §4.1.
- **Gazelle owns most `BUILD` files** — don't hand-edit generated targets; change the source and
  re-run gazelle.
- **One Version Rule** — one resolved version per dependency per ecosystem. To deliberately
  diverge, add a *separate* hub/module, not a second version to the shared hub. See
  `docs/dependency-versioning/`.
- **Dependency changes** = edit the manifest, then re-lock, then gazelle:
  - Python: `pyproject.toml` → `./tools/repin` → `bazel run //:gazelle`
  - JS/TS: `pnpm add …` (one pnpm workspace / `pnpm-lock.yaml`)
  - Go: `go mod tidy` → `bazel mod tidy` → `bazel run //:gazelle` (multi-module `go.work`: `.`, `apps/cli/homelab`, `apps/cli/devx`)
  - JVM: edit `maven.install` in `MODULE.bazel` → `bazel run @maven//:pin`; Rust: `Cargo.toml` → `bazel run //tools/crates:lock` (resolves for the Bazel toolchain's Rust version); Ruby: `Gemfile`
  - GitOps Helm chart pins (`gitops/argocd/**` `Application`/`ApplicationSet` `targetRevision`): tracked by Renovate
    (`renovate.json5`, scoped to `enabledManagers: ["argocd"]` only — it never touches the ecosystems above,
    which stay Dependabot's). Renovate opens the bump PR; review and merge it like any other PR, no re-lock step.
- The **`infrastructure/pulumi` Go modules are intentionally kept OUT of `go.work`** — don't add them.
- **License headers are enforced** (`addlicense`; CI `license-check`) — run the add helper before committing.
- **Build cache:** both a local `--disk_cache` (opt-in; see `user.bazelrc.example`) and remote
  RBE via `--config=remote` (BuildBuddy, needs a key) are available — no vendor is forced.

## Homelab access (tool-specific)
Driving the homelab k3s cluster or SSH-ing to its nodes from a *cloud* agent session needs
transport onto the tailnet, and that wiring is specific to whichever tool you run. The
Claude Code setup (SessionStart hooks, SOCKS5 proxy, key install) is documented separately
in [`docs/admin/claude-code-cloud-sessions.md`](docs/admin/claude-code-cloud-sessions.md)
so it does not leak into this vendor-neutral guide.

What generalises, whatever tool you are on:
- The cluster API is the HA name `https://k8s-api.lab.ipv1337.dev:6443` (a Cloudflare A
  record to the three control-plane tailnet IPs; the serving cert carries it as a
  `tls-san`, so TLS validates whichever control plane answers).
- Node access is by SSH **key**, as user `james`. Tailscale SSH is *not* enabled on these
  hosts.
- Local (non-cloud) sessions with tailnet access already need none of the proxy plumbing.

## Copybara (component sync)
The monorepo is the **single source of truth**; each standalone repo is a read-only mirror.
Components (`devx`, `homelab`, `mcp-slack`, `nexus-agent`, `oauth-user-inspector`) export one-way on
push; the `pulumi-*` trees are export-only. Nothing syncs bidirectionally. External contributions
come back only as a mirror PR labelled `import-to-monorepo`, imported hourly as a monorepo PR for
review. Never edit a mirror directly, never delete standalone-only files or import monorepo-only
ones — respect `standalone_only` (e.g. `package-lock.json`,
`.github/workflows/sync-to-monorepo.yaml`) and the gazelle-generated `BUILD` files (monorepo-only).
See `docs/admin/copybara-sync.md`.

## How this repo is maintained
- vitruvian-core was generated from the **kitchen-sink** starter and **does not auto-receive
  template updates** — platform changes are *manually ported* here (this repo doubles as the test
  bed that proves starter-template changes actually build).
- **Conventional commits** (`feat:`, `fix:`, `chore:`, `docs:` …).
  A `feat`/`fix` releases every product whose folder the pull request changes.
  The `release-scope` check fails one that would release a product its scope
  does not name: split it, use a type that does not release, or add a
  `Releases: a, b` line to the description (`.github/workflows/README.md`).
- Planning docs live in `docs/archive/planning/` and `docs/superpowers/`. Ones marked `status: completed` are done —
  don't treat them as open TODOs.
