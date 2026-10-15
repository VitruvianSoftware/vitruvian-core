# `//tools/worktree` — isolated worktrees with per-worktree Bazel servers

This checkout is routinely shared across sessions and agents. If two of them do
branch work in the same working tree they stomp each other's `HEAD` and contend
on a single Bazel server / `output_base`. **Branch work must happen in a git
worktree** (issue #455).

This tool wraps `git worktree add` and — crucially — writes a gitignored
`user.bazelrc` into the new worktree pinning a unique `--output_user_root`, so
each worktree runs its own Bazel server and analysis cache instead of fighting
over the main checkout's. It also removes worktrees again, but only when that
cannot lose work.

## Usage

```sh
bazel run //tools/worktree -- <branch> [base-ref]   # create; base defaults to origin/main
bazel run //tools/worktree -- --list                # list worktrees
bazel run //tools/worktree -- --remove <branch>     # remove that worktree (branch kept)
bazel run //tools/worktree -- --remove <branch> --force          # ...with its uncommitted files
bazel run //tools/worktree -- --remove <branch> --delete-branch  # ...and its branch, if clean AND landed
bazel run //tools/worktree -- --prune               # dry run: what would go, what stays and why
bazel run //tools/worktree -- --prune --execute     # remove them, with their branches
```

Then `cd` into the printed path and work there.

## What `--prune` removes

A worktree goes only when **every** one of these holds. Anything else is kept,
and the dry run prints the reason next to it.

| Kept when… | Why |
|---|---|
| it is the primary checkout, or the worktree you ran the command from | never removed |
| it is locked (`git worktree lock`) | somebody's work in progress; the lock reason is shown |
| it has uncommitted or untracked files | unsaved work |
| a Bazel server is running for it | it is in use |
| its branch has no commits of its own yet | almost always a worktree that was just made |
| `//tools/landed -- --branch <branch>` says it is not landed | commits that are not on `origin/main` |
| it is detached, or its directory is missing | nothing to check against |

"Landed" means every commit on the **local** branch is on `origin/main`: the
branch is behind main, or merging it into main would change nothing (this is
what survives a squash merge), or its PR merged and the local branch has nothing
past the PR's head. A branch whose PR merged but which then got more local
commits is **not** landed.

`--execute` re-checks each worktree just before removing it.

## Notes

- The parent directory for worktrees defaults to `<repo-parent>/<repo>-worktrees`;
  override with the `WORKTREE_ROOT` environment variable.
- Run from the primary checkout or from inside any worktree: paths always come
  from the primary checkout. A worktree is never removed by a command run from
  inside it; run that from the primary checkout.
- The generated `user.bazelrc` is picked up via `.bazelrc`'s
  `try-import %workspace%/user.bazelrc` and is never committed (`user.bazelrc` is
  gitignored). Edit or delete it freely.
- The per-worktree output root (`~/.cache/bazel/worktrees/<repo>-<branch>`) gets a
  `.vitruvian-worktree` file naming the worktree. `//tools/bazel-cache:gc` uses
  it to tell an orphaned root from a live one.
- Removing a worktree first stops its Bazel server in **both** places it can
  have one (the default output root and its own), then deletes its own output root.
- `--remove` finds the worktree by the branch checked out in it, so it works
  for a worktree made by hand under any directory name. It exits non-zero and
  removes nothing when no worktree has that branch.
- `--remove` keeps a worktree that has uncommitted or untracked files, and lists
  them. `--remove <branch> --force` removes it with them. `--delete-branch` never
  does: it needs a clean worktree. A locked worktree is kept either way: unlock
  it first.
- Without `--delete-branch`, `--remove` keeps the branch.
