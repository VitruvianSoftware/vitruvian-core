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
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Side-by-side behavioural parity test comparing bazel-cache.sh and the Rust
# binary across normal, edge-case, and failure-injection scenarios.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SH_BIN="${1:-${SCRIPT_DIR}/bazel-cache.sh}"
RS_BIN="${2:-${SCRIPT_DIR}/gc}"

if [[ "${SH_BIN}" != /* ]]; then
  SH_BIN="${PWD}/${SH_BIN}"
fi
if [[ "${RS_BIN}" != /* ]]; then
  RS_BIN="${PWD}/${RS_BIN}"
fi

[[ -f "${SH_BIN}" ]] || { echo "FAIL: sh script not found: ${SH_BIN}" >&2; exit 1; }
[[ -x "${RS_BIN}" ]] || { echo "FAIL: rust binary not executable: ${RS_BIN}" >&2; exit 1; }

WORK="$(mktemp -d)"
cleanup() {
  chmod -R u+rwX "${WORK}" 2>/dev/null || true
  rm -rf "${WORK}"
}
trap cleanup EXIT

export LC_ALL=C
BASE_PATH="${PATH}:/sbin:/usr/sbin"
export PATH="${BASE_PATH}"
export GIT_AUTHOR_NAME="Test Author"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test Author"
export GIT_COMMITTER_EMAIL="test@example.com"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
export GIT_CONFIG_NOSYSTEM=1

md5_of() {
  if command -v md5 >/dev/null 2>&1; then
    printf '%s' "$1" | md5 -q
  elif [[ -x /sbin/md5 ]]; then
    printf '%s' "$1" | /sbin/md5 -q
  else
    printf '%s' "$1" | md5sum | awk '{print $1}'
  fi
}

# Normalise ONLY the leading script/binary path (`${SH_BIN}:` or `${RS_BIN}:`)
# to `<prog>:`, preserving `line <N>` verbatim so any wrong line number fails.
# For `printf: write error: Broken pipe`, normalise `line <N>` because when
# piped to `head -n K` with SIGPIPE ignored, kernel pipe scheduling determines
# whether `head` closes the read end before line 63 (`info`), line 250 (`KEEP`),
# or line 255 (`RECLAIM`).
normalize_stderr() {
  sed \
    -e "s|^${SH_BIN}:|<prog>:|" \
    -e "s|^${RS_BIN}:|<prog>:|" \
    -e 's|^<prog>: line [0-9]*: printf: write error: Broken pipe$|<prog>: line <N>: printf: write error: Broken pipe|'
}

snapshot_state() {
  local scn_dir="$1" out_dir="$2"
  if [[ -d "${scn_dir}" ]]; then
    (
      cd "${scn_dir}"
      find . -mindepth 1 | LC_ALL=C sort > "${out_dir}/tree.txt"
      while IFS= read -r rel; do
        if [[ -L "${rel}" ]]; then
          printf '%s:link\n' "${rel}"
        elif [[ -f "${rel}" ]]; then
          if [[ -r "${rel}" ]]; then
            printf '%s:file:%s\n' "${rel}" "$(wc -c < "${rel}" | tr -d ' ')"
          else
            printf '%s:file:unreadable\n' "${rel}"
          fi
        elif [[ -d "${rel}" ]]; then
          printf '%s:dir\n' "${rel}"
        fi
      done < "${out_dir}/tree.txt" > "${out_dir}/fs_meta.txt"
    )
  else
    : > "${out_dir}/tree.txt"
    : > "${out_dir}/fs_meta.txt"
  fi
}

SCENARIOS_RUN=0

wipe_scn() {
  local target="$1"
  if [[ -e "${target}" ]]; then
    chmod -R u+rwX "${target}" 2>/dev/null || true
    rm -rf "${target}"
  fi
}

# run_parity_scenario <name> <setup_fn> <cwd_rel> [args...]
# Builds the scenario at ${WORK}/scn, runs .sh, snapshots, wipes, rebuilds at
# the exact same path ${WORK}/scn, runs Rust, snapshots, and diffs all outputs.
run_parity_scenario() {
  local name="$1"
  local setup_fn="$2"
  local cwd_rel="$3"
  shift 3

  local scn="${WORK}/scn"
  local sh_snap="${WORK}/snap_sh"
  local rs_snap="${WORK}/snap_rs"
  wipe_scn "${scn}"
  rm -rf "${sh_snap}" "${rs_snap}"
  mkdir -p "${sh_snap}" "${rs_snap}"

  # --- Run 1: bash implementation ---
  mkdir -p "${scn}"
  "${setup_fn}" "${scn}"
  local sh_rc=0
  (
    cd "${scn}/${cwd_rel}"
    PATH="${RUN_PATH:-${PATH}}" HOME="${scn}/home" GIT_CONFIG_GLOBAL="${scn}/home/.gitconfig" \
      env bash "${SH_BIN}" "$@"
  ) >"${sh_snap}/stdout.txt" 2>"${sh_snap}/stderr.raw" || sh_rc=$?
  printf '%d\n' "${sh_rc}" > "${sh_snap}/rc.txt"
  normalize_stderr < "${sh_snap}/stderr.raw" > "${sh_snap}/stderr.txt"
  if [[ -e "${scn}/kill_was_called" ]]; then
    echo "FAIL [${name}]: external kill binary was invoked by bash!" >&2
    exit 1
  fi
  if [[ -f "${scn}/tool_calls.log" ]]; then
    cp "${scn}/tool_calls.log" "${sh_snap}/tool_calls.log"
    rm -f "${scn}/tool_calls.log"
  else
    : > "${sh_snap}/tool_calls.log"
  fi
  snapshot_state "${scn}" "${sh_snap}"

  # --- Run 2: Rust implementation (at the exact same path) ---
  wipe_scn "${scn}"
  mkdir -p "${scn}"
  "${setup_fn}" "${scn}"
  local rs_rc=0
  (
    cd "${scn}/${cwd_rel}"
    PATH="${RUN_PATH:-${PATH}}" HOME="${scn}/home" GIT_CONFIG_GLOBAL="${scn}/home/.gitconfig" \
      "${RS_BIN}" "$@"
  ) >"${rs_snap}/stdout.txt" 2>"${rs_snap}/stderr.raw" || rs_rc=$?
  printf '%d\n' "${rs_rc}" > "${rs_snap}/rc.txt"
  normalize_stderr < "${rs_snap}/stderr.raw" > "${rs_snap}/stderr.txt"
  if [[ -e "${scn}/kill_was_called" ]]; then
    echo "FAIL [${name}]: external kill binary was invoked by Rust!" >&2
    exit 1
  fi
  if [[ -f "${scn}/tool_calls.log" ]]; then
    cp "${scn}/tool_calls.log" "${rs_snap}/tool_calls.log"
    rm -f "${scn}/tool_calls.log"
  else
    : > "${rs_snap}/tool_calls.log"
  fi
  snapshot_state "${scn}" "${rs_snap}"

  # --- Compare ---
  local failed=0
  for facet in rc.txt stdout.txt stderr.txt tree.txt fs_meta.txt tool_calls.log; do
    if ! diff -u "${sh_snap}/${facet}" "${rs_snap}/${facet}" > "${WORK}/diff.txt"; then
      echo "FAIL [${name}]: mismatch in ${facet}:" >&2
      cat "${WORK}/diff.txt" >&2
      failed=1
    fi
  done
  if (( failed != 0 )); then
    exit 1
  fi
  SCENARIOS_RUN=$((SCENARIOS_RUN + 1))
  echo "ok ${SCENARIOS_RUN} - ${name}"
}

# Helper to compute `touch -t` format YYYYMMDDhhmm.SS for `N` seconds ago.
ts_seconds_ago() {
  local secs="$1"
  local now_epoch target_epoch
  now_epoch="$(date +%s)"
  target_epoch=$((now_epoch - secs))
  date -r "${target_epoch}" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@${target_epoch}" +%Y%m%d%H%M.%S
}

# --- Scenario setups ---

setup_empty() {
  local scn="$1"
  mkdir -p "${scn}/home" "${scn}/cwd"
}

setup_outside_git() {
  local scn="$1"
  mkdir -p "${scn}/home/.cache/bazel/_bazel_${USER}" "${scn}/cwd"
}

setup_all_kept() {
  local scn="$1"
  local home="${scn}/home"
  local repo="${scn}/repo"
  mkdir -p "${home}"
  git init -q "${repo}"
  git -C "${repo}" commit --allow-empty -q -m "init"

  local uroot="${home}/.cache/bazel/_bazel_${USER}"
  mkdir -p "${uroot}/install" "${uroot}/cache"
  local fresh="${uroot}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  mkdir -p "${fresh}"
  dd if=/dev/zero of="${fresh}/blob" bs=1024 count=16 status=none
}

setup_full_matrix() {
  local scn="$1"
  local home="${scn}/home"
  local repo="${scn}/repo"
  local wt_live="${scn}/wt-live"
  local wt_held="${scn}/wt-held"
  mkdir -p "${home}"

  git init -q "${repo}"
  git -C "${repo}" commit --allow-empty -q -m "init"
  git -C "${repo}" worktree add -q -b b-live "${wt_live}"
  git -C "${repo}" worktree add -q -b b-held "${wt_held}"
  git -C "${repo}" worktree lock --reason "keep" "${wt_held}"

  local uroot="${home}/.cache/bazel/_bazel_${USER}"
  mkdir -p "${uroot}"

  make_base() {
    local name="$1" ws="$2" age_days="$3" pid="$4"
    local d="${uroot}/${name}"
    mkdir -p "${d}/server"
    dd if=/dev/zero of="${d}/dummy" bs=1024 count=64 status=none
    if [[ -n "${ws}" ]]; then
      printf '%s' "${ws}" > "${d}/DO_NOT_BUILD_HERE"
    fi
    if [[ -n "${pid}" ]]; then
      printf '%s\n' "${pid}" > "${d}/server/server.pid.txt"
    fi
    if (( age_days > 0 )); then
      local ts
      ts="$(ts_seconds_ago $((age_days * 86400 + 3600)))"
      if [[ -f "${d}/DO_NOT_BUILD_HERE" ]]; then
        touch -t "${ts}" "${d}/DO_NOT_BUILD_HERE"
      fi
      if [[ -f "${d}/server/server.pid.txt" ]]; then
        touch -t "${ts}" "${d}/server/server.pid.txt"
      fi
      touch -t "${ts}" "${d}/server" "${d}/dummy" "${d}"
    fi
  }

  local old_ts
  old_ts="$(ts_seconds_ago $((10 * 86400 + 3600)))"

  # 1. Stale unknown base
  make_base "stale111stale111stale111stale111" "" 10 ""
  # 2. Live server pid
  make_base "live2222live2222live2222live2222" "" 10 "$$"
  # 3. Dead server pid (should not count as busy)
  make_base "dead2222dead2222dead2222dead2222" "" 10 "999999"
  # 4. Fresh unknown base
  make_base "fresh333fresh333fresh333fresh333" "" 0 ""
  # 5. Orphan worktree >1d old
  make_base "orphan44orphan44orphan44orphan44" "${scn}/wt-deleted-long-ago" 5 ""
  # 6. Orphan worktree <1d old (guarded)
  make_base "recur666recur666recur666recur666" "${scn}/wt-being-recreated" 0 ""
  # 7. Primary live worktree >10d old
  make_base "primary5primary5primary5primary5" "${repo}" 10 ""
  # 8. Workspace identified via execroot/DO_NOT_BUILD_HERE
  mkdir -p "${uroot}/exec7777exec7777exec7777exec7777/execroot"
  printf '%s\n' "${scn}/wt-gone-execroot" > "${uroot}/exec7777exec7777exec7777exec7777/execroot/DO_NOT_BUILD_HERE"
  touch -t "${old_ts}" "${uroot}/exec7777exec7777exec7777exec7777" "${uroot}/exec7777exec7777exec7777exec7777/execroot" "${uroot}/exec7777exec7777exec7777exec7777/execroot/DO_NOT_BUILD_HERE"
  # 9. Workspace identified via NUL-separated server/cmdline
  mkdir -p "${uroot}/cmdl8888cmdl8888cmdl8888cmdl8888/server"
  printf 'bazel\0--workspace_directory=%s\0build\0' "${scn}/wt-gone-cmdline" > "${uroot}/cmdl8888cmdl8888cmdl8888cmdl8888/server/cmdline"
  touch -t "${old_ts}" "${uroot}/cmdl8888cmdl8888cmdl8888cmdl8888" "${uroot}/cmdl8888cmdl8888cmdl8888cmdl8888/server" "${uroot}/cmdl8888cmdl8888cmdl8888cmdl8888/server/cmdline"
  # 10. Existing directory that is NOT in git worktree list (old vs new)
  mkdir -p "${scn}/other-checkout-old" "${scn}/other-checkout-new"
  make_base "exold999exold999exold999exold999" "${scn}/other-checkout-old" 10 ""
  make_base "exnew999exnew999exnew999exnew999" "${scn}/other-checkout-new" 0 ""
  # 11. Live worktree matched by MD5 of path (no DO_NOT_BUILD_HERE file)
  local h_live
  h_live="$(md5_of "${wt_live}")"
  make_base "${h_live}" "" 10 ""

  # Non-32-hex siblings must be skipped
  mkdir -p "${uroot}/install/abc" "${uroot}/cache/repos/v1"

  # Per-worktree output_user_roots
  local wt_roots="${home}/.cache/bazel/worktrees"
  mkdir -p "${wt_roots}/repo-gone" "${wt_roots}/repo-gone-fresh" \
           "${wt_roots}/repo-held" "${wt_roots}/repo-pinned" \
           "${wt_roots}/repo-busy/aaaa1111aaaa1111aaaa1111aaaa1111/server" \
           "${wt_roots}/repo-childws/bbbb2222bbbb2222bbbb2222bbbb2222" \
           "${wt_roots}/repo-existing-nonwt" \
           "${wt_roots}/repo-nomarker-old" "${wt_roots}/repo-nomarker-new"

  printf '%s\n' "${scn}/wt-no-longer-here" > "${wt_roots}/repo-gone/.vitruvian-worktree"
  dd if=/dev/zero of="${wt_roots}/repo-gone/blob" bs=1024 count=32 status=none
  touch -t "${old_ts}" "${wt_roots}/repo-gone" "${wt_roots}/repo-gone/.vitruvian-worktree" "${wt_roots}/repo-gone/blob"

  printf '%s\n' "${scn}/wt-just-removed" > "${wt_roots}/repo-gone-fresh/.vitruvian-worktree"
  dd if=/dev/zero of="${wt_roots}/repo-gone-fresh/blob" bs=1024 count=32 status=none

  printf '%s\n' "${wt_held}" > "${wt_roots}/repo-held/.vitruvian-worktree"
  dd if=/dev/zero of="${wt_roots}/repo-held/blob" bs=1024 count=32 status=none
  touch -t "${old_ts}" "${wt_roots}/repo-held" "${wt_roots}/repo-held/.vitruvian-worktree" "${wt_roots}/repo-held/blob"

  printf 'startup --output_user_root=%s\n' "${wt_roots}/repo-pinned" > "${repo}/user.bazelrc"
  dd if=/dev/zero of="${wt_roots}/repo-pinned/blob" bs=1024 count=32 status=none
  touch -t "${old_ts}" "${wt_roots}/repo-pinned" "${wt_roots}/repo-pinned/blob"

  printf '%s\n' "$$" > "${wt_roots}/repo-busy/aaaa1111aaaa1111aaaa1111aaaa1111/server/server.pid.txt"
  touch -t "${old_ts}" "${wt_roots}/repo-busy"

  printf '%s\n' "${scn}/wt-gone-childws" > "${wt_roots}/repo-childws/bbbb2222bbbb2222bbbb2222bbbb2222/DO_NOT_BUILD_HERE"
  touch -t "${old_ts}" "${wt_roots}/repo-childws" "${wt_roots}/repo-childws/bbbb2222bbbb2222bbbb2222bbbb2222" "${wt_roots}/repo-childws/bbbb2222bbbb2222bbbb2222bbbb2222/DO_NOT_BUILD_HERE"

  printf '%s\n' "${scn}/other-checkout-old" > "${wt_roots}/repo-existing-nonwt/.vitruvian-worktree"
  touch -t "${old_ts}" "${wt_roots}/repo-existing-nonwt" "${wt_roots}/repo-existing-nonwt/.vitruvian-worktree"

  touch -t "${old_ts}" "${wt_roots}/repo-nomarker-old"

  # Stray bases directly under ~/Library/Caches/bazel and ~/.cache/bazel
  local stray1="${home}/Library/Caches/bazel/deadbeefdeadbeefdeadbeefdeadbeef"
  local stray2="${home}/.cache/bazel/cafebabecafebabecafebabecafebabe"
  local stray_busy="${home}/.cache/bazel/11112222333344445555666677778888"
  mkdir -p "${stray1}/execroot" "${stray2}/external" "${stray_busy}/server"
  printf '%s\n' "$$" > "${stray_busy}/server/server.pid.txt"
  dd if=/dev/zero of="${stray1}/execroot/blob" bs=1024 count=32 status=none
  dd if=/dev/zero of="${stray2}/external/blob" bs=1024 count=32 status=none
}

setup_faked_tools() {
  local scn="$1"
  setup_all_kept "${scn}"
  local uroot="${scn}/home/.cache/bazel/_bazel_${USER}"
  local stale="${uroot}/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  local stale_unremovable="${uroot}/cccccccccccccccccccccccccccccccc"
  local live_b="${uroot}/dddddddddddddddddddddddddddddddd"
  mkdir -p "${stale}" "${stale_unremovable}" "${live_b}/server"
  printf '%s\n' "$$" > "${live_b}/server/server.pid.txt"
  local old_ts
  old_ts="$(ts_seconds_ago $((10 * 86400 + 3600)))"
  touch -t "${old_ts}" "${stale}" "${stale_unremovable}" "${live_b}"

  # Create fake du, date, kill, chmod, rm wrappers on PATH that record every
  # invocation (argv[0] + all arguments with boundaries + sorted env minus volatile vars).
  # Note that bash uses its `kill` builtin, so `kill` must NEVER be called by either.
  mkdir -p "${scn}/fakebin"
  cat > "${scn}/fakebin/_log_helper.sh" <<EOF
log_invocation() {
  {
    printf 'ARGV:'
    printf '<%s>' "\$0" "\$@"
    printf '\nENV:'
    /usr/bin/env -0 | /usr/bin/grep -zv -E '^(SHLVL|_)=|^BASH_FUNC_' | /usr/bin/sort -z | /usr/bin/tr '\0' '|'
    printf '\n'
  } >> "${scn}/tool_calls.log"
}
EOF
  cat > "${scn}/fakebin/du" <<EOF
#!/usr/bin/env bash
source "${scn}/fakebin/_log_helper.sh"
log_invocation "\$@"
printf '2097152\t%s\n' "\$2"
EOF
  cat > "${scn}/fakebin/date" <<EOF
#!/usr/bin/env bash
source "${scn}/fakebin/_log_helper.sh"
log_invocation "\$@"
exit 1
EOF
  cat > "${scn}/fakebin/kill" <<EOF
#!/usr/bin/env bash
source "${scn}/fakebin/_log_helper.sh"
log_invocation "\$@"
: > "${scn}/kill_was_called"
exit 1
EOF
  cat > "${scn}/fakebin/chmod" <<EOF
#!/usr/bin/env bash
source "${scn}/fakebin/_log_helper.sh"
log_invocation "\$@"
exec /bin/chmod "\$@"
EOF
  cat > "${scn}/fakebin/rm" <<EOF
#!/usr/bin/env bash
source "${scn}/fakebin/_log_helper.sh"
log_invocation "\$@"
case "\$*" in
  *cccccccccccccccccccccccccccccccc*) exit 1 ;;
esac
exec /bin/rm "\$@"
EOF
  chmod +x "${scn}/fakebin/du" "${scn}/fakebin/date" "${scn}/fakebin/kill" \
           "${scn}/fakebin/chmod" "${scn}/fakebin/rm"
}

# Finding 1: --days with unit suffixes (0, 12h, 30d) and near-threshold ages
setup_age_thresholds() {
  local scn="$1"
  setup_all_kept "${scn}"
  local uroot="${scn}/home/.cache/bazel/_bazel_${USER}"
  local wtroots="${scn}/home/.cache/bazel/worktrees"
  mkdir -p "${uroot}" "${wtroots}"

  local ts_6h ts_11h40m ts_12h20m ts_23h40m ts_24h20m ts_29d20h ts_30d4h
  ts_6h="$(ts_seconds_ago $((6 * 3600)))"
  ts_11h40m="$(ts_seconds_ago $((11 * 3600 + 2400)))"
  ts_12h20m="$(ts_seconds_ago $((12 * 3600 + 1200)))"
  ts_23h40m="$(ts_seconds_ago $((23 * 3600 + 2400)))"
  ts_24h20m="$(ts_seconds_ago $((24 * 3600 + 1200)))"
  ts_29d20h="$(ts_seconds_ago $((29 * 86400 + 20 * 3600)))"
  ts_30d4h="$(ts_seconds_ago $((30 * 86400 + 4 * 3600)))"

  mkdir -p "${uroot}/age_06h" "${uroot}/age_11h40m" "${uroot}/age_12h20m" \
           "${uroot}/age_23h40m" "${uroot}/age_24h20m" \
           "${uroot}/age_29d20h" "${uroot}/age_30d04h" \
           "${uroot}/orphan_23h40m" "${uroot}/orphan_24h20m" \
           "${wtroots}/wt_11h40m" "${wtroots}/wt_12h20m"

  printf '%s\n' "${scn}/gone-ws-1" > "${uroot}/orphan_23h40m/DO_NOT_BUILD_HERE"
  printf '%s\n' "${scn}/gone-ws-2" > "${uroot}/orphan_24h20m/DO_NOT_BUILD_HERE"

  touch -t "${ts_6h}"     "${uroot}/age_06h"
  touch -t "${ts_11h40m}" "${uroot}/age_11h40m" "${wtroots}/wt_11h40m"
  touch -t "${ts_12h20m}" "${uroot}/age_12h20m" "${wtroots}/wt_12h20m"
  touch -t "${ts_23h40m}" "${uroot}/age_23h40m" "${uroot}/orphan_23h40m/DO_NOT_BUILD_HERE" "${uroot}/orphan_23h40m"
  touch -t "${ts_24h20m}" "${uroot}/age_24h20m" "${uroot}/orphan_24h20m/DO_NOT_BUILD_HERE" "${uroot}/orphan_24h20m"
  touch -t "${ts_29d20h}" "${uroot}/age_29d20h"
  touch -t "${ts_30d4h}"  "${uroot}/age_30d04h"
}

# Finding 3: Unreadable .vitruvian-worktree marker
setup_unreadable_marker() {
  local scn="$1"
  setup_all_kept "${scn}"
  local wtroots="${scn}/home/.cache/bazel/worktrees"
  local old_ts
  old_ts="$(ts_seconds_ago $((10 * 86400)))"
  mkdir -p "${wtroots}/01_unreadable" "${wtroots}/02_after"
  printf '%s\n' "${scn}/gone-1" > "${wtroots}/01_unreadable/.vitruvian-worktree"
  printf '%s\n' "${scn}/gone-2" > "${wtroots}/02_after/.vitruvian-worktree"
  touch -t "${old_ts}" "${wtroots}/01_unreadable" "${wtroots}/02_after"
  chmod 000 "${wtroots}/01_unreadable/.vitruvian-worktree"
}

# Finding 4: PATH without external `kill` binary (plus EPERM pid 1 and ESRCH pid 999999)
setup_path_without_kill() {
  local scn="$1"
  setup_all_kept "${scn}"
  local uroot="${scn}/home/.cache/bazel/_bazel_${USER}"
  local old_ts
  old_ts="$(ts_seconds_ago $((10 * 86400)))"

  mkdir -p "${uroot}/pid_self/server" "${uroot}/pid_init/server" \
           "${uroot}/pid_dead/server" "${uroot}/pid_bogus/server"
  printf '%s\n' "$$" > "${uroot}/pid_self/server/server.pid.txt"
  printf '1\n'       > "${uroot}/pid_init/server/server.pid.txt"
  printf '999999\n'  > "${uroot}/pid_dead/server/server.pid.txt"
  printf 'notapid\n' > "${uroot}/pid_bogus/server/server.pid.txt"
  touch -t "${old_ts}" "${uroot}/pid_self" "${uroot}/pid_init" "${uroot}/pid_dead" "${uroot}/pid_bogus"

  mkdir -p "${scn}/nokill_bin"
  for tool in env bash basename id git sed tr head tail cat cut awk find du date chmod rm md5sum md5 openssl; do
    if p="$(command -v "${tool}" 2>/dev/null)"; then
      ln -s "${p}" "${scn}/nokill_bin/${tool}"
    fi
  done
}

# Finding 6 & X2: Locale collation under LC_ALL=en_US.UTF-8
setup_locale_collation() {
  local scn="$1"
  setup_all_kept "${scn}"
  local uroot="${scn}/home/.cache/bazel/_bazel_${USER}"
  local wtroots="${scn}/home/.cache/bazel/worktrees"
  local old_ts dname
  old_ts="$(ts_seconds_ago $((10 * 86400)))"

  # Names that order differently in C vs en_US.UTF-8, including `x` vs `x_y`
  # where the trailing `/` in `*/` flips order under UTF-8 collation.
  for dname in A0 A_0 AB A_B AC x x_y a-b A-c; do
    mkdir -p "${uroot}/${dname}" "${wtroots}/${dname}"
    touch -t "${old_ts}" "${uroot}/${dname}" "${wtroots}/${dname}"
  done
}

# Finding 8 & X3: Non-UTF-8 paths in workspace records, markers, user.bazelrc, and git worktree output
setup_non_utf8() {
  local scn="$1"
  setup_all_kept "${scn}"
  local uroot="${scn}/home/.cache/bazel/_bazel_${USER}"
  local wtroots="${scn}/home/.cache/bazel/worktrees"
  local old_ts
  old_ts="$(ts_seconds_ago $((10 * 86400)))"

  local bad_bytes=$'\xff\xfe'
  local fake_wt="${scn}/wt_${bad_bytes}"
  local fake_wt_hash
  fake_wt_hash="$(md5_of "${fake_wt}")"

  # Base matching md5 of non-UTF-8 live worktree path
  mkdir -p "${uroot}/${fake_wt_hash}"
  touch -t "${old_ts}" "${uroot}/${fake_wt_hash}"

  # Base with non-UTF-8 gone workspace in DO_NOT_BUILD_HERE
  mkdir -p "${uroot}/nonutf8_base_gone"
  printf '%s\n' "${scn}/gone_${bad_bytes}" > "${uroot}/nonutf8_base_gone/DO_NOT_BUILD_HERE"
  touch -t "${old_ts}" "${uroot}/nonutf8_base_gone/DO_NOT_BUILD_HERE" "${uroot}/nonutf8_base_gone"

  # Root with non-UTF-8 gone worktree in .vitruvian-worktree
  mkdir -p "${wtroots}/nonutf8_root_gone"
  printf '%s\n' "${scn}/gone_root_${bad_bytes}" > "${wtroots}/nonutf8_root_gone/.vitruvian-worktree"
  touch -t "${old_ts}" "${wtroots}/nonutf8_root_gone/.vitruvian-worktree" "${wtroots}/nonutf8_root_gone"

  # Mock git that outputs the real repo worktree, the non-UTF-8 worktree, and an unterminated last line
  mkdir -p "${scn}/fakegit"
  local real_git
  real_git="$(command -v git)"
  cat > "${scn}/fakegit/git" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
  printf 'worktree %s\n\n' "${scn}/repo"
  printf 'worktree %s/wt_\xff\xfe\n\n' "${scn}"
  printf 'worktree %s/unterminated_must_be_dropped' "${scn}"
  exit 0
fi
exec "${real_git}" "\$@"
EOF
  chmod +x "${scn}/fakegit/git"

  # Create a base that would match the unterminated line if it were not dropped
  local unterm_hash
  unterm_hash="$(md5_of "${scn}/unterminated_must_be_dropped")"
  mkdir -p "${uroot}/${unterm_hash}"
  touch -t "${old_ts}" "${uroot}/${unterm_hash}"
}

# Symlinked bases and roots
setup_symlinked_bases() {
  local scn="$1"
  setup_all_kept "${scn}"
  local uroot="${scn}/home/.cache/bazel/_bazel_${USER}"
  local wtroots="${scn}/home/.cache/bazel/worktrees"
  local stray_dir="${scn}/home/Library/Caches/bazel"
  local targets="${scn}/sym_targets"
  mkdir -p "${uroot}" "${wtroots}" "${stray_dir}" \
           "${targets}/t_stale" "${targets}/t_live" "${targets}/t_root" "${targets}/t_stray"
  echo "keep-me" > "${targets}/t_stale/payload"
  echo "keep-me" > "${targets}/t_live/payload"
  printf '%s\n' "${scn}/repo" > "${targets}/t_live/DO_NOT_BUILD_HERE"

  local old_ts
  old_ts="$(ts_seconds_ago $((10 * 86400)))"
  touch -t "${old_ts}" "${targets}/t_stale" "${targets}/t_live" "${targets}/t_root" "${targets}/t_stray"

  ln -s "${targets}/t_stale" "${uroot}/sym_stale"
  ln -s "${targets}/t_live"  "${uroot}/sym_live"
  ln -s "${targets}/no_such" "${uroot}/sym_broken"
  ln -s "${targets}/t_root"  "${wtroots}/sym_root"
  ln -s "${targets}/t_stray" "${stray_dir}/12345678123456781234567812345678"
  touch -h -t "${old_ts}" "${uroot}/sym_stale" "${uroot}/sym_live" "${uroot}/sym_broken" \
                          "${wtroots}/sym_root" "${stray_dir}/12345678123456781234567812345678" 2>/dev/null || true
}

# Finding 9: No md5 tool available
setup_no_md5_tool() {
  local scn="$1"
  setup_all_kept "${scn}"
  mkdir -p "${scn}/nomd5_bin"
  cat > "${scn}/nomd5_bin/md5sum" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${scn}/nomd5_bin/md5sum"
}

# Finding 9: USER unset and `id -un` failing
setup_failing_id() {
  local scn="$1"
  setup_empty "${scn}"
  mkdir -p "${scn}/failid_bin"
  cat > "${scn}/failid_bin/id" <<'EOF'
#!/usr/bin/env bash
echo "id: cannot find name for user ID 99999" >&2
exit 1
EOF
  chmod +x "${scn}/failid_bin/id"
}

# Y4: Child killed by a signal (exits 128+sig, never 1)
setup_signaled_id() {
  local scn="$1"
  setup_empty "${scn}"
  mkdir -p "${scn}/sigid_bin"
  cat > "${scn}/sigid_bin/id" <<'EOF'
#!/usr/bin/env bash
kill -TERM $$
EOF
  chmod +x "${scn}/sigid_bin/id"
}

# Round-2 Finding 4: First md5 candidate (md5sum) fails immediately without
# reading stdin; must fall back to next candidate without SIGPIPE killing parent.
setup_failing_md5_candidate() {
  local scn="$1"
  setup_all_kept "${scn}"
  mkdir -p "${scn}/failmd5_bin"
  cat > "${scn}/failmd5_bin/md5sum" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${scn}/failmd5_bin/md5sum"
}

# Round-2 Findings 2 & 3: Pidfile edge cases (" $$", "$$ ", "$$\t", "$$\r", "+$$",
# "java", "", "$$\0") and NUL bytes in DO_NOT_BUILD_HERE, execroot/DO_NOT_BUILD_HERE,
# .vitruvian-worktree, and user.bazelrc.
setup_pid_and_nul_edge_cases() {
  local scn="$1"
  setup_all_kept "${scn}"
  local repo="${scn}/repo"
  local uroot="${scn}/home/.cache/bazel/_bazel_${USER}"
  local wtroots="${scn}/home/.cache/bazel/worktrees"
  local old_ts
  old_ts="$(ts_seconds_ago $((10 * 86400)))"

  mkdir -p "${scn}/existing-ws" "${wtroots}/pinned-by-nul-rc"
  touch -t "${old_ts}" "${wtroots}/pinned-by-nul-rc"
  printf 'startup --output_user_root=%s/pinned-by-\0nul-rc\n' "${wtroots}" > "${repo}/user.bazelrc"

  # Pidfile edge cases
  mkdir -p "${uroot}/pid_lead_sp/server" \
           "${uroot}/pid_trail_sp/server" \
           "${uroot}/pid_trail_tab/server" \
           "${uroot}/pid_trail_cr/server" \
           "${uroot}/pid_plus/server" \
           "${uroot}/pid_java/server" \
           "${uroot}/pid_empty/server" \
           "${uroot}/pid_nul/server"
  printf ' %s\n' "$$"   > "${uroot}/pid_lead_sp/server/server.pid.txt"
  printf '%s \n' "$$"   > "${uroot}/pid_trail_sp/server/server.pid.txt"
  printf '%s\t\n' "$$"  > "${uroot}/pid_trail_tab/server/server.pid.txt"
  printf '%s\r\n' "$$"  > "${uroot}/pid_trail_cr/server/server.pid.txt"
  printf '+%s\n' "$$"   > "${uroot}/pid_plus/server/server.pid.txt"
  printf 'java\n'       > "${uroot}/pid_java/server/server.pid.txt"
  :                     > "${uroot}/pid_empty/server/server.pid.txt"
  printf '%s\0\n' "$$"  > "${uroot}/pid_nul/server/server.pid.txt"

  for d in pid_lead_sp pid_trail_sp pid_trail_tab pid_trail_cr pid_plus pid_java pid_empty pid_nul; do
    touch -t "${old_ts}" "${uroot}/${d}" "${uroot}/${d}/server" "${uroot}/${d}/server/server.pid.txt"
  done

  # NUL bytes in DO_NOT_BUILD_HERE (live worktree and existing workspace)
  mkdir -p "${uroot}/ws_nul_live" "${uroot}/ws_nul_existing" "${uroot}/ws_only_nul/execroot"
  printf '%s\0\n' "${repo}" > "${uroot}/ws_nul_live/DO_NOT_BUILD_HERE"
  printf '%s/existing-\0ws\n' "${scn}" > "${uroot}/ws_nul_existing/DO_NOT_BUILD_HERE"
  printf '\0\n' > "${uroot}/ws_only_nul/DO_NOT_BUILD_HERE"
  printf '%s\0\n' "${repo}" > "${uroot}/ws_only_nul/execroot/DO_NOT_BUILD_HERE"
  touch -t "${old_ts}" "${uroot}/ws_nul_live" "${uroot}/ws_nul_existing" "${uroot}/ws_only_nul"

  # NUL byte in .vitruvian-worktree marker (live worktree and existing workspace)
  mkdir -p "${wtroots}/marker_nul_live" "${wtroots}/marker_nul_existing"
  printf '%s\0\n' "${repo}" > "${wtroots}/marker_nul_live/.vitruvian-worktree"
  printf '%s/existing-\0ws\n' "${scn}" > "${wtroots}/marker_nul_existing/.vitruvian-worktree"
  touch -t "${old_ts}" "${wtroots}/marker_nul_live" "${wtroots}/marker_nul_existing"
}

# Scenario with Library/Caches/bazel/_bazel_$USER precedence and empty USER env
setup_library_caches() {
  local scn="$1"
  local actual_user
  actual_user="$(id -un)"
  mkdir -p "${scn}/home/Library/Caches/bazel/_bazel_${actual_user}/stale111stale111stale111stale111"
  mkdir -p "${scn}/home/.cache/bazel/_bazel_${actual_user}/stale222stale222stale222stale222"
  local old_ts
  old_ts="$(ts_seconds_ago $((10 * 86400)))"
  touch -t "${old_ts}" \
    "${scn}/home/Library/Caches/bazel/_bazel_${actual_user}/stale111stale111stale111stale111" \
    "${scn}/home/.cache/bazel/_bazel_${actual_user}/stale222stale222stale222stale222"
  mkdir -p "${scn}/cwd"
}

# Finding 2 & X1: Broken pipe during `gc --execute | head -n K` stops deleting
setup_broken_pipe() {
  local scn="$1"
  setup_all_kept "${scn}"
  local uroot="${scn}/home/.cache/bazel/_bazel_${USER}"
  local old_ts bname
  old_ts="$(ts_seconds_ago $((10 * 86400)))"
  for bname in stale_01 stale_02 stale_03 stale_04 stale_05; do
    mkdir -p "${uroot}/${bname}"
    touch -t "${old_ts}" "${uroot}/${bname}"
  done
  # Wrap `du` with a tiny sleep so `head` deterministically closes the pipe
  # after reading the N lines before the next item's `printf` writes to stdout.
  mkdir -p "${scn}/pipebin"
  cat > "${scn}/pipebin/du" <<'EOF'
#!/usr/bin/env bash
sleep 0.05
printf '1024\t%s\n' "$2"
EOF
  chmod +x "${scn}/pipebin/du"
}

run_home_unset_scenario() {
  local name="home-unset"
  local scn="${WORK}/scn"
  local sh_snap="${WORK}/snap_sh"
  local rs_snap="${WORK}/snap_rs"
  wipe_scn "${scn}"
  rm -rf "${sh_snap}" "${rs_snap}"
  mkdir -p "${scn}/cwd" "${sh_snap}" "${rs_snap}"

  local sh_rc=0
  (
    cd "${scn}/cwd"
    env -u HOME bash "${SH_BIN}" gc
  ) >"${sh_snap}/stdout.txt" 2>"${sh_snap}/stderr.raw" || sh_rc=$?
  printf '%d\n' "${sh_rc}" > "${sh_snap}/rc.txt"
  normalize_stderr < "${sh_snap}/stderr.raw" > "${sh_snap}/stderr.txt"

  local rs_rc=0
  (
    cd "${scn}/cwd"
    env -u HOME "${RS_BIN}" gc
  ) >"${rs_snap}/stdout.txt" 2>"${rs_snap}/stderr.raw" || rs_rc=$?
  printf '%d\n' "${rs_rc}" > "${rs_snap}/rc.txt"
  normalize_stderr < "${rs_snap}/stderr.raw" > "${rs_snap}/stderr.txt"

  for facet in rc.txt stdout.txt stderr.txt; do
    if ! diff -u "${sh_snap}/${facet}" "${rs_snap}/${facet}" > "${WORK}/diff.txt"; then
      echo "FAIL [${name}]: mismatch in ${facet}:" >&2
      cat "${WORK}/diff.txt" >&2
      exit 1
    fi
  done
  SCENARIOS_RUN=$((SCENARIOS_RUN + 1))
  echo "ok ${SCENARIOS_RUN} - ${name}"
}

run_broken_pipe_scenario() {
  local name="$1"
  local head_lines="$2"
  local ignore_sigpipe="${3:-0}"
  local scn="${WORK}/scn"
  local sh_snap="${WORK}/snap_sh"
  local rs_snap="${WORK}/snap_rs"
  wipe_scn "${scn}"
  rm -rf "${sh_snap}" "${rs_snap}"
  mkdir -p "${scn}" "${sh_snap}" "${rs_snap}"

  setup_broken_pipe "${scn}"
  local sh_rc=0
  (
    set +o pipefail
    if (( ignore_sigpipe != 0 )); then
      trap '' PIPE
    fi
    cd "${scn}/repo"
    PATH="${scn}/pipebin:${ORIG_PATH}" HOME="${scn}/home" GIT_CONFIG_GLOBAL="${scn}/home/.gitconfig" \
      env bash "${SH_BIN}" gc --days 1 --execute | head -n "${head_lines}"
    printf '%d\n' "${PIPESTATUS[0]}" > "${sh_snap}/rc.txt"
  ) >"${sh_snap}/stdout.txt" 2>"${sh_snap}/stderr.raw" || sh_rc=$?
  normalize_stderr < "${sh_snap}/stderr.raw" > "${sh_snap}/stderr.txt"
  snapshot_state "${scn}" "${sh_snap}"

  wipe_scn "${scn}"
  mkdir -p "${scn}"
  setup_broken_pipe "${scn}"
  local rs_rc=0
  (
    set +o pipefail
    if (( ignore_sigpipe != 0 )); then
      trap '' PIPE
    fi
    cd "${scn}/repo"
    PATH="${scn}/pipebin:${ORIG_PATH}" HOME="${scn}/home" GIT_CONFIG_GLOBAL="${scn}/home/.gitconfig" \
      "${RS_BIN}" gc --days 1 --execute | head -n "${head_lines}"
    printf '%d\n' "${PIPESTATUS[0]}" > "${rs_snap}/rc.txt"
  ) >"${rs_snap}/stdout.txt" 2>"${rs_snap}/stderr.raw" || rs_rc=$?
  normalize_stderr < "${rs_snap}/stderr.raw" > "${rs_snap}/stderr.txt"
  snapshot_state "${scn}" "${rs_snap}"

  for facet in rc.txt stdout.txt stderr.txt tree.txt fs_meta.txt; do
    if ! diff -u "${sh_snap}/${facet}" "${rs_snap}/${facet}" > "${WORK}/diff.txt"; then
      echo "FAIL [${name}]: mismatch in ${facet}:" >&2
      cat "${WORK}/diff.txt" >&2
      exit 1
    fi
  done
  SCENARIOS_RUN=$((SCENARIOS_RUN + 1))
  echo "ok ${SCENARIOS_RUN} - ${name}"
}

run_closed_stdout_scenario() {
  local name="closed-stdout-execute"
  local scn="${WORK}/scn"
  local sh_snap="${WORK}/snap_sh"
  local rs_snap="${WORK}/snap_rs"
  wipe_scn "${scn}"
  rm -rf "${sh_snap}" "${rs_snap}"
  mkdir -p "${scn}" "${sh_snap}" "${rs_snap}"

  setup_broken_pipe "${scn}"
  local sh_rc=0
  (
    cd "${scn}/repo"
    PATH="${ORIG_PATH}" HOME="${scn}/home" GIT_CONFIG_GLOBAL="${scn}/home/.gitconfig" \
      env bash "${SH_BIN}" gc --days 1 --execute >&-
  ) 2>"${sh_snap}/stderr.raw" || sh_rc=$?
  printf '%d\n' "${sh_rc}" > "${sh_snap}/rc.txt"
  normalize_stderr < "${sh_snap}/stderr.raw" > "${sh_snap}/stderr.txt"
  snapshot_state "${scn}" "${sh_snap}"

  wipe_scn "${scn}"
  mkdir -p "${scn}"
  setup_broken_pipe "${scn}"
  local rs_rc=0
  (
    cd "${scn}/repo"
    PATH="${ORIG_PATH}" HOME="${scn}/home" GIT_CONFIG_GLOBAL="${scn}/home/.gitconfig" \
      "${RS_BIN}" gc --days 1 --execute >&-
  ) 2>"${rs_snap}/stderr.raw" || rs_rc=$?
  printf '%d\n' "${rs_rc}" > "${rs_snap}/rc.txt"
  normalize_stderr < "${rs_snap}/stderr.raw" > "${rs_snap}/stderr.txt"
  # Verify no deletions happened when stdout write failed at header.
  if [[ ! -d "${scn}/home/.cache/bazel/_bazel_${USER}/stale_01" ]]; then
    echo "FAIL [${name}]: stale_01 was deleted despite closed stdout!" >&2
    exit 1
  fi
  snapshot_state "${scn}" "${rs_snap}"

  for facet in rc.txt stderr.txt tree.txt fs_meta.txt; do
    if ! diff -u "${sh_snap}/${facet}" "${rs_snap}/${facet}" > "${WORK}/diff.txt"; then
      echo "FAIL [${name}]: mismatch in ${facet}:" >&2
      cat "${WORK}/diff.txt" >&2
      exit 1
    fi
  done
  SCENARIOS_RUN=$((SCENARIOS_RUN + 1))
  echo "ok ${SCENARIOS_RUN} - ${name}"
}

run_dev_full_scenario() {
  if [[ ! -w /dev/full ]]; then
    echo "Note: skipping dev-full-execute (/dev/full not available on $(uname -s))"
    return 0
  fi
  local name="dev-full-execute"
  local scn="${WORK}/scn"
  local sh_snap="${WORK}/snap_sh"
  local rs_snap="${WORK}/snap_rs"
  wipe_scn "${scn}"
  rm -rf "${sh_snap}" "${rs_snap}"
  mkdir -p "${scn}" "${sh_snap}" "${rs_snap}"

  setup_broken_pipe "${scn}"
  local sh_rc=0
  (
    cd "${scn}/repo"
    PATH="${ORIG_PATH}" HOME="${scn}/home" GIT_CONFIG_GLOBAL="${scn}/home/.gitconfig" \
      env bash "${SH_BIN}" gc --days 1 --execute >/dev/full
  ) 2>"${sh_snap}/stderr.raw" || sh_rc=$?
  printf '%d\n' "${sh_rc}" > "${sh_snap}/rc.txt"
  normalize_stderr < "${sh_snap}/stderr.raw" > "${sh_snap}/stderr.txt"
  snapshot_state "${scn}" "${sh_snap}"

  wipe_scn "${scn}"
  mkdir -p "${scn}"
  setup_broken_pipe "${scn}"
  local rs_rc=0
  (
    cd "${scn}/repo"
    PATH="${ORIG_PATH}" HOME="${scn}/home" GIT_CONFIG_GLOBAL="${scn}/home/.gitconfig" \
      "${RS_BIN}" gc --days 1 --execute >/dev/full
  ) 2>"${rs_snap}/stderr.raw" || rs_rc=$?
  printf '%d\n' "${rs_rc}" > "${rs_snap}/rc.txt"
  normalize_stderr < "${rs_snap}/stderr.raw" > "${rs_snap}/stderr.txt"
  snapshot_state "${scn}" "${rs_snap}"

  for facet in rc.txt stderr.txt tree.txt fs_meta.txt; do
    if ! diff -u "${sh_snap}/${facet}" "${rs_snap}/${facet}" > "${WORK}/diff.txt"; then
      echo "FAIL [${name}]: mismatch in ${facet}:" >&2
      cat "${WORK}/diff.txt" >&2
      exit 1
    fi
  done
  SCENARIOS_RUN=$((SCENARIOS_RUN + 1))
  echo "ok ${SCENARIOS_RUN} - ${name}"
}

run_suite_for_bash() {
  local bash_bin="$1"
  mkdir -p "${WORK}/active_bash_bin"
  ln -sf "${bash_bin}" "${WORK}/active_bash_bin/bash"
  export PATH="${WORK}/active_bash_bin:${BASE_PATH}"
  ORIG_PATH="${PATH}"

  local bash_ver
  bash_ver="$("${bash_bin}" -c 'printf "%s" "${BASH_VERSION:-unknown}"')"
  echo "=== Running parity suite against ${bash_bin} (version ${bash_ver}) ==="

  run_parity_scenario "no-args" setup_empty "cwd"
  run_parity_scenario "unknown-subcommand" setup_empty "cwd" foo
  run_parity_scenario "gc-help" setup_empty "cwd" gc --help
  run_parity_scenario "gc-unknown-flag" setup_empty "cwd" gc --bogus
  run_parity_scenario "gc-days-missing-val" setup_empty "cwd" gc --days
  run_parity_scenario "gc-days-empty-val" setup_empty "cwd" gc --days ""
  run_parity_scenario "outside-git-repo" setup_outside_git "cwd" gc
  run_parity_scenario "all-kept-dry-run" setup_all_kept "repo" gc --days 30
  run_parity_scenario "full-matrix-dry-run" setup_full_matrix "repo" gc --days 1
  run_parity_scenario "full-matrix-execute-days-9999" setup_full_matrix "repo" gc --days 9999 --execute
  run_parity_scenario "full-matrix-execute-days-1" setup_full_matrix "repo" gc --days 1 --execute

  # Finding 1: --days 0, 12h, 30d, near-threshold ages, and invalid unit suffix
  run_parity_scenario "days-0-dry-run" setup_age_thresholds "repo" gc --days 0
  run_parity_scenario "days-12h-execute" setup_age_thresholds "repo" gc --days 12h --execute
  run_parity_scenario "days-30d-execute" setup_age_thresholds "repo" gc --days 30d --execute
  run_parity_scenario "days-1-boundary-execute" setup_age_thresholds "repo" gc --days 1 --execute
  run_parity_scenario "days-invalid-unit" setup_age_thresholds "repo" gc --days 5x

  # Finding 3: Unreadable .vitruvian-worktree marker aborts under set -e
  run_parity_scenario "unreadable-marker-aborts" setup_unreadable_marker "repo" gc --days 1 --execute

  # Finding 4: PATH without external `kill` binary
  RUN_PATH="${WORK}/scn/nokill_bin"
  run_parity_scenario "path-without-kill-builtin" setup_path_without_kill "repo" gc --days 1 --execute
  unset RUN_PATH

  # Finding 5: HOME unset
  run_home_unset_scenario

  # Finding 6 & X2: Directory order under LC_ALL=en_US.UTF-8
  case "$(locale -a 2>/dev/null || true)" in
    *en_US.UTF-8*|*en_US.utf8*)
      export LC_ALL=en_US.UTF-8
      run_parity_scenario "locale-en_US.UTF-8-collation" setup_locale_collation "repo" gc --days 1
      export LC_ALL=C
      ;;
    *)
      echo "Note: skipping locale-en_US.UTF-8-collation (en_US.UTF-8 not in locale -a)"
      ;;
  esac

  # Finding 7: Failed cd stderr when BUILD_WORKSPACE_DIRECTORY does not exist
  export BUILD_WORKSPACE_DIRECTORY="${WORK}/scn/nonexistent_ws_dir"
  run_parity_scenario "failed-cd-stderr" setup_empty "cwd" gc
  unset BUILD_WORKSPACE_DIRECTORY

  # Finding 8 & X3 & Probable/minor: Non-UTF-8 paths and unterminated git worktree line
  RUN_PATH="${WORK}/scn/fakegit:${ORIG_PATH}"
  run_parity_scenario "non-utf8-paths-and-unterminated-worktree" setup_non_utf8 "repo" gc --days 1 --execute
  run_parity_scenario "non-utf8-unknown-flag" setup_empty "cwd" gc $'--flag-\xff\xfe'
  unset RUN_PATH

  # Symlinked bases
  run_parity_scenario "symlinked-bases-dry-run" setup_symlinked_bases "repo" gc --days 1
  run_parity_scenario "symlinked-bases-execute" setup_symlinked_bases "repo" gc --days 1 --execute

  ORIG_USER="${USER:-}"
  export USER=""
  run_parity_scenario "library-caches-precedence-and-empty-user" setup_library_caches "cwd" gc --days 1 --execute

  # Finding 9: USER unset and `id -un` failing under set -e
  RUN_PATH="${WORK}/scn/failid_bin:${ORIG_PATH}"
  run_parity_scenario "user-unset-and-id-failing" setup_failing_id "cwd" gc
  unset RUN_PATH

  # Y4: Child killed by signal exits 128+sig
  RUN_PATH="${WORK}/scn/sigid_bin:${ORIG_PATH}"
  run_parity_scenario "user-unset-and-id-signaled" setup_signaled_id "cwd" gc
  unset RUN_PATH
  export USER="${ORIG_USER}"

  # Finding 9: No md5 tool available
  RUN_PATH="${WORK}/scn/nomd5_bin:${ORIG_PATH}"
  run_parity_scenario "no-md5-tool" setup_no_md5_tool "repo" gc
  unset RUN_PATH

  # Round-2 Finding 4: Failing md5sum candidate falls back to md5 without SIGPIPE
  RUN_PATH="${WORK}/scn/failmd5_bin:${ORIG_PATH}"
  run_parity_scenario "failing-md5-candidate-fallback" setup_failing_md5_candidate "repo" gc --days 1
  unset RUN_PATH

  # Round-2 Findings 2 & 3: Pidfile edge cases and NUL bytes in records
  run_parity_scenario "pid-and-nul-edge-cases-dry-run" setup_pid_and_nul_edge_cases "repo" gc --days 1
  run_parity_scenario "pid-and-nul-edge-cases-execute" setup_pid_and_nul_edge_cases "repo" gc --days 1 --execute

  # Scenario with faked du/date/kill/chmod/rm on PATH (failure injection + argv/env log parity)
  RUN_PATH="${WORK}/scn/fakebin:${ORIG_PATH}"
  run_parity_scenario "faked-tools-dry-run" setup_faked_tools "repo" gc --days 1
  run_parity_scenario "faked-tools-execute-chmod-rm-log" setup_faked_tools "repo" gc --days 1 --execute
  unset RUN_PATH

  # Closed stdout and /dev/full during gc --execute
  run_closed_stdout_scenario
  run_dev_full_scenario

  # Broken pipe with SIGPIPE default (141) and SIGPIPE ignored (write error, exit 1)
  run_broken_pipe_scenario "broken-pipe-execute-head-3" 3 0
  run_broken_pipe_scenario "broken-pipe-execute-head-5" 5 0
  run_broken_pipe_scenario "sigpipe-ignored-execute-head-1" 1 1
  run_broken_pipe_scenario "sigpipe-ignored-execute-head-3" 3 1
  run_broken_pipe_scenario "sigpipe-ignored-execute-head-5" 5 1
}

# Discover every distinct bash available among standard locations and PATH.
BASH_CANDIDATES=()
for cand in /bin/bash /usr/bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash /run/current-system/sw/bin/bash "$(command -v bash 2>/dev/null || true)"; do
  [[ -n "${cand}" && -x "${cand}" ]] || continue
  "${cand}" -c ':' >/dev/null 2>&1 || continue
  dup=0
  for seen in ${BASH_CANDIDATES[@]+"${BASH_CANDIDATES[@]}"}; do
    if [[ "${cand}" -ef "${seen}" ]]; then
      dup=1
      break
    fi
  done
  if (( dup == 0 )); then
    BASH_CANDIDATES+=("${cand}")
  fi
done

if (( ${#BASH_CANDIDATES[@]} == 0 )); then
  echo "FAIL: no runnable bash found" >&2
  exit 1
fi

for bash_bin in "${BASH_CANDIDATES[@]}"; do
  run_suite_for_bash "${bash_bin}"
done

echo "PASS: all ${SCENARIOS_RUN} bazel-cache parity scenarios across ${#BASH_CANDIDATES[@]} bash version(s) matched byte-for-byte"
