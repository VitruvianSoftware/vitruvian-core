# Changelog

All notable changes to gh-watch are recorded here.

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
