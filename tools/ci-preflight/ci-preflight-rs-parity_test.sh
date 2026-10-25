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

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SH_BIN="${SH_UNDER_TEST:-${SCRIPT_DIR}/ci-preflight.sh}"
RS_BIN="${RS_UNDER_TEST:-${SCRIPT_DIR}/ci-preflight}"

case "${SH_BIN}" in /*) ;; *) SH_BIN="${PWD}/${SH_BIN}" ;; esac
case "${RS_BIN}" in /*) ;; *) RS_BIN="${PWD}/${RS_BIN}" ;; esac

[ -f "${SH_BIN}" ] || { echo "missing SH_BIN: ${SH_BIN}" >&2; exit 1; }
[ -x "${RS_BIN}" ] || { echo "missing RS_BIN: ${RS_BIN}" >&2; exit 1; }

# Resolve all distinct bash binaries available before tests manipulate PATH.
BASH_BIN="$(command -v bash)"
BASH_LIST=()
BASH_SEEN=" "
for candidate_bash in /bin/bash /usr/bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash /run/current-system/sw/bin/bash "${BASH_BIN}"; do
  if [ -n "${candidate_bash}" ] && [ -x "${candidate_bash}" ]; then
    real_id="$(stat -f '%d:%i' "${candidate_bash}" 2>/dev/null || stat -c '%d:%i' "${candidate_bash}" 2>/dev/null || printf '%s' "${candidate_bash}")"
    case "${BASH_SEEN}" in
      *" ${real_id} "*) ;;
      *)
        BASH_SEEN="${BASH_SEEN}${real_id} "
        BASH_LIST+=("${candidate_bash}")
        ;;
    esac
  fi
done

BASH4_LIST=()
for candidate_bash in "${BASH_LIST[@]}"; do
  if "${candidate_bash}" -c 'set -u; a=(); : "${a[@]}"' 2>/dev/null; then
    BASH4_LIST+=("${candidate_bash}")
  fi
done

# Bash binaries whose compiled-in DEFAULT_PATH_VALUE when PATH is unset includes standard tools
# (Nix's bash is compiled with DEFAULT_PATH_VALUE="/no-such-path", so `env -u PATH` in Nix bash
# cannot find `grep`/`sed`/`sort` in ci-preflight.sh).
BASH_DEFAULT_PATH_LIST=()
for candidate_bash in "${BASH_LIST[@]}"; do
  if env -u PATH "${candidate_bash}" -c 'command -v grep && command -v sed && command -v sort' >/dev/null 2>&1; then
    BASH_DEFAULT_PATH_LIST+=("${candidate_bash}")
  fi
done

WORK_ROOT="$(mktemp -d)"
trap 'rm -rf "${WORK_ROOT}"' EXIT

SCENARIO_DIR="${WORK_ROOT}/scenario"
SNAP_SH="${WORK_ROOT}/snap_sh"
SNAP_RS="${WORK_ROOT}/snap_rs"

PASS=0
FAIL=0

SYS_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# Detect how `script` runs a command in a pseudo-TTY on this OS (Linux util-linux vs BSD/macOS).
if script -qc "true" /dev/null >/dev/null 2>&1 </dev/null; then
  SCRIPT_STYLE="linux"
elif script -q /dev/null true >/dev/null 2>&1 </dev/null; then
  SCRIPT_STYLE="bsd"
else
  SCRIPT_STYLE="none"
fi

cat > "${WORK_ROOT}/pty_run.sh" <<'EOF'
#!/usr/bin/env bash
"$@" 2>"${PTY_ERR_FILE}"
printf '%s\n' "$?" > "${PTY_RC_FILE}"
EOF
chmod +x "${WORK_ROOT}/pty_run.sh"

normalize_stderr() {
  # Replace ONLY the script/binary path prefix, never the line number.
  sed \
    -e "s|^${SH_BIN}: |<prog>: |" \
    -e "s|^${RS_BIN}: |<prog>: |"
}

snapshot_state() {
  local snap_dir="$1"
  local rc="$2"
  printf '%s\n' "${rc}" > "${snap_dir}/exit_code"
  normalize_stderr < "${snap_dir}/stderr.raw" > "${snap_dir}/stderr"
  if [ -f "${SCENARIO_DIR}/tool_calls.log" ]; then
    cp "${SCENARIO_DIR}/tool_calls.log" "${snap_dir}/tool_calls.log"
  else
    : > "${snap_dir}/tool_calls.log"
  fi

  if [ -d "${SCENARIO_DIR}/repo" ]; then
    (
      cd "${SCENARIO_DIR}/repo" &&
      find . -type f ! -path './.git/*' | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s ' "$f"
        shasum -a 256 "$f" | awk '{print $1}'
      done
    ) > "${snap_dir}/fs_state"
  else
    : > "${snap_dir}/fs_state"
  fi

  if [ -d "${SCENARIO_DIR}/repo/.git" ]; then
    (
      cd "${SCENARIO_DIR}/repo" &&
      git for-each-ref &&
      git worktree list --porcelain &&
      git log --format='%H%x00%an%x00%ae%x00%cn%x00%s' --all &&
      git status --porcelain
    ) > "${snap_dir}/git_state" 2>&1
  else
    : > "${snap_dir}/git_state"
  fi
}

run_single_snap() {
  local snap_dir="$1"
  local impl="$2"
  local sh_runner="$3"
  local setup_fn="$4"
  local use_bwd="$5"
  local gh_repo_env="$6"
  shift 6

  local locale_val="${PARITY_LOCALE:-}"
  local extra_path="${PARITY_EXTRA_PATH:-}"
  local custom_path="${PARITY_CUSTOM_PATH:-}"
  local unset_path="${PARITY_UNSET_PATH:-0}"
  local bash_env_val="${PARITY_BASH_ENV:-}"
  local start_subdir="${PARITY_START_SUBDIR:-}"
  local stdin_file="${PARITY_STDIN_FILE:-}"
  local use_pty="${PARITY_PTY:-0}"
  local close_stdout="${PARITY_CLOSE_STDOUT:-0}"
  local close_stderr="${PARITY_CLOSE_STDERR:-0}"
  local stdout_target="${PARITY_STDOUT_TARGET:-}"
  local ulimit_zero="${PARITY_ULIMIT_ZERO:-0}"
  local sigpipe_ign="${PARITY_SIGPIPE_IGN:-0}"

  rm -rf "${SCENARIO_DIR}" "${snap_dir}"
  mkdir -p "${SCENARIO_DIR}/repo" "${SCENARIO_DIR}/bin" "${SCENARIO_DIR}/home" "${snap_dir}"
  "${setup_fn}"

  local bwd_val=""
  if [ "${use_bwd}" = "1" ]; then
    bwd_val="${SCENARIO_DIR}/repo"
  elif [ "${use_bwd}" != "0" ]; then
    bwd_val="${use_bwd}"
  fi

  local run_path="${SCENARIO_DIR}/bin:${SYS_PATH}"
  if [ -n "${extra_path}" ]; then
    run_path="${SCENARIO_DIR}/bin:${extra_path}:${SYS_PATH}"
  fi
  if [ -n "${custom_path}" ]; then
    run_path="${custom_path}"
  fi

  local start_dir="${SCENARIO_DIR}/repo"
  if [ -n "${start_subdir}" ]; then
    mkdir -p "${SCENARIO_DIR}/repo/${start_subdir}"
    start_dir="${SCENARIO_DIR}/repo/${start_subdir}"
  fi

  local cmd=()
  if [ "${impl}" = "sh" ]; then
    cmd=("${sh_runner}" "${SH_BIN}" "$@")
  else
    cmd=("${RS_BIN}" "$@")
  fi

  local env_cmd=(env)
  if [ "${unset_path}" = "1" ]; then
    env_cmd+=("-u" "PATH")
  fi
  if [ -z "${bash_env_val}" ]; then
    env_cmd+=("-u" "BASH_ENV")
  fi
  if [ "${unset_path}" != "1" ]; then
    env_cmd+=("PATH=${run_path}")
  fi
  if [ -n "${bash_env_val}" ]; then
    env_cmd+=("BASH_ENV=${bash_env_val}")
  fi
  env_cmd+=(
    "HOME=${SCENARIO_DIR}/home"
    "BUILD_WORKSPACE_DIRECTORY=${bwd_val}"
    "GITHUB_REPOSITORY=${gh_repo_env}"
    "GIT_CONFIG_GLOBAL=/dev/null"
    "GIT_CONFIG_NOSYSTEM=1"
    "GIT_AUTHOR_NAME=Test Bot"
    "GIT_AUTHOR_EMAIL=bot@example.com"
    "GIT_COMMITTER_NAME=Test Bot"
    "GIT_COMMITTER_EMAIL=bot@example.com"
    "GIT_AUTHOR_DATE=2026-01-01T00:00:00Z"
    "GIT_COMMITTER_DATE=2026-01-01T00:00:00Z"
  )
  if [ -n "${locale_val}" ]; then
    env_cmd+=("LC_ALL=${locale_val}")
  fi

  : > "${snap_dir}/stdout"
  : > "${snap_dir}/stderr.raw"

  local rc=0
  if [ "${use_pty}" = "1" ]; then
    local rc_file="${snap_dir}/pty_rc"
    env_cmd+=("PTY_ERR_FILE=${snap_dir}/stderr.raw" "PTY_RC_FILE=${rc_file}")
    if [ "${SCRIPT_STYLE}" = "linux" ]; then
      local quoted_cmd=""
      local arg
      for arg in "${WORK_ROOT}/pty_run.sh" "${cmd[@]}"; do
        quoted_cmd="${quoted_cmd} $(printf '%q' "${arg}")"
      done
      (
        cd "${start_dir}" &&
        "${env_cmd[@]}" script -qc "${quoted_cmd}" /dev/null </dev/null 2>/dev/null
      ) | sed $'s/\\^D\x08\x08//g; s/\r//g' > "${snap_dir}/stdout"
    else
      (
        cd "${start_dir}" &&
        "${env_cmd[@]}" script -q /dev/null "${WORK_ROOT}/pty_run.sh" "${cmd[@]}" </dev/null 2>/dev/null
      ) | sed $'s/\\^D\x08\x08//g; s/\r//g' > "${snap_dir}/stdout"
    fi
    rc="$(cat "${rc_file}" 2>/dev/null || echo 1)"
  elif [ "${close_stdout}" = "1" ]; then
    (
      cd "${start_dir}" &&
      "${env_cmd[@]}" "${cmd[@]}" 2>"${snap_dir}/stderr.raw" >&-
    )
    rc=$?
  elif [ "${close_stderr}" = "1" ]; then
    (
      cd "${start_dir}" &&
      "${env_cmd[@]}" "${cmd[@]}" >"${snap_dir}/stdout" 2>&-
    )
    rc=$?
  elif [ -n "${stdout_target}" ]; then
    (
      cd "${start_dir}" &&
      "${env_cmd[@]}" "${cmd[@]}" >"${stdout_target}" 2>"${snap_dir}/stderr.raw"
    )
    rc=$?
  elif [ "${ulimit_zero}" = "1" ]; then
    (
      set -o pipefail &&
      (
        cd "${start_dir}" &&
        trap '' XFSZ &&
        ulimit -f 0 &&
        "${env_cmd[@]}" "${cmd[@]}" 2>&1 >"${snap_dir}/stdout"
      ) | cat > "${snap_dir}/stderr.raw"
    )
    rc=$?
  elif [ "${sigpipe_ign}" = "1" ]; then
    (
      cd "${start_dir}" &&
      trap '' PIPE &&
      set -o pipefail &&
      "${env_cmd[@]}" "${cmd[@]}" 2>"${snap_dir}/stderr.raw" | head -n 1 >"${snap_dir}/stdout"
    )
    rc=$?
  elif [ -n "${stdin_file}" ]; then
    (
      cd "${start_dir}" &&
      "${env_cmd[@]}" "${cmd[@]}" <"${stdin_file}" >"${snap_dir}/stdout" 2>"${snap_dir}/stderr.raw"
    )
    rc=$?
  else
    (
      cd "${start_dir}" &&
      "${env_cmd[@]}" "${cmd[@]}" >"${snap_dir}/stdout" 2>"${snap_dir}/stderr.raw"
    )
    rc=$?
  fi

  snapshot_state "${snap_dir}" "${rc}"
}

run_parity() {
  local name="$1"
  local setup_fn="$2"
  local use_bwd="$3"
  local gh_repo_env="$4"
  shift 4

  local runners=()
  if [ -n "${PARITY_BASH_OVERRIDE:-}" ]; then
    runners=("${PARITY_BASH_OVERRIDE}")
  elif [ "${PARITY_UNSET_PATH:-0}" = "1" ]; then
    runners=("${BASH_DEFAULT_PATH_LIST[@]}")
  elif [ "${PARITY_REQUIRE_BASH4:-0}" = "1" ]; then
    runners=("${BASH4_LIST[@]}")
  else
    runners=("${BASH_LIST[@]}")
  fi

  if [ "${#runners[@]}" -eq 0 ]; then
    printf '  SKIP  %s (no compatible bash binary available)\n' "${name}"
    return 0
  fi

  run_single_snap "${SNAP_RS}" "rs" "" "${setup_fn}" "${use_bwd}" "${gh_repo_env}" "$@"

  local failed=0
  local sh_runner
  for sh_runner in "${runners[@]}"; do
    run_single_snap "${SNAP_SH}" "sh" "${sh_runner}" "${setup_fn}" "${use_bwd}" "${gh_repo_env}" "$@"

    local field
    for field in exit_code stdout stderr tool_calls.log fs_state git_state; do
      if ! diff -a -u "${SNAP_SH}/${field}" "${SNAP_RS}/${field}" > "${WORK_ROOT}/diff.${field}" 2>&1; then
        if [ "${failed}" -eq 0 ]; then
          printf '  \033[31mFAIL\033[0m  %s (bash=%s)\n' "${name}" "${sh_runner}"
        fi
        failed=1
        printf '    --- mismatch in %s (bash=%s) ---\n' "${field}" "${sh_runner}"
        sed 's/^/    /' "${WORK_ROOT}/diff.${field}"
      fi
    done
  done

  if [ "${failed}" -eq 0 ]; then
    printf '  \033[32mPASS\033[0m  %s\n' "${name}"
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
}

# Helper to install a logging fake `gh` (logs argv[0], each arg with boundaries, and sorted env -0 minus volatile vars)
install_fake_gh() {
  local mode="$1"
  local target_path="${2:-${SCENARIO_DIR}/bin/gh}"
  cat > "${target_path}" <<EOF
#!/bin/bash
{
  printf 'gh '
  printf '<%s>' "\$0" "\$@"
  printf ' cwd=<%s> oldpwd=<%s> env={' "\$PWD" "\${OLDPWD:-}"
  LC_ALL=C /usr/bin/env -0 | LC_ALL=C /usr/bin/sort -z | /usr/bin/tr '\0' '\n' | LC_ALL=C /usr/bin/grep -a -vE '^(SHLVL|_|PTY_ERR_FILE|PTY_RC_FILE|CheckSubshell)=|^BASH_FUNC_' | /usr/bin/tr '\n' ';'
  printf '}\n'
} >> "${SCENARIO_DIR}/tool_calls.log"
mode="${mode}"
case "\${mode}" in
  unauth)
    if [[ "\$*" == *"auth status"* ]]; then exit 1; fi
    exit 0
    ;;
  norepo)
    if [[ "\$*" == *"auth status"* ]]; then exit 0; fi
    if [[ "\$*" == *"repo view"* ]]; then exit 1; fi
    exit 0
    ;;
  403)
    if [[ "\$*" == *"auth status"* ]]; then exit 0; fi
    if [[ "\$*" == *"repo view"* ]]; then echo "acme/widget"; exit 0; fi
    exit 1
    ;;
  dep_empty)
    case "\$*" in
      *"auth status"*)        exit 0 ;;
      *"repo view"*)          echo "acme/widget"; exit 0 ;;
      *"dependabot/secrets"*) exit 0 ;;
      *"actions/secrets"*)    printf 'PR_SECRET\nPUSH_SECRET\n'; exit 0 ;;
      *"actions/variables"*)  printf 'PR_VAR\n'; exit 0 ;;
      *"environments"*)       exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  all_green)
    case "\$*" in
      *"auth status"*)        exit 0 ;;
      *"repo view"*)          echo "acme/widget"; exit 0 ;;
      *"dependabot/secrets"*) printf 'PR_SECRET\n'; exit 0 ;;
      *"actions/secrets"*)    printf 'PR_SECRET\nPUSH_SECRET\n'; exit 0 ;;
      *"actions/variables"*)  printf 'PR_VAR\n'; exit 0 ;;
      *"environments"*)       exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  missing_sec_and_var)
    case "\$*" in
      *"auth status"*)        exit 0 ;;
      *"repo view"*)          echo "acme/widget"; exit 0 ;;
      *"dependabot/secrets"*) printf 'PR_SECRET\n'; exit 0 ;;
      *"actions/secrets"*)    printf 'PR_SECRET\n'; exit 0 ;;
      *"actions/variables"*)  exit 0 ;;
      *"environments"*)       exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  env_scoped)
    case "\$*" in
      *"auth status"*)                    exit 0 ;;
      *"repo view"*)                      echo "acme/widget"; exit 0 ;;
      *"dependabot/secrets"*)             printf 'PR_SECRET\n'; exit 0 ;;
      *"repos/acme/widget/actions/secrets"*)   printf 'PR_SECRET\n'; exit 0 ;;
      *"repos/acme/widget/actions/variables"*) exit 0 ;;
      *"environments/prod/secrets"*)      printf 'PUSH_SECRET\n'; exit 0 ;;
      *"environments/prod/variables"*)    exit 0 ;;
      *"environments/staging/secrets"*)   exit 0 ;;
      *"environments/staging/variables"*) printf 'PR_VAR\n'; exit 0 ;;
      *"repos/acme/widget/environments"*) printf 'prod\nstaging\n'; exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  env_no_trailing_newline)
    case "\$*" in
      *"auth status"*)                    exit 0 ;;
      *"repo view"*)                      echo "acme/widget"; exit 0 ;;
      *"dependabot/secrets"*)             printf 'PR_SECRET\n'; exit 0 ;;
      *"repos/acme/widget/actions/secrets"*)   printf 'PR_SECRET\n'; exit 0 ;;
      *"repos/acme/widget/actions/variables"*) exit 0 ;;
      *"environments/prod/secrets"*)      printf 'PUSH_SECRET\n'; exit 0 ;;
      *"environments/prod/variables"*)    exit 0 ;;
      *"environments/staging/secrets"*)   printf 'NEVER_REACHED\n'; exit 0 ;;
      *"environments/staging/variables"*) printf 'PR_VAR\n'; exit 0 ;;
      *"repos/acme/widget/environments"*) printf 'prod\nstaging'; exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  non_utf8_live)
    case "\$*" in
      *"auth status"*)                    exit 0 ;;
      *"repo view"*)                      printf 'acme/wid\xffget\n'; exit 0 ;;
      *"dependabot/secrets"*)             printf 'PR_SECRET\n'; exit 0 ;;
      *"actions/secrets"*)                printf 'PR_SECRET\n'; exit 0 ;;
      *"actions/variables"*)              exit 0 ;;
      *"environments/"*"/secrets"*)       printf 'PUSH_SECRET\n'; exit 0 ;;
      *"environments/"*"/variables"*)     printf 'PR_VAR\n'; exit 0 ;;
      *"/environments"*)                  printf 'pr\xffod\n'; exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  read_stdin)
    case "\$*" in
      *"auth status"*)
        read -r line || true
        printf 'gh_stdin=[%s]\n' "\${line}" >> "${SCENARIO_DIR}/tool_calls.log"
        exit 0
        ;;
      *"repo view"*)          echo "acme/widget"; exit 0 ;;
      *"dependabot/secrets"*) printf 'PR_SECRET\n'; exit 0 ;;
      *"actions/secrets"*)    printf 'PR_SECRET\nPUSH_SECRET\n'; exit 0 ;;
      *"actions/variables"*)  printf 'PR_VAR\n'; exit 0 ;;
      *"environments"*)       exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
esac
EOF
  chmod +x "${target_path}"
}

setup_standard_repo() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  cat > "${d}/.github/workflows/pr.yaml" <<'EOF'
name: PR
on:
  pull_request:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - env:
          TOKEN: ${{ secrets.PR_SECRET }}
          GATE: ${{ vars.PR_VAR }}
        run: echo hi
EOF
  cat > "${d}/.github/workflows/push.yaml" <<'EOF'
name: Push
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - env:
          TOKEN: ${{ secrets.PUSH_SECRET }}
        run: echo hi
EOF
}

setup_no_workflows() {
  :
}

setup_push_only_workflows() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  cat > "${d}/.github/workflows/push.yaml" <<'EOF'
name: Push Only
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - env:
          TOKEN: ${{ secrets.PUSH_SECRET }}
          GATE: ${{ vars.PR_VAR }}
        run: echo hi
EOF
  install_fake_gh all_green
}

setup_hostile_awk() {
  setup_dep_empty
  cat > "${SCENARIO_DIR}/bin/awk" <<'EOF'
#!/usr/bin/env bash
echo "awk must not be used for trigger detection" >&2
exit 127
EOF
  chmod +x "${SCENARIO_DIR}/bin/awk"
}

setup_flow_trigger() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  cat > "${d}/.github/workflows/flow.yaml" <<'EOF'
name: Flow
on: [pull_request, push]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - env:
          T: ${{ secrets.PR_SECRET }}
          V: ${{ vars.PR_VAR }}
        run: echo hi
EOF
  install_fake_gh dep_empty
}

setup_nested_not_trigger() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  cat > "${d}/.github/workflows/nested.yaml" <<'EOF'
name: Nested
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    if: github.event.pull_request.number
    steps:
      - env:
          T: ${{ secrets.PUSH_SECRET }}
          V: ${{ vars.PR_VAR }}
        run: echo pull_request
EOF
  install_fake_gh dep_empty
}

setup_four_space_trigger() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  cat > "${d}/.github/workflows/four-space.yaml" <<'EOF'
name: Four Space
on:
    pull_request:
        branches: [main]
jobs:
    a:
        runs-on: ubuntu-latest
        steps:
            - env:
                  T: ${{ secrets.PR_SECRET }}
                  V: ${{ vars.PR_VAR }}
              run: echo hi
EOF
  install_fake_gh dep_empty
}

setup_complex_workflows_and_actions() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows/subdir" "${d}/.github/actions/my-action"
  cat > "${d}/.github/workflows/01_a.yaml" <<'EOF'
name: First PR
on: [pull_request, push]
jobs:
  a:
    steps:
      - run: echo ${{ secrets.Z_FIRST }} ${{ secrets.A0 }} ${{ secrets.A_0 }} ${{ secrets.AB }} ${{ secrets.A_B }} ${{ secrets.GITHUB_TOKEN }}
EOF
  cat > "${d}/.github/workflows/02_b.yml" <<'EOF'
name: FourSpace And Comments
on:
  # comment inside on:
    
    pull_request_target:
        types: [opened]
jobs:
  b:
    steps:
      - run: echo ${{ secrets.B_SECOND }} ${{ vars.VAR_Z }} ${{ vars.VAR_A }}
EOF
  cat > "${d}/.github/workflows/03_nested_not_pr.yaml" <<'EOF'
name: Push Only With Nested Mention
on:
  push:
    branches: [main]
jobs:
  c:
    if: github.event.pull_request.number
    steps:
      - run: echo ${{ secrets.ONLY_PUSH_SEC }}
EOF
  cat > "${d}/.github/workflows/04_unclosed_on.yaml" <<'EOF'
name: Unclosed On Range
on:
  workflow_dispatch:
  pull_request:
EOF
  cat > "${d}/.github/workflows/.hidden.yaml" <<'EOF'
on:
  pull_request:
jobs:
  h:
    steps:
      - run: echo ${{ secrets.HIDDEN_FILE_SEC }}
EOF
  cat > "${d}/.github/actions/my-action/action.yml" <<'EOF'
name: Action
runs:
  using: composite
  steps:
    - run: echo ${{ secrets.ACTION_SEC }} ${{ vars.ACTION_VAR }}
EOF
  install_fake_gh dep_empty
}

setup_dep_empty() {
  setup_standard_repo
  install_fake_gh dep_empty
}

setup_all_green() {
  setup_standard_repo
  install_fake_gh all_green
}

setup_missing_sec_and_var() {
  setup_standard_repo
  install_fake_gh missing_sec_and_var
}

setup_env_scoped() {
  setup_standard_repo
  install_fake_gh env_scoped
}

setup_env_no_trailing_newline() {
  setup_standard_repo
  install_fake_gh env_no_trailing_newline
}

setup_github_token() {
  setup_standard_repo
  cat > "${SCENARIO_DIR}/repo/.github/workflows/tok.yaml" <<'EOF'
name: Tok
on:
  pull_request:
jobs:
  a:
    steps:
      - run: echo ${{ secrets.GITHUB_TOKEN }}
EOF
  install_fake_gh all_green
}

setup_offline_no_gh() {
  setup_standard_repo
}

setup_offline_unauth() {
  setup_standard_repo
  install_fake_gh unauth
}

setup_offline_norepo() {
  setup_standard_repo
  install_fake_gh norepo
}

setup_offline_403() {
  setup_standard_repo
  install_fake_gh 403
}

setup_section4_python_pass() {
  setup_standard_repo
  install_fake_gh all_green
  mkdir -p "${SCENARIO_DIR}/repo/tools/lint-naming"
  cat > "${SCENARIO_DIR}/repo/tools/lint-naming/lint_naming.py" <<'EOF'
#!/usr/bin/env python3
import sys
print("lint_naming python ok:", " ".join(sys.argv[1:]))
sys.exit(0)
EOF
  cat > "${SCENARIO_DIR}/bin/python3" <<EOF
#!/usr/bin/env bash
{
  printf 'python3 '
  printf '<%s>' "\$0" "\$@"
  printf ' cwd=<%s> oldpwd=<%s> env={' "\$PWD" "\${OLDPWD:-}"
  env -0 | LC_ALL=C sort -z | tr '\0' '\n' | grep -vE '^(SHLVL|_|PTY_ERR_FILE|PTY_RC_FILE|CheckSubshell)=|^BASH_FUNC_' | tr '\n' ';'
  printf '}\n'
} >> "${SCENARIO_DIR}/tool_calls.log"
echo "All naming conventions passed!"
exit 0
EOF
  chmod +x "${SCENARIO_DIR}/bin/python3"
}

setup_section4_python_fail() {
  setup_section4_python_pass
  cat > "${SCENARIO_DIR}/bin/python3" <<EOF
#!/usr/bin/env bash
{
  printf 'python3 '
  printf '<%s>' "\$0" "\$@"
  printf ' cwd=<%s> oldpwd=<%s> env={' "\$PWD" "\${OLDPWD:-}"
  env -0 | LC_ALL=C sort -z | tr '\0' '\n' | grep -vE '^(SHLVL|_|PTY_ERR_FILE|PTY_RC_FILE|CheckSubshell)=|^BASH_FUNC_' | tr '\n' ';'
  printf '}\n'
} >> "${SCENARIO_DIR}/tool_calls.log"
echo "Found 1 naming violation"
exit 1
EOF
  chmod +x "${SCENARIO_DIR}/bin/python3"
}

setup_section4_bazel_pass() {
  setup_section4_python_pass
  touch "${SCENARIO_DIR}/repo/MODULE.bazel"
  cat > "${SCENARIO_DIR}/bin/bazel" <<EOF
#!/usr/bin/env bash
{
  printf 'bazel '
  printf '<%s>' "\$0" "\$@"
  printf ' cwd=<%s> oldpwd=<%s> env={' "\$PWD" "\${OLDPWD:-}"
  env -0 | LC_ALL=C sort -z | tr '\0' '\n' | grep -vE '^(SHLVL|_|PTY_ERR_FILE|PTY_RC_FILE|CheckSubshell)=|^BASH_FUNC_' | tr '\n' ';'
  printf '}\n'
} >> "${SCENARIO_DIR}/tool_calls.log"
echo "//tools/lint-naming:lint-naming_test PASSED"
exit 0
EOF
  chmod +x "${SCENARIO_DIR}/bin/bazel"
}

setup_section4_bazel_fail() {
  setup_section4_bazel_pass
  cat > "${SCENARIO_DIR}/bin/bazel" <<EOF
#!/usr/bin/env bash
{
  printf 'bazel '
  printf '<%s>' "\$0" "\$@"
  printf ' cwd=<%s> oldpwd=<%s> env={' "\$PWD" "\${OLDPWD:-}"
  env -0 | LC_ALL=C sort -z | tr '\0' '\n' | grep -vE '^(SHLVL|_|PTY_ERR_FILE|PTY_RC_FILE|CheckSubshell)=|^BASH_FUNC_' | tr '\n' ';'
  printf '}\n'
} >> "${SCENARIO_DIR}/tool_calls.log"
echo "//tools/lint-naming:lint-naming_test FAILED"
exit 1
EOF
  chmod +x "${SCENARIO_DIR}/bin/bazel"
}

setup_git_toplevel_discovery() {
  setup_standard_repo
  install_fake_gh all_green
  (
    cd "${SCENARIO_DIR}/repo" &&
    git init -q &&
    git add . &&
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME="Test Bot" GIT_AUTHOR_EMAIL="bot@example.com" \
    GIT_COMMITTER_NAME="Test Bot" GIT_COMMITTER_EMAIL="bot@example.com" \
    GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
    git commit -q -m "init"
  )
}

# --- New scenarios for findings & parity gaps ---

setup_locale_collation() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  # Workflow filenames that order differently in C vs en_US.UTF-8:
  # C order:         A-c.yaml, A0.yaml, A_0.yaml, a-b.yaml, a_b.yaml
  # en_US.UTF-8:     A_0.yaml, a_b.yaml, a-b.yaml, A-c.yaml, A0.yaml
  cat > "${d}/.github/workflows/a-b.yaml" <<'EOF'
name: a-b
on: [pull_request]
jobs:
  j:
    steps:
      - run: echo ${{ secrets.WF_A_DASH_B }}
EOF
  cat > "${d}/.github/workflows/A-c.yaml" <<'EOF'
name: A-c
on: [pull_request]
jobs:
  j:
    steps:
      - run: echo ${{ secrets.WF_UPPER_A_DASH_C }}
EOF
  cat > "${d}/.github/workflows/a_b.yaml" <<'EOF'
name: a_b
on: [pull_request]
jobs:
  j:
    steps:
      - run: echo ${{ secrets.WF_A_UNDER_B }}
EOF
  cat > "${d}/.github/workflows/A0.yaml" <<'EOF'
name: A0
on: [pull_request]
jobs:
  j:
    steps:
      - run: echo ${{ secrets.A0 }} ${{ secrets.A_0 }} ${{ secrets.AB }} ${{ secrets.A_B }} ${{ secrets.AC }}
      - run: echo ${{ vars.V0 }} ${{ vars.V_0 }} ${{ vars.VB }} ${{ vars.V_B }} ${{ vars.VC }}
EOF
  cat > "${d}/.github/workflows/A_0.yaml" <<'EOF'
name: A_0
on: [pull_request]
jobs:
  j:
    steps:
      - run: echo ${{ secrets.WF_A_UNDER_0 }}
EOF
  install_fake_gh dep_empty
}

setup_symlinks() {
  local d="${SCENARIO_DIR}/repo"
  local ext="${SCENARIO_DIR}/outside"
  mkdir -p "${d}/.github/workflows" "${d}/.github/actions/sub" "${ext}/ext_dir"

  cat > "${d}/.github/workflows/real.yaml" <<'EOF'
name: Real
on: [pull_request]
jobs:
  j:
    steps:
      - run: echo ${{ secrets.PR_SECRET }} ${{ vars.PR_VAR }}
EOF

  cat > "${ext}/ext_pr.yaml" <<'EOF'
name: External Symlinked Workflow
on: [pull_request]
jobs:
  j:
    steps:
      - run: echo ${{ secrets.SYMLINK_WF_SEC }} ${{ vars.SYMLINK_WF_VAR }}
EOF

  cat > "${ext}/ext_dir/inside.yaml" <<'EOF'
name: Inside Symlinked Dir
on: [pull_request]
jobs:
  j:
    steps:
      - run: echo ${{ secrets.SYMLINK_DIR_SEC }} ${{ vars.SYMLINK_DIR_VAR }}
EOF

  cat > "${ext}/ext_action.yml" <<'EOF'
name: External Symlinked Action
runs:
  using: composite
  steps:
    - run: echo ${{ secrets.SYMLINK_ACT_SEC }} ${{ vars.SYMLINK_ACT_VAR }}
EOF

  ln -s "${ext}/ext_pr.yaml" "${d}/.github/workflows/linked_wf.yaml"
  ln -s "${ext}/ext_dir" "${d}/.github/workflows/linked_dir"
  ln -s "${ext}/does_not_exist.yaml" "${d}/.github/workflows/broken.yaml"
  ln -s "${ext}/ext_action.yml" "${d}/.github/actions/sub/action.yml"

  install_fake_gh dep_empty
}

setup_binary_and_latin1() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  # Binary workflow with NUL and PNG header bytes + valid secret/var references
  printf 'name: Bin\non:\n  pull_request:\n# bin: \x00\x89PNG\xff\xfe\njobs:\n  j:\n    steps:\n      - run: echo ${{ secrets.PR_SECRET }} ${{ vars.PR_VAR }}\n' \
    > "${d}/.github/workflows/01_binary.yaml"
  # Latin-1 invalid UTF-8 bytes (\xe9 \xfc \xff) in comments and step names
  printf 'name: Latin1 caf\xe9 \xfc \xff\non: [pull_request]\njobs:\n  j:\n    steps:\n      - run: echo "\xe9\xfc" ${{ secrets.PUSH_SECRET }} ${{ vars.PR_VAR }}\n' \
    > "${d}/.github/workflows/02_latin1.yaml"
  install_fake_gh dep_empty
}

setup_crlf() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  printf 'name: CRLF Flow\r\non: [pull_request, push]\r\njobs:\r\n  j:\r\n    steps:\r\n      - run: echo ${{ secrets.PR_SECRET }} ${{ vars.PR_VAR }}\r\n' \
    > "${d}/.github/workflows/01_crlf_flow.yaml"
  printf 'name: CRLF Block\r\non:\r\n  pull_request:\r\n    branches: [main]\r\njobs:\r\n  j:\r\n    steps:\r\n      - run: echo ${{ secrets.PUSH_SECRET }}\r\n' \
    > "${d}/.github/workflows/02_crlf_block.yaml"
  install_fake_gh dep_empty
}

setup_unicode_spaces() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  # Include UTF-8 NBSP (\xc2\xa0) and EM SPACE (\xe2\x80\x83) on trigger lines
  printf 'name: Unicode Spaces\non:\xc2\xa0[pull_request]\njobs:\n  j:\n    steps:\n      - run: echo ${{ secrets.PR_SECRET }} ${{ vars.PR_VAR }}\n' \
    > "${d}/.github/workflows/01_nbsp_flow.yaml"
  printf 'name: Unicode Block\non:\n\xe2\x80\x83pull_request:\njobs:\n  j:\n    steps:\n      - run: echo ${{ secrets.PUSH_SECRET }}\n' \
    > "${d}/.github/workflows/02_emspace_block.yaml"
  install_fake_gh dep_empty
}

setup_huge_on_block() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  {
    printf 'name: Huge On Block\non:\n  pull_request:\n    branches:\n'
    # Emit > 128 KB inside the `on:` block after `pull_request:` so `grep -qE` exits early
    # while `sed` is still writing into the pipe under `set -o pipefail`.
    awk 'BEGIN { for (i = 0; i < 4000; i++) printf "      - branch-name-padding-for-pipe-buffer-%05d\n", i }'
    printf 'jobs:\n  j:\n    steps:\n      - run: echo ${{ secrets.PR_SECRET }} ${{ vars.PR_VAR }}\n'
  } > "${d}/.github/workflows/huge_on.yaml"
  install_fake_gh dep_empty
}

setup_empty_secrets_and_vars() {
  local d="${SCENARIO_DIR}/repo"
  mkdir -p "${d}/.github/workflows"
  cat > "${d}/.github/workflows/plain.yaml" <<'EOF'
name: No Secrets Or Vars
on: [pull_request]
jobs:
  j:
    steps:
      - run: echo "nothing required"
EOF
  install_fake_gh all_green
}

setup_non_exec_gh_only() {
  setup_standard_repo
  install_fake_gh all_green
  chmod 644 "${SCENARIO_DIR}/bin/gh"
}

setup_non_exec_gh_then_exec_gh() {
  setup_standard_repo
  mkdir -p "${SCENARIO_DIR}/bin2"
  install_fake_gh all_green
  mv "${SCENARIO_DIR}/bin/gh" "${SCENARIO_DIR}/bin2/gh"
  printf '#!/usr/bin/env bash\nexit 99\n' > "${SCENARIO_DIR}/bin/gh"
  chmod 644 "${SCENARIO_DIR}/bin/gh"
}

setup_non_exec_bazel() {
  setup_section4_bazel_pass
  chmod 644 "${SCENARIO_DIR}/bin/bazel"
}

setup_non_exec_python3() {
  setup_section4_python_pass
  chmod 644 "${SCENARIO_DIR}/bin/python3"
}

setup_missing_python3() {
  setup_standard_repo
  install_fake_gh all_green
  mkdir -p "${SCENARIO_DIR}/repo/tools/lint-naming" "${SCENARIO_DIR}/isolated_bin"
  touch "${SCENARIO_DIR}/repo/tools/lint-naming/lint_naming.py"
  mv "${SCENARIO_DIR}/bin/gh" "${SCENARIO_DIR}/isolated_bin/gh"
  for tool in bash env grep sed sort tr cat printf rm mkdir chmod git; do
    p="$(command -v "${tool}" || true)"
    [ -n "${p}" ] && ln -sf "${p}" "${SCENARIO_DIR}/isolated_bin/${tool}"
  done
}

setup_gh_reads_stdin() {
  setup_standard_repo
  install_fake_gh read_stdin
  printf 'hello-from-inherited-stdin\n' > "${SCENARIO_DIR}/stdin.txt"
}

setup_symlink_dotdot_root() {
  # Physical target of `sym_out` is `${SCENARIO_DIR}/outside_target/nested`, so
  # physical `..` would land in `${SCENARIO_DIR}/outside_target` (which has NO `.github/workflows`),
  # whereas logical `cd -L` normalises `sym_out/..` to `${SCENARIO_DIR}/real_location/repo`
  # (which HAS `.github/workflows` and section 4 `lint_naming.py`).
  setup_section4_python_pass
  mkdir -p "${SCENARIO_DIR}/real_location" "${SCENARIO_DIR}/outside_target/nested"
  mv "${SCENARIO_DIR}/repo" "${SCENARIO_DIR}/real_location/repo"
  mkdir -p "${SCENARIO_DIR}/repo"
  ln -s "${SCENARIO_DIR}/outside_target/nested" "${SCENARIO_DIR}/real_location/repo/sym_out"
}

setup_symlink_parent_dotdot_root() {
  setup_section4_python_pass
  mkdir -p "${SCENARIO_DIR}/real_location" "${SCENARIO_DIR}/sym_parent"
  mv "${SCENARIO_DIR}/repo" "${SCENARIO_DIR}/real_location/repo"
  mkdir -p "${SCENARIO_DIR}/real_location/repo/subdir" "${SCENARIO_DIR}/repo"
  ln -s "${SCENARIO_DIR}/real_location/repo" "${SCENARIO_DIR}/sym_parent/repo_link"
}

setup_non_utf8_live() {
  setup_section4_python_pass
  install_fake_gh non_utf8_live
}

setup_non_utf8_repo_from_gh() {
  setup_standard_repo
  install_fake_gh non_utf8_repo_view
}

setup_unset_path_with_dot_gh() {
  setup_standard_repo
  install_fake_gh all_green
  # Bash's built-in default PATH ends with `:.`, so a `./gh` executable in the repo root
  # is discovered by `command -v gh` when PATH is unset!
  cp "${SCENARIO_DIR}/bin/gh" "${SCENARIO_DIR}/repo/gh"
  chmod +x "${SCENARIO_DIR}/repo/gh"
}

setup_bash_env_trap() {
  setup_standard_repo
  install_fake_gh all_green
  # When BASH_ENV is set in the environment, top-level bash reads it once on startup.
  # If a port spawns `bash -c` per workflow, BASH_ENV would be re-evaluated for each workflow.
  cat > "${SCENARIO_DIR}/bash_env_probe.sh" <<'EOF'
if [ "${CI_PREFLIGHT_BASH_ENV_SEEN:-0}" = "1" ]; then
  echo "SUBSHELL_RE_READ_BASH_ENV" >&2
fi
export CI_PREFLIGHT_BASH_ENV_SEEN=1
EOF
}

setup_bulk_secrets_with_section4() {
  setup_section4_python_pass
  {
    printf 'name: Many Secrets\non: [pull_request]\njobs:\n  j:\n    steps:\n      - run: |\n'
    awk 'BEGIN { for (i = 0; i < 3000; i++) printf "          echo ${{ secrets.BULK_SECRET_FOR_PIPE_%04d }}\n", i }'
  } > "${SCENARIO_DIR}/repo/.github/workflows/many.yaml"
}

setup_section4_python_sigkill() {
  setup_section4_python_pass
  cat > "${SCENARIO_DIR}/bin/python3" <<EOF
#!/usr/bin/env bash
{
  printf 'python3 '
  printf '<%s>' "\$0" "\$@"
  printf ' cwd=<%s>\n' "\$PWD"
} >> "${SCENARIO_DIR}/tool_calls.log"
kill -PIPE \$\$
EOF
  chmod +x "${SCENARIO_DIR}/bin/python3"
}

run_broken_pipe_parity() {
  local name="$1"
  shift
  local failed=0

  for current_bash in "${BASH_LIST[@]}"; do
    rm -rf "${SCENARIO_DIR}" "${SNAP_SH}"
    mkdir -p "${SCENARIO_DIR}/repo" "${SCENARIO_DIR}/bin" "${SCENARIO_DIR}/home" "${SNAP_SH}"
    setup_bulk_secrets_with_section4
    (
      cd "${SCENARIO_DIR}/repo" &&
      set -o pipefail &&
      PATH="${SCENARIO_DIR}/bin:${SYS_PATH}" \
      BUILD_WORKSPACE_DIRECTORY="${SCENARIO_DIR}/repo" \
      "${current_bash}" "${SH_BIN}" "$@" 2>"${SNAP_SH}/stderr.raw" | head -n 1 >"${SNAP_SH}/stdout"
    )
    local sh_rc=$?
    printf '%s\n' "${sh_rc}" > "${SNAP_SH}/exit_code"
    normalize_stderr < "${SNAP_SH}/stderr.raw" > "${SNAP_SH}/stderr"
    if [ -f "${SCENARIO_DIR}/tool_calls.log" ]; then
      cp "${SCENARIO_DIR}/tool_calls.log" "${SNAP_SH}/tool_calls"
    else
      : > "${SNAP_SH}/tool_calls"
    fi

    rm -rf "${SCENARIO_DIR}" "${SNAP_RS}"
    mkdir -p "${SCENARIO_DIR}/repo" "${SCENARIO_DIR}/bin" "${SCENARIO_DIR}/home" "${SNAP_RS}"
    setup_bulk_secrets_with_section4
    (
      cd "${SCENARIO_DIR}/repo" &&
      set -o pipefail &&
      PATH="${SCENARIO_DIR}/bin:${SYS_PATH}" \
      BUILD_WORKSPACE_DIRECTORY="${SCENARIO_DIR}/repo" \
      "${RS_BIN}" "$@" 2>"${SNAP_RS}/stderr.raw" | head -n 1 >"${SNAP_RS}/stdout"
    )
    local rs_rc=$?
    printf '%s\n' "${rs_rc}" > "${SNAP_RS}/exit_code"
    normalize_stderr < "${SNAP_RS}/stderr.raw" > "${SNAP_RS}/stderr"
    if [ -f "${SCENARIO_DIR}/tool_calls.log" ]; then
      cp "${SCENARIO_DIR}/tool_calls.log" "${SNAP_RS}/tool_calls"
    else
      : > "${SNAP_RS}/tool_calls"
    fi

    if [ "${sh_rc}" -ne 141 ] || [ "${rs_rc}" -ne 141 ]; then
      failed=1
      printf '  \033[31mFAIL\033[0m  %s [%s] (expected SIGPIPE exit 141, got sh=%d rs=%d)\n' "${name}" "${current_bash}" "${sh_rc}" "${rs_rc}"
    fi
    for field in exit_code stdout stderr tool_calls; do
      if ! diff -u "${SNAP_SH}/${field}" "${SNAP_RS}/${field}" > "${WORK_ROOT}/diff.${field}" 2>&1; then
        if [ "${failed}" -eq 0 ]; then
          printf '  \033[31mFAIL\033[0m  %s [%s]\n' "${name}" "${current_bash}"
        fi
        failed=1
        printf '    --- mismatch in %s (%s) ---\n' "${field}" "${current_bash}"
        sed 's/^/    /' "${WORK_ROOT}/diff.${field}"
      fi
    done
  done

  if [ "${failed}" -eq 0 ]; then
    printf '  \033[32mPASS\033[0m  %s\n' "${name}"
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
}

echo "ci-preflight_parity_test (bashes: ${BASH_LIST[*]}):"

run_parity "help flag -h" setup_standard_repo 1 "" -h
run_parity "help flag --help" setup_standard_repo 1 "" --help
run_parity "unknown flag --bogus" setup_standard_repo 1 "" --bogus
run_parity "unknown positional arg" setup_standard_repo 1 "" unexpected_arg
run_parity "missing --repo value at end" setup_standard_repo 1 "" --repo
run_parity "empty --repo value" setup_standard_repo 1 "" --repo ""
run_parity "missing .github/workflows dir" setup_no_workflows 1 ""
run_parity "--list on standard repo" setup_standard_repo 1 "" --list
run_parity "--list on push-only workflows (no PR-triggered secrets)" setup_push_only_workflows 1 "" --list
run_parity "live report on push-only workflows" setup_push_only_workflows 1 ""
run_parity "hostile awk on PATH does not break PR detection (3b)" setup_hostile_awk 1 ""
run_parity "flow-style pull_request trigger detected (3c)" setup_flow_trigger 1 ""
run_parity "nested pull_request reference is not a trigger (3d)" setup_nested_not_trigger 1 ""
run_parity "four-space-indented pull_request trigger detected (3e)" setup_four_space_trigger 1 ""
run_parity "--list on complex workflows and actions" setup_complex_workflows_and_actions 1 "" --list
run_parity "live report on complex workflows and actions" setup_complex_workflows_and_actions 1 ""
run_parity "PR secret missing from Dependabot store (#1164)" setup_dep_empty 1 ""
run_parity "all secrets and vars configured" setup_all_green 1 ""
run_parity "missing repo secret and variable fails with exit 1" setup_missing_sec_and_var 1 ""
run_parity "environment-scoped secrets and variables" setup_env_scoped 1 ""
run_parity "GITHUB_TOKEN auto-provided" setup_github_token 1 ""
run_parity "offline when gh is not installed" setup_offline_no_gh 1 ""
run_parity "offline when gh auth status fails" setup_offline_unauth 1 ""
run_parity "offline when gh repo view fails and no --repo" setup_offline_norepo 1 ""
run_parity "offline with --repo override when gh auth fails" setup_offline_unauth 1 "" --repo custom/slug
run_parity "GITHUB_REPOSITORY env var skips gh repo view" setup_all_green 1 "acme/widget"
run_parity "--repo overrides GITHUB_REPOSITORY" setup_all_green 1 "ignored/slug" --repo acme/widget
run_parity "unreadable API (all-empty 403) treated as unknown" setup_offline_403 1 ""
run_parity "section 4 lint-naming via python3 (pass)" setup_section4_python_pass 1 ""
run_parity "section 4 lint-naming via python3 (fail)" setup_section4_python_fail 1 ""
run_parity "section 4 lint-naming via bazel (pass)" setup_section4_bazel_pass 1 ""
run_parity "section 4 lint-naming via bazel (fail)" setup_section4_bazel_fail 1 ""
run_parity "root discovery via git rev-parse when BUILD_WORKSPACE_DIRECTORY unset" setup_git_toplevel_discovery 0 ""

# --- New scenarios ---

# 1. Locale collation under LC_ALL=en_US.UTF-8 (X2 & Finding 1)
if locale -a 2>/dev/null | grep -E '^en_US\.(UTF-8|utf8)$' >/dev/null; then
  PARITY_LOCALE="en_US.UTF-8" run_parity "locale collation en_US.UTF-8 --list (sort -u and workflow glob)" setup_locale_collation 1 "" --list
  PARITY_LOCALE="en_US.UTF-8" run_parity "locale collation en_US.UTF-8 live report" setup_locale_collation 1 ""
else
  printf '  SKIP  locale collation en_US.UTF-8 (locale -a lacks en_US.UTF-8)\n'
fi

# 2. Symlinks (Finding 2)
run_parity "symlinks in workflows and actions --list" setup_symlinks 1 "" --list
run_parity "symlinks in workflows and actions live report" setup_symlinks 1 ""

# 3. Binary + Latin-1 non-UTF-8 workflow files (Finding 3)
run_parity "binary and Latin-1 workflow files --list" setup_binary_and_latin1 1 "" --list
run_parity "binary and Latin-1 workflow files live report" setup_binary_and_latin1 1 ""

# 4. CRLF line endings
run_parity "CRLF workflow files --list" setup_crlf 1 "" --list
run_parity "CRLF workflow files live report" setup_crlf 1 ""

# 5. Unicode spaces in workflow files
run_parity "Unicode spaces in workflow files --list" setup_unicode_spaces 1 "" --list
run_parity "Unicode spaces in workflow files live report" setup_unicode_spaces 1 ""

# 6. Huge on: block pipefail behavior
run_parity "huge on: block (>128KB) pipefail behavior --list" setup_huge_on_block 1 "" --list
run_parity "huge on: block (>128KB) pipefail behavior live report" setup_huge_on_block 1 ""

# 7. Empty secret/var set (using BASH4_LIST due to KEEP-SAFE bash 3.2 empty-array bug)
if [ "${#BASH4_LIST[@]}" -gt 0 ]; then
  PARITY_REQUIRE_BASH4=1 run_parity "empty secret and var set --list" setup_empty_secrets_and_vars 1 "" --list
  PARITY_REQUIRE_BASH4=1 run_parity "empty secret and var set live report" setup_empty_secrets_and_vars 1 ""
else
  printf '  SKIP  empty secret/var set parity (no bash >= 4 available; bash 3.2 crashes on empty arrays)\n'
fi

# 8. Environments list without trailing newline
run_parity "environments list without trailing newline" setup_env_no_trailing_newline 1 ""

# 9. Broken pipe (X1 & Finding 4)
run_broken_pipe_parity "broken pipe on --list (| head -n 1)" --list
run_broken_pipe_parity "broken pipe on live report (| head -n 1)"

# 10. command -v semantics: non-executable gh, bazel, python3 (Finding 5)
run_parity "non-executable gh on PATH passes command -v and fails auth status" setup_non_exec_gh_only 1 ""
PARITY_EXTRA_PATH="${SCENARIO_DIR}/bin2" run_parity "non-executable gh before executable gh on PATH uses executable gh" setup_non_exec_gh_then_exec_gh 1 ""
run_parity "non-executable bazel on PATH passes command -v and fails with Permission denied" setup_non_exec_bazel 1 ""
run_parity "non-executable python3 on PATH fails with Permission denied" setup_non_exec_python3 1 ""

# 11. Missing python3 (Finding 6)
PARITY_CUSTOM_PATH="${SCENARIO_DIR}/isolated_bin" run_parity "missing python3 prints command not found and counts as naming failure" setup_missing_python3 1 ""

# 12. Failed cd to repo root (Finding 7 & X4)
run_parity "failed cd to nonexistent BUILD_WORKSPACE_DIRECTORY" setup_standard_repo "${SCENARIO_DIR}/nonexistent_root_dir" ""

# 13. Non-UTF-8 arguments and env (X3 & Finding 8 & Round 2 Finding 3)
run_parity "non-UTF-8 unknown flag preserves raw bytes" setup_standard_repo 1 "" $'--bad\xff\xfe'
run_parity "non-UTF-8 --repo value in offline report preserves raw bytes" setup_offline_no_gh 1 "" --repo $'acme/wid\xffget'
run_parity "non-UTF-8 --repo and non-UTF-8 env name in live report with logging gh (Round 2 Finding 3)" setup_non_utf8_live 1 "" --repo $'acme/wid\xffget'
run_parity "non-UTF-8 repo slug from gh repo view in live report (Round 2 Finding 3)" setup_non_utf8_repo_from_gh 1 ""

# 14. Inherited stdin and PWD/OLDPWD updates after cd (X5)
PARITY_START_SUBDIR="nested/start" PARITY_STDIN_FILE="${SCENARIO_DIR}/stdin.txt" run_parity "cd updates PWD and OLDPWD and gh inherits stdin" setup_gh_reads_stdin 1 ""

# 15. Pseudo-TTY colour paths and padding of coloured cells
if [ "${SCRIPT_STYLE}" != "none" ]; then
  PARITY_PTY=1 run_parity "PTY colour output: --list" setup_complex_workflows_and_actions 1 "" --list
  PARITY_PTY=1 run_parity "PTY colour output: all green" setup_all_green 1 ""
  PARITY_PTY=1 run_parity "PTY colour output: Dependabot gap" setup_dep_empty 1 ""
  PARITY_PTY=1 run_parity "PTY colour output: missing secret and var (padding of coloured cells)" setup_missing_sec_and_var 1 ""
  PARITY_PTY=1 run_parity "PTY colour output: offline warning" setup_offline_no_gh 1 ""
  PARITY_PTY=1 run_parity "PTY colour output: unknown flag on stderr" setup_standard_repo 1 "" --bogus
else
  printf '  SKIP  PTY colour scenarios (script utility not available)\n'
fi

# 16. Closed stdout / stderr (Y1, Y2 & Round 2 Finding 1)
PARITY_CLOSE_STDOUT=1 run_parity "closed stdout (>&-) on --list exits 1 with write error" setup_standard_repo 1 "" --list
PARITY_CLOSE_STDOUT=1 run_parity "closed stdout (>&-) on live report exits 1 before section 4" setup_section4_python_pass 1 ""
PARITY_CLOSE_STDOUT=1 run_parity "closed stdout (>&-) on -h exits 1 with write error" setup_standard_repo 1 "" -h
PARITY_CLOSE_STDERR=1 run_parity "closed stderr (2>&-) on unknown flag exits 2" setup_standard_repo 1 "" --bogus
PARITY_CLOSE_STDERR=1 run_parity "closed stderr (2>&-) on missing workflows dir exits 2" setup_no_workflows 1 ""

# 17. /dev/full (Linux) and ulimit -f 0 write error (Y2 & Y7)
if [ -w /dev/full ]; then
  PARITY_STDOUT_TARGET="/dev/full" run_parity "/dev/full write error on --list" setup_standard_repo 1 "" --list
  PARITY_STDOUT_TARGET="/dev/full" run_parity "/dev/full write error on live report" setup_section4_python_pass 1 ""
else
  printf '  SKIP  /dev/full write error scenarios (/dev/full not available on macOS; covered via closed-stdout, ulimit -f 0, and SIGPIPE-ignored EPIPE)\n'
fi
PARITY_ULIMIT_ZERO=1 run_parity "ulimit -f 0 (EFBIG) write error on --list" setup_standard_repo 1 "" --list
PARITY_ULIMIT_ZERO=1 run_parity "ulimit -f 0 (EFBIG) write error on live report before section 4" setup_section4_python_pass 1 ""

# 18. SIGPIPE ignored at entry (Y1, Y2, Y3 & Y7)
PARITY_SIGPIPE_IGN=1 run_parity "SIGPIPE ignored at entry (EPIPE write error) on --list" setup_bulk_secrets_with_section4 1 "" --list
PARITY_SIGPIPE_IGN=1 run_parity "SIGPIPE ignored at entry (EPIPE write error) on live report before section 4" setup_bulk_secrets_with_section4 1 ""

# 19. Root path with symlink/.. logical cd -L normalisation (Round 2 Finding 2)
run_parity "root path with symlink/.. normalises logically like cd -L" setup_symlink_dotdot_root "${SCENARIO_DIR}/real_location/repo/sym_out/.." ""
run_parity "root path with symlink_parent/repo_link/subdir/.. normalises logically" setup_symlink_parent_dotdot_root "${SCENARIO_DIR}/sym_parent/repo_link/subdir/.." ""

# 20. Unset PATH and BASH_ENV not re-read per workflow (Round 2 Finding 4 & Y5)
if [ "${#BASH_DEFAULT_PATH_LIST[@]}" -gt 0 ]; then
  PARITY_UNSET_PATH=1 run_parity "unset PATH uses bash default search path (--list)" setup_standard_repo 1 "" --list
  PARITY_UNSET_PATH=1 run_parity "unset PATH uses bash default search path (offline report)" setup_standard_repo 1 ""
  PARITY_UNSET_PATH=1 run_parity "unset PATH finds ./gh in '.' from bash default search path (live report)" setup_unset_path_with_dot_gh 1 ""
fi
PARITY_BASH_ENV="${SCENARIO_DIR}/bash_env_probe.sh" run_parity "BASH_ENV is not re-read per workflow" setup_bash_env_trap 1 ""

# 21. Child killed by signal in section 4 (Y4)
run_parity "child python3 killed by SIGKILL in section 4" setup_section4_python_sigkill 1 ""

echo
printf '  %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
