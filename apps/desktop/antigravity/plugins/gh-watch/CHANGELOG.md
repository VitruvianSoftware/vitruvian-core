# Changelog

All notable changes to gh-watch are recorded here.

## 0.7.3

- Merged pull requests keep watching the base branch after a check fails (so a
  re-run or transient failure recovers to `Merged · landed`), update their
  card check counts and failing check list from the base branch's checks,
  ignore unrelated dynamic `Dependabot` runs on `main`, and hide leftover
  `Review requested` badges once a pull request is no longer open.
- Pull requests in the merge queue stay on the fast polling interval even when
  the panel is closed, and **Check now** refreshes merged pull requests and
  review lists immediately.

## 0.7.2

- Action status messages (such as `Watching #123 for this conversation.`) now
  appear directly below the **Watch a pull request** card at the top of the
  panel, and automatically clear when that pull request is no longer being
  watched.

## 0.7.1

- "Repositories to list" can be collapsed like the lists below it. Its
  heading says how many are ticked ("3 of 10"), and the panel remembers
  whether it was left open or closed. Errors and action results now show
  under it, so they are visible when it is closed.

## 0.7.0

- Two new lists under "Waiting on your review": **Your open pull requests**
  (everything you opened, anywhere on GitHub, drafts included) and **All
  open pull requests** (everyone's, in the repositories you have ticked).
  Each row has the same CI and conflict badges, and a Watch button that ties
  it to the conversation the panel is open in, or says it is already watched.
- The repository tick boxes now sit above the lists and apply to all three.
  They cover every repository seen in your review requests, your own pull
  requests and your watched ones. Ticking one reads the lists again at once.

## 0.6.1

- "Waiting on your review" shows merge conflicts as their own red
  "Conflicts" badge. Before, a conflicted pull request with passing CI showed
  only "Passing", and the missing buttons were the only hint.
- Approve and Approve & merge now need GitHub to have confirmed there is no
  conflict. While GitHub is still working that out, the row shows "Checking
  for conflicts" and no buttons.

## 0.6.0

- "Waiting on your review" rows get Approve and Approve & merge buttons, shown
  only once the pull request's pipeline is fully green (every check finished,
  none failed or cancelled, not already queued, no conflicts). Each needs a
  second click to confirm, and the panel re-reads the pull request and
  refuses if it is no longer green. Approve & merge turns on GitHub's
  auto-merge, which joins the merge queue where there is one; it never
  bypasses branch protection.

## 0.5.0

- Pull requests opened by a subagent, a delegated CLI such as `claude -p`, or
  a script can now be watched. The hook never sees those, so the plugin ships
  a standing instruction (`rules/AGENTS.md`) asking the agent to sign each one
  up with `GH_WATCH=1 gh pr view <number or URL> --json url --jq .url`. The
  hook recognises that command and the pull request is watched for the
  conversation that ran it. The panel marks these "added by the agent".

## 0.4.0

- Compact single-repo review list: when a single repository is selected in
  "Waiting on your review", the `org/repo` prefix is omitted from each row
  (showing `#123 Title` instead of `org/repo#123 Title`).
- Pipeline and merge-queue badges on review requests: each pull request in
  "Waiting on your review" displays its live CI status (`Passing`, `N running`,
  `N failing`) or merge queue position (`In merge queue #N`).

## 0.3.0

- Review status badge: shows whether a pull request is Approved, Changes requested,
  or Review required, falling back gracefully to latest reviews and review requests
  on branches without required review protection.
- Inline failure log drawer: expand any failing check in the side panel to view a
  cleaned failure excerpt directly, without opening GitHub Actions in a browser.
- One-click rerun for failed checks: rerun failed jobs directly from the card.

## 0.2.0

- "Waiting on your review" has a tick box per repository, so you can choose
  which repositories are listed. The choice is remembered. A repository that
  asks for your review for the first time is listed until you untick it.
- The list now reads up to 100 review requests instead of 20, and its heading
  shows how many are listed out of how many there are.
- The panel shows the plugin's version next to its title.
- Releases are now tagged. Each version in this file has a matching `v` tag
  and GitHub release, so an install can be pinned to one.

## 0.1.0

First public release.

- Watches pull requests and wakes the owning Antigravity conversation when a
  CI check starts failing: once per failing check per commit, waiting for
  related checks so failures arrive together.
- Reports merge conflicts, with up to three reminders.
- Passes on new review comments from collaborators and bots, marked as quoted
  text. Off by default.
- Follows a change after its checks pass: all green, merged, and whether the
  base branch's checks passed afterwards.
- Remembers flaky checks and tells the agent to re-run them before changing
  code.
- Starts watching a pull request automatically when an agent runs
  `gh pr create`.
- Side panel with per-pull-request switches, merge-queue position, GitHub
  auto-merge, pull requests waiting on your review, and settings for polling
  speed.
