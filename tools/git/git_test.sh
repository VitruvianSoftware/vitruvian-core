#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# git_test.sh — //tools/git:commit, :push and :sync do the write they promise
# and refuse every one they must, each refusal naming the command to use
# instead. Throwaway repos with a bare repo as origin, the real pinned gitleaks
# (found through runfiles, as under `bazel run`) and a fake agent-app.
set -uo pipefail

SCRIPT="${UNDER_TEST:-${1:?usage: git_test.sh <git.sh>}}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=t@t
git config --global init.defaultBranch main
git config --global advice.detachedHead false

SECRET="Zq8Lm3Rt""7Vx2Kp9W""n4Hs6Jd1""Fg5Bc0Ya" # see secret-scan_test.sh
plant() { printf 'first line\napi_token = "%s"\n' "$SECRET" >"$1"; }

# A fake //tools/agent-app: records how it was called, prints the exports the
# real `env` command prints, fails for an unknown agent.
cat >"$work/agent-app.sh" <<'FAKE'
#!/usr/bin/env bash
printf '%s|%s\n' "$*" "$BUILD_WORKSPACE_DIRECTORY" >>"$FAKE_AGENT_LOG"
[ "$1" = env ] && [ "$2" = wren ] || { echo "agent-app: unknown agent '$2'" >&2; exit 1; }
echo "export GH_TOKEN=token-for-wren"
echo "export GIT_AUTHOR_NAME='vitruvian-wren-agent[bot]'"
echo "export GIT_AUTHOR_EMAIL='4521094+vitruvian-wren-agent[bot]@users.noreply.github.com'"
echo "export GIT_COMMITTER_NAME='vitruvian-wren-agent[bot]'"
echo "export GIT_COMMITTER_EMAIL='4521094+vitruvian-wren-agent[bot]@users.noreply.github.com'"
FAKE
export AGENT_APP="$work/agent-app.sh" FAKE_AGENT_LOG="$work/agent-app.log"

# origin (bare), the primary checkout, and "other": someone else pushing to main.
git init -q --bare "$work/origin.git"
git clone -q "$work/origin.git" "$work/repo" 2>/dev/null
repo="$work/repo"
printf 'one\ntwo\nthree\n' >"$repo/shared.txt"
git -C "$repo" add shared.txt
git -C "$repo" commit -q -m "chore: base"
git -C "$repo" push -q origin main
git clone -q "$work/origin.git" "$work/other"
other_push_main() { # <file> <content>: someone else lands a commit on main
    printf '%s\n' "$2" >"$work/other/$1"
    git -C "$work/other" add "$1"
    git -C "$work/other" commit -q -m "chore: $1 from main"
    git -C "$work/other" push -q origin main
}

run_subject() {
    case "$SCRIPT" in
        *.sh) bash "$SCRIPT" "$@" ;;
        *) "$SCRIPT" "$@" ;;
    esac
}
# run <worktree> <command> [args...]: the target, as `bazel run` starts it.
run() {
    local wt="$1"; shift
    (cd "$work" && BUILD_WORKSPACE_DIRECTORY="$wt" BUILD_WORKING_DIRECTORY="${WDIR:-$wt}" run_subject "$@")
}
head_of() { git -C "$1" rev-parse HEAD; }
on_origin() { git -C "$work/origin.git" rev-parse --verify --quiet "refs/heads/$1"; }

wt="$work/wt-a"
git -C "$repo" worktree add -q -b feat/a "$wt" origin/main 2>/dev/null

echo "commit"
# C1. The primary checkout is refused, with the worktree command to use.
echo x >"$repo/x.txt"
out="$(run "$repo" commit -m "feat: x" x.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "main checkout" <<<"$out" && grep -q "bazel run //tools/worktree" <<<"$out" && grep -q "git diff HEAD --binary > /tmp/wip.patch" <<<"$out" && grep -q "git apply /tmp/wip.patch" <<<"$out" && [ -z "$(git -C "$repo" diff --cached --name-only)" ]; then
    pass "refuses in the main checkout and names //tools/worktree"
else
    fail "refuses in the main checkout and names //tools/worktree -- output: $out"
fi
rm -f "$repo/x.txt"

# C2. main, even in a linked worktree, is refused; so is a detached HEAD.
git clone -q "$work/origin.git" "$work/repo2"
git -C "$work/repo2" checkout -q -b elsewhere
git -C "$work/repo2" worktree add -q "$work/wt-main" main
echo y >"$work/wt-main/y.txt"
out="$(run "$work/wt-main" commit -m "feat: y" y.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "this is main" <<<"$out"; then
    pass "refuses on main in a worktree"
else
    fail "refuses on main in a worktree -- output: $out"
fi
git -C "$repo" worktree add -q --detach "$work/wt-detached" origin/main
echo z >"$work/wt-detached/z.txt"
out="$(run "$work/wt-detached" commit -m "feat: z" z.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "detached" <<<"$out" && grep -q "//tools/worktree" <<<"$out"; then
    pass "refuses on a detached HEAD and names //tools/worktree"
else
    fail "refuses on a detached HEAD and names //tools/worktree -- output: $out"
fi

# C3. Nothing staged; no message; not a Conventional Commit; a bad flag.
out="$(run "$wt" commit -m "feat: nothing" 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "nothing is staged" <<<"$out" && grep -q "bazel run //tools/git:commit -- -m" <<<"$out"; then
    pass "refuses with nothing staged and shows how to name paths"
else
    fail "refuses with nothing staged and shows how to name paths -- output: $out"
fi
echo a >"$wt/a.txt"
out="$(run "$wt" commit a.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "message is required" <<<"$out"; then
    pass "refuses without a message and shows one"
else
    fail "refuses without a message and shows one -- output: $out"
fi
out="$(run "$wt" commit -m "added a file" a.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "Conventional Commit" <<<"$out" && grep -q "fix(worktree)" <<<"$out"; then
    pass "refuses a message that is not a Conventional Commit"
else
    fail "refuses a message that is not a Conventional Commit -- output: $out"
fi
out="$(run "$wt" commit --amend 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q -- "--fixup" <<<"$out"; then
    pass "refuses --amend and offers --fixup"
else
    fail "refuses --amend and offers --fixup -- output: $out"
fi
out="$(run "$wt" commit --bogus 2>&1)"; rc=$?
if [ $rc -eq 2 ]; then
    pass "an unknown flag is a usage error"
else
    fail "an unknown flag is a usage error -- output: $out"
fi

# C4. The happy path: only the named path, the caller's trailer kept.
echo b >"$wt/b.txt"
out="$(run "$wt" commit -m "feat(a): add a" -m "Co-Authored-By: Someone <s@example.com>" a.txt 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(git -C "$wt" show --name-only --format= HEAD)" = a.txt ] && git -C "$wt" log -1 --format=%B | grep -q "^Co-Authored-By: Someone" && [ -n "$(git -C "$wt" status --porcelain b.txt)" ]; then
    pass "commits only the named path, with the caller's trailer"
else
    fail "commits only the named path, with the caller's trailer -- output: $out"
fi
if grep -q "committed .* on feat/a" <<<"$out" && grep -q "bazel run //tools/git:push" <<<"$out"; then
    pass "says what it committed and what to run next"
else
    fail "says what it committed and what to run next -- output: $out"
fi
if grep -q "not an agent's bot" <<<"$out" && grep -q -- "--agent <name>" <<<"$out"; then
    pass "without --agent, notes the author is not an agent's bot"
else
    fail "without --agent, notes the author is not an agent's bot -- output: $out"
fi

# C4b. A revert's own title, as git and GitHub's Revert button write it.
echo r >"$wt/r.txt"
out="$(run "$wt" commit -m 'Revert "fix: x (#12)"' r.txt 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(git -C "$wt" log -1 --format=%s)" = 'Revert "fix: x (#12)"' ]; then
    pass "accepts a Revert \"<title>\" message"
else
    fail "accepts a Revert \"<title>\" message -- output: $out"
fi
echo r2 >>"$wt/r.txt"
out="$(run "$wt" commit -m 'Revert fix x' r.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "Conventional Commit" <<<"$out"; then
    pass "still refuses an unquoted Revert title"
else
    fail "still refuses an unquoted Revert title -- output: $out"
fi
git -C "$wt" checkout -q -- r.txt

# C4c. --agent: author AND committer are the agent's bot, via agent-app env.
echo w >"$wt/w.txt"
: >"$FAKE_AGENT_LOG"
out="$(run "$wt" commit --agent wren -m "feat(a): as wren" w.txt 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(git -C "$wt" log -1 --format='%an|%cn')" = "vitruvian-wren-agent[bot]|vitruvian-wren-agent[bot]" ] && [ "$(git -C "$wt" log -1 --format=%ae)" = "4521094+vitruvian-wren-agent[bot]@users.noreply.github.com" ] && grep -qx "env wren|$wt" "$FAKE_AGENT_LOG" && ! grep -q "not an agent" <<<"$out"; then
    pass "--agent wren commits as wren's bot (author and committer), via agent-app env"
else
    fail "--agent wren commits as wren's bot (author and committer), via agent-app env -- output: $out"
fi
before="$(head_of "$wt")"
echo w2 >"$wt/w2.txt"
out="$(run "$wt" commit --agent nobody -m "feat(a): as nobody" w2.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ "$(head_of "$wt")" = "$before" ] && grep -q "unknown agent" <<<"$out" && [ -z "$(git -C "$wt" diff --cached --name-only)" ]; then
    pass "--agent with an unknown name is refused before anything is staged or committed"
else
    fail "--agent with an unknown name is refused before anything is staged or committed -- output: $out"
fi
rm -f "$wt/w2.txt"

# C5. Paths are relative to where the command was run.
mkdir -p "$wt/sub"; echo c >"$wt/sub/c.txt"
out="$(WDIR="$wt/sub" run "$wt" commit -m "feat(a): add c" c.txt 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(git -C "$wt" show --name-only --format= HEAD)" = sub/c.txt ]; then
    pass "a path is read relative to the directory it was run from"
else
    fail "a path is read relative to the directory it was run from -- output: $out"
fi

# C6. --all stages new files and deletions; -F reads a message file.
git -C "$wt" rm -q --cached sub/c.txt >/dev/null; rm -f "$wt/sub/c.txt"
printf 'docs(a): from a file\n\nBody line.\n' >"$work/msg.txt"
out="$(run "$wt" commit -F "$work/msg.txt" --all 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(git -C "$wt" log -1 --format=%s)" = "docs(a): from a file" ] && git -C "$wt" show --name-status --format= HEAD | grep -q "^A.*b.txt" && git -C "$wt" show --name-status --format= HEAD | grep -q "^D.*sub/c.txt"; then
    pass "--all stages new files and deletions; -F reads the message"
else
    fail "--all stages new files and deletions; -F reads the message -- output: $out"
fi

# C7. A staged secret: refused, file and line named, the secret never printed.
before="$(head_of "$wt")"
plant "$wt/leak.txt"
out="$(run "$wt" commit -m "feat(a): add config" leak.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ "$(head_of "$wt")" = "$before" ] && grep -q "leak.txt:2" <<<"$out" && grep -q "secret scan did not pass" <<<"$out"; then
    pass "a secret in the staged change is refused and nothing is committed"
else
    fail "a secret in the staged change is refused and nothing is committed -- output: $out"
fi
if ! grep -qF "$SECRET" <<<"$out"; then
    pass "the secret itself is never printed"
else
    fail "the secret itself is never printed -- output: $out"
fi
git -C "$wt" rm -q --cached leak.txt; rm -f "$wt/leak.txt"

# C7b. A tracked file in an ignored folder (.claude/settings.json under
# .claude/) commits by name; a new file there is still refused.
printf '.hidden/\n' >"$wt/.gitignore"
mkdir -p "$wt/.hidden"; echo one >"$wt/.hidden/settings.json"
git -C "$wt" add .gitignore && git -C "$wt" add -f .hidden/settings.json && git -C "$wt" commit -q -m "chore(a): hidden settings"
echo two >"$wt/.hidden/settings.json"
out="$(run "$wt" commit -m "fix(a): change hidden settings" .hidden/settings.json 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(git -C "$wt" show --name-only --format= HEAD)" = .hidden/settings.json ]; then
    pass "a tracked file in an ignored folder commits by name"
else
    fail "a tracked file in an ignored folder commits by name -- output: $out"
fi
before="$(head_of "$wt")"
echo new >"$wt/.hidden/new.json"
out="$(run "$wt" commit -m "feat(a): add hidden file" .hidden/new.json 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ "$(head_of "$wt")" = "$before" ] && [ -z "$(git -C "$wt" diff --cached --name-only)" ]; then
    pass "a new file in an ignored folder is still refused"
else
    fail "a new file in an ignored folder is still refused -- output: $out"
fi
rm -f "$wt/.hidden/new.json"

# C8. --fixup: a fixup! commit for a commit on this branch; never one on main.
target="$(git -C "$wt" log --format=%H --grep='^feat(a): add a$' -1)"
echo a2 >>"$wt/a.txt"
out="$(run "$wt" commit --fixup "$target" a.txt 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(git -C "$wt" log -1 --format=%s)" = "fixup! feat(a): add a" ] && grep -q "sync -- --autosquash" <<<"$out"; then
    pass "--fixup makes a fixup! commit and says to fold it in with sync --autosquash"
else
    fail "--fixup makes a fixup! commit and says to fold it in with sync --autosquash -- output: $out"
fi
echo a3 >>"$wt/a.txt"
out="$(run "$wt" commit --fixup origin/main a.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "already on origin/main" <<<"$out"; then
    pass "--fixup of a commit already on main is refused"
else
    fail "--fixup of a commit already on main is refused -- output: $out"
fi
git -C "$wt" checkout -q -- a.txt; git -C "$wt" reset -q

echo "sync"
# S1. Local changes: refused, and nothing is stashed.
echo dirty >>"$wt/shared.txt"
out="$(run "$wt" sync 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "never stashes" <<<"$out" && [ -z "$(git -C "$wt" stash list)" ] && grep -q dirty "$wt/shared.txt" && grep -q "bazel run //tools/git:commit" <<<"$out"; then
    pass "refuses with uncommitted changes and never stashes"
else
    fail "refuses with uncommitted changes and never stashes -- output: $out"
fi
git -C "$wt" checkout -q -- shared.txt

# S2. --autosquash folds the fixup in while rebasing onto a newer main.
other_push_main main1.txt "from main"
n_before="$(git -C "$wt" rev-list --count origin/main..HEAD)"
out="$(run "$wt" sync --autosquash 2>&1)"; rc=$?
if [ $rc -eq 0 ] && git -C "$wt" merge-base --is-ancestor origin/main HEAD && [ -f "$wt/main1.txt" ] && [ "$(git -C "$wt" rev-list --count origin/main..HEAD)" -eq $((n_before - 1)) ] && ! git -C "$wt" log --format=%s origin/main..HEAD | grep -q "^fixup!" && grep -q a2 "$wt/a.txt"; then
    pass "rebases onto the new origin/main and folds the fixup in"
else
    fail "rebases onto the new origin/main and folds the fixup in -- output: $out"
fi

# S2b. --autosquash --keep-base folds fixups in without bringing in new main.
echo k1 >"$wt/k.txt"
run "$wt" commit -m "feat(a): add k" k.txt >/dev/null 2>&1
echo k2 >"$wt/k.txt"
run "$wt" commit --fixup "$(head_of "$wt")" k.txt >/dev/null 2>&1
base_before="$(git -C "$wt" merge-base HEAD origin/main)"
other_push_main k-main.txt "main moved on"
out="$(run "$wt" sync --autosquash --keep-base 2>&1)"; rc=$?
if [ $rc -eq 0 ] && ! git -C "$wt" log --format=%s origin/main..HEAD | grep -q "^fixup!" && [ "$(cat "$wt/k.txt")" = k2 ] && [ "$(git -C "$wt" merge-base HEAD origin/main)" = "$base_before" ] && [ ! -f "$wt/k-main.txt" ] && grep -q "was not brought in" <<<"$out"; then
    pass "--autosquash --keep-base folds the fixup in and leaves the base where it was"
else
    fail "--autosquash --keep-base folds the fixup in and leaves the base where it was -- output: $out"
fi
out="$(run "$wt" sync --merge --keep-base 2>&1)"; rc=$?
if [ $rc -eq 2 ]; then
    pass "--keep-base with --merge is a usage error"
else
    fail "--keep-base with --merge is a usage error -- output: $out"
fi

# S3. A rebase conflict is undone and the files listed, with --merge offered.
printf 'one\nTWO from branch\nthree\n' >"$wt/shared.txt"
out="$(run "$wt" commit -m "fix(a): change two" shared.txt 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then
    pass "(setup) commits a change to shared.txt"
else
    fail "(setup) commits a change to shared.txt -- output: $out"
fi
other_push_main shared.txt "$(printf 'one\nTWO from main\nthree')"
git -C "$wt" fetch -q origin
git -C "$wt" rebase -q origin/main >/dev/null 2>&1   # a by-hand rebase, stopped on the conflict
out="$(run "$wt" commit -m "fix(a): mid-rebase" shared.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "a rebase is in progress" <<<"$out" && ! grep -q "detached" <<<"$out" && grep -q "sync -- --abort" <<<"$out"; then
    pass "during a rebase, commit says a rebase is in progress (not 'detached')"
else
    fail "during a rebase, commit says a rebase is in progress (not 'detached') -- output: $out"
fi
out="$(run "$wt" sync --abort 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(git -C "$wt" symbolic-ref --short HEAD)" = feat/a ]; then
    pass "--abort drops an unfinished rebase"
else
    fail "--abort drops an unfinished rebase -- output: $out"
fi
before="$(head_of "$wt")"
out="$(run "$wt" sync 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ "$(head_of "$wt")" = "$before" ] && [ ! -d "$(git -C "$wt" rev-parse --git-path rebase-merge)" ] && grep -q "^    shared.txt" <<<"$out" && grep -q "sync -- --merge" <<<"$out" && [ -z "$(git -C "$wt" status --porcelain --untracked-files=no)" ]; then
    pass "a rebase conflict is undone, the files listed, and --merge offered"
else
    fail "a rebase conflict is undone, the files listed, and --merge offered -- output: $out"
fi

# S4. --merge with a conflict: left in progress, files and both ways out named.
out="$(run "$wt" sync --merge 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ -f "$(git -C "$wt" rev-parse --git-path MERGE_HEAD)" ] && grep -q "^    shared.txt" <<<"$out"; then
    pass "--merge leaves a conflicted merge in progress and lists the files"
else
    fail "--merge leaves a conflicted merge in progress and lists the files -- output: $out"
fi
if grep -q "bazel run //tools/git:commit -- shared.txt\$" <<<"$out" && grep -q "bazel run //tools/git:sync -- --abort" <<<"$out" && ! grep -q "git add" <<<"$out" && ! grep -q "git merge --abort" <<<"$out"; then
    pass "--merge names how to finish and give up, with the targets, not raw git"
else
    fail "--merge names how to finish and give up, with the targets, not raw git -- output: $out"
fi

# C9. Concluding: unresolved files, then leftover markers, are refused.
out="$(run "$wt" commit 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "still have merge conflicts" <<<"$out" && grep -q "commit -- shared.txt" <<<"$out" && [ -f "$(git -C "$wt" rev-parse --git-path MERGE_HEAD)" ]; then
    pass "commit refuses to conclude while files are still unmerged"
else
    fail "commit refuses to conclude while files are still unmerged -- output: $out"
fi
out="$(run "$wt" commit -- shared.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "conflict markers" <<<"$out" && grep -qE "shared.txt:[0-9]+" <<<"$out" && [ -f "$(git -C "$wt" rev-parse --git-path MERGE_HEAD)" ]; then
    pass "commit refuses a file staged with its conflict markers, naming file:line"
else
    fail "commit refuses a file staged with its conflict markers, naming file:line -- output: $out"
fi

# C10. Concluding still runs the secret scan.
{ printf 'one\nTWO from both\nthree\n'; printf 'api_token = "%s"\n' "$SECRET"; } >"$wt/shared.txt"
out="$(run "$wt" commit -- shared.txt 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "shared.txt:4" <<<"$out" && [ -f "$(git -C "$wt" rev-parse --git-path MERGE_HEAD)" ]; then
    pass "concluding a merge still runs the secret scan"
else
    fail "concluding a merge still runs the secret scan -- output: $out"
fi

# C11. Resolved, then staged by hand (the documented two-step), then concluded.
printf 'one\nTWO from both\nthree\n' >"$wt/shared.txt"
git -C "$wt" add shared.txt
out="$(run "$wt" commit 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ ! -f "$(git -C "$wt" rev-parse --git-path MERGE_HEAD)" ] && [ "$(git -C "$wt" rev-list --parents -n1 HEAD | wc -w | tr -d " ")" = 3 ] && git -C "$wt" log -1 --format=%s | grep -q "^Merge"; then
    pass "commit with no paths concludes the merge as a two-parent commit"
else
    fail "commit with no paths concludes the merge as a two-parent commit -- output: $out"
fi
if ! git -C "$wt" log -1 --format=%B | grep -qi "conflicts"; then
    pass "the merge message has no '# Conflicts:' notes (--cleanup=strip)"
else
    fail "the merge message kept its conflict notes: $(git -C "$wt" log -1 --format=%B)"
fi

# S5. --merge with no conflict; then --abort on a fresh conflict.
other_push_main main2.txt "more from main"
out="$(run "$wt" sync --merge 2>&1)"; rc=$?
if [ $rc -eq 0 ] && git -C "$wt" merge-base --is-ancestor origin/main HEAD && [ -f "$wt/main2.txt" ]; then
    pass "--merge without conflicts merges origin/main in"
else
    fail "--merge without conflicts merges origin/main in -- output: $out"
fi
printf 'one\nTWO again on branch\nthree\n' >"$wt/shared.txt"
run "$wt" commit -m "fix(a): again" shared.txt >/dev/null 2>&1
other_push_main shared.txt "$(printf 'one\nTWO again on main\nthree')"
run "$wt" sync --merge >/dev/null 2>&1
before="$(git -C "$wt" rev-parse ORIG_HEAD)"
out="$(run "$wt" sync --abort 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ ! -f "$(git -C "$wt" rev-parse --git-path MERGE_HEAD)" ] && [ "$(head_of "$wt")" = "$before" ] && [ -z "$(git -C "$wt" status --porcelain --untracked-files=no)" ]; then
    pass "--abort drops an unfinished merge"
else
    fail "--abort drops an unfinished merge -- output: $out"
fi
before="$(head_of "$wt")"
out="$(run "$wt" sync 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ "$(head_of "$wt")" = "$before" ] && grep -q "merge commit" <<<"$out" && grep -q "bazel run //tools/git:sync -- --merge" <<<"$out"; then
    pass "a plain sync on a branch with merge commits is refused and points to --merge"
else
    fail "a plain sync on a branch with merge commits is refused and points to --merge -- output: $out"
fi
out="$(run "$wt" sync --autosquash 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ "$(head_of "$wt")" = "$before" ]; then
    pass "so is sync --autosquash"
else
    fail "so is sync --autosquash -- output: $out"
fi
out="$(run "$wt" sync --merge --autosquash 2>&1)"; rc=$?
if [ $rc -eq 2 ]; then
    pass "--merge with --autosquash is a usage error"
else
    fail "--merge with --autosquash is a usage error -- output: $out"
fi

# S6. main only fast-forwards.
out="$(run "$work/wt-main" sync 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "git pull --ff-only" <<<"$out"; then
    pass "sync on main is refused and names git pull --ff-only"
else
    fail "sync on main is refused and names git pull --ff-only -- output: $out"
fi

echo "push"
# P1. Push the branch and set its upstream.
git -C "$wt" reset -q --hard "$(git -C "$wt" rev-parse HEAD)"
git -C "$repo" config push.followTags true
git -C "$wt" tag -a v9.9.9 -m "a tag" HEAD
out="$(run "$wt" push 2>&1)"; rc=$?
if [ -z "$(git -C "$work/origin.git" tag -l)" ] && ! grep -q "new tag" <<<"$out"; then
    pass "with push.followTags=true, no tag is pushed"
else
    fail "with push.followTags=true, no tag is pushed -- output: $out"
fi

if [ $rc -eq 0 ] && [ "$(on_origin feat/a)" = "$(head_of "$wt")" ] && [ "$(git -C "$wt" rev-parse --abbrev-ref "@{u}")" = origin/feat/a ]; then
    pass "pushes the branch under its own name and sets the upstream"
else
    fail "pushes the branch under its own name and sets the upstream -- output: $out"
fi

# P2. Plain force is never offered; a branch or remote argument is refused.
for f in --force -f --force=x; do
    out="$(run "$wt" push "$f" 2>&1)"; rc=$?
    if [ $rc -eq 1 ] && grep -q "bazel run //tools/git:push -- --force-with-lease" <<<"$out"; then
        pass "push $f is refused and names --force-with-lease"
    else
        fail "push $f is refused and names --force-with-lease -- output: $out"
    fi
done
out="$(run "$wt" push origin main 2>&1)"; rc=$?
if [ $rc -eq 2 ]; then
    pass "push takes no branch or remote argument"
else
    fail "push takes no branch or remote argument -- output: $out"
fi

# P3. After a history rewrite: a plain push is rejected, --force-with-lease works.
pushed="$(on_origin feat/a)"
git -C "$wt" commit -q --amend -m "fix(a): again, reworded"
out="$(run "$wt" push 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ "$(on_origin feat/a)" = "$pushed" ] && grep -q -- "--force-with-lease" <<<"$out"; then
    pass "a rewritten branch is rejected without --force-with-lease, which is named"
else
    fail "a rewritten branch is rejected without --force-with-lease, which is named -- output: $out"
fi
out="$(run "$wt" push --force-with-lease 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(on_origin feat/a)" = "$(head_of "$wt")" ]; then
    pass "--force-with-lease publishes the rewritten branch"
else
    fail "--force-with-lease publishes the rewritten branch -- output: $out"
fi

# P4. main is never pushed.
main_before="$(on_origin main)"
git -C "$work/wt-main" add y.txt; git -C "$work/wt-main" commit -q -m "feat: y"
out="$(run "$work/wt-main" push 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ "$(on_origin main)" = "$main_before" ] && grep -q "this is main" <<<"$out"; then
    pass "never pushes main"
else
    fail "never pushes main -- output: $out"
fi

# P5. A secret in a commit not yet on origin blocks the push.
plant "$wt/leak.txt"
git -C "$wt" add leak.txt; git -C "$wt" commit -q -m "feat(a): oops"
pushed="$(on_origin feat/a)"
out="$(run "$wt" push 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ "$(on_origin feat/a)" = "$pushed" ] && grep -q "leak.txt:2" <<<"$out" && grep -q -- "--fixup" <<<"$out" && ! grep -qF "$SECRET" <<<"$out"; then
    pass "a secret in an unpushed commit blocks the push and names the way out"
else
    fail "a secret in an unpushed commit blocks the push and names the way out -- output: $out"
fi
git -C "$wt" reset -q --hard HEAD~1

# P6. --agent: agent-app's public `env` command, run against this worktree,
# supplies the token git pushes with.
echo more >"$wt/more.txt"; git -C "$wt" add more.txt; git -C "$wt" commit -q -m "feat(a): more"
hooks="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/hooks"
mkdir -p "$hooks"
# shellcheck disable=SC2016 # the hook expands $GH_TOKEN when git runs it
printf '#!/usr/bin/env bash\necho "$GH_TOKEN" >"%s"\n' "$work/pushed-with" >"$hooks/pre-push"
chmod +x "$hooks/pre-push"
: >"$FAKE_AGENT_LOG"
out="$(run "$wt" push --agent wren 2>&1)"; rc=$?
if grep -qx "env wren|$wt" "$FAKE_AGENT_LOG"; then
    pass "--agent runs agent-app env <name> for this worktree"
else
    fail "--agent runs agent-app env <name> for this worktree -- output: $out"
fi
if [ $rc -eq 0 ] && [ "$(cat "$work/pushed-with")" = token-for-wren ] && grep -q "pushing as vitruvian-wren-agent" <<<"$out" && [ "$(on_origin feat/a)" = "$(head_of "$wt")" ]; then
    pass "--agent pushes with that agent's token and says who it pushed as"
else
    fail "--agent pushes with that agent's token and says who it pushed as -- output: $out"
fi
rm -f "$hooks/pre-push"
echo more2 >"$wt/more2.txt"; git -C "$wt" add more2.txt; git -C "$wt" commit -q -m "feat(a): more2"
pushed="$(on_origin feat/a)"
out="$(run "$wt" push --agent nobody 2>&1)"; rc=$?
if [ $rc -eq 1 ] && [ "$(on_origin feat/a)" = "$pushed" ] && grep -q "unknown agent" <<<"$out"; then
    pass "an unknown agent is refused and nothing is pushed"
else
    fail "an unknown agent is refused and nothing is pushed -- output: $out"
fi

echo "git_test: $pass_n passed, $fail_n failed"
[ "$fail_n" -eq 0 ]
