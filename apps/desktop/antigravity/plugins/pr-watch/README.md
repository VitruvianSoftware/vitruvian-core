# pr-watch

An Antigravity desktop plugin. It watches the pull requests you choose and,
when a CI check on one starts failing, sends a message into the conversation
that owns it so the agent can fix it. It is modelled on the "Auto-fix CI"
switch in Claude Code's desktop app.

## What it does

- A background process, started by Antigravity when the plugin is enabled,
  asks GitHub for the state of each watched pull request every 30 seconds.
- When a check fails, the owning conversation gets one message naming the
  failing checks. It is told once per failing check per commit, never twice.
- If one check fails while others in the same workflow are still running, it
  waits up to 5 minutes so the failures arrive in one message.
- A side panel lists the watched pull requests with their check counts, and
  has a switch per pull request to turn the wake-ups off.

It does not merge anything and does not read review comments. Those are
planned, along with adjustable polling speeds.

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
