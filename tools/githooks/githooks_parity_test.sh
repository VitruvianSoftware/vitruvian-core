#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
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
#
# Hermetic parity test for tools/githooks/{check-config.sh,pre-commit} vs Rust ports.

set -uo pipefail

SH_CHECK_CONFIG="${1:?missing check-config.sh path}"
RS_CHECK_CONFIG="${2:?missing :check_config path}"
SH_PRE_COMMIT="${3:?missing pre-commit path}"
RS_PRE_COMMIT="${4:?missing :pre_commit path}"

for var in SH_CHECK_CONFIG RS_CHECK_CONFIG SH_PRE_COMMIT RS_PRE_COMMIT; do
  eval "val=\${${var}}"
  case "${val}" in /*) ;; *) eval "${var}=${PWD}/${val}" ;; esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export HOME="${WORK}/home"
mkdir -p "${HOME}"
git config --global user.name "Test User"
git config --global user.email "test@example.com"
git config --global init.defaultBranch main

pass=0
fail=0

compare_runs() {
  local label="$1"
  local sh_dir="$2"
  local rs_dir="$3"
  local sh_bin="$4"
  local rs_bin="$5"
  shift 5
  # Remaining args are env KEY=VAL pairs

  (
    cd "${sh_dir}" &&
    env "$@" "${sh_bin}"
  ) >"${WORK}/sh.stdout" 2>"${WORK}/sh.stderr"
  local sh_rc=$?

  (
    cd "${rs_dir}" &&
    env "$@" "${rs_bin}"
  ) >"${WORK}/rs.stdout" 2>"${WORK}/rs.stderr"
  local rs_rc=$?

  local ok=1
  diff -u "${WORK}/sh.stdout" "${WORK}/rs.stdout" >"${WORK}/diff.stdout" 2>&1 || ok=0
  diff -u "${WORK}/sh.stderr" "${WORK}/rs.stderr" >"${WORK}/diff.stderr" 2>&1 || ok=0
  [ "${sh_rc}" = "${rs_rc}" ] || ok=0

  if [ "${ok}" -eq 1 ]; then
    echo "PASS: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label} (sh_rc=${sh_rc}, rs_rc=${rs_rc})" >&2
    [ -s "${WORK}/diff.stdout" ] && cat "${WORK}/diff.stdout" >&2
    [ -s "${WORK}/diff.stderr" ] && cat "${WORK}/diff.stderr" >&2
    fail=$((fail + 1))
  fi
}

init_repo_pair() {
  local name="$1"
  rm -rf "${WORK}/${name}_sh" "${WORK}/${name}_rs"
  mkdir -p "${WORK}/${name}_sh" "${WORK}/${name}_rs"
  for side in sh rs; do
    (
      cd "${WORK}/${name}_${side}" &&
      git init -q -b main &&
      echo "hello" > README.md &&
      git add README.md &&
      git commit -q -m "initial"
    )
  done
}

# Stub uname in a dedicated bin dir so check-config tests are OS-deterministic
STUB_BIN="${WORK}/stub_bin"
mkdir -p "${STUB_BIN}"
cat > "${STUB_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
echo "${FAKE_UNAME_S:-Linux}"
EOF
chmod +x "${STUB_BIN}/uname"

cat > "${STUB_BIN}/xcode-select" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${STUB_BIN}/xcode-select"

TEST_PATH="${STUB_BIN}:${PATH}"

# ─── 1. check-config.sh parity tests ─────────────────────────────────────────

# 1a. Outside a git worktree
mkdir -p "${WORK}/nogit_sh" "${WORK}/nogit_rs"
compare_runs "check-config: outside git worktree" \
  "${WORK}/nogit_sh" "${WORK}/nogit_rs" \
  "${SH_CHECK_CONFIG}" "${RS_CHECK_CONFIG}" \
  PATH="${TEST_PATH}" CI="" GITHUB_ACTIONS="" CLAUDE_CODE_REMOTE="" VITRUVIAN_ALLOW_PRIMARY_BRANCH=""

# 1b. Primary repo on main, core.hooksPath unset -> warns about core.hooksPath
init_repo_pair "cc_main_nohooks"
compare_runs "check-config: primary checkout on main without core.hooksPath" \
  "${WORK}/cc_main_nohooks_sh" "${WORK}/cc_main_nohooks_rs" \
  "${SH_CHECK_CONFIG}" "${RS_CHECK_CONFIG}" \
  PATH="${TEST_PATH}" CI="" GITHUB_ACTIONS="" CLAUDE_CODE_REMOTE="" VITRUVIAN_ALLOW_PRIMARY_BRANCH=""

# 1c. Primary repo on main, core.hooksPath set -> clean
init_repo_pair "cc_main_hooks"
for side in sh rs; do
  git -C "${WORK}/cc_main_hooks_${side}" config core.hooksPath tools/githooks
done
compare_runs "check-config: primary checkout on main with core.hooksPath set" \
  "${WORK}/cc_main_hooks_sh" "${WORK}/cc_main_hooks_rs" \
  "${SH_CHECK_CONFIG}" "${RS_CHECK_CONFIG}" \
  PATH="${TEST_PATH}" CI="" GITHUB_ACTIONS="" CLAUDE_CODE_REMOTE="" VITRUVIAN_ALLOW_PRIMARY_BRANCH=""

# 1d. Primary repo on feature branch -> refused (exit 1)
init_repo_pair "cc_feat"
for side in sh rs; do
  git -C "${WORK}/cc_feat_${side}" config core.hooksPath tools/githooks
  git -C "${WORK}/cc_feat_${side}" checkout -q -b feat/my-branch
done
compare_runs "check-config: primary checkout on feature branch refused" \
  "${WORK}/cc_feat_sh" "${WORK}/cc_feat_rs" \
  "${SH_CHECK_CONFIG}" "${RS_CHECK_CONFIG}" \
  PATH="${TEST_PATH}" CI="" GITHUB_ACTIONS="" CLAUDE_CODE_REMOTE="" VITRUVIAN_ALLOW_PRIMARY_BRANCH=""

# 1e. Primary repo on detached HEAD -> refused (exit 1)
init_repo_pair "cc_detached"
for side in sh rs; do
  git -C "${WORK}/cc_detached_${side}" config core.hooksPath tools/githooks
  git -C "${WORK}/cc_detached_${side}" checkout -q --detach HEAD
done
compare_runs "check-config: primary checkout on detached HEAD refused" \
  "${WORK}/cc_detached_sh" "${WORK}/cc_detached_rs" \
  "${SH_CHECK_CONFIG}" "${RS_CHECK_CONFIG}" \
  PATH="${TEST_PATH}" CI="" GITHUB_ACTIONS="" CLAUDE_CODE_REMOTE="" VITRUVIAN_ALLOW_PRIMARY_BRANCH=""

# 1f. Primary repo on feature branch with VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 -> allowed
compare_runs "check-config: break-glass VITRUVIAN_ALLOW_PRIMARY_BRANCH=1" \
  "${WORK}/cc_feat_sh" "${WORK}/cc_feat_rs" \
  "${SH_CHECK_CONFIG}" "${RS_CHECK_CONFIG}" \
  PATH="${TEST_PATH}" CI="" GITHUB_ACTIONS="" CLAUDE_CODE_REMOTE="" VITRUVIAN_ALLOW_PRIMARY_BRANCH="1"

# 1g. Primary repo on feature branch with CI=true -> allowed
compare_runs "check-config: CI=true exempts branch guard" \
  "${WORK}/cc_feat_sh" "${WORK}/cc_feat_rs" \
  "${SH_CHECK_CONFIG}" "${RS_CHECK_CONFIG}" \
  PATH="${TEST_PATH}" CI="true" GITHUB_ACTIONS="" CLAUDE_CODE_REMOTE="" VITRUVIAN_ALLOW_PRIMARY_BRANCH=""

# 1h. Linked worktree on feature branch -> allowed
init_repo_pair "cc_wt_base"
for side in sh rs; do
  git -C "${WORK}/cc_wt_base_${side}" config core.hooksPath tools/githooks
  git -C "${WORK}/cc_wt_base_${side}" worktree add -q -b feat/linked "${WORK}/cc_wt_linked_${side}"
done
compare_runs "check-config: linked worktree on feature branch allowed" \
  "${WORK}/cc_wt_linked_sh" "${WORK}/cc_wt_linked_rs" \
  "${SH_CHECK_CONFIG}" "${RS_CHECK_CONFIG}" \
  PATH="${TEST_PATH}" CI="" GITHUB_ACTIONS="" CLAUDE_CODE_REMOTE="" VITRUVIAN_ALLOW_PRIMARY_BRANCH=""

# 1i. Darwin Xcode version mismatch warning
for side in sh rs; do
  echo "99.9" > "${WORK}/cc_main_hooks_${side}/.xcode-version"
done
compare_runs "check-config: Darwin Xcode mismatch warning" \
  "${WORK}/cc_main_hooks_sh" "${WORK}/cc_main_hooks_rs" \
  "${SH_CHECK_CONFIG}" "${RS_CHECK_CONFIG}" \
  PATH="${TEST_PATH}" FAKE_UNAME_S="Darwin" CI="" GITHUB_ACTIONS="" CLAUDE_CODE_REMOTE="" VITRUVIAN_ALLOW_PRIMARY_BRANCH=""

# ─── 2. pre-commit parity tests ──────────────────────────────────────────────

# 2a. Clean staged files using prebuilt bazel-out format & gazelle binaries
init_repo_pair "pc_clean"
for side in sh rs; do
  d="${WORK}/pc_clean_${side}"
  mkdir -p "${d}/bazel-out/bazel_env-opt/bin/tools/bazel_env/bin"
  cat > "${d}/bazel-out/bazel_env-opt/bin/tools/bazel_env/bin/format" <<'EOF'
#!/usr/bin/env bash
echo "format-stub: $*"
EOF
  chmod +x "${d}/bazel-out/bazel_env-opt/bin/tools/bazel_env/bin/format"
  cat > "${d}/bazel-out/bazel_env-opt/bin/tools/bazel_env/bin/gazelle" <<'EOF'
#!/usr/bin/env bash
echo "gazelle-stub"
EOF
  chmod +x "${d}/bazel-out/bazel_env-opt/bin/tools/bazel_env/bin/gazelle"
  echo "staged content" > "${d}/app.rs"
  git -C "${d}" add app.rs
done
compare_runs "pre-commit: clean staged files with bazel_env binaries" \
  "${WORK}/pc_clean_sh" "${WORK}/pc_clean_rs" \
  "${SH_PRE_COMMIT}" "${RS_PRE_COMMIT}" \
  PATH="${TEST_PATH}"

# 2b. Formatter modifies staged file + gazelle modifies BUILD and adds untracked BUILD.bazel
init_repo_pair "pc_dirty"
cat > "${STUB_BIN}/bazel" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "run" ] && [ "$2" = "//tools/format" ]; then
  shift 3
  for f in "$@"; do
    echo "// formatted" >> "$f"
  done
  exit 0
fi
if [ "$1" = "run" ] && [ "$2" = "//:gazelle" ]; then
  echo "# gazelle updated" >> BUILD
  mkdir -p pkg
  echo "# new build" > pkg/BUILD.bazel
  exit 0
fi
exit 1
EOF
chmod +x "${STUB_BIN}/bazel"

for side in sh rs; do
  d="${WORK}/pc_dirty_${side}"
  echo "# root build" > "${d}/BUILD"
  git -C "${d}" add BUILD
  git -C "${d}" commit -q -m "add BUILD"
  echo "fn main() {}" > "${d}/main.rs"
  git -C "${d}" add main.rs
done
compare_runs "pre-commit: formatter modifies staged file and gazelle updates BUILD" \
  "${WORK}/pc_dirty_sh" "${WORK}/pc_dirty_rs" \
  "${SH_PRE_COMMIT}" "${RS_PRE_COMMIT}" \
  PATH="${TEST_PATH}"

echo ""
echo "Summary: ${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
