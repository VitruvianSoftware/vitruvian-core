# `//tools/git` — commit, push and sync for agents

Agents are about to be blocked from running `git commit`, `git push`,
`git rebase` and the other git writes directly. These three targets replace
them. Each one does the write and the checks that should come with it, and
every refusal prints the command to run instead.

Run them from inside your worktree (made with `//tools/worktree`), never the
main checkout.

```sh
bazel run //tools/git:commit -- --agent <you> -m "fix(scope): what changed" <paths>...
bazel run //tools/git:push -- --agent <you>
bazel run //tools/git:sync                                # catch up with main
```

## Commit

```sh
bazel run //tools/git:commit -- -m "feat(x): add y" path/a path/b
bazel run //tools/git:commit -- -m "feat(x): add y" -m "Co-Authored-By: ..." --all
bazel run //tools/git:commit -- -F message.txt <paths>...
bazel run //tools/git:commit -- --fixup <sha> <paths>...   # fold in later: sync --autosquash
bazel run //tools/git:commit -- --agent <you> ...          # commit as your agent's bot
bazel run //tools/git:commit                               # during a merge: finish it
```

It stages the paths you name, or everything with `--all`. Paths and `-F` files
are relative to the directory you ran it from. Pass your own trailers as extra
`-m` paragraphs.

It refuses when:

- you are on `main`, on a detached HEAD, or in the main checkout (it also
  says how to carry edits across: `git diff HEAD --binary > /tmp/wip.patch`
  there, then `git apply /tmp/wip.patch` in the new worktree);
- a rebase is in progress;
- nothing is staged;
- there is no message, or the first line is neither a
  [Conventional Commit](../../CONTRIBUTING.md) (`fix(scope): …`) nor a
  revert's own `Revert "<title>"` (what `git revert` and GitHub write);
- the secret scan (`//tools/secret-scan -- --staged`) finds something. It
  names the file and line, never the secret, and nothing is committed;
- `--fixup` names a commit that is not on this branch, or is already on `main`.

`--amend` and `--no-verify` are not offered. Use `--fixup` and
`sync --autosquash` to change an earlier commit.

**Finishing a merge.** With a merge in progress (after `sync --merge`), running
it with no paths and no `--all` concludes the merge with git's merge message.
Naming the fixed files stages them and concludes in one step. git's
`# Conflicts:` notes are stripped from the message. Either way it
refuses while any file is still unmerged, or while a file both sides changed
still holds `<<<<<<<` / `>>>>>>>` markers (it names the file and line), and the
secret scan still runs.

**Who the commit is from.** `--agent <name>` makes that agent's GitHub App bot
the author and the committer. It asks `//tools/agent-app -- env <name>` (the same
lookup push uses) and keeps only the identity, not the token. Without it, the
commit is from whoever `GIT_AUTHOR_*`/`GIT_COMMITTER_*` or git config say, which
for an agent that skipped this is the machine owner. It prints the author after
each commit and says so when it is not an agent's bot.

## Push

```sh
bazel run //tools/git:push                          # push this branch, set its upstream
bazel run //tools/git:push -- --agent <name>        # push as that agent's GitHub App
bazel run //tools/git:push -- --force-with-lease    # after sync rewrote the branch
bazel run //tools/git:push -- --dry-run
```

It always pushes the current branch to `origin` under the same name, with an
explicit refspec, so it cannot write anywhere else, and with `--no-follow-tags`,
so `push.followTags` cannot send tags along. It never pushes `main`.
Plain `--force` is refused. `--force-with-lease` (with `--force-if-includes`)
only overwrites what you last fetched.

Before pushing, it scans the commits `origin` does not have yet for secrets.

`--agent <name>` runs `//tools/agent-app`'s public `env <name>` command for this
worktree and pushes with the token it returns. Keys are found exactly the way
agent-app finds them (including `AGENT_KEY_DIR`); this tool has no lookup of
its own.

## Sync

```sh
bazel run //tools/git:sync                   # fetch, rebase onto origin/main
bazel run //tools/git:sync -- --autosquash   # ...and fold in --fixup commits
bazel run //tools/git:sync -- --autosquash --keep-base  # fold them in where the branch is; main stays out
bazel run //tools/git:sync -- --merge        # merge origin/main in; no force-push needed after
bazel run //tools/git:sync -- --abort        # give up an unfinished merge or rebase
```

It refuses when tracked files have uncommitted changes. It **never stashes**:
the stash is shared by every worktree, so another session could pop yours.
Untracked files are fine; git stops on its own if one would be overwritten.

- **Rebase** (the default): on a conflict the rebase is undone, your branch is
  exactly as it was, and the conflicting files are listed. If the branch was
  already pushed, it tells you to push with `--force-with-lease`. A branch that
  has merge commits since `origin/main` (from `--merge`) is never rebased, since
  that would quietly drop them: it refuses and points you to `--merge`.
- **`--merge`**: for a branch that is already pushed and should not be
  force-pushed. On a conflict the merge is left in progress. It lists the files
  and prints how to finish (`bazel run //tools/git:commit -- <files>`) or give
  up (`bazel run //tools/git:sync -- --abort`).
- **`--keep-base`**: rewrite the branch where it stands, without bringing in
  newer main. Use it with `--autosquash` when main now conflicts with the
  commit you are fixing up: autosquash replays that commit before its fixups,
  so it would hit the conflict first. Fold in place, then run a plain `sync`.
- On `main` it refuses and points at `git pull --ff-only`.

## Tests

`bazel test //tools/git:git_test` (and `//tools/git:git-rs_test`,
`//tools/git:git-rs-parity_test`) drives all three in throwaway repos, with a
bare repo as `origin`, the real pinned gitleaks and a fake agent-app. It never
touches this repository.

Deliberate `KEEP-SAFE` differences in the Rust port (`src/lib.rs`) over `git.sh`:
- `--agent` parses `export KEY=VALUE` lines from `agent-app.sh env` rather than running shell `eval`.
- Conflict-marker detection during merge commits prepends literal file paths instead of `sed "s|^|${f}:|"`, so markers in files named with `|` or `&` are still caught and reported literally.
- Runfiles resolution matches `runfiles.bash` lookup order without exporting bash shell functions (`BASH_FUNC_rlocation%%`), `_RLOCATION_*`, or `RUNFILES_REPO_MAPPING` into child environments.
