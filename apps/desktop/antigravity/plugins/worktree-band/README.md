# worktree-band

An Antigravity desktop plugin that tracks active git worktrees, their GitHub
pull request status and CI checks, and their isolated Bazel output-base disk
usage, offering one-click (or automatic) post-merge cleanup.

## What it does

- **Automatic session discovery**: A `SessionStart` hook (`hooks/session-worktree.sh`)
  records active workspace paths and `conversationId` into
  `~/.gemini/antigravity/worktree-band-inbox/` whenever a conversation starts.
- **Pull request & check rollup**: Queries `gh pr view` for each linked feature
  worktree to show PR number, state (`OPEN`, `MERGED`, `CLOSED`), and check
  counts (`passed`, `failed`, `running`, `total`).
- **Disk usage accounting**: Measures the worktree folder and any isolated Bazel
  output base belonging exclusively to that worktree (either pinned via
  `--output_user_root` in `user.bazelrc` or verified via `DO_NOT_BUILD_HERE`).
- **Safe post-merge cleanup**: Once a pull request is merged into the default
  branch, `worktree-band` verifies there are no uncommitted files and no unpushed
  local commits before offering cleanup. Cleaning up shuts down the worktree's
  Bazel server, removes its isolated Bazel output base, and runs
  `git worktree remove` without `--force`.
- **OpenUI Lang v0.5 dashboard**: Exposes `/api/openui` and renders an OpenUI
  Lang v0.5 summary card with KPIs and a worktree status table.

## Install

From GitHub:

```bash
agy plugin install https://github.com/VitruvianSoftware/worktree-band
```

Or from a local checkout:

```bash
ln -s "$(pwd)" ~/.gemini/config/plugins/worktree-band
```

Then enable it under Customizations → Installed, and open it from any
conversation: the ⋮ menu → Extensions → Worktree Band.

## Update

Disable the plugin under Customizations → Installed, pull the latest changes,
then enable it again:

```bash
git -C ~/.gemini/config/plugins/worktree-band pull
```

## Requirements

The hook is written in Rust using only the standard library. The first time
it runs, `hooks/rust-hook.sh` compiles it with `rustc` (about 1 s) into
`~/.cache/antigravity-plugins/`, and later runs reuse that binary. You need
Rust installed ([rustup.rs](https://rustup.rs)); without it the hook does
nothing but say why on stderr, and tells the agent the worktree is not being tracked. The side panel runs on Antigravity's
Node.js.

## Layout

| Path | What it is |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `sidecars/panel/sidecar.json` | Background process and panel manifest |
| `sidecars/panel/main.mjs` | Panel backend: HTTP routes (`/api/state`, `/api/openui`, `/api/refresh`, `/api/cleanup`, `/api/track`) |
| `hooks.json`, `hooks/session-worktree.sh` | `SessionStart` hook recording active workspace paths |
| `hooks/rust-hook.sh` | Builds the hook from `hooks/src` with `rustc` on first use, then runs it |
| `hooks/src/` | The hook: `lib.rs` (logic and tests), `main.rs` (entry point) |
| `rules/AGENTS.md` | Standing instructions for agents working with worktrees |
| `skills/worktree-band/SKILL.md` | Skill guide for inspecting and cleaning up worktrees |
| `sidecars/panel/lib/core.mjs` | Pure logic: `countChecks`, `fmtSize`, `isRemovable`, `judgeCleanup`, `summariseWorktrees` |
| `sidecars/panel/lib/openui.mjs` | OpenUI Lang v0.5 parser, HTML compiler, and `toOpenUILang(state)` |
| `sidecars/panel/{index.html,app.js,styles.css}` | Interactive side panel UI |

## Test

From the plugin folder:

```bash
node --test sidecars/panel/lib/*.test.mjs
rustc --edition 2021 --test hooks/src/lib.rs -o /tmp/worktree-band-hook-test && /tmp/worktree-band-hook-test
```

Or via Bazel in the monorepo:

```bash
bazel test //apps/desktop/antigravity/plugins/worktree-band/...
```
