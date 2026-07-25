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

UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/landed.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find landed.sh" >&2; exit 1; }

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
        bash "${UNDER_TEST}" "$3" 2>&1)"; rc=$?
}

echo "landed_test:"

# --- 1. syntax. --------------------------------------------------------------
bash -n "${UNDER_TEST}" 2>/dev/null; check "script parses" "$?"

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
out="$(cd "${repo}" && BUILD_WORKSPACE_DIRECTORY="${repo}" PATH="${bin}:${PATH}" bash "${UNDER_TEST}" 2>&1)"; rc=$?
check "no argument -> usage error" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
rm -rf "${repo}" "${bin}"

echo
if [ "${FAIL}" -ne 0 ]; then
  printf '\033[31mFAIL\033[0m — %d passed, %d failed\n' "${PASS}" "${FAIL}"; exit 1
fi
printf '\033[32mPASS\033[0m — %d passed\n' "${PASS}"
