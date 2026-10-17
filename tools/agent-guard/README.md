# agent-guard

AI agents working in vitruvian-core must run repo and dev operations through
Bazel targets: `bazel run //tools/git:commit`, not `git commit`; `bazel test`,
not `go test`. Instructions alone did not hold, so agent-guard enforces it. It
is a hook for Claude Code and Antigravity (agy) that reads each command an
agent is about to run and refuses the ones that have a Bazel route, naming the
target to use instead. It runs from the repo itself: every checkout and
worktree is guarded with nothing to install (see "How it is wired").

It is a **guardrail, not a security boundary**. It reads command text, so it
stops habits; a determined workaround (a script that calls git inside it) gets
past it. Agents are told not to route around it.

**James's own terminal is never affected.** Hooks run only inside agent loops.
There is no escape hatch for agents: if a target is missing, the refusal says
so and tells the agent to stop and tell James.

```mermaid
flowchart LR
  A[Agent command] --> P[Split into every program it runs]
  P --> S{"Inside a vitruvian-core checkout, or location unknown?"}
  S -- no --> OK[Allow, log]
  S -- yes --> C{Read-only, Bazel, or not governed?}
  C -- yes --> OK
  C -- no --> M{Category mode}
  M -- enforce --> X[Refuse, name the target, log]
  M -- warn --> W[Run, tell the agent, log]
  M -- off --> OK
```

## How it is wired: from the repo, plus a thin per-user backstop

Every checkout and worktree is guarded the moment it exists: the repo carries
the hook itself. Project hooks only load in a session STARTED inside
vitruvian-core, though, so a one-time per-user backstop covers sessions started
anywhere else (below).

```mermaid
flowchart LR
  CC["Claude Code<br/>.claude/settings.json"] --> H["tools/agent-guard/hook.sh<br/>(this checkout)"]
  AG["Antigravity<br/>.agents/hooks.json"] --> H
  U["backstop<br/>~/.claude/settings.json<br/>~/.gemini/config/hooks.json"] --> HM["tools/agent-guard/hook.sh<br/>(the main checkout)"]
  HM --> Q
  H --> Q{"origin/main has the guard?"}
  Q -- yes --> M["run origin/main's agent_guard.py + policy.json<br/>(cached by blob id)"]
  Q -- "no, or git fails" --> L["run this checkout's copy<br/>(logged as working-copy)"]
```

- **Claude Code**: `.claude/settings.json` has two `PreToolUse` entries, both
  running `/bin/sh "$CLAUDE_PROJECT_DIR/tools/agent-guard/hook.sh"`:
  - **command tools** (`Bash`, `Monitor`, the terminal panel, Desktop
    Commander's `start_process`/`interact_with_process`, the auto-merge tool,
    the kubernetes MCP write tools) with `onFailure: block`: if the hook
    cannot run, the command is refused, not let through. Claude Code honours
    this in project settings: the hooks reference's own example of it is a
    `PreToolUse` hook "in `.claude/settings.json`" (Hooks reference, "Block the
    action when a hook fails"; Claude Code 2.1.295+, here 2.1.302);
  - **file tools** (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`, Desktop
    Commander's `write_file`, `edit_block`, `move_file`, `create_directory`,
    `write_pdf`) with **no** `onFailure`. They are checked only to protect the
    guard's own files, so a broken hook never stops code edits.

  `"disableAllHooks": false` is set there too. Project settings outrank user
  settings, so a user-level `true` cannot switch the guard off in the repo
  (Hooks reference, "Disable or remove hooks": a `"disableAllHooks": false`
  "in a project's `.claude/settings.json` overrides a `true` in your user
  settings").

  The repo's `.claude/block-queue-bypass.sh` hook stays beside them. Both run,
  and either one's refusal wins. Project hooks need the folder trusted in an
  interactive session; `-p` and SDK sessions always run them.
- **Antigravity (agy)**: `.agents/hooks.json` has one named hook,
  `agent-guard`, in the grouped shape (details below). agy runs a hook from the
  folder holding its `hooks.json`, so the command is
  `/bin/sh ../tools/agent-guard/hook.sh`.

**The launcher, `hook.sh`**, finds the checkout from its own path, never from
the working folder (agy runs it from `.agents/`, Claude Code from wherever the
agent is). Then:

1. **It runs the guard as it is on `origin/main`, not this checkout's copy.**
   `git rev-parse origin/main:tools/agent-guard/agent_guard.py` (and
   `policy.json`) gives their blob ids; the files are written once per change
   on main to `~/.local/state/agent-guard/cache/` and reused from there. So an
   agent's edit to `agent_guard.py` or `policy.json` in a worktree governs
   nothing until it is reviewed and merged, and agents may edit those files
   like any other code. `origin/main` is as fresh as your last fetch.
2. **If that is not possible**, because there is no `origin/main`, main has no
   guard yet, git is missing, or the cache cannot be written, it runs this
   checkout's copy and says so: on stderr, and in the log's `source` field
   (`working-copy (why)` instead of `origin/main:<blob>`). It does the same if
   main's copy will not start on a python.
3. **It tries each python3 in turn**, with `-I -S` (no `PYTHON*` variables, no
   site packages; the guard needs only the standard library), until one exits
   cleanly. The order is the one the per-user installer used: Homebrew's
   versioned links newest first (`/opt/homebrew/opt/python@3.N/bin/python3.N`,
   then `/usr/local/opt/...`; independent of Xcode, stable across patch
   upgrades, and including every `python@3.N` installed on request, which
   Homebrew's cleanup leaves alone), then the Command Line Tools' python3,
   then Apple's `/usr/bin/python3` shim (resolved through `xcode-select` on
   every call, so it fails while Xcode is being replaced). It exits 1 only if
   none works, and the call is then refused (Claude Code's `onFailure: block`;
   agy always fails closed). It caches the guard's bytecode for whichever
   python runs, since Apple's never writes its own.

**Speed.** About 48 ms a call on this Mac with a warm cache (median of 30,
Homebrew python 3.15): ~4 ms for `sh`, ~12 ms for the `git rev-parse`, ~14 ms
for python to start, the rest the guard. The first call after main changes
also writes the cache: ~110 ms. The old copied install was ~30 ms because it
had no git step. If those 12 ms ever matter, the launcher could key its cache on
the `origin/main` commit read straight from `.git` (no process) and call git
only when that commit changes.

**The guard's own files are protected** (category `guard-config`): agents may
not write, move or delete `.claude/settings.json`, `.claude/settings.local.json`
(it could switch hooks off), the hook scripts `.claude/*.sh` (session-start,
block-queue-bypass, kube-setup, tailscale-up: they run from the project
settings), `.agents/hooks.json` or `tools/agent-guard/hook.sh` in any
vitruvian-core checkout, through the file tools or the obvious shell
writes (`>`, `tee`, `cp` onto them, `mv`, `rm`, `sed -i`, `perl -i`,
`python -c` that writes, `chmod`). Those take effect before review, so
changing them is James's call. Reading them, `git diff`, and running the
launcher by hand are fine. The rest of `tools/agent-guard/` is ordinary code.

**Fetches that could move origin/main are refused** (category `git-other`),
because origin/main is what hook.sh runs: a `src:dst` refspec
(`git fetch https://github.com/someone/fork +main:refs/remotes/origin/main`,
`git fetch origin main:main`), `--refmap`, or a `-c remote.*`/`-c url.*`
override, on `git fetch` or `git pull`. `git fetch`, `git fetch origin` and
`git fetch -q origin main` stay allowed.

**Checking it.**

```sh
bazel run //tools/agent-guard:install -- --check
```

It fails if agent-guard's entries in either repo file are missing or differ
from `install.py`'s `claude_entries()`/`agy_entry()`, if
`"disableAllHooks": false` is missing, or if the backstop is missing, still
the old copy, or points at a `hook.sh` that is gone. Then it runs the repo
launcher and the backstop on sample tool calls in Claude Code's and agy's real
payload shapes, from the folder each runs them in: `git status` must be
allowed, `git stash` (Claude Code) and `go vet` (agy) refused. It says which
copy of the guard answered.

### The per-user backstop

Claude Code loads `.claude/settings.json` only for a session started inside
the checkout, and agy loads `.agents/hooks.json` only when started there
(checked live on 2026-10-17: agy started in another folder ran a command in a
worktree of this branch, and only the per-user hook logged it). A session
started in `~`, another repo or Cowork that then works here would be
unguarded. So, once, from **your own terminal** (agents may only `--dry-run`
or `--check`):

```sh
bazel run //tools/agent-guard:install -- --dry-run   # see the exact change to both user files
bazel run //tools/agent-guard:install
```

It merges the same two Claude Code entries into `~/.claude/settings.json`, and
the same `agent-guard` hook into `~/.gemini/config/hooks.json` if `~/.gemini`
exists. The command is a short `/bin/sh -c '...'` script written into the
entry itself (`BACKSTOP_SCRIPT` in `install.py`), given the main checkout's
absolute path, which is found from wherever you run the install, even a
worktree. If `<main checkout>/tools/agent-guard/hook.sh` exists, the script
runs it. Nothing is copied:

- **Guard changes need no reinstall.** The backstop runs the main checkout's
  `hook.sh`, which loads the guard from `origin/main`, so changes arrive with
  a pull or fetch.
- **Moving or deleting the main checkout needs a reinstall**, as does
  checking out a branch there that predates `hook.sh`. Until then the script
  finds no launcher and fails closed **only for vitruvian-core**: a call whose
  payload names the main checkout or its `-worktrees/` sibling is refused with
  "agent-guard: its launcher is missing from <main>; James must reinstall..."
  (Claude Code: exit 2 with that reason; agy: its deny JSON). Every other call,
  in any other repo, is let through with a warning on stderr. `--check` says
  so; reinstall, or `--uninstall`.
- **It migrates the old install.** Entries that point at the old copy in
  `~/.local/share/agent-guard` are replaced, and that copy is deleted, once the
  new entries pass a self-test (`git status` allowed, `git stash` and `go vet`
  refused, in both payload shapes, from a folder outside any checkout). If the
  self-test fails, or a write fails part-way, both files are put back and
  nothing is deleted.
- Every other hook is kept, each file is backed up beside itself before a
  write, and running it twice changes nothing. `--uninstall` removes only
  agent-guard's entries (and any old copy); the log stays.

**Running twice is harmless.** In a session started inside the repo both the
project hook and the backstop run (their commands differ, so Claude Code does
not merge them). They run the same guard from the same `origin/main`, so they
give the same answer, and a refusal from either wins. Claude Code runs them
in parallel. agy seemed to run them one after the other: their log lines were
about 40 ms apart, and on a refusal only one of them logged. The log gets two
lines for each allowed call.

### Antigravity details

Verified live against agy 1.4.0. The entry in `.agents/hooks.json`:

```json
"agent-guard": {
  "enabled": true,
  "PreToolUse": [
    {"matcher": "run_command|shell_exec|send_command_input|manage_task|git_commit|write_to_file|replace_file_content|multi_replace_file_content|notebook_edit",
     "hooks": [{"type": "command", "command": "/bin/sh ../tools/agent-guard/hook.sh", "timeout": 10}]}
  ]
}
```

- **Read from the project.** agy reads `.agents/hooks.json` in the folder it
  runs in as well as `~/.gemini/config/hooks.json`, and runs a hook from the
  folder holding its file. Tested on 2026-10-17 in a worktree of this branch:
  agy refused `go vet ./does-not-exist-agent-guard-probe/...` with the guard's
  reason and let `git status` run, and the log showed the repo hook's lines
  (marked by forcing the launcher's working-copy path for the test) next to
  the per-user hook's. The same name in both files does not clash: both ran.
- **Grouped shape only.** agy loads a flat `PreToolUse` entry (`type` and
  `command` beside `matcher`) but silently ignores it.
- **One regex matcher** against the tool name; plain `|` alternation was
  checked live. Which names are confirmed:
  - seen live in a hook payload: `run_command` (`CommandLine`, `Cwd`),
    `write_to_file` and `replace_file_content` (`TargetFile`);
  - in agy's own tool declarations, not yet seen in a hook payload:
    `multi_replace_file_content` (`TargetFile`), `notebook_edit`
    (`NotebookPath`), `manage_task` (`Action: "send_input"` with `Input`
    sends input to a running command);
  - in the agy binary only, never seen offered to the model, so their argument
    names are guesses: `shell_exec` (read like `run_command`; the guard tries
    `Command`, `command`, `CommandLine`), `send_command_input` (`Input` or
    `input`) and `git_commit` (refused as a commit whatever its arguments).
- **Where a command runs.** agy sends no top-level `cwd`. The guard uses
  `args.Cwd`; without it, a `workspacePaths` entry inside vitruvian-core if any
  is, else the first one; without either, the location is unknown and the
  command is judged as if it were inside vitruvian-core. The hook's own folder
  (`.agents/`) is never used: a missing location never means allowed.
- **Replies.** Allow prints nothing; deny prints
  `{"decision":"deny","reason":"..."}`. Warn mode prints nothing (agy has no
  "allow with a note" reply), so a warning reaches only the log.
- **A broken hook fails closed** (tested live with agy 1.4.0): agy refused the
  `run_command` call when the hook exited 1, printed half-finished JSON, hung
  past its timeout, or could not start its interpreter.
- Not checked: whether agy started in a subfolder of the checkout still finds
  `.agents/hooks.json` at the top.

## If the hook breaks

A broken hook refuses every command an agent runs (by design: it fails
closed). In Claude Code, file edits keep working; in agy, which has one
matcher for commands and file writes, probably not. The launcher's python
fallback and its working-copy fallback make this unlikely. Run
`bazel run //tools/agent-guard:install -- --check` from your own terminal
(hooks do not run there) to see why. To switch the guard off while you fix it,
from your own terminal: remove the two agent-guard entries from
`.claude/settings.json` and the `"agent-guard"` key from `.agents/hooks.json`
in the affected checkout (or set `"enabled": false` there), run
`bazel run //tools/agent-guard:install -- --uninstall` for the backstop, and
land the fix through a PR.

## What is blocked, and what to use

Every category defaults to `enforce`. Some targets are still being built on
another branch; until one lands, the refusal says so and points to James.

| Category | Blocked | Use instead |
|---|---|---|
| `git-commit` | `git add`, `rm`, `mv`, `commit`, `apply --index`/`--3way` | `bazel run //tools/git:commit` |
| `git-push` | `git push` | `bazel run //tools/git:push` |
| `git-history` | `git rebase`, `merge`, `pull` (except `--ff-only` in the primary checkout) | `bazel run //tools/git:sync` |
| | `git reset`, `cherry-pick`, `revert`, `am`, `bisect`, `tag` | no target yet: tell James |
| `git-stash` | `git stash` except `list`/`show` (the stash is shared by every worktree) | commit to your branch, or use another worktree |
| `git-branch` | `git checkout -b`/`<branch>`, `git switch`, `git branch <new>`/`-m`, `gh pr checkout` | `bazel run //tools/worktree -- <branch> [base]` |
| | `git branch -d/-D` | `bazel run //tools/worktree -- --remove <branch> --delete-branch` or `--prune` |
| `git-worktree` | `git worktree add/remove/prune/lock/unlock`, `rm -r` of a worktree | `bazel run //tools/worktree` with `--detach <ref>`, `--remove`, `--prune`, `--lock`/`--unlock` |
| `git-other` | any other git verb that writes: `config` writes, `remote add`, `clean` (except `-n`), `gc`, `clone`, ...; a `git fetch`/`pull` that names where it writes (`src:dst` refspec, `--refmap`, `-c remote.*`/`url.*`) | no target: tell James |
| `gh-pr` | `gh pr create` | `bazel run //tools/agent-app -- pr-create` (PR #3427) |
| | `gh pr merge` (with or without `--auto`), the auto-merge MCP tool | `bazel run //tools/agent-app -- pr-enqueue <pr>` |
| | `gh pr edit/comment/ready/close/review` | `pr-edit`, `pr-comment`, `pr-ready` are planned in agent-app: tell James |
| `gh-run` | `gh workflow run/enable/disable`, `gh run rerun/cancel/delete` | no target yet: tell James |
| `gh-api` | `gh api` with a write method or fields, GraphQL mutations | no target: tell James |
| `gh-other` | other `gh` writes: `release create`, `secret set`, `label create`, ... | no target: tell James |
| `go` | `go test/vet/build/run/install/mod/get/fmt` | `bazel test`, `bazel build`, `//tools/gomod:tidy`, `//tools/format` |
| `swift` | `swift build/test/run/package`, `swiftc` | `bazel test //apps/desktop/<app>:<Tests>` |
| `xcode` | `xcodebuild`, `xcrun notarytool/stapler/altool` | the app's `bazel build`/`test` and packaging targets |
| `node` | `npm`/`pnpm`/`yarn`/`bun` install, test, run, exec; `npx` | `bazel test` / `bazel run`; Bazel installs node_modules itself |
| `cargo` | `cargo build/test/run/check/clippy/publish` | `bazel test` / `bazel build` |
| `gradle` | `gradle`, `./gradlew` | `bazel build //apps/mobile/<app>:app` |
| `pytest` | `pytest`, `python -m pytest`, `uv run pytest` | `bazel test` |
| `lint` | `gofmt`, `golangci-lint`, `ruff`, `eslint`, `prettier`, `shellcheck`, `buildifier`, ... | `bazel run //tools/format` (or `//:tidy`), `aspect lint` |
| `actionlint` | `actionlint` | `bazel run //tools/ci:actionlint` |
| `secret-scan` | `gitleaks` | `bazel run //tools/secret-scan` |
| `iac` | `pulumi` (anything but read-only commands like `stack ls`), `terraform apply/destroy/import` | `bazel run //infrastructure/pulumi/<project>:preview` |
| `kubectl` | `apply/delete/patch/create/replace` | `bazel run //tools/gitops:{apply,delete,patch}`, or change git |
| | `edit/exec/rollout restart/scale/label/...` | no target: tell James |
| `helm` | `install/upgrade/uninstall/rollback` | `bazel run //tools/gitops:helm`, or change git |
| `bazel-cache` | `rm -r` of `~/.cache/bazel`, `~/Library/Caches/bazel` or `_bazel_*`; `find -delete` there; `bazel clean --expunge`; `--output_user_root`/`--output_base` | `bazel run //tools/bazel-cache:gc` |
| `guard-config` | agents writing, moving or deleting the hook files in any checkout (`.claude/settings.json`, `.claude/settings.local.json`, `.claude/*.sh`, `.agents/hooks.json`, `tools/agent-guard/hook.sh`); writing, moving or deleting the guard's log and cache (`~/.local/state/agent-guard`) or the old per-user copy (copying or reading FROM them is fine, in the shell or in `python -c`); running `//tools/agent-guard:install` (`bazel run`, `bazel-bin/.../install` or `install.py`) without `--dry-run`/`--check`; hiding the agent session (`CLAUDECODE=`/`ANTIGRAVITY_*=`/`GEMINI_CLI=` prefixes, `env -u`, `env -i`, `unset`, `export -n`) in a command that runs anything agent-guard. Matched on the parsed commands, so `grep 'unset CLAUDECODE'` is just a grep | James does this from his own terminal |
| `oversize` | a command with more than 20,000 simple commands in it (the hook must answer inside its 10 s timeout, and command tools fail closed) | split it into smaller commands |

**Always allowed:** read-only git (`status log diff show fetch rev-parse
ls-files grep blame`, `branch` listing, `worktree list`, `merge-base`,
`cat-file`, `config --get`, `remote -v`, `stash list`, `tag -l`, `restore`,
`checkout -- <path>`, `apply <patch>` to the working tree, `clean -n`,
`pull --ff-only` in the primary checkout); read-only gh (`view list checks diff status`, `gh api` GETs and
GraphQL queries, `gh issue ...`); anything run by `bazel`, `bazelisk`,
`aspect` or `ibazel`; `--version` and `--help` of every tool; and every program
the guard does not govern (`cat`, `jq`, `ls`, `python3 -c`, `docker`, ...).

**Half-finished operations are never stranded.** While a merge, rebase or
cherry-pick is in progress (git's `MERGE_HEAD`, `REBASE_HEAD`/`rebase-merge`/
`rebase-apply` or `CHERRY_PICK_HEAD`, found with `git rev-parse --git-path`, so
worktrees work), these are allowed: `git merge --continue/--abort`,
`git rebase --continue/--abort/--skip`, `git cherry-pick --continue/--abort`,
and `git add` of the conflicted files by name. The same commands are refused
when nothing is in progress. A `git commit` that would conclude a merge points
to `bazel run //tools/git:commit`, which concludes it.

## What it sees through

It splits a command into every program it runs: `&&`, `||`, `;`, `|`,
newlines, `( )` and `{ }`, `$(...)`, backticks, `<(...)`, `if/for/while`
bodies, `bash -c`/`sh -c`/`zsh -lc`, `bash <<EOF` and `<<<`, `eval`, `env`
(including `-S`), `xargs`, `find -exec`, `watch`, `nice`, `time`, `timeout`,
`nohup`, `command`, `exec`, `sudo`, `caffeinate`, `direnv exec`, `uv run`,
`uvx` and `python -m`. It matches programs by basename (`/usr/bin/git` is git)
and follows `cd`, `git -C`, `--git-dir` and `--work-tree` to decide scope. A
heredoc fed to `cat` is data, including inside `"$(cat <<'EOF' ... EOF)"`
with apostrophes or backticks in the body; one fed to `bash` is a script. In
an UNQUOTED heredoc (`<<EOF`, not `<<'EOF'`) the shell runs every `$(...)` and
backtick in the body, so the guard checks those (`\$(...)` and `` \` `` stay
text).

## Scope

It governs only commands whose directory is inside a vitruvian-core checkout or
worktree: one with a `MODULE.bazel` declaring `module(name = "vitruvian_core")`.
Anywhere else, including other repos, it allows the command and logs it. Two
categories apply everywhere, because what they protect is not in the checkout:
`bazel-cache` and `guard-config`. A `gh` command that names its repository
(`-R`/`--repo`, a PR or issue URL, or a `repos/<owner>/<name>/` API path) is
scoped by that repository instead: vitruvian-core is in scope wherever the
command runs, and any other repository is out of scope even from inside this
checkout. `{owner}/{repo}` placeholders mean the current directory's repo.
For Antigravity the directory is `args.Cwd`, then a `workspacePaths` entry
inside vitruvian-core (or the first one if none is); with neither, the command is treated as inside (see "Antigravity details").

## Modes

`tools/agent-guard/policy.json` sets each category to `enforce`, `warn` or
`off`. `enforce` refuses. `warn` lets the command run, tells the agent it would
have been refused, and logs it. `off` skips the check. A missing or broken
policy file means enforce everything. The hook reads the policy from
`origin/main`, so a mode changes for every agent when a change to this file
merges, not when someone edits it locally.

## The log

Every command an agent runs through a covered tool is one JSON line in
`~/.local/state/agent-guard/log.jsonl`: time, agent (`claude-code` or
`antigravity`), tool, directory, scope, category, operation, decision, the
command (redacted, cut to 1,000 characters) and the session. For Antigravity
the directory is the one the guard judged by (empty if agy gave none, with
scope `unknown`) and the session is agy's `conversationId`. `source` says which
copy of the guard decided: `origin/main:<blob id>`, or `working-copy (why)`
when the launcher fell back (lines from the old copied install have no
`source`). File edits are logged only when refused. The directory is 0700
and the file 0600. Secrets are replaced by `[REDACTED]`: values after
`--password`/`--token`/`--secret`, attached `-pPASSWORD` (not `git log -p 5`),
`curl -u user:pass`, `gh secret set ... --body`, `NAME_TOKEN=`/`*_KEY=`/
`password=`, `Authorization:`, `X-Api-Key:` and other `*-Key`/`*Token*`/
`*Secret*` headers, `Bearer`, `scheme://user:pass@` URLs, and GitHub, Slack,
OpenAI/Anthropic, AWS and Google (`AIza...`) key shapes. The file rolls over to `log.jsonl.1`
at 10 MB.

```sh
# What was refused today, by category
jq -r 'select(.decision=="deny") | .category' ~/.local/state/agent-guard/log.jsonl | sort | uniq -c | sort -rn
# The last ten refusals, with the command
jq -c 'select(.decision=="deny") | {ts, category, command}' ~/.local/state/agent-guard/log.jsonl | tail -10
# What warn mode would have refused
jq -c 'select(.decision=="warn")' ~/.local/state/agent-guard/log.jsonl
# Calls decided by a checkout's own copy rather than origin/main's
jq -c 'select(.source // "" | startswith("working-copy"))' ~/.local/state/agent-guard/log.jsonl
```

## Limits

- **It reads text.** A script that calls git inside it (`bash tools/x.sh`,
  `make`, a Python `subprocess`), a variable used as a command (`g=git; $g push`)
  or an alias is not seen. A second layer (agent-only `git`/`gh` shims on
  `PATH`) is planned to catch most of these.
- **Unquoted heredocs** (`<<EOF`) are only half-read. The guard checks the
  `$(...)` and backtick commands in the body, which the shell runs, but treats
  the rest as text: it does not expand variables, and a body piped into a
  shell (`cat <<EOF | sh`) is not read as a script. Quote the delimiter
  (`<<'EOF'`) when the body is meant as text.
- **Speed and size.** The hook decides a 1 MB single-word command or a 5 MB
  heredoc in well under a second (the tests hold each case under 1 s; most
  take 10-300 ms). It logs and redacts only the first 1,200 characters. A
  command with more than 20,000 simple commands in it is refused as
  `oversize` rather than checked.
- **It cannot see inside `bazel run`.** That is by design: targets run git
  freely. A target that misbehaves has to be fixed in the target.
- **Only the tools in its matchers.** A new MCP server or agy tool that runs
  commands or changes the repo is a gap until it is added to the matchers in
  `install.py`, the two hook files and the tool tables in `agent_guard.py`
  (`hook_test` fails if the files and `install.py` disagree).
- **The launcher and the two hook files run from the checkout**, not from
  `origin/main`: something has to start the hook. That is why agents may not
  write them. A checkout whose files were changed by hand, or a branch that
  predates them, runs whatever it has; `--check` shows it.
- **`origin/main` is only as fresh as the last fetch**, so a merged guard
  change reaches a checkout when it next fetches.
- **Shell writes to the hook files are matched by name**, like everything
  else here. A patch can still reach them: `git apply`, `patch -p1` or
  `git checkout <ref> -- .claude/settings.json`, as can a script that writes
  them. `tools/cloud-bootstrap/cloud-bootstrap.sh`, which
  `.claude/session-start.sh` runs, is not protected either.
- **The backstop's user files** (`~/.claude/settings.json`,
  `~/.gemini/config/hooks.json`) are not protected, so an agent could remove
  the backstop there; `--check` shows it. In the repo, `"disableAllHooks":
  false` outranks a user-level `true`, but a nested `claude -p --settings
  '{"disableAllHooks": true}'` started by an agent would run unguarded.
- **Agent detection is by environment marker** (`CLAUDECODE`,
  `ANTIGRAVITY_AGENT`, `ANTIGRAVITY_*`, `GEMINI_CLI`). `ANTIGRAVITY_AGENT=1` is
  in the agy binary; the Gemini CLI marker is the `GEMINI_CLI` name its
  wrapper uses. Neither was seen live in an agent shell.
- **`git checkout <name>`** is treated as a file restore when `<name>` exists
  as a path, and as a branch switch otherwise.
- **Antigravity** is guarded through the hook above, verified live for
  `run_command`, and a broken hook fails closed there. Not verified: the real
  argument names of `shell_exec`, `send_command_input` and
  `git_commit`. The older Gemini CLI has no usable hook.
- Each refusal costs the agent a turn; expect some friction at first.

## Tests

```sh
bazel test //tools/agent-guard/...
```

`agent_guard_test` replays a table of 400+ real commands (from a week of agent
logs) against expected decisions, plus redaction, scope, modes, the hook's
input and output in both formats (including agy's captured payload shape,
the missing-`Cwd` fallback and the log fields), the hook files' protection, a
real git merge conflict, and timing on 100 KB, 1 MB and 5 MB inputs.
`hook_test` runs `hook.sh` in a throwaway git checkout with an `origin/main`:
origin/main's guard wins over a broken local edit, a merged change takes
effect, the cache, each working-copy fallback, the python fallback, agy's
`.agents/` working folder; it also reads the real `.claude/settings.json` and
`.agents/hooks.json` and fails if agent-guard is unwired from either.
`install_test` runs against a temporary HOME: the backstop's two entries and
agy hook pointing at the main checkout (also from a worktree), migrating and
deleting the old copy, idempotence, dry run, rollback when the self-test
fails, `--uninstall` (both files, shared groups, the desktop app's JSON style,
a broken `hooks.json`), refusal inside an agent session, and `--check`
passing and failing (no backstop, the old copy, a moved main checkout, an
unwired repo file, a broken launcher, a category switched off).
