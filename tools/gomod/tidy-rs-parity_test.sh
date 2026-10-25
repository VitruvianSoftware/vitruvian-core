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

# Side-by-side behavioural parity test comparing tidy.sh and the Rust port
# across CLI flags, module discovery, check/fix modes, transient error
# classification/retries, environment propagation, signal handling, write
# errors, and filesystem/git effects across every distinct bash available.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIDY_SH="${TIDY_SH:-${SCRIPT_DIR}/tidy.sh}"
TIDY_RS="${TIDY_RS:-${SCRIPT_DIR}/tidy}"
CHECK_RS="${CHECK_RS:-${SCRIPT_DIR}/check}"

if [[ "${TIDY_SH}" != /* ]]; then
  TIDY_SH="$(cd "$(dirname "${TIDY_SH}")" && pwd)/$(basename "${TIDY_SH}")"
fi
if [[ "${TIDY_RS}" != /* ]]; then
  TIDY_RS="$(cd "$(dirname "${TIDY_RS}")" && pwd)/$(basename "${TIDY_RS}")"
fi
if [[ "${CHECK_RS}" != /* ]]; then
  CHECK_RS="$(cd "$(dirname "${CHECK_RS}")" && pwd)/$(basename "${CHECK_RS}")"
fi

[ -f "${TIDY_SH}" ] || { echo "missing TIDY_SH: ${TIDY_SH}" >&2; exit 1; }
[ -x "${TIDY_RS}" ] || { echo "missing TIDY_RS: ${TIDY_RS}" >&2; exit 1; }
[ -x "${CHECK_RS}" ] || { echo "missing CHECK_RS: ${CHECK_RS}" >&2; exit 1; }

# Discover every distinct bash executable available.
BASH_LIST=()
BASH_SEEN=":"
for _cand in \
    /bin/bash \
    /usr/bin/bash \
    /usr/local/bin/bash \
    /opt/homebrew/bin/bash \
    /run/current-system/sw/bin/bash \
    "$(command -v bash 2>/dev/null || true)"; do
  [ -n "${_cand}" ] && [ -x "${_cand}" ] || continue
  _real="$(cd "$(dirname "${_cand}")" 2>/dev/null && pwd -P)/$(basename "${_cand}")"
  case "${BASH_SEEN}" in
    *":${_real}:"*) ;;
    *)
      BASH_SEEN="${BASH_SEEN}${_real}:"
      BASH_LIST+=("${_real}")
      ;;
  esac
done
[ "${#BASH_LIST[@]}" -gt 0 ] || BASH_LIST=("bash")

export GIT_AUTHOR_NAME="Parity Test"
export GIT_AUTHOR_EMAIL="parity@example.com"
export GIT_COMMITTER_NAME="Parity Test"
export GIT_COMMITTER_EMAIL="parity@example.com"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
export GIT_CONFIG_NOSYSTEM=1
export LC_ALL=C

BASE_TMP="$(mktemp -d)"
trap 'chmod -R u+rwx "${BASE_TMP}" 2>/dev/null || true; rm -rf "${BASE_TMP}"' EXIT

WORK_DIR="${BASE_TMP}/work"
BIN_DIR="${BASE_TMP}/bin"
SNAP_SH="${BASE_TMP}/snap_sh"
SNAP_RS="${BASE_TMP}/snap_rs"
export HOME="${BASE_TMP}/home"
export GIT_CONFIG_GLOBAL="${HOME}/.gitconfig"
mkdir -p "${HOME}"
touch "${GIT_CONFIG_GLOBAL}"

PASS=0
FAIL=0

install_fake_sleep() {
  local sleep_rc="${1:-0}"
  mkdir -p "${BIN_DIR}"
  cat > "${BIN_DIR}/sleep" <<EOF
#!/usr/bin/env bash
{
  printf 'sleep argv='
  printf '<%s>' "\$0" "\$@"
  printf '\n'
  env -0 | grep -azvE '^(_|SHLVL|BASH_EXECUTION_STRING|BASH_FUNC_.*)=' | LC_ALL=C sort -z | tr '\0' '\n'
  printf -- '---\n'
} >> "${BIN_DIR}/calls.log"
exit ${sleep_rc}
EOF
  chmod +x "${BIN_DIR}/sleep"
}

install_fake_go_basic() {
  local diff_rc="$1"
  mkdir -p "${BIN_DIR}"
  install_fake_sleep
  cat > "${BIN_DIR}/go" <<EOF
#!/usr/bin/env bash
{
  printf 'go argv='
  printf '<%s>' "\$0" "\$@"
  printf '\n'
  env -0 | grep -azvE '^(_|SHLVL|BASH_EXECUTION_STRING|BASH_FUNC_.*)=' | LC_ALL=C sort -z | tr '\0' '\n'
  printf -- '---\n'
} >> "${BIN_DIR}/calls.log"
if [ -n "\${GO_HOOK_CMD:-}" ]; then
  eval "\${GO_HOOK_CMD}"
fi
case "\$*" in
  *"mod tidy -diff"*)
    if [ "${diff_rc}" -ne 0 ]; then
      echo "-google.golang.org/grpc v1.80.0"
      echo "+google.golang.org/grpc v1.82.1"
    fi
    exit ${diff_rc}
    ;;
  *"mod tidy"*)
    if [ -n "\${TIDY_FIX_KILL_SIG:-}" ]; then
      kill -"\${TIDY_FIX_KILL_SIG}" "\$\$"
    fi
    echo "// tidied" >> go.mod
    if [ -f go.sum ] && [ "\${TOUCH_GOSUM:-0}" = "1" ]; then
      echo "example.com/dep v1.0.0 h1:abc=" >> go.sum
    fi
    exit \${TIDY_FIX_RC:-0}
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "${BIN_DIR}/go"
}

install_fake_go_transient() {
  local fail_times="$1"
  local msg="${2:-go: github.com/pulumi/pulumi-gcp/sdk/v9@v9.34.1: read \"https://proxy.golang.org/...\": stream error: stream ID 7; INTERNAL_ERROR; received from peer}"
  mkdir -p "${BIN_DIR}"
  install_fake_sleep
  echo 0 > "${BIN_DIR}/attempts"
  cat > "${BIN_DIR}/go" <<EOF
#!/usr/bin/env bash
{
  printf 'go argv='
  printf '<%s>' "\$0" "\$@"
  printf '\n'
  env -0 | grep -azvE '^(_|SHLVL|BASH_EXECUTION_STRING|BASH_FUNC_.*)=' | LC_ALL=C sort -z | tr '\0' '\n'
  printf -- '---\n'
} >> "${BIN_DIR}/calls.log"
case "\$*" in
  *"mod tidy -diff"*)
    n=\$(cat "${BIN_DIR}/attempts")
    n=\$((n + 1))
    echo "\$n" > "${BIN_DIR}/attempts"
    if [ "\$n" -le ${fail_times} ]; then
      printf '%s\n' '${msg}' >&2
      exit 1
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "${BIN_DIR}/go"
}

# Narrow normaliser: replace ONLY the script/binary path, NEVER the line number.
normalize_stream() {
  local file="$1"
  sed -E \
    -e 's#^([[:space:]]*)[^:]+/(tidy\.sh|tidy|check)(: line [0-9]+:)#\1<prog>\3#' \
    -e 's#(<prog>: line [0-9]+: )[[:space:]]*[0-9]+ (Terminated|Killed):#\1<PID> \2:#' \
    -e '/^mktemp:/s/tmp\.[A-Za-z0-9_]+/tmp.XXXXXX/g' \
    "${file}" > "${file}.norm"
  mv "${file}.norm" "${file}"
}

snapshot_state() {
  local snap_dir="$1"
  mkdir -p "${snap_dir}"
  normalize_stream "${snap_dir}/stdout"
  normalize_stream "${snap_dir}/stderr"
  if [ -f "${BIN_DIR}/calls.log" ]; then
    cp "${BIN_DIR}/calls.log" "${snap_dir}/calls.log"
  else
    : > "${snap_dir}/calls.log"
  fi
  (
    if [ -d "${WORK_DIR}" ]; then
      cd "${WORK_DIR}"
      find . -not -path '*/.git/*' -not -name '.git' -not -path './isolated_bin*' -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
        ck="$(cksum "$f" 2>/dev/null || echo "unreadable")"
        printf '%s :: %s\n' "$f" "$ck"
      done
    fi
  ) > "${snap_dir}/fs_state.txt"

  if [ -d "${WORK_DIR}/.git" ]; then
    (
      cd "${WORK_DIR}"
      git for-each-ref
      git status --porcelain
      git log --format='%H%x00%an%x00%ae%x00%cn%x00%s' --all 2>/dev/null || true
    ) > "${snap_dir}/git_state.txt"
  else
    : > "${snap_dir}/git_state.txt"
  fi
}

invoke_target() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2
  if [ "${PARITY_CLOSE_STDOUT:-0}" = "1" ]; then
    : > "${stdout_file}"
    "$@" >&- 2>"${stderr_file}"
  elif [ "${PARITY_CLOSE_STDERR:-0}" = "1" ]; then
    : > "${stderr_file}"
    "$@" >"${stdout_file}" 2>&-
  elif [ -n "${PARITY_STDOUT_FILE:-}" ]; then
    : > "${stdout_file}"
    "$@" >"${PARITY_STDOUT_FILE}" 2>"${stderr_file}"
  else
    "$@" >"${stdout_file}" 2>"${stderr_file}"
  fi
}

run_parity_case_one_bash() {
  local test_bash="$1"
  local name="$2"
  local setup_fn="$3"
  shift 3

  chmod -R u+rwx "${WORK_DIR}" 2>/dev/null || true
  rm -rf "${WORK_DIR}" "${BIN_DIR}" "${SNAP_SH}" "${SNAP_RS}"
  mkdir -p "${WORK_DIR}" "${BIN_DIR}" "${SNAP_SH}" "${SNAP_RS}"
  "${setup_fn}"
  ln -sf "${test_bash}" "${BIN_DIR}/bash"

  local run_path="${BIN_DIR}:${PATH}"
  local bwd="${PARITY_BWD_OVERRIDE:-${WORK_DIR}}"
  if [ "${PARITY_UNSET_BWD:-0}" = "1" ]; then
    bwd=""
  fi
  if [ -n "${PARITY_CUSTOM_PATH:-}" ]; then
    run_path="${PARITY_CUSTOM_PATH}"
  fi

  local sh_bin="${PARITY_SH_BIN:-${TIDY_SH}}"
  local rs_bin="${PARITY_RS_BIN:-${TIDY_RS}}"
  if [ "${PARITY_USE_CHECK_BIN:-0}" = "1" ]; then
    rs_bin="${CHECK_RS}"
  fi
  local run_locale="${PARITY_LOCALE:-C}"
  local run_tmpdir="${PARITY_TMPDIR:-${TMPDIR:-/tmp}}"

  (
    cd "${WORK_DIR}"
    if [ -n "${PARITY_STALE_PWD:-}" ]; then
      export PWD="${PARITY_STALE_PWD}"
    fi
    if [ -n "${PARITY_RUNFILES_DIR:-}" ]; then
      export RUNFILES_DIR="${PARITY_RUNFILES_DIR}"
    fi
    if [ -n "${PARITY_BASH_ENV:-}" ]; then
      export BASH_ENV="${PARITY_BASH_ENV}"
    fi
    if [ "${PARITY_UNSET_BWD:-0}" = "1" ]; then
      unset BUILD_WORKSPACE_DIRECTORY
      LC_ALL="${run_locale}" TMPDIR="${run_tmpdir}" PATH="${run_path}" GOWORK="" \
        invoke_target "${SNAP_SH}/stdout" "${SNAP_SH}/stderr" "${test_bash}" "${sh_bin}" "$@"
    else
      LC_ALL="${run_locale}" TMPDIR="${run_tmpdir}" PATH="${run_path}" GOWORK="" BUILD_WORKSPACE_DIRECTORY="${bwd}" \
        invoke_target "${SNAP_SH}/stdout" "${SNAP_SH}/stderr" "${test_bash}" "${sh_bin}" "$@"
    fi
  )
  echo "$?" > "${SNAP_SH}/rc"
  snapshot_state "${SNAP_SH}"

  chmod -R u+rwx "${WORK_DIR}" 2>/dev/null || true
  rm -rf "${WORK_DIR}" "${BIN_DIR}"
  mkdir -p "${WORK_DIR}" "${BIN_DIR}"
  "${setup_fn}"
  ln -sf "${test_bash}" "${BIN_DIR}/bash"

  sh_bin="${PARITY_SH_BIN:-${TIDY_SH}}"
  rs_bin="${PARITY_RS_BIN:-${TIDY_RS}}"
  if [ "${PARITY_USE_CHECK_BIN:-0}" = "1" ]; then
    rs_bin="${CHECK_RS}"
  fi
  bwd="${PARITY_BWD_OVERRIDE:-${WORK_DIR}}"
  run_tmpdir="${PARITY_TMPDIR:-${TMPDIR:-/tmp}}"

  (
    cd "${WORK_DIR}"
    if [ -n "${PARITY_STALE_PWD:-}" ]; then
      export PWD="${PARITY_STALE_PWD}"
    fi
    if [ -n "${PARITY_RUNFILES_DIR:-}" ]; then
      export RUNFILES_DIR="${PARITY_RUNFILES_DIR}"
    fi
    if [ -n "${PARITY_BASH_ENV:-}" ]; then
      export BASH_ENV="${PARITY_BASH_ENV}"
    fi
    if [ "${PARITY_UNSET_BWD:-0}" = "1" ]; then
      unset BUILD_WORKSPACE_DIRECTORY
      LC_ALL="${run_locale}" TMPDIR="${run_tmpdir}" PATH="${run_path}" GOWORK="" \
        invoke_target "${SNAP_RS}/stdout" "${SNAP_RS}/stderr" "${rs_bin}" "$@"
    else
      LC_ALL="${run_locale}" TMPDIR="${run_tmpdir}" PATH="${run_path}" GOWORK="" BUILD_WORKSPACE_DIRECTORY="${bwd}" \
        invoke_target "${SNAP_RS}/stdout" "${SNAP_RS}/stderr" "${rs_bin}" "$@"
    fi
  )
  echo "$?" > "${SNAP_RS}/rc"
  snapshot_state "${SNAP_RS}"

  local ok=0
  for item in rc stdout stderr calls.log fs_state.txt git_state.txt; do
    if ! cmp -s "${SNAP_SH}/${item}" "${SNAP_RS}/${item}"; then
      ok=1
      printf '  \033[31mDIFF\033[0m  %s [%s] (%s)\n' "${name}" "${test_bash}" "${item}" >&2
      diff -u "${SNAP_SH}/${item}" "${SNAP_RS}/${item}" >&2 || true
    fi
  done

  if [ "${ok}" -eq 0 ]; then
    printf '  \033[32mPASS\033[0m  %s [%s]\n' "${name}" "${test_bash}"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s [%s]\n' "${name}" "${test_bash}"
    FAIL=$((FAIL + 1))
  fi
}

run_parity_case() {
  local name="$1"
  local setup_fn="$2"
  shift 2
  local b
  for b in "${BASH_LIST[@]}"; do
    run_parity_case_one_bash "${b}" "${name}" "${setup_fn}" "$@"
  done
}

link_standard_tools_into_bindir() {
  local tool p
  for tool in bash dirname find sort sed cat rm mktemp grep git env tr; do
    p="$(command -v "$tool" 2>/dev/null || true)"
    if [ -n "$p" ]; then
      ln -sf "$p" "${BIN_DIR}/$tool"
    fi
  done
}

# --- Scenario setup helpers --------------------------------------------------

setup_two_mods_drifted() {
  install_fake_go_basic 1
  for i in 1 2; do
    mkdir -p "${WORK_DIR}/src/m${i}"
    printf 'module example.com/m%s\n\ngo 1.26.2\n' "$i" > "${WORK_DIR}/src/m${i}/go.mod"
  done
}

setup_three_mods_tidy() {
  install_fake_go_basic 0
  for i in 1 2 3; do
    mkdir -p "${WORK_DIR}/src/m${i}"
    printf 'module example.com/m%s\n\ngo 1.26.2\n' "$i" > "${WORK_DIR}/src/m${i}/go.mod"
  done
}

setup_empty_src() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/src"
}

setup_nested_mods() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/src/nested" "${WORK_DIR}/src/a-b" "${WORK_DIR}/src/a"
  printf 'module example.com/top\n\ngo 1.26.2\n' > "${WORK_DIR}/src/go.mod"
  printf 'module example.com/nested\n\ngo 1.26.2\n' > "${WORK_DIR}/src/nested/go.mod"
  printf 'module example.com/ab\n\ngo 1.26.2\n' > "${WORK_DIR}/src/a-b/go.mod"
  printf 'module example.com/a\n\ngo 1.26.2\n' > "${WORK_DIR}/src/a/go.mod"
}

setup_locale_collation_mods() {
  install_fake_go_basic 1
  for d in A0 A_0 AB A_B AC x x_y a-b A-c a_b network network_peering; do
    mkdir -p "${WORK_DIR}/src/${d}"
    printf 'module example.com/%s\n\ngo 1.26.2\n' "$d" > "${WORK_DIR}/src/${d}/go.mod"
  done
}

setup_vendor_tree() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/src/m1/vendor/example.com/dep"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
  printf 'module example.com/dep\n' > "${WORK_DIR}/src/m1/vendor/example.com/dep/go.mod"
}

setup_symlinked_root() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/real_src/m1"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/real_src/m1/go.mod"
  ln -s real_src "${WORK_DIR}/src_link"
}

setup_unreadable_subdir() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/src/m1" "${WORK_DIR}/src/zzz_locked"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
  printf 'module example.com/locked\n\ngo 1.26.2\n' > "${WORK_DIR}/src/zzz_locked/go.mod"
  chmod 000 "${WORK_DIR}/src/zzz_locked"
}

setup_unenterable_mod_on_second() {
  install_fake_go_basic 1
  for i in 1 2; do
    mkdir -p "${WORK_DIR}/src/m${i}"
    printf 'module example.com/m%s\n\ngo 1.26.2\n' "$i" > "${WORK_DIR}/src/m${i}/go.mod"
  done
}

setup_go_becomes_unexecutable() {
  link_standard_tools_into_bindir
  install_fake_go_basic 1
  for i in 1 2; do
    mkdir -p "${WORK_DIR}/src/m${i}"
    printf 'module example.com/m%s\n\ngo 1.26.2\n' "$i" > "${WORK_DIR}/src/m${i}/go.mod"
  done
}

setup_go_disappears_midrun() {
  link_standard_tools_into_bindir
  install_fake_go_basic 1
  for i in 1 2; do
    mkdir -p "${WORK_DIR}/src/m${i}"
    printf 'module example.com/m%s\n\ngo 1.26.2\n' "$i" > "${WORK_DIR}/src/m${i}/go.mod"
  done
}

setup_transient_recovers_2() {
  install_fake_go_transient 2
  mkdir -p "${WORK_DIR}/src/m1"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
}

setup_transient_recovers_1() {
  install_fake_go_transient 1 "dial tcp 142.250.1.1:443: connect: connection refused"
  mkdir -p "${WORK_DIR}/src/m1"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
}

setup_transient_permanent() {
  install_fake_go_transient 99 "GET https://proxy.golang.org/foo/@v/list: 503 Service Unavailable"
  mkdir -p "${WORK_DIR}/src/m1"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
}

setup_transient_failing_sleep() {
  install_fake_go_transient 2
  install_fake_sleep 7
  mkdir -p "${WORK_DIR}/src/m1"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
}

setup_transient_missing_sleep() {
  install_fake_go_transient 2
  rm -f "${BIN_DIR}/sleep"
  for tool in bash dirname find sort sed cat rm mktemp grep git env tr; do
    p="$(command -v "$tool" 2>/dev/null || true)"
    if [ -n "$p" ]; then
      ln -sf "$p" "${BIN_DIR}/$tool"
    fi
  done
  mkdir -p "${WORK_DIR}/src/m1"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
}

setup_isolated_missing_lib() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/isolated_bin" "${WORK_DIR}/src/m1"
  cp "${TIDY_SH}" "${WORK_DIR}/isolated_bin/tidy.sh"
  cp "${TIDY_RS}" "${WORK_DIR}/isolated_bin/tidy"
  chmod +x "${WORK_DIR}/isolated_bin/tidy.sh" "${WORK_DIR}/isolated_bin/tidy"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
}

setup_isolated_root_custom_lib() {
  setup_isolated_missing_lib
  install_fake_go_transient 1 "CUSTOM_WORKSPACE_TRANSIENT_BLIP_XYZ"
  mkdir -p "${WORK_DIR}/tools/ci"
  cat > "${WORK_DIR}/tools/ci/transient-lib.sh" <<'EOF'
is_transient_network_error() {
  grep -q 'CUSTOM_WORKSPACE_TRANSIENT_BLIP_XYZ' "$1"
}
EOF
}

setup_isolated_unreadable_lib() {
  setup_isolated_missing_lib
  mkdir -p "${WORK_DIR}/tools/ci"
  cat > "${WORK_DIR}/tools/ci/transient-lib.sh" <<'EOF'
is_transient_network_error() {
  return 1
}
EOF
  chmod 000 "${WORK_DIR}/tools/ci/transient-lib.sh"
}

setup_isolated_failing_lib() {
  setup_isolated_missing_lib
  install_fake_go_basic 1
  mkdir -p "${WORK_DIR}/tools/ci"
  cat > "${WORK_DIR}/tools/ci/transient-lib.sh" <<'EOF'
false
is_transient_network_error() {
  return 1
}
EOF
}

setup_bash_env_logger() {
  setup_three_mods_tidy
  cat > "${WORK_DIR}/bash_env_hook.sh" <<EOF
echo "sourced" >> "${WORK_DIR}/bash_env.log"
EOF
}

setup_unwritable_tmpdir() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/src/m1" "${WORK_DIR}/ro_tmp"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
  chmod 0500 "${WORK_DIR}/ro_tmp"
}

setup_mixed_unreachable_and_drifted() {
  mkdir -p "${BIN_DIR}"
  install_fake_sleep
  cat > "${BIN_DIR}/go" <<EOF
#!/usr/bin/env bash
{
  printf 'go argv='
  printf '<%s>' "\$0" "\$@"
  printf '\n'
  env -0 | grep -azvE '^(_|SHLVL|BASH_EXECUTION_STRING|BASH_FUNC_.*)=' | LC_ALL=C sort -z | tr '\0' '\n'
  printf -- '---\n'
} >> "${BIN_DIR}/calls.log"
case "\${PWD}" in
  */m1)
    echo "-example.com/old v1.0.0"
    echo "+example.com/new v1.1.0"
    exit 1
    ;;
  */m2)
    echo "read tcp: connection reset by peer" >&2
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "${BIN_DIR}/go"
  for i in 1 2 3; do
    mkdir -p "${WORK_DIR}/src/m${i}"
    printf 'module example.com/m%s\n\ngo 1.26.2\n' "$i" > "${WORK_DIR}/src/m${i}/go.mod"
  done
}

setup_fix_with_gosum() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/src/m1" "${WORK_DIR}/src/m2"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
  printf 'example.com/x v1.0.0 h1:111=\n' > "${WORK_DIR}/src/m1/go.sum"
  printf 'module example.com/m2\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m2/go.mod"
}

setup_fix_unreadable_gosum() {
  setup_fix_with_gosum
  chmod 000 "${WORK_DIR}/src/m1/go.sum"
}

setup_fix_unreadable_gomod_with_gosum() {
  setup_fix_with_gosum
  chmod 000 "${WORK_DIR}/src/m1/go.mod"
}

setup_default_roots_present() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/packages/pulumi/library/go"
  mkdir -p "${WORK_DIR}/packages/pulumi/examples/go-foundation/ex1"
  mkdir -p "${WORK_DIR}/infrastructure/pulumi/platform/repo-config"
  printf 'module example.com/lib\n' > "${WORK_DIR}/packages/pulumi/library/go/go.mod"
  printf 'module example.com/ex1\n' > "${WORK_DIR}/packages/pulumi/examples/go-foundation/ex1/go.mod"
  printf 'module example.com/rc\n' > "${WORK_DIR}/infrastructure/pulumi/platform/repo-config/go.mod"
}

setup_unicode_and_spaces() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/src/mod with spaces" "${WORK_DIR}/src/mód-üñîçødé"
  printf 'module example.com/spaces\n' > "${WORK_DIR}/src/mod with spaces/go.mod"
  printf 'module example.com/unicode\n' > "${WORK_DIR}/src/mód-üñîçødé/go.mod"
}

setup_git_toplevel() {
  install_fake_go_basic 0
  (
    cd "${WORK_DIR}"
    git init -q
    mkdir -p src/m1
    printf 'module example.com/m1\n' > src/m1/go.mod
    git add src/m1/go.mod
    git commit -q -m "initial"
  )
}

setup_no_go_on_path() {
  mkdir -p "${BIN_DIR}"
  link_standard_tools_into_bindir
  mkdir -p "${WORK_DIR}/src/m1"
  printf 'module example.com/m1\n' > "${WORK_DIR}/src/m1/go.mod"
}

setup_invalid_utf8_diff() {
  mkdir -p "${BIN_DIR}"
  install_fake_sleep
  cat > "${BIN_DIR}/go" <<EOF
#!/usr/bin/env bash
{
  printf 'go argv='
  printf '<%s>' "\$0" "\$@"
  printf '\n'
  env -0 | grep -azvE '^(_|SHLVL|BASH_EXECUTION_STRING|BASH_FUNC_.*)=' | LC_ALL=C sort -z | tr '\0' '\n'
  printf -- '---\n'
} >> "${BIN_DIR}/calls.log"
printf 'diff-invalid: \xff\xfe\n'
exit 1
EOF
  chmod +x "${BIN_DIR}/go"
  mkdir -p "${WORK_DIR}/src/m1"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
}

setup_find_with_empty_line() {
  install_fake_go_basic 0
  mkdir -p "${WORK_DIR}/src/m1"
  printf 'module example.com/root\n\ngo 1.26.2\n' > "${WORK_DIR}/go.mod"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
  cat > "${BIN_DIR}/find" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "src" ]; then
  printf 'src/m1/go.mod\n\n'
else
  exec /usr/bin/find "$@"
fi
EOF
  chmod +x "${BIN_DIR}/find"
}

echo "gomod tidy-rs-parity_test (bashes: ${BASH_LIST[*]}):"

run_parity_case "help short flag (-h)" setup_three_mods_tidy -h
run_parity_case "help long flag (--help)" setup_three_mods_tidy --help
run_parity_case "help after --check (--check --help)" setup_three_mods_tidy --check --help
run_parity_case "unknown short flag (-x)" setup_three_mods_tidy -x
run_parity_case "unknown long flag (--bogus)" setup_three_mods_tidy --bogus
run_parity_case "bare dash (-)" setup_three_mods_tidy -
run_parity_case "double dash (--)" setup_three_mods_tidy --
run_parity_case "unknown flag before -h (--bogus -h)" setup_three_mods_tidy --bogus -h
run_parity_case "non-UTF-8 unknown flag" setup_three_mods_tidy $'--bogus-\xff\xfe'
run_parity_case "non-UTF-8 missing root" setup_three_mods_tidy --check $'missing-\xff\xfe'

PARITY_CUSTOM_PATH="${BIN_DIR}" run_parity_case "go missing from PATH" setup_no_go_on_path --check src

run_parity_case "check mode: tidy tree (3 modules)" setup_three_mods_tidy --check src
run_parity_case "check mode: drifted tree (2 modules)" setup_two_mods_drifted --check src
run_parity_case "check mode: empty sweep fails" setup_empty_src --check src
run_parity_case "check mode: missing root fails" setup_empty_src --check no-such-dir
run_parity_case "check mode: exact <dir>/go.mod root" setup_nested_mods --check src/go.mod
run_parity_case "check mode: subtree recursion and sort order (C locale)" setup_nested_mods --check src
run_parity_case "check mode: missing exact <dir>/go.mod" setup_nested_mods --check src/nope/go.mod
run_parity_case "check mode: vendor/ excluded" setup_vendor_tree --check src
run_parity_case "check mode: symlinked root is not descended by find" setup_symlinked_root --check src_link
run_parity_case "check mode: empty line from find preserved as ." setup_find_with_empty_line --check src

if grep -qi '^en_US\.UTF-8$' <<<"$(PATH="/usr/bin:${PATH}" locale -a 2>/dev/null)"; then
  PARITY_LOCALE="en_US.UTF-8" run_parity_case "check mode: locale collation under en_US.UTF-8" setup_locale_collation_mods --check src
  PARITY_LOCALE="en_US.UTF-8" run_parity_case "check mode: invalid UTF-8 in go diff under en_US.UTF-8" setup_invalid_utf8_diff --check src
else
  printf '  \033[33mSKIP\033[0m  check mode: locale collation under en_US.UTF-8 (en_US.UTF-8 not in locale -a)\n'
fi

if [ "$(id -u)" -ne 0 ]; then
  run_parity_case "check mode: unreadable subdirectory stderr passthrough" setup_unreadable_subdir --check src
  GO_HOOK_CMD='chmod 000 "${BUILD_WORKSPACE_DIRECTORY}/src/m2" 2>/dev/null || true' \
    run_parity_case "check mode: unenterable module dir mid-run" setup_unenterable_mod_on_second --check src
  GO_HOOK_CMD='chmod 000 "${BUILD_WORKSPACE_DIRECTORY}/src/m2" 2>/dev/null || true' \
    run_parity_case "fix mode: unenterable module dir mid-run" setup_unenterable_mod_on_second src
  PARITY_CUSTOM_PATH="${BIN_DIR}" GO_HOOK_CMD='chmod 0644 "${BIN_DIR}/go"' \
    run_parity_case "check mode: go not executable mid-run (126 in diff)" setup_go_becomes_unexecutable --check src
  PARITY_CUSTOM_PATH="${BIN_DIR}" GO_HOOK_CMD='chmod 0644 "${BIN_DIR}/go"' \
    run_parity_case "fix mode: go not executable mid-run (exit 126)" setup_go_becomes_unexecutable src
  PARITY_CUSTOM_PATH="${BIN_DIR}" GO_HOOK_CMD='rm -f "${BIN_DIR}/go"' \
    run_parity_case "fix mode: go disappears mid-run (exit 127)" setup_go_disappears_midrun src
  PARITY_TMPDIR="${WORK_DIR}/ro_tmp" run_parity_case "mktemp failure: unwritable TMPDIR" setup_unwritable_tmpdir --check src
  run_parity_case "fix mode: unreadable go.sum fails at line 273 before go runs" setup_fix_unreadable_gosum src
  run_parity_case "fix mode: unreadable go.mod (with go.sum) fails at line 273 before go runs" setup_fix_unreadable_gomod_with_gosum src
  GO_HOOK_CMD='chmod 000 go.sum 2>/dev/null || true' \
    run_parity_case "fix mode: go.sum becoming unreadable mid-run fails at line 276" setup_fix_with_gosum src
  PARITY_SH_BIN="${WORK_DIR}/isolated_bin/tidy.sh" PARITY_RS_BIN="${WORK_DIR}/isolated_bin/tidy" PARITY_RUNFILES_DIR="${WORK_DIR}/no_runfiles" \
    run_parity_case "unreadable transient-lib.sh fails at line 106" setup_isolated_unreadable_lib --check src
fi

PARITY_TMPDIR="${WORK_DIR}/no_such_tmpdir" run_parity_case "mktemp failure: missing TMPDIR" setup_three_mods_tidy --check src
PARITY_BWD_OVERRIDE="${WORK_DIR}/no_such_bwd" run_parity_case "missing BUILD_WORKSPACE_DIRECTORY fails with cd error" setup_three_mods_tidy --check src

PARITY_SH_BIN="${WORK_DIR}/isolated_bin/tidy.sh" PARITY_RS_BIN="${WORK_DIR}/isolated_bin/tidy" PARITY_RUNFILES_DIR="${WORK_DIR}/no_runfiles" \
  run_parity_case "missing transient-lib.sh fails on unbound C_RED" setup_isolated_missing_lib --check src
C_RED="" GLYPH_FAIL="✗" C_RESET="" PARITY_SH_BIN="${WORK_DIR}/isolated_bin/tidy.sh" PARITY_RS_BIN="${WORK_DIR}/isolated_bin/tidy" PARITY_RUNFILES_DIR="${WORK_DIR}/no_runfiles" \
  run_parity_case "missing transient-lib.sh with C_RED/GLYPH_FAIL/C_RESET set prints message" setup_isolated_missing_lib --check src
PARITY_SH_BIN="${WORK_DIR}/isolated_bin/tidy.sh" PARITY_RS_BIN="${WORK_DIR}/isolated_bin/tidy" PARITY_RUNFILES_DIR="${WORK_DIR}/no_runfiles" \
  run_parity_case "classifier resolved from ROOT/tools/ci/transient-lib.sh" setup_isolated_root_custom_lib --check src
PARITY_SH_BIN="${WORK_DIR}/isolated_bin/tidy.sh" PARITY_RS_BIN="${WORK_DIR}/isolated_bin/tidy" PARITY_RUNFILES_DIR="${WORK_DIR}/no_runfiles" \
  run_parity_case "failing top-level command in transient-lib.sh fails at start" setup_isolated_failing_lib --check src

PARITY_BASH_ENV="${WORK_DIR}/bash_env_hook.sh" run_parity_case "BASH_ENV read once at start and not re-read by internal subshells" setup_bash_env_logger --check src

run_parity_case "check mode: transient failure recovers after 2 retries" setup_transient_recovers_2 --check src
run_parity_case "check mode: transient failure recovers after 1 retry" setup_transient_recovers_1 --check src
run_parity_case "check mode: permanent transient failure reports INFRASTRUCTURE" setup_transient_permanent --check src
run_parity_case "check mode: mixed drifted and unreachable modules" setup_mixed_unreachable_and_drifted --check src
run_parity_case "check mode: failing sleep aborts retry with sleep exit code" setup_transient_failing_sleep --check src
PARITY_CUSTOM_PATH="${BIN_DIR}" run_parity_case "check mode: missing sleep aborts retry with exit 127" setup_transient_missing_sleep --check src

run_parity_case "fix mode: default without go.sum" setup_two_mods_drifted src
TOUCH_GOSUM=1 run_parity_case "fix mode: with go.sum modified" setup_fix_with_gosum --fix src
TOUCH_GOSUM=0 run_parity_case "fix mode: with go.sum unchanged" setup_fix_with_gosum --check --fix src
TIDY_FIX_RC=42 run_parity_case "fix mode: go mod tidy non-zero exit propagation" setup_two_mods_drifted src
TIDY_FIX_KILL_SIG=TERM run_parity_case "fix mode: go killed by SIGTERM exits 143 (128+15)" setup_two_mods_drifted src

run_parity_case "default roots: missing default root fails" setup_three_mods_tidy --check
run_parity_case "default roots: all present and tidy" setup_default_roots_present --check
run_parity_case "multiple roots on command line" setup_default_roots_present --check packages/pulumi/library/go/go.mod packages/pulumi/examples/go-foundation

run_parity_case "module directories with spaces and unicode" setup_unicode_and_spaces --check src
PARITY_UNSET_BWD=1 run_parity_case "BUILD_WORKSPACE_DIRECTORY unset uses git rev-parse --show-toplevel" setup_git_toplevel --check src
PARITY_UNSET_BWD=1 PARITY_STALE_PWD="${BASE_TMP}" run_parity_case "stale PWD (no git, no BUILD_WORKSPACE_DIRECTORY) uses getcwd in check mode" setup_three_mods_tidy --check src
PARITY_UNSET_BWD=1 PARITY_STALE_PWD="${BASE_TMP}" run_parity_case "stale PWD (no git, no BUILD_WORKSPACE_DIRECTORY) uses getcwd in fix mode" setup_two_mods_drifted src
PARITY_USE_CHECK_BIN=1 run_parity_case "check binary target with --check passed" setup_two_mods_drifted --check src
PARITY_USE_CHECK_BIN=1 run_parity_case "check binary target without --check defaults to fix mode" setup_two_mods_drifted src

# --- Closed stdout / stderr and /dev/full write error parity tests -----------
PARITY_CLOSE_STDOUT=1 run_parity_case "closed stdout (>&-) in fix mode fails at line 209 before go runs" setup_two_mods_drifted src
PARITY_CLOSE_STDOUT=1 run_parity_case "closed stdout (>&-) in check mode fails at line 209 before go runs" setup_two_mods_drifted --check src
PARITY_CLOSE_STDOUT=1 run_parity_case "closed stdout (>&-) on -h fails via sed" setup_three_mods_tidy -h
PARITY_CLOSE_STDERR=1 run_parity_case "closed stderr (2>&-) on unknown flag exits 1" setup_three_mods_tidy --bogus

# Explicitly assert no go call happened in the closed-stdout fix-mode snapshot.
if [ ! -s "${SNAP_RS}/calls.log" ]; then
  printf '  \033[32mPASS\033[0m  closed stdout in fix mode: verified zero go invocations\n'
  PASS=$((PASS + 1))
else
  printf '  \033[31mFAIL\033[0m  closed stdout in fix mode: expected zero go invocations\n' >&2
  FAIL=$((FAIL + 1))
fi

if [ -c /dev/full ] && ! (printf 'x' >/dev/full) 2>/dev/null; then
  PARITY_STDOUT_FILE="/dev/full" run_parity_case "/dev/full stdout in fix mode fails at line 209 before go runs" setup_two_mods_drifted src
  PARITY_STDOUT_FILE="/dev/full" run_parity_case "/dev/full stdout in check mode fails at line 209 before go runs" setup_two_mods_drifted --check src
else
  printf '  \033[33mSKIP\033[0m  /dev/full write error cases (/dev/full not available on macOS)\n'
fi

# --- Broken pipe (SIGPIPE default) parity test -------------------------------
test_broken_pipe_parity() {
  local test_bash="$1"
  local name="broken pipe (SIGPIPE default): killed with 141, stops mid-run, cleans temp file [${test_bash}]"
  rm -rf "${WORK_DIR}" "${BIN_DIR}" "${SNAP_SH}" "${SNAP_RS}"
  mkdir -p "${WORK_DIR}/tmp_sh" "${BIN_DIR}" "${SNAP_SH}" "${SNAP_RS}"
  setup_two_mods_drifted
  ln -sf "${test_bash}" "${BIN_DIR}/bash"

  (
    set -o pipefail
    cd "${WORK_DIR}"
    TMPDIR="${WORK_DIR}/tmp_sh" PATH="${BIN_DIR}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${WORK_DIR}" \
      "${test_bash}" "${TIDY_SH}" --check src 2>"${SNAP_SH}/stderr" | head -n 1 >"${SNAP_SH}/stdout"
  )
  echo "$?" > "${SNAP_SH}/rc"
  local sh_calls sh_leaked
  sh_calls="$(grep -c '^go argv=' "${BIN_DIR}/calls.log" 2>/dev/null || echo 0)"
  sh_leaked="$(find "${WORK_DIR}/tmp_sh" -type f | wc -l | tr -d ' ')"

  rm -rf "${WORK_DIR}" "${BIN_DIR}"
  mkdir -p "${WORK_DIR}/tmp_rs" "${BIN_DIR}"
  setup_two_mods_drifted
  ln -sf "${test_bash}" "${BIN_DIR}/bash"

  (
    set -o pipefail
    cd "${WORK_DIR}"
    TMPDIR="${WORK_DIR}/tmp_rs" PATH="${BIN_DIR}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${WORK_DIR}" \
      "${TIDY_RS}" --check src 2>"${SNAP_RS}/stderr" | head -n 1 >"${SNAP_RS}/stdout"
  )
  echo "$?" > "${SNAP_RS}/rc"
  local rs_calls rs_leaked
  rs_calls="$(grep -c '^go argv=' "${BIN_DIR}/calls.log" 2>/dev/null || echo 0)"
  rs_leaked="$(find "${WORK_DIR}/tmp_rs" -type f | wc -l | tr -d ' ')"

  if [ "$(cat "${SNAP_SH}/rc")" = "141" ] \
    && [ "$(cat "${SNAP_RS}/rc")" = "141" ] \
    && cmp -s "${SNAP_SH}/stdout" "${SNAP_RS}/stdout" \
    && [ ! -s "${SNAP_RS}/stderr" ] \
    && [ "${sh_calls}" = "1" ] \
    && [ "${rs_calls}" = "1" ] \
    && [ "${sh_leaked}" = "0" ] \
    && [ "${rs_leaked}" = "0" ]; then
    printf '  \033[32mPASS\033[0m  %s\n' "${name}"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s (sh_rc=%s rs_rc=%s sh_calls=%s rs_calls=%s sh_leaked=%s rs_leaked=%s)\n' \
      "${name}" "$(cat "${SNAP_SH}/rc")" "$(cat "${SNAP_RS}/rc")" "${sh_calls}" "${rs_calls}" "${sh_leaked}" "${rs_leaked}" >&2
    diff -u "${SNAP_SH}/stdout" "${SNAP_RS}/stdout" >&2 || true
    cat "${SNAP_RS}/stderr" >&2 || true
    FAIL=$((FAIL + 1))
  fi
}

# --- SIGPIPE ignored at entry (trap '' PIPE) parity test ---------------------
test_sigpipe_ignored_parity() {
  local test_bash="$1"
  local mode_label="$2"
  shift 2
  local name="SIGPIPE ignored at entry (${mode_label}): EPIPE write error, cleans temp file [${test_bash}]"

  rm -rf "${WORK_DIR}" "${BIN_DIR}" "${SNAP_SH}" "${SNAP_RS}"
  mkdir -p "${WORK_DIR}/tmp_run" "${BIN_DIR}" "${SNAP_SH}" "${SNAP_RS}"
  setup_two_mods_drifted
  ln -sf "${test_bash}" "${BIN_DIR}/bash"

  (
    set -o pipefail
    trap '' PIPE
    cd "${WORK_DIR}"
    TMPDIR="${WORK_DIR}/tmp_run" PATH="${BIN_DIR}:${PATH}" GOWORK="" BUILD_WORKSPACE_DIRECTORY="${WORK_DIR}" \
      "${test_bash}" "${TIDY_SH}" "$@" 2>"${SNAP_SH}/stderr" | head -n 1 >"${SNAP_SH}/stdout"
  )
  echo "$?" > "${SNAP_SH}/rc"
  local sh_leaked
  sh_leaked="$(find "${WORK_DIR}/tmp_run" -type f | wc -l | tr -d ' ')"
  rm -rf "${WORK_DIR}/tmp_run"
  snapshot_state "${SNAP_SH}"

  rm -rf "${WORK_DIR}" "${BIN_DIR}"
  mkdir -p "${WORK_DIR}/tmp_run" "${BIN_DIR}"
  setup_two_mods_drifted
  ln -sf "${test_bash}" "${BIN_DIR}/bash"

  (
    set -o pipefail
    trap '' PIPE
    cd "${WORK_DIR}"
    TMPDIR="${WORK_DIR}/tmp_run" PATH="${BIN_DIR}:${PATH}" GOWORK="" BUILD_WORKSPACE_DIRECTORY="${WORK_DIR}" \
      "${TIDY_RS}" "$@" 2>"${SNAP_RS}/stderr" | head -n 1 >"${SNAP_RS}/stdout"
  )
  echo "$?" > "${SNAP_RS}/rc"
  local rs_leaked
  rs_leaked="$(find "${WORK_DIR}/tmp_run" -type f | wc -l | tr -d ' ')"
  rm -rf "${WORK_DIR}/tmp_run"
  snapshot_state "${SNAP_RS}"

  local ok=0
  for item in rc stdout stderr calls.log fs_state.txt; do
    if ! cmp -s "${SNAP_SH}/${item}" "${SNAP_RS}/${item}"; then
      ok=1
      printf '  \033[31mDIFF\033[0m  %s (%s)\n' "${name}" "${item}" >&2
      diff -u "${SNAP_SH}/${item}" "${SNAP_RS}/${item}" >&2 || true
    fi
  done
  if [ "${sh_leaked}" != "0" ] || [ "${rs_leaked}" != "0" ]; then
    ok=1
  fi

  if [ "${ok}" -eq 0 ]; then
    printf '  \033[32mPASS\033[0m  %s\n' "${name}"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s (sh_leaked=%s rs_leaked=%s)\n' "${name}" "${sh_leaked}" "${rs_leaked}" >&2
    FAIL=$((FAIL + 1))
  fi
}

# --- SIGINT ignored in background job with kill -INT parity test -------------
test_sigint_ignored_background_parity() {
  local test_bash="$1"
  local name="SIGINT ignored at entry (background & job + kill -INT): finishes tidy and exits 0 [${test_bash}]"

  rm -rf "${WORK_DIR}" "${BIN_DIR}" "${SNAP_SH}" "${SNAP_RS}"
  mkdir -p "${WORK_DIR}/tmp_run" "${BIN_DIR}" "${SNAP_SH}" "${SNAP_RS}"
  setup_two_mods_drifted
  ln -sf "${test_bash}" "${BIN_DIR}/bash"

  (
    trap '' INT
    cd "${WORK_DIR}"
    GO_HOOK_CMD='kill -INT "$PPID" 2>/dev/null || true' \
      TMPDIR="${WORK_DIR}/tmp_run" PATH="${BIN_DIR}:${PATH}" GOWORK="" BUILD_WORKSPACE_DIRECTORY="${WORK_DIR}" \
      "${test_bash}" "${TIDY_SH}" src >"${SNAP_SH}/stdout" 2>"${SNAP_SH}/stderr" &
    bg_pid=$!
    kill -INT "${bg_pid}" 2>/dev/null || true
    wait "${bg_pid}"
  )
  echo "$?" > "${SNAP_SH}/rc"
  local sh_leaked
  sh_leaked="$(find "${WORK_DIR}/tmp_run" -type f | wc -l | tr -d ' ')"
  rm -rf "${WORK_DIR}/tmp_run"
  snapshot_state "${SNAP_SH}"

  rm -rf "${WORK_DIR}" "${BIN_DIR}"
  mkdir -p "${WORK_DIR}/tmp_run" "${BIN_DIR}"
  setup_two_mods_drifted
  ln -sf "${test_bash}" "${BIN_DIR}/bash"

  (
    trap '' INT
    cd "${WORK_DIR}"
    GO_HOOK_CMD='kill -INT "$PPID" 2>/dev/null || true' \
      TMPDIR="${WORK_DIR}/tmp_run" PATH="${BIN_DIR}:${PATH}" GOWORK="" BUILD_WORKSPACE_DIRECTORY="${WORK_DIR}" \
      "${TIDY_RS}" src >"${SNAP_RS}/stdout" 2>"${SNAP_RS}/stderr" &
    bg_pid=$!
    kill -INT "${bg_pid}" 2>/dev/null || true
    wait "${bg_pid}"
  )
  echo "$?" > "${SNAP_RS}/rc"
  local rs_leaked
  rs_leaked="$(find "${WORK_DIR}/tmp_run" -type f | wc -l | tr -d ' ')"
  rm -rf "${WORK_DIR}/tmp_run"
  snapshot_state "${SNAP_RS}"

  local ok=0
  for item in rc stdout stderr calls.log fs_state.txt; do
    if ! cmp -s "${SNAP_SH}/${item}" "${SNAP_RS}/${item}"; then
      ok=1
      printf '  \033[31mDIFF\033[0m  %s (%s)\n' "${name}" "${item}" >&2
      diff -u "${SNAP_SH}/${item}" "${SNAP_RS}/${item}" >&2 || true
    fi
  done
  if [ "$(cat "${SNAP_RS}/rc")" != "0" ] || [ "${sh_leaked}" != "0" ] || [ "${rs_leaked}" != "0" ]; then
    ok=1
  fi

  if [ "${ok}" -eq 0 ]; then
    printf '  \033[32mPASS\033[0m  %s\n' "${name}"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s (rc=%s sh_leaked=%s rs_leaked=%s)\n' \
      "${name}" "$(cat "${SNAP_RS}/rc")" "${sh_leaked}" "${rs_leaked}" >&2
    FAIL=$((FAIL + 1))
  fi
}

for _b in "${BASH_LIST[@]}"; do
  test_broken_pipe_parity "${_b}"
  test_sigpipe_ignored_parity "${_b}" "check mode" --check src
  test_sigpipe_ignored_parity "${_b}" "fix mode" src
  test_sigint_ignored_background_parity "${_b}"
done

# --- SIGTERM temp file cleanup parity test -----------------------------------
test_sigterm_tempfile_cleanup() {
  local name="SIGTERM cleanup: removes mktemp diff_file on signal termination"
  rm -rf "${WORK_DIR}" "${BIN_DIR}"
  mkdir -p "${WORK_DIR}/tmp_rs" "${BIN_DIR}" "${WORK_DIR}/src/m1"
  printf 'module example.com/m1\n\ngo 1.26.2\n' > "${WORK_DIR}/src/m1/go.mod"
  cat > "${BIN_DIR}/go" <<'EOF'
#!/usr/bin/env bash
kill -TERM "$PPID" 2>/dev/null || true
sleep 1
exit 1
EOF
  chmod +x "${BIN_DIR}/go"

  (
    cd "${WORK_DIR}"
    TMPDIR="${WORK_DIR}/tmp_rs" PATH="${BIN_DIR}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${WORK_DIR}" \
      "${TIDY_RS}" --check src >/dev/null 2>&1
  )
  local rs_leaked
  rs_leaked="$(find "${WORK_DIR}/tmp_rs" -type f | wc -l | tr -d ' ')"
  if [ "${rs_leaked}" = "0" ]; then
    printf '  \033[32mPASS\033[0m  %s\n' "${name}"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s (rs_leaked=%s)\n' "${name}" "${rs_leaked}" >&2
    FAIL=$((FAIL + 1))
  fi
}
test_sigterm_tempfile_cleanup

echo
printf '  %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
