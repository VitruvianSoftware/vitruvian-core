# worktree-band: git worktree and Bazel output-base hygiene

`worktree-band` tracks the linked git worktrees your conversations use,
monitors their GitHub pull request status and CI checks, measures the disk
space used by each worktree and its isolated Bazel output base, and reclaims
both once the pull request has merged cleanly into the default branch.

- When you start a session inside a linked git worktree, `worktree-band`
  automatically discovers the workspace via its `SessionStart` hook.
- Never force-remove a worktree (`git worktree remove --force`) or delete the
  shared Bazel cache root (`~/Library/Caches/bazel/_bazel_<user>` or
  `~/.cache/bazel/_bazel_<user>`). Only per-worktree output bases verified by
  `DO_NOT_BUILD_HERE` or `--output_user_root` are eligible for cleanup.
- Before cleaning up a merged worktree, ensure `git status --porcelain` is
  empty and `HEAD` matches the merged pull request's head commit.
