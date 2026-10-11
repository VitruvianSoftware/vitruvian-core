# pr-watch

An Antigravity desktop plugin. It watches the pull requests you choose and,
when a CI check on one starts failing, sends a message into the conversation
that owns it so the agent can fix it. It is modelled on the "Auto-fix CI"
switch in Claude Code's desktop app.

## What it does

- A background process, started by Antigravity when the plugin is enabled,
  asks GitHub for the state of each watched pull request. It checks every 30
  seconds while a check is still running or the panel is open, and every 5
  minutes once every watched pull request has settled.
- When a check fails, the owning conversation gets one message naming the
  failing checks. It is told once per failing check per commit, never twice.
- If one check fails while others in the same workflow are still running, it
  waits up to 5 minutes so the failures arrive in one message.
- A side panel lists the watched pull requests with their check counts. Each
  has a switch for the wake-ups and a switch for GitHub's auto-merge.
- Opening the panel after it was closed checks everything at once.

It does not read review comments or report merge conflicts yet.

## Settings

Open **Settings** at the bottom of the panel. Changes apply on the next tick,
without restarting anything.

| Setting | Default | Range |
| --- | --- | --- |
| Check every, while CI is running or the panel is open | 30 s | 10–600 s |
| Check every, once all checks have settled | 300 s | 30–3600 s |
| Wait for related checks before waking the agent | 300 s | 0–1800 s |
| Auto-merge method, for repositories without a merge queue | squash | squash, merge, rebase |

## Auto-merge

The auto-merge switch turns GitHub's own auto-merge on or off for that pull
request (`gh pr merge --auto`). GitHub does the merging, once the required
checks and reviews are in; the plugin never merges anything itself. A
repository with a merge queue decides how to merge, so the method setting only
matters where there is none. Draft pull requests cannot auto-merge.

## Requirements

- Antigravity desktop. Terminal-only `agy` sessions are not covered, because
  only the desktop app runs plugin background processes.
- The GitHub CLI (`gh`) on your `PATH`, signed in (`gh auth status`).

## Install

Link the plugin folder into Antigravity's plugin directory, then enable it
under Customizations → Installed:

```bash
ln -s "$(git rev-parse --show-toplevel)/apps/desktop/antigravity/plugins/pr-watch" ~/.gemini/config/plugins/pr-watch
```

Open it from any conversation: the ⋮ menu → Extensions → PR Watch.

## Use

1. Open the panel from the conversation that is working on the pull request.
2. Leave the box blank to watch the pull request for the branch checked out
   in that conversation's workspace, or paste a pull request URL or number.
3. Leave "Wake the agent when CI fails" on.

Watching only works while Antigravity is running.

## Layout

| Path | What it is |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `sidecars/panel/sidecar.json` | Background process and panel manifest |
| `sidecars/panel/main.mjs` | Panel backend: HTTP routes, starts the watcher |
| `sidecars/panel/lib/decide.mjs` | When to wake and when to wait (pure logic) |
| `sidecars/panel/lib/watcher.mjs` | The polling loop |
| `sidecars/panel/lib/pace.mjs` | How often to poll, and the settings limits (pure logic) |
| `sidecars/panel/lib/github.mjs` | Reads pull requests through `gh` |
| `sidecars/panel/lib/store.mjs` | The saved watch list |
| `sidecars/panel/{index.html,app.js,styles.css}` | The side panel |

The watch list is saved in Antigravity's data folder for the plugin
(`~/.gemini/antigravity/sidecar_data/pr-watch/panel/data/watches.json`), and
the process log is next to it under `logs/sidecar.log`.

## Test

```bash
bazel test //apps/desktop/antigravity/plugins/pr-watch/...
```

After changing `main.mjs` or anything under `lib/`, disable and re-enable the
plugin so Antigravity restarts the background process. Changes to the panel's
HTML, CSS and `app.js` show up on reload.
