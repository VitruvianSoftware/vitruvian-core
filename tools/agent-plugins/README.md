# `//tools/agent-plugins`

Puts the current version of this repo's agent plugins into every agent harness on your Mac, and checks that it worked.

```sh
bazel run //tools/agent-plugins:refresh             # update, reinstall where needed, verify
bazel run //tools/agent-plugins:refresh -- --check  # report only; exit 1 if anything is stale
```

## Why it exists

A merged plugin change does not reach a harness on its own:

| Harness | What it runs | What refresh does |
|---|---|---|
| Claude Code | A copy under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>`, made at install time | Updates the `vitruvian-core` marketplace and the plugin. If the copy still differs, uninstalls (keeping the plugin's data) and installs again |
| Antigravity | A copy under `~/.gemini/config/plugins/<plugin>` | Uninstalls and installs again from the main checkout |
| OpenCode | Two loader files in `~/.config/opencode/plugins/<plugin>` that import the plugin from the main checkout | Runs the plugin's `install.sh` if the loaders are missing or point elsewhere |

Claude Code stores its copy under the plugin's version number, and our plugins rarely bump it, so `claude plugin update` alone can leave the old files in place. That is why refresh compares the files instead of trusting the version.

Everything installs from the **main checkout**, wherever you run this from, so refresh first fast-forwards it to `origin/main`. It refuses when the checkout is on another branch or has local changes. Pass `--no-pull` to skip that step.

After a refresh, running sessions still use the old code: run `/reload-plugins` in Claude Code, and restart Antigravity and OpenCode.

## Keep it current without asking

```sh
bazel run //tools/agent-plugins:schedule -- install   # every 30 minutes and at login
bazel run //tools/agent-plugins:schedule -- status    # is it loaded; last logged run
bazel run //tools/agent-plugins:schedule -- remove
```

`install` adds a launchd job (`dev.vitruvian.agent-plugins-refresh`) that runs the main checkout's `refresh.sh --quiet`. Refresh fast-forwards the main checkout first, so the job always runs the newest refresh. A run that finds nothing to do logs nothing. A run that updates something, finds a copy stale or fails writes its report to `~/Library/Logs/vitruvian/agent-plugins-refresh.log`. `--every <minutes>` changes the interval (5 or more). The job uses a login shell, so it finds `claude`, `agy`, `git` and `python3` the way a terminal does.

The schedule only keeps copies current. Open sessions still need `/reload-plugins` or a restart.

## Third-party Claude Code plugins

Claude Code does not auto-update plugins from marketplaces other than its official one, so a
plugin installed from GitHub stays on the version it was installed at. (The Antigravity
plugin sat on 0.22.0 for months while its `pro` tier pointed at a model Antigravity had
dropped.) So the refresh also runs `claude plugin update` on every **user-scope** plugin whose
marketplace comes from a remote (GitHub, git or URL), and reports each version change.
Directory marketplaces and project-scope installs are left alone. It never accepts a
marketplace-declared command: an update that needs one fails, is reported, and is yours to
run by hand. `--check` compares installed versions with each marketplace's local catalog and
changes nothing. Turn it off with `--no-third-party`.

## Options

- `--check`: change nothing; list what is stale and exit 1 if anything is.
- `--no-pull`: don't fast-forward the main checkout.
- `--no-third-party`: skip the third-party Claude Code plugins.
- `--quiet`: print nothing unless something changed, is stale or failed (used by the schedule).
- `--plugin <name>`: the plugin folder name under `apps/<harness>/plugins/` (default `vitruvian-orchestrator`). A harness without that folder is skipped.

## Interface
- `[refresh.sh:script entrypoint]`
- `[schedule.sh:script entrypoint]`

## Invariants
- None

## Side Effects
- [refresh.sh:108]: `git -C "$MAIN" fetch -q origin main || note "could not fetch origin/main; usi...`

## Verification
- Run: `bazel test //tools/agent-plugins/...`
