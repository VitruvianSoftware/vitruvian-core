# Changelog

All notable changes to gh-watch are recorded here.

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
