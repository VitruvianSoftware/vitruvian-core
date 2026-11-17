---
title: "Prompts Don't Hold Under Pressure: Building a Self-Protecting Pre-Tool Guardrail for Claude Code and Antigravity"
description: >-
  Every team starts with an AGENTS.md file telling AI coding agents what not to run—and
  every team watches agents ignore it forty turns into a hard bug. Here is how we built
  agent-guard, a 50-millisecond Rust PreToolUse hook for Claude Code and Antigravity that
  compiles itself from origin/main, teaches the right command on refusal, and cannot be
  weakened by the agents it governs.
date: 2026-11-16 18:00:00 +0000
categories: [agents, security, developer-tools, rust, architecture]
image: /images/agent-guard-overview.svg
---

Every team adopting AI coding agents starts the same way: you write an `AGENTS.md` or `CLAUDE.md` file listing the rules that keep the repository safe. *Always run tests through Bazel. Never `git stash` inside a shared worktree. Never push directly to `main`. Always commit under your own bot identity.*

For the first ten turns of a session, the rules hold. Forty turns later—deep inside a failing test, a stale cache, and a context window packed with compiler errors—muscle memory from pre-training takes over. The model runs `go test`, `git stash`, or `rm -rf` on a shared cache directory because that is the fastest path to green.

In an earlier post on [architecting your codebase for agentic development]({{ '/blog/2026/10/11/architecting-your-codebase-for-agentic-development/' | relative_url }}), we shared how we structure `vitruvian-core` around specialized subagents and [per-agent GitHub App identities]({{ '/blog/2026/10/09/every-ai-agent-gets-its-own-github-identity/' | relative_url }}). In this guide, we dive deep into how we enforce those rules at runtime: **`agent-guard`**, a standard-library Rust `PreToolUse` hook for both **Claude Code** and **Antigravity (`agy`)** that intercepts tool calls before they execute, refuses habits in roughly 50 milliseconds, teaches the exact replacement command, and prevents agents from weakening the guard on their own branches.

*(Tip: click or tap any diagram below—or focus it and press Enter—to inspect it full size or zoom 2×.)*

![Prompts Advise vs. Deterministic PreToolUse Guardrails](/images/agent-guard-overview.svg)
*Figure 1: Advisory rules in Markdown degrade under deep debugging context pressure. A deterministic `PreToolUse` hook intercepts each proposed tool call before execution, refuses unsafe habits, and returns the exact canonical Bazel command so the agent self-corrects on its next turn.*

---

## 1. Why prompts fail—and what our real audit logs revealed

Prompts are advisory; hooks are mechanical. Asking a stochastic model never to run `git commit` or `gh pr view` when those commands are seared into its weights means you are banking on 100% compliance across thousands of turns. Even 99% obedience guarantees multiple broken states every week when multiple agents run concurrently.

Inside [`vitruvian-core`](https://github.com/VitruvianSoftware/vitruvian-core/tree/main/tools/agent-guard), every `PreToolUse` evaluation—whether allowed or denied—appends one redacted JSON line to `~/.local/state/agent-guard/log.jsonl` (created `0600` inside a `0700` state directory, rolling over at 10 MB).

Looking at a real **5,792-call snapshot** across live agent sessions (`4,770` Claude Code calls and `1,022` Antigravity calls) shows both how low the overhead is and what models actually try to run when left unchecked:

![Real PreToolUse Audit Telemetry Across 5,792 Tool Calls](/images/agent-guard-telemetry-breakdown.svg)
*Figure 2: Across 5,792 audited `PreToolUse` calls in local sessions, 99.14% (`5,742`) passed straight through in ~50 ms while 50 slipped habits were stopped before execution—led by raw `gh` reads (`16`), raw `go` commands (`7`), `git stash` across shared worktrees (`5`), raw `git commit` (`4`), and 2 attempts to touch protected hook configuration files (`guard-config`).*

Three lessons stood out immediately from that data:

1. **Read-only habits dominate, so refusals must teach—not merely scold.** Sixteen of the 50 blocks were agents running `gh pr view` or `gh run list` directly instead of `bazel run //tools/agent-app -- read ...`. Notice what our refusal constructor in [`tools/agent-guard/src/classify.rs`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/tools/agent-guard/src/classify.rs) returns to the harness:
   ```rust
   format!(
       "Blocked by agent-guard: `{}` must go through Bazel in vitruvian-core. Use `{}`.",
       self.op, use_
   )
   ```
   Instead of forcing the model to re-read root documentation and burn three reasoning turns guessing the replacement, the refusal names the exact `bazel run` wrapper on the spot. On the very next turn, the agent runs the right command cleanly.
2. **Even destructive or shared-state mistakes recur without a gate.** Agents tried `git stash` 5 times (dangerous because git's stash is shared across every worktree), bypassed secret-scanning commits 4 times, and tried deleting Bazel caches twice (`bazel-cache`).
3. **Agents will touch the hook files if left unguarded.** Twice in that window, an agent triggered `guard-config` by attempting to modify protected configuration paths. If a guardrail relies on files an agent can edit, the guardrail has a hole.

---

## 2. The core design trick: run the guard from `origin/main`, never the branch

If you commit a hook script into a repository and configure Claude Code or Antigravity to execute the working-tree copy, an agent on a feature branch can open its editor, flip a policy flag from `"enforce"` to `"off"`, and immediately bypass the hook—all before a pull request ever reaches human review.

`agent-guard` closes this loop completely inside [`tools/agent-guard/hook.sh`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/tools/agent-guard/hook.sh). Instead of trusting the active checkout, the launcher resolves the exact git object IDs of the Rust source tree and `policy.json` from **`origin/main`**.

![Running the Guard from origin/main](/images/agent-guard-origin-main-compile.svg)
*Figure 3: Execution and fallback architecture of `tools/agent-guard/hook.sh`. Source files and `policy.json` are extracted from `origin/main` by git object ID, compiled once into a private `0700` state cache, and fail closed if no copy can execute.*

We chose **standard-library-only Rust** (zero Cargo dependencies, zero network access, zero Bazel startup penalty on every command) for a specific performance reason: a Python hook or Cargo rebuild on every `PreToolUse` invocation adds noticeable drag when an agent runs 50 shell commands in five minutes. Compiling `lib.rs` and `main.rs` directly with `rustc --edition 2021 -O` takes **about 2.5 seconds once** after `main` changes; every subsequent call reuses the content-addressed binary in **`~/.local/state/agent-guard/cache/guard-<tree-oid>`** and finishes in **about 50 milliseconds**.

Here is the heart of `hook.sh` showing how it extracts `origin/main` cleanly and caches the compiled binary atomically:

```sh
umask 077
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CEILING_DIRECTORIES

if ! ids=$(git -C "$root" rev-parse "origin/main:$rel/src" "origin/main:$rel/policy.json" 2>/dev/null); then
  source="working-copy (no origin/main:$rel in $root)"
else
  set -- $ids
  gbin=$cache/guard-$1
  pfile=$cache/policy-$2.json
  if [ ! -s "$pfile" ] && mkdir -p "$cache" 2>/dev/null &&
    git -C "$root" cat-file blob "$2" >"$pfile.new.$$" 2>/dev/null; then
    mv -f "$pfile.new.$$" "$pfile"
  fi
  if [ ! -x "$gbin" ] && [ -s "$pfile" ]; then
    s=$(mktemp -d "$cache/src.XXXXXX" 2>/dev/null) &&
      git -C "$root" archive --format=tar "$1" 2>/dev/null | tar -xf - -C "$s" 2>/dev/null &&
      build "$s" "$gbin"
  fi
fi
```

Notice three subtle security and reliability details in those lines:

1. **Private `0700` cache, never `$TMPDIR`.** Because `$TMPDIR` is world-writable and git object IDs are predictable, caching compiled binaries in `/tmp` would let an agent pre-plant a fake `guard-<next-oid>` executable before `origin/main` updates. Storing binaries under `~/.local/state/agent-guard/cache` (protected globally by `guard-config`) prevents tampering.
2. **Multi-toolchain `rustc` discovery.** On a developer Mac, `rustc` might live in a `rustup` toolchain, Homebrew, Bazel's `rules_rust` output base, or `PATH`. Crucially, `hook.sh` checks `~/.rustup/toolchains/*/bin/rustc` *before* `~/.cargo/bin/rustc` because the rustup proxy can stall trying to download a missing toolchain mid-hook.
3. **Fail-closed semantics.** If `origin/main` isn't available yet (e.g., an uninitialized test checkout), the launcher falls back to the checksummed working copy—or to the newest previously built `origin/main` binary, never an older unreviewed branch edit—while logging the reason loudly. If nothing builds or runs, `hook.sh` exits `1`, which both Claude Code (`"onFailure": "block"`) and Antigravity treat as a hard command refusal.

We also set the hook timeout to **60 seconds** in [PR #4991](https://github.com/VitruvianSoftware/vitruvian-core/pull/4991): a cold compile after pulling `main` takes ~2.5 seconds on a desktop Mac, and under heavy Bazel builds a tight 10-second timeout caused spurious fail-closed blocks.

---

## 3. Dual harness wiring and the per-user backstop

Because we work in both **Claude Code** and **Antigravity (`agy`)**, the guard speaks both hook schemas natively through the exact same binary.

![Coverage Without Friction: Project Hooks + Per-User Backstop](/images/agent-guard-dual-wiring-backstop.svg)
*Figure 4: Combining repo-committed hooks (for sessions started inside any checkout or worktree) with a thin per-user backstop in `~/.claude/settings.json` and `~/.gemini/config/hooks.json` eliminates cross-folder escape hatches while leaving interactive human terminals untouched.*

In **Claude Code** ([`.claude/settings.json`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/.claude/settings.json)), we wire separate matchers for command tools (`onFailure: "block"` so a hook crash never lets an arbitrary shell command run) and file-edit tools (omitting `onFailure` so a broken compiler never strands code edits), plus `"disableAllHooks": false` so project settings outrank a user-level opt-out:

```json
{
  "disableAllHooks": false,
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^(Bash|Monitor|mcp__terminal__run_in_terminal|...)$",
        "hooks": [
          {
            "type": "command",
            "command": "/bin/sh \"$CLAUDE_PROJECT_DIR/tools/agent-guard/hook.sh\"",
            "timeout": 60,
            "onFailure": "block"
          }
        ]
      }
    ]
  }
}
```

In **Antigravity** ([`.agents/hooks.json`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/.agents/hooks.json)), hooks must use the grouped `PreToolUse` object shape (flat entries are silently ignored) and resolve paths relative to `.agents/`:

```json
{
  "agent-guard": {
    "enabled": true,
    "PreToolUse": [
      {
        "matcher": "run_command|shell_exec|send_command_input|manage_task|git_commit|write_to_file|replace_file_content|multi_replace_file_content|notebook_edit",
        "hooks": [
          {
            "type": "command",
            "command": "/bin/sh ../tools/agent-guard/hook.sh",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

### Closing the cross-folder blind spot

When we tested project hooks live, we uncovered an easy bypass: both Claude Code and Antigravity only load project hook configs for the directory where the session **started**. If an agent session launches in `~` or an unrelated scratch folder and runs `git -C ~/Workspace/.../vitruvian-core push`, no project hook fires at all.

To close that without duplicating stale binaries across `HOME`, running `bazel run //tools/agent-guard:install` once installs a thin **per-user backstop** into `~/.claude/settings.json` and `~/.gemini/config/hooks.json`. It doesn't copy the guard—it simply points back at `<main-checkout>/tools/agent-guard/hook.sh`:

- **Inside `vitruvian-core`** (detected by walking up to `MODULE.bazel`, inspecting `gh -R` flags, or tracking `cd` / `git -C` targets): all 31 policy categories apply.
- **Unknown working directory** (for example, an Antigravity `manage_task` `send_input` call carrying only a `TaskId`): `hook.sh` fails safe and evaluates the call *as if* it were inside `vitruvian-core`.
- **Outside `vitruvian-core`**: commands pass straight through, *except* for two global rules (`guard-config` and `bazel-cache`) protecting the user's hook files and shared local Bazel caches.
- **Interactive human shells**: completely unaffected, because hooks only run inside agent loops.

---

## 4. Why naive regex hooks fail: inside the Rust shell parser

If your `PreToolUse` check is `if command.startswith("git push")`, an agent will bypass it accidentally within an hour. Real agent invocations chain commands, wrap them in `env` or `xargs`, `cd` between directories, or rewrite `argv[0]`.

Our initial prototype was Python (`agent_guard.py`), which we replaced in [PR #4081](https://github.com/VitruvianSoftware/vitruvian-core/pull/4081) with standard-library Rust (`shell.rs`, `invocations.rs`, `unicode_tables.rs`, `gitstate.rs`) verified against an **800-case golden table** ([`decision_table.json`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/tools/agent-guard/testdata/decision_table.json)) harvested from real session logs.

![Inside the Rust Shell & Context Decomposer](/images/agent-guard-shell-parser.svg)
*Figure 5: How `agent-guard` decomposes shell payloads before applying policy rules—handling recursive subshells, ANSI-C hex/NUL escapes, macOS APFS Unicode case folding, bash-vs-zsh prefix parsing differences, and live git conflict-recovery exceptions.*

Here are four real parsing problems the guard handles that naive grep rules miss:

1. **Recursive compound commands & directory tracking:** `shell.rs` unpacks `&&`, `||`, `;`, `|`, `{ }`, `$(...)`, backticks, `<(...)`, `if/for/while` bodies, unquoted `cat <<EOF` / `bash <<EOF` heredocs, `eval`, `env -S`, `xargs`, `find -exec`, `uv run`, `python -m`, and `sudo`, updating its active directory state sequentially across every `cd` and `git -C` invocation.
2. **Escapes, NUL truncation, and APFS case folding:** At `execve()` time, `$'\x67it'`, `$'git\0zz'`, `/usr/bin/GIT`, zsh's `=git`, and Unicode case-insensitively resolved binaries on macOS APFS (`baſʜ`, Kelvin `K`, ligatures `ﬀ`) all invoke `git` or `bash`. The parser decodes ANSI-C escapes, truncates at NUL bytes, strips paths and `=` prefixes, and folds Unicode characters via `unicode_tables.rs`.
3. **Conservative bash-vs-zsh ambiguity handling:** Notice this subtle differential bug: in bash 3.2 and 5.2, a prefix like `A[ x ]=1 git push` is read as a single variable assignment word followed by `git push`, whereas zsh splits it at spaces and fails with `bad pattern`. When prefix syntax is ambiguous, `agent-guard` evaluates **both** interpretations and refuses if either is blocked. Similarly, setting `RUSTUP_FORCE_ARG0` forces rustup proxies (`cargo`, `rustc`) to be judged by the target binary's file stem—and a dynamic `$VAR` in `RUSTUP_FORCE_ARG0` refuses every rustup proxy outright.
4. **Never stranding half-finished operations:** Blocking `git` writes blindly would freeze an agent mid-conflict. When `git rev-parse --git-path` detects an active `MERGE_HEAD`, `REBASE_HEAD`, or `CHERRY_PICK_HEAD`, `agent-guard` allows `git rebase --continue/--abort`, `git merge --continue/--abort`, and `git add <conflicted-file>` while still blocking arbitrary commits until the conflict is resolved. Similarly, `git checkout <name>` is checked on disk: if `<name>` is an existing path (a file restore), it passes; if not (a branch switch), it points to `//tools/worktree`.

---

## 5. Four rings of self-defense (so the guard can't be weakened)

In an autonomous repo where agents can edit code, open pull requests, and trigger peer reviews, the obvious attack vector isn't malicious intent—it's an over-eager model trying to "fix a hook error" by softening the rule.

We protect the guard across four independent rings:

![Four Rings of Self-Defense](/images/agent-guard-self-defense-rings.svg)
*Figure 6: Four concentric layers prevent an agent from disabling hooks locally, poisoning `origin/main` via custom fetch refspecs, tampering with the backstop installer, or auto-merging rule changes without human sign-off.*

1. **Ring 1 — Local file, user hook, and environment locking (`guard-config`):**
   - Inside any checkout, `guard-config` blocks writes to `.claude/settings*.json`, `.claude/*.sh`, `.agents/hooks.json`, `tools/agent-guard/hook.sh`, and `~/.local/state/agent-guard/` across all shell commands, file-edit tools, and MCP filesystem tools.
   - For user-level files (`~/.claude/settings.json` and `~/.gemini/config/hooks.json`), Claude Code's `Edit`/`MultiEdit` is simulated on the JSON before execution: agents are free to add or configure unrelated plugins as long as every `agent-guard` entry stays intact and `"disableAllHooks": true` is never written.
   - Commands attempting to hide agent identity (`unset CLAUDECODE`, `env -u`, `ANTIGRAVITY_*=`) are blocked before running.
2. **Ring 2 — Protecting `origin/main` (`git-other`):**
   Because `hook.sh` compiles whatever `origin/main` points to, running `git fetch https://fork +main:refs/remotes/origin/main` locally would swap out the guard in one command. `agent-guard` refuses explicit `src:dst` refspecs, `--refmap`, and `-c remote.*`/`-c url.*` overrides while allowing standard `git fetch origin main`.
3. **Ring 3 — Byte-for-byte installer verification:**
   Running `bazel run //tools/agent-guard:install` compiles from the local checkout, which means an unreviewed edit to `install/installer.rs` could alter the user's hooks if allowed freely. The guard (running from `origin/main`) permits agent invocations of `:install` **only** if `BUILD`, `src/**`, and `install/**` are byte-for-byte identical to `origin/main` and no `.bazelrc` contains `--run_under` or `--script_path` overrides. `--uninstall` and `--mode` are always reserved for the human maintainer.
4. **Ring 4 — GitHub Ruleset via Pulumi (`agent-guard-review`):**
   Every normal PR in `vitruvian-core` can be peer-reviewed and queued by specialized bot agents. Not rule changes. Declared in Go under [`infrastructure/pulumi/platform/repo-config/guard_review.go`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/infrastructure/pulumi/platform/repo-config/guard_review.go), the `agent-guard-review` GitHub ruleset requires fresh approval from `agent-guard-approvers` on any PR touching the 14 protected globs (`tools/agent-guard/**`, `.claude/**`, `.agents/hooks.json`, `.github/workflows/**`, `.github/actions/**`, and `guard_review.go` itself).
   - **Why a GitHub ruleset instead of a PR workflow check?** A PR workflow runs from the PR's *own* copy of the workflow file—so a PR could edit the check to mark itself green. A GitHub ruleset lives server-side in GitHub and can only be updated after merge.
   - **A real GitHub limit we hit ([#4259](https://github.com/VitruvianSoftware/vitruvian-core/pull/4259)):** GitHub caps `required_reviewers` rules at **15 file patterns** and only rejects a 16th pattern *after* merge during Pulumi apply (`HTTP 422`). Adding a Go unit test (`TestGuardReviewPatternLimit`) alongside a conformance check (`check_guard_review_paths`) ensures we never cross 15 patterns or leave a stale glob behind after a rename.

---

## 6. Being honest about limits

Every real guardrail has boundaries, and documenting them explicitly keeps teams from confusing ergonomics with sandboxing:

- **It is a guardrail, not a OS sandbox.** Because `agent-guard` inspects command strings, a script file invoked indirectly (`bash tools/my_helper.sh` calling `git` inside) or a shell variable holding a command name (`g=git; $g push`) is outside what static text parsing sees.
- **Agents share the same `gh` identity boundary if misused.** `agent-guard-review` verifies that the repository owner account approved a protected-path PR—not whether a human clicked the button if an agent was ever handed owner credentials.
- **Break-glass belongs cleanly to the maintainer.** Because hooks run *only* inside agent harnesses (`CLAUDECODE`, `ANTIGRAVITY_*`, `GEMINI_CLI`), a developer typing in their own terminal pays zero latency, never hits refusals, and can fix or tune any hook immediately.

---

## 7. Adopting this in your own repository (without slowing day-one work)

You do not need Bazel, Rust, or Pulumi to get 80% of this protection in an afternoon.

![Four-Step Playbook for Adopting PreToolUse Guardrails](/images/agent-guard-adoption-blueprint.svg)
*Figure 7: Roll out `PreToolUse` guardrails in four incremental stages—starting in silent `warn` mode to capture real habits, adding teaching error messages, locking behavior behind a regression test table, and pinning enforcement to `origin/main`.*

1. **Start with a logging hook in `warn` mode.** Wire a `PreToolUse` hook (even a 30-line script at first) with every category set to `"warn"`. Let agents work normally for a few days and inspect your JSONL log with `jq` to see the exact habits that keep slipping through `AGENTS.md`.
2. **Pair every block with a one-line fix.** Never add a "Blocked" message that doesn't tell the model the exact command to run next. Every refusal is a free in-context prompt injection at the exact moment the agent needs it.
3. **Harvest real commands into a golden decision table.** Whenever a rule misfires on a safe command (or misses an edge case), add that literal command string to a test fixture (`decision_table.json` now holds 800 real cases in our repo) before fixing the parser.
4. **Separate who *runs* the rule from who *edits* the branch.** Once enforcement matters, stop reading rules from the active git worktree. Load your hook binary and policy from `origin/main`, protect `.claude/` / `.agents/` files locally, and require human review on PRs that modify workflows or hook directories.

---

*All source code, the Rust parser, the per-user installer, the 800-case decision table, and the Pulumi ruleset definition live in [vitruvian-core under `tools/agent-guard/`](https://github.com/VitruvianSoftware/vitruvian-core/tree/main/tools/agent-guard), MIT-licensed. Adapt whatever helps keep your agents honest.*
