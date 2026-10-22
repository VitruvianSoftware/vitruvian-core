# gh-watch

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
  failing checks, with a short log excerpt for up to two non-flaky failures.
  It is told once per failing check per commit, never twice, unless you click
  **Wake agent now** in the panel.
- If one check fails while others in the same workflow are still running, it
  waits up to 5 minutes so the failures arrive in one message (or you can wake
  the agent immediately with **Wake agent now**).
- If the pull request starts conflicting with its base branch, the
  conversation is told once and asked to merge the base in. It is reminded at
  most three times, 30 minutes apart and doubling, and told again if a push
  leaves the conflict in place.
- New review comments from collaborators and bots are passed on, quoted and
  marked as other people's text. Comments already there when watching began
  are not.
- Once nothing is failing, it follows the change the rest of the way and
  tells the conversation when all checks have passed, when it merges, and
  whether the checks on the base branch passed afterwards. So an agent never
  has to sit and poll CI to find out it is done.
- It remembers checks that failed and then passed on a re-run of the same
  commit. Once a check has done that twice in 30 days it is called flaky, and
  the next time it fails the agent is told to re-run it before changing code.
- The panel also lists the pull requests waiting on your review, anywhere on
  GitHub, with a tick box per repository so you can choose which ones are
  listed. Two more lists show your own open pull requests and all open pull
  requests in the ticked repositories, each with a Watch button, review and
  auto-merge badges, and a two-click Auto-merge button once checks are green. A row with
  merge conflicts says so in its own red badge, even when
  CI is passing. Once a pull request's pipeline is fully green and GitHub
  has confirmed it has no conflicts, its row gets Approve and Approve & merge
  buttons. It marks a watched pull request "Ready to merge" when it is green
  and mergeable but nothing is set to merge it.
- When an agent runs `gh pr create` or `bazel run //tools/agent-app -- pr-create`,
  the new pull request is watched automatically for the conversation that opened it.
- When a subagent, a delegated CLI such as `claude -p`, or a script opens the
  pull request instead, the hook cannot see it. The plugin's standing
  instruction (`rules/AGENTS.md`) tells the agent to sign it up with one
  command, `GH_WATCH=1 gh pr view <number or URL> --json url --jq .url`, and
  it is then watched for that conversation.
- A side panel lists the watched pull requests with their check counts. Each
  has switches for the wake-ups, for review comments and for GitHub's
  auto-merge.
- Opening the panel after it was closed checks everything at once.
- A merged or closed pull request stays in the list for a day, greyed out,
  and is then removed (or you can clear settled ones immediately with **Clear closed**).
  If it is reopened in that time it is watched again.

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
- The GitHub CLI (`gh`) on your `PATH`, signed in (`gh auth status`). The
  plugin reads GitHub as you, with whatever access that login has.

## Platforms

| Platform | Status |
| --- | --- |
| macOS | Tested |
| Linux | Expected to work; not tested |
| Windows | Not supported yet: the sign-up hook is a shell script, and Antigravity runs hooks through `cmd` there. Watching a pull request by hand from the panel should still work, but is untested |

## What it sends and where

Nothing leaves your machine except the requests `gh` makes to GitHub. The
watch list, settings and flaky-check memory are files in Antigravity's data
folder on your machine. There is no telemetry.

## Install

From GitHub:

```bash
agy plugin install https://github.com/VitruvianSoftware/gh-watch
```

Or from a clone. Run this inside the plugin folder (the one holding
`plugin.json`), which links it into Antigravity's plugin directory:

```bash
ln -s "$(pwd)" ~/.gemini/config/plugins/gh-watch
```

Then enable it under Customizations → Installed, and open it from any
conversation: the ⋮ menu → Extensions → GH Watch.

## Update

An install from GitHub is a git clone in Antigravity's plugin folder, and
Antigravity has no update command for it. To update, disable the plugin
under Customizations → Installed, pull, then enable it again:

```bash
git -C ~/.gemini/config/plugins/gh-watch pull
```

Disabling first matters: Antigravity only reloads a plugin's background
process when the plugin is switched off and on. Your watch list and settings
are kept; they live outside the plugin folder.

If you disable the plugin and later reinstall it, it comes back disabled,
because Antigravity remembers that choice by folder name. Enable it again.

### Versions

The panel shows the installed version next to its title. Each version has a
`v` tag and a [GitHub release](https://github.com/VitruvianSoftware/gh-watch/releases)
with its notes, which are also in [CHANGELOG.md](CHANGELOG.md).

A plain install follows the newest code. To stay on one version instead,
disable the plugin, check out its tag, then enable it again:

```bash
git -C ~/.gemini/config/plugins/gh-watch checkout v0.2.0
```

To go back to following the newest code, check out `main` the same way.

## Use

A pull request an agent opens with `gh pr create` is watched without you
doing anything. One opened for the agent by a subagent or a delegated CLI is
watched once the agent signs it up, which the plugin's standing instruction
asks it to do. To watch one yourself:

1. Open the panel from the conversation that is working on the pull request.
2. Leave the box blank to watch the pull request for the branch checked out
   in that conversation's workspace, or paste a pull request URL or number.

Each watched pull request has four switches:

- **Wake the agent when CI fails or the branch conflicts.**
- **Tell the agent when it goes green, merges and lands.** One short message
  at each step. After a merge the base branch is followed for up to two
  hours; if its checks fail, the agent is asked to work out whether the merge
  caused it and to fix it with a new pull request, never by pushing to the
  base branch.
- **Tell the agent about new review comments.** Off by default. Only comments from people who
  can already push to the repository (owner, member, collaborator) and from
  bots are passed on, never your own and never a stranger's.
- **Auto-merge on GitHub when ready.**

Watching only works while Antigravity is running.

## Review comments and trust

Review comments are other people's words placed in front of an agent that can
change and push code. The plugin limits that in three ways: it only forwards
comments from collaborators and bots on the repository, it wraps them in
markers that say they are quoted feedback and not instructions, and it caps
what it sends at 10 comments of 1,500 characters each. The switch is off for every
pull request until you turn it on.

## Layout

| Path | What it is |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `sidecars/panel/sidecar.json` | Background process and panel manifest |
| `sidecars/panel/main.mjs` | Panel backend: HTTP routes, starts the watcher |
| `hooks.json`, `hooks/note-pr-create.sh` | The hook that notices `gh pr create` and the sign-up command |
| `rules/AGENTS.md` | Standing instruction: sign up pull requests a subagent opened |
| `sidecars/panel/lib/decide.mjs` | When to wake and when to wait (pure logic) |
| `sidecars/panel/lib/flakes.mjs` | Remembering flaky checks (pure logic) |
| `sidecars/panel/lib/landing.mjs` | Green, queued, merged, landed (pure logic) |
| `sidecars/panel/lib/logs.mjs` | Failure log parsing and excerpt extraction (pure logic) |
| `sidecars/panel/lib/notices.mjs` | Merge conflicts, review feedback and the message text (pure logic) |
| `sidecars/panel/lib/inbox.mjs` | Reads the notes the hook leaves |
| `sidecars/panel/lib/watcher.mjs` | The polling loop |
| `sidecars/panel/lib/pace.mjs` | How often to poll, and the settings limits (pure logic) |
| `sidecars/panel/lib/reviews.mjs` | Which review requests to list, and which are green enough to act on (pure logic) |
| `sidecars/panel/lib/actions.mjs` | Approve, and approve & merge, from the review list |
| `sidecars/panel/lib/github.mjs` | Reads pull requests through `gh` |
| `sidecars/panel/lib/store.mjs` | The saved watch list |
| `sidecars/panel/{index.html,app.js,styles.css}` | The side panel |

The watch list is saved in Antigravity's data folder for the plugin
(`~/.gemini/antigravity/sidecar_data/<plugin folder>/panel/data/watches.json`), and
the process log is next to it under `logs/sidecar.log`.

## Moving or renaming the plugin folder

Disable the plugin in Antigravity first. Antigravity keeps the hook
registered against the folder it was loaded from, so moving the folder while
the plugin is enabled leaves every conversation running a hook whose script
is gone.

## Test

The logic is plain JavaScript with no dependencies, tested with Node's
built-in runner. From the plugin folder:

```bash
node --test sidecars/panel/lib/
bash hooks/note-pr-create_test.sh
```

This plugin is developed in the
[vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core)
monorepo, under `apps/desktop/antigravity/plugins/gh-watch`, and published
from there to [VitruvianSoftware/gh-watch](https://github.com/VitruvianSoftware/gh-watch).
In the monorepo the same tests run through Bazel:

```bash
bazel test //apps/desktop/antigravity/plugins/gh-watch/...
```

After changing `main.mjs` or anything under `lib/`, disable and re-enable the
plugin so Antigravity restarts the background process. Changes to the panel's
HTML, CSS and `app.js` show up on reload.

## Release

A release is cut by a version change, with nothing to run by hand:

1. Raise `version` in `plugin.json` and in `sidecars/panel/package.json`.
2. Add a `## <version>` section at the top of `CHANGELOG.md`.

Once that lands and is published to the public repository, a workflow there
(`.github/workflows/release.yml`) sees a version with no tag, tags the commit
`v<version>` and creates a GitHub release with that changelog section as its
notes. A test (`version_test`) fails if the three files disagree.
