# `//tools/worktree` — isolated worktrees with per-worktree Bazel servers

This checkout is routinely shared across sessions and agents. If two of them do
branch work in the same working tree they stomp each other's `HEAD` and contend
on a single Bazel server / `output_base`. **Branch work must happen in a git
worktree** (issue #455).

This tool wraps `git worktree add` and — crucially — writes a gitignored
`user.bazelrc` into the new worktree pinning a unique `--output_user_root`, so
each worktree runs its own Bazel server and analysis cache instead of fighting
over the main checkout's.

## Usage

```sh
bazel run //tools/worktree -- <branch> [base-ref]   # create; base defaults to origin/main
bazel run //tools/worktree -- --list                # list worktrees
bazel run //tools/worktree -- --remove <branch>     # remove that worktree
```

Then `cd` into the printed path and work there.

## Notes

- The parent directory for worktrees defaults to `<repo-parent>/<repo>-worktrees`;
  override with the `WORKTREE_ROOT` environment variable.
- The generated `user.bazelrc` is picked up via `.bazelrc`'s
  `try-import %workspace%/user.bazelrc` and is never committed (`user.bazelrc` is
  gitignored). Edit or delete it freely.
- `--remove` deletes the worktree but keeps the branch (`git branch -D <branch>`
  to drop the branch too).
