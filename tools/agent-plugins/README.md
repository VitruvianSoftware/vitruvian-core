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

## Options

- `--check`: change nothing; list what is stale and exit 1 if anything is.
- `--no-pull`: don't fast-forward the main checkout.
- `--plugin <name>`: the plugin folder name under `apps/<harness>/plugins/` (default `vitruvian-orchestrator`). A harness without that folder is skipped.

## Interface
- `[refresh.sh:script entrypoint]`

## Invariants
- None

## Side Effects
- [refresh.sh:108]: `git -C "$MAIN" fetch -q origin main || note "could not fetch origin/main; usi...`

## Verification
- Run: `bazel test //tools/agent-plugins/...`
