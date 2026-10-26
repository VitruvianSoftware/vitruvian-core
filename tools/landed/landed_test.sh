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

# Hermetic self-test for landed.sh: a fake `gh` on PATH and a scratch git repo
# shaped like a real squash-merge, so no network and no live PRs are involved.
#
# The scratch repo is the point. It reproduces the exact topology that breaks the
# naive check: a topic commit that is NOT an ancestor of main, plus a separate
# squashed commit that IS. A test built on a fast-forward merge would pass with
# the buggy one-liner and prove nothing.

set -uo pipefail

# LANDED_UNDER_TEST names another implementation to hold to these cases (the
# Rust port, //tools/landed:landed); by default it is landed.sh beside this file.
UNDER_TEST="${LANDED_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/landed.sh}"
case "${UNDER_TEST}" in /*) ;; *) UNDER_TEST="${PWD}/${UNDER_TEST}" ;; esac
[ -f "${UNDER_TEST}" ] || { echo "cannot find ${UNDER_TEST}" >&2; exit 1; }
# A script runs under bash; a compiled port runs as itself.
invoke() {
  case "${UNDER_TEST}" in
    *.sh) bash "${UNDER_TEST}" "$@" ;;
    *) "${UNDER_TEST}" "$@" ;;
  esac
}

PASS=0; FAIL=0
check() {
  if [ "$2" = "0" ]; then printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1))
  else printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); fi
}

# A repo with a REAL squash topology:
#   main:  base -> squashed          (squashed carries the change)
#   topic: base -> topic_commit      (never an ancestor of main)
new_repo() {
  r="$(mktemp -d)"
  (
    cd "${r}" || exit 1
    git init -q -b main
    git config user.email t@t; git config user.name t
    echo base > f.txt; git add -A; git commit -qm base

    git checkout -q -b topic
    echo change > f.txt; git add -A; git commit -qm "the change (topic)"

    git checkout -q main
    # The squash: same CONTENT, brand-new commit, parented on main.
    echo change > f.txt; git add -A; git commit -qm "the change (#42)"
    # origin/main, so the script's BASE resolves without a network remote.
    git update-ref refs/remotes/origin/main refs/heads/main
  ) >/dev/null 2>&1
  printf '%s' "${r}"
}

# fake_gh <bin> <state> <mergeSha> [prNumber]
# Stands in for the three gh calls landed.sh can make: `pr list --head`,
# `api .../commits/<sha>/pulls`, and `pr view`.
fake_gh() {
  bin="$1"; state="$2"; sha="$3"; num="${4:-42}"
  mkdir -p "${bin}"
  cat > "${bin}/gh" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr list")  echo "${num}" ;;
  "api repos"*|"api") echo "${num}" ;;
  "pr view")  echo "${state} ${sha}" ;;
  *)          echo "${num}" ;;
esac
EOF
  chmod +x "${bin}/gh"
}

run() { # <repo> <bin> <ref> -> sets out/rc
  out="$(cd "$1" && BUILD_WORKSPACE_DIRECTORY="$1" PATH="$2:${PATH}" \
        invoke "$3" 2>&1)"; rc=$?
}

echo "landed_test:"

# --- 1. syntax. --------------------------------------------------------------
case "${UNDER_TEST}" in
  *.sh) bash -n "${UNDER_TEST}" 2>/dev/null; check "script parses" "$?" ;;
  *) [ -x "${UNDER_TEST}" ]; check "binary is executable" "$?" ;;
esac

# --- 2. THE REGRESSION: a squash-merged PR reads as landed. ------------------
# The naive `--is-ancestor <topic-sha>` says NO here. This must say YES.
repo="$(new_repo)"; bin="$(mktemp -d)"
squashed="$(git -C "${repo}" rev-parse main)"
topic="$(git -C "${repo}" rev-parse topic)"
fake_gh "${bin}" MERGED "${squashed}"
run "${repo}" "${bin}" 42
check "squash-merged PR reports LANDED" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
case "${out}" in *"${squashed:0:8}"*) check "...and names the squashed sha" 0 ;; *) check "...and names the squashed sha" 1 ;; esac
# Prove the scratch repo really is the breaking topology, so test 2 is meaningful.
git -C "${repo}" merge-base --is-ancestor "${topic}" origin/main 2>/dev/null
check "(sanity) the topic sha is NOT an ancestor -- naive check would fail" "$([ "$?" != "0" ] && echo 0 || echo 1)"
rm -rf "${repo}" "${bin}"

# --- 3. an OPEN pr is not landed. --------------------------------------------
repo="$(new_repo)"; bin="$(mktemp -d)"
fake_gh "${bin}" OPEN "-"
run "${repo}" "${bin}" 42
check "OPEN pr reports NOT landed" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
case "${out}" in *OPEN*) check "...and says which state it is in" 0 ;; *) check "...and says which state it is in" 1 ;; esac
rm -rf "${repo}" "${bin}"

# --- 4. MERGED-but-not-in-this-checkout must NOT report green. ---------------
# Trusting GitHub's MERGED alone would pass here. The question is about THIS
# checkout's origin/main, and a stale fetch is exactly when someone is confused.
repo="$(new_repo)"; bin="$(mktemp -d)"
orphan="$(git -C "${repo}" rev-parse topic)"   # a real commit, not on main
fake_gh "${bin}" MERGED "${orphan}"
run "${repo}" "${bin}" 42
check "MERGED but absent from origin/main -> NOT landed" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
rm -rf "${repo}" "${bin}"

# --- 5. a sha GitHub has never seen is not landed. ---------------------------
# The local-only-commit case: gh resolves nothing, and that IS the answer.
repo="$(new_repo)"; bin="$(mktemp -d)"
mkdir -p "${bin}"; printf '#!/usr/bin/env bash\necho ""\n' > "${bin}/gh"; chmod +x "${bin}/gh"
run "${repo}" "${bin}" deadbeef
check "unresolvable ref -> NOT landed, with a reason" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
case "${out}" in *resolve*) check "...and says it could not resolve it" 0 ;; *) check "...and says it could not resolve it" 1 ;; esac
rm -rf "${repo}" "${bin}"

# --- 6. no argument is a usage error, not a false green. ---------------------
repo="$(new_repo)"; bin="$(mktemp -d)"; fake_gh "${bin}" MERGED "$(git -C "${repo}" rev-parse main)"
out="$(cd "${repo}" && BUILD_WORKSPACE_DIRECTORY="${repo}" PATH="${bin}:${PATH}" invoke 2>&1)"; rc=$?
check "no argument -> usage error" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
rm -rf "${repo}" "${bin}"

# --- 7. fallback when gh fails but squashed commit exists on origin/main -----
repo="$(new_repo)"; bin="$(mktemp -d)"
(
  cd "${repo}" || exit 1
  echo change > f.txt
  git add -A
  git commit -qm "the change (#42)"
  git update-ref refs/remotes/origin/main refs/heads/main
) >/dev/null 2>&1
cat > "${bin}/gh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${bin}/gh"
run "${repo}" "${bin}" 42
check "fallback: squashed commit on origin/main reports LANDED when gh fails" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
case "${out}" in *commit\ log*) check "...and notes it was resolved via commit log" 0 ;; *) check "...and notes it was resolved via commit log" 1 ;; esac
rm -rf "${repo}" "${bin}"

# ── --branch: the gate //tools/worktree uses before deleting a branch. ───────
# gh_fails: a gh that cannot answer, so the content check must stand on its own.
gh_fails() { mkdir -p "$1"; printf '#!/usr/bin/env bash\nexit 1\n' > "$1/gh"; chmod +x "$1/gh"; }
# gh_pr <bin> <state> <headSha> <mergeSha>: what `gh pr list --head` returns.
gh_pr() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\necho "42 %s %s %s"\n' "$2" "$3" "$4" > "$1/gh"; chmod +x "$1/gh"
}
gate() { out="$(cd "$1" && BUILD_WORKSPACE_DIRECTORY="$1" LANDED_NO_FETCH=1 PATH="$2:${PATH}" \
        invoke --branch "$3" 2>&1)"; rc=$?; }

# 8. squash-merged branch passes on CONTENT alone, with no GitHub at all.
repo="$(new_repo)"; bin="$(mktemp -d)"; gh_fails "${bin}"
gate "${repo}" "${bin}" topic
check "--branch: squash-merged branch is landed by content, gh unavailable" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
case "${out}" in *content*) check "...and says it was the content check" 0 ;; *) check "...and says it was the content check: ${out}" 1 ;; esac

# 9. THE DATA-LOSS CASE: PR merged, then the branch grew another local commit.
#    `landed 42` would say yes; --branch must say no.
head_at_merge="$(git -C "${repo}" rev-parse topic)"
( cd "${repo}" && git checkout -q topic && echo more > g.txt && git add -A &&
  git commit -qm "after the merge" && git checkout -q main ) >/dev/null 2>&1
gh_pr "${bin}" MERGED "${head_at_merge}" "$(git -C "${repo}" rev-parse main)"
gate "${repo}" "${bin}" topic
check "--branch: merged PR + extra local commit -> NOT landed" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
case "${out}" in *"past what the PR merged"*) check "...and names the unmerged commits as the reason" 0 ;;
  *) check "...and names the unmerged commits as the reason: ${out}" 1 ;; esac
rm -rf "${repo}" "${bin}"

# 10. a branch that never landed, gh unavailable -> NOT landed (unknown fails safe).
repo="$(new_repo)"; bin="$(mktemp -d)"; gh_fails "${bin}"
( cd "${repo}" && git checkout -q -b wip main && echo wip > w.txt && git add -A &&
  git commit -qm wip && git checkout -q main ) >/dev/null 2>&1
gate "${repo}" "${bin}" wip
check "--branch: unlanded branch -> NOT landed" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"

# 11. an OPEN PR does not make it landed.
gh_pr "${bin}" OPEN "$(git -C "${repo}" rev-parse wip)" "-"
gate "${repo}" "${bin}" wip
check "--branch: open PR -> NOT landed" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"

# 12. a branch with no commits of its own has nothing to lose.
git -C "${repo}" branch -q empty main
gate "${repo}" "${bin}" empty
check "--branch: no commits of its own -> landed" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
case "${out}" in *"no commits of its own"*) check "...and says so (worktree --prune keys on this)" 0 ;; *) check "...and says so: ${out}" 1 ;; esac

# 13. no such branch is an error, not a green.
gate "${repo}" "${bin}" nope
check "--branch: unknown branch -> error" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
rm -rf "${repo}" "${bin}"

# 14. merged PR, but main has since changed the SAME lines: the content check
#     sees a difference, so the PR proof (local tip == PR head) must carry it.
repo="$(new_repo)"; bin="$(mktemp -d)"
squashed="$(git -C "${repo}" rev-parse main)"
( cd "${repo}" && echo later > f.txt && git add -A && git commit -qm "later edit" &&
  git update-ref refs/remotes/origin/main refs/heads/main ) >/dev/null 2>&1
gh_pr "${bin}" MERGED "$(git -C "${repo}" rev-parse topic)" "${squashed}"
gate "${repo}" "${bin}" topic
check "--branch: merged PR whose lines main later changed -> landed via the PR" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
rm -rf "${repo}" "${bin}"

# ── --remote-branch, and commits a branch grows after its PR merged. ─────────
remote_gate() { out="$(cd "$1" && BUILD_WORKSPACE_DIRECTORY="$1" LANDED_NO_FETCH=1 PATH="$2:${PATH}" \
        invoke --remote-branch "$3" 2>&1)"; rc=$?; }
# grown_repo <g-content>: PR #42's head is `topic`; after it merged, the branch
# grew an empty commit, a clean merge of main, and a commit adding g.txt. main
# has its own commit adding g.txt (content "g"), then changes g.txt again, so
# neither the content check nor "tip is the PR head" can pass: only proof 4 can.
grown_repo() {
  r="$(new_repo)"
  (
    cd "${r}" || exit 1
    echo g > g.txt; git add -A; git commit -qm "add g (#43)"
    echo g2 > g.txt; git add -A; git commit -qm "change g (#44)"
    git update-ref refs/remotes/origin/main refs/heads/main
    git checkout -q topic
    git commit -q --allow-empty -m "trigger release"
    git merge -q --no-edit "$(git rev-parse 'main~2')"
    echo "$1" > g.txt; git add -A; git commit -qm "add g"
    git update-ref refs/remotes/origin/topic HEAD
    git checkout -q main
  ) >/dev/null 2>&1
  printf '%s' "${r}"
}

# 15. everything past the PR's head is empty, a clean merge, or a patch main has.
repo="$(grown_repo g)"; bin="$(mktemp -d)"
gh_pr "${bin}" MERGED "$(git -C "${repo}" rev-parse topic~3)" "$(git -C "${repo}" rev-parse main~2)"
remote_gate "${repo}" "${bin}" topic
check "--remote-branch: merged PR, then empty + clean merge + a patch main has -> landed" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
case "${out}" in *"branch on origin"*) check "...and says it judged the branch on origin" 0 ;; *) check "...and says it judged the branch on origin: ${out}" 1 ;; esac
# The local branch is the PR head with nothing more, so it must not be what was judged.
git -C "${repo}" branch -qf topic "$(git -C "${repo}" rev-parse topic~3)"
remote_gate "${repo}" "${bin}" topic
check "--remote-branch: judges origin's copy, not the local branch" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
rm -rf "${repo}" "${bin}"

# 16. the same, but the commit after the PR's head is work main does not have.
repo="$(grown_repo "g, but mine")"; bin="$(mktemp -d)"
gh_pr "${bin}" MERGED "$(git -C "${repo}" rev-parse topic~3)" "$(git -C "${repo}" rev-parse main~2)"
remote_gate "${repo}" "${bin}" topic
check "--remote-branch: merged PR, then a commit main lacks -> NOT landed" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
case "${out}" in *"not on origin/main"*) check "...and says those commits are not on main" 0 ;; *) check "...and says those commits are not on main: ${out}" 1 ;; esac
rm -rf "${repo}" "${bin}"

# 17. a branch origin does not have is an error, not a green.
repo="$(new_repo)"; bin="$(mktemp -d)"; gh_fails "${bin}"
remote_gate "${repo}" "${bin}" topic
check "--remote-branch: no such branch on origin -> error" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
rm -rf "${repo}" "${bin}"

echo
if [ "${FAIL}" -ne 0 ]; then
  printf '\033[31mFAIL\033[0m — %d passed, %d failed\n' "${PASS}" "${FAIL}"; exit 1
fi
printf '\033[32mPASS\033[0m — %d passed\n' "${PASS}"

