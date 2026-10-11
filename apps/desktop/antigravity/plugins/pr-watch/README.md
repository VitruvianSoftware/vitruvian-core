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
- If the pull request starts conflicting with its base branch, the
  conversation is told once and asked to merge the base in. It is reminded at
  most three times, 30 minutes apart and doubling, and told again if a push
  leaves the conflict in place.
- New review comments from collaborators and bots are passed on, quoted and
  marked as other people's text. Comments already there when watching began
  are not.
- When an agent runs `gh pr create`, the new pull request is watched
  automatically for the conversation that opened it.
- A side panel lists the watched pull requests with their check counts. Each
  has switches for the wake-ups, for review comments and for GitHub's
  auto-merge.
- Opening the panel after it was closed checks everything at once.
- A merged or closed pull request stays in the list for a day, greyed out,
  and is then removed. If it is reopened in that time it is watched again.

## Settings

Open **Settings** at the bottom of the panel. Changes apply on the next tick,
without restarting anything.

| Setting | Default | Range |
| --- | --- | --- |
| Check every, while CI is running or the panel is open | 30 s | 10–600 s |
| Check every, once all checks have settled | 300 s | 30–3600 s |
| Wait for related checks before waking the agent | 300 s | 0–1800 s |
| Auto-merge method, for repositories without a merge queue | squash | squash, merge, rebase |
| Keep a merged or closed pull request in the list | 24 h | 0–720 h |
| Watch pull requests automatically when an agent opens one | on | on, off |

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

A pull request an agent opens with `gh pr create` is watched without you
doing anything. To watch one yourself:

1. Open the panel from the conversation that is working on the pull request.
2. Leave the box blank to watch the pull request for the branch checked out
   in that conversation's workspace, or paste a pull request URL or number.

Each watched pull request has three switches:

- **Wake the agent when CI fails or the branch conflicts.**
- **Tell the agent about new review comments.** Only comments from people who
  can already push to the repository (owner, member, collaborator) and from
  bots are passed on, never your own and never a stranger's.
- **Auto-merge on GitHub when ready.**

Watching only works while Antigravity is running.

## Review comments and trust

Review comments are other people's words placed in front of an agent that can
change and push code. The plugin limits that in three ways: it only forwards
comments from collaborators and bots on the repository, it wraps them in
markers that say they are quoted feedback and not instructions, and it caps
what it sends at 10 comments of 1,500 characters each. If that is still more
trust than you want to give, turn the review-comments switch off for that
pull request.

## Layout

| Path | What it is |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `sidecars/panel/sidecar.json` | Background process and panel manifest |
| `sidecars/panel/main.mjs` | Panel backend: HTTP routes, starts the watcher |
| `hooks.json`, `hooks/note-pr-create.sh` | The hook that notices `gh pr create` |
| `sidecars/panel/lib/decide.mjs` | When to wake and when to wait (pure logic) |
| `sidecars/panel/lib/notices.mjs` | Merge conflicts, review feedback and the message text (pure logic) |
| `sidecars/panel/lib/inbox.mjs` | Reads the notes the hook leaves |
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
