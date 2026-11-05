---
name: worktree-band
description: Inspect and clean up linked git worktrees and isolated Bazel output bases using the worktree-band Antigravity plugin. Use when checking worktree disk usage, verifying whether a merged feature branch worktree is safe to remove, or reclaiming Bazel output-base disk space.
---

# worktree-band

Use this skill when working with the `worktree-band` Antigravity desktop plugin
to inspect linked git worktrees, pull request status, Bazel output-base disk
usage, and post-merge cleanup readiness.

## How `worktree-band` works

1. **Discovery**: The `SessionStart` hook (`hooks/session-worktree.sh`) drops a
   note in `~/.gemini/antigravity/worktree-band-inbox/` containing the session's
   `conversationId` and `workspacePaths`. You can also register a worktree path
   directly from the Worktree Band side panel (`/api/track`).
2. **Inspection**: For each tracked worktree, the sidecar checks:
   - `git rev-parse --path-format=absolute --show-toplevel --git-common-dir HEAD`
   - `git symbolic-ref --short -q HEAD`
   - `gh pr view <branch> --json number,state,url,baseRefName,headRefOid,isDraft,statusCheckRollup`
   - `du -sk` on the worktree and its isolated Bazel output bases.
3. **Safe cleanup**: A worktree is only `ready` when its PR is `MERGED` into the
   default branch, it is a linked worktree (`isLinked: true`), `git status --porcelain`
   is empty, and `HEAD` matches the PR's `headRefOid`.
