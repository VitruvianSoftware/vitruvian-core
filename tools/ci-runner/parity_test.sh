#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

# Hermetic parity test: run parity.sh and the Rust binary side-by-side with
# stubbed environments, comparing stdout, stderr, and exit code.

set -uo pipefail

SH_BIN="${1:?usage: parity_test.sh <parity.sh> <parity-rs>}"
RS_BIN="${2:?usage: parity_test.sh <parity.sh> <parity-rs>}"

case "${SH_BIN}" in /*) ;; *) SH_BIN="${PWD}/${SH_BIN}" ;; esac
case "${RS_BIN}" in /*) ;; *) RS_BIN="${PWD}/${RS_BIN}" ;; esac

[ -f "${SH_BIN}" ] || { echo "missing SH_BIN: ${SH_BIN}" >&2; exit 1; }
[ -x "${RS_BIN}" ] || { echo "missing RS_BIN: ${RS_BIN}" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

pass=0
fail=0

# --- Stub environment builder ------------------------------------------------

# Build a complete fake environment in a directory. All tools are stubs that
# exit 0. Caller can remove/break individual stubs to test failure paths.
build_env() {
    local envdir="$1"
    rm -rf "${envdir}"
    mkdir -p "${envdir}/bin" "${envdir}/runner/bin"

    # os-release
    cat > "${envdir}/os-release" <<'OSEOF'
NAME="Ubuntu"
VERSION="26.04 LTS (Noble Numbat)"
VERSION_ID="26.04"
ID=ubuntu
OSEOF

    # id stub: returns runner:1001
    cat > "${envdir}/bin/id" <<'IDEOF'
#!/bin/sh
case "$1" in
    -un) echo "runner" ;;
    -u)  echo "1001" ;;
    *)   echo "runner" ;;
esac
IDEOF
    chmod +x "${envdir}/bin/id"

    # sudo stub
    cat > "${envdir}/bin/sudo" <<'SUDOEOF'
#!/bin/sh
shift  # skip -n
exec "$@"
SUDOEOF
    chmod +x "${envdir}/bin/sudo"

    # dpkg stub
    cat > "${envdir}/bin/dpkg" <<'DPKGEOF'
#!/bin/sh
echo "dpkg 1.0"
DPKGEOF
    chmod +x "${envdir}/bin/dpkg"

    # true stub (needed because sudo calls it)
    cat > "${envdir}/bin/true" <<'TRUEEOF'
#!/bin/sh
exit 0
TRUEEOF
    chmod +x "${envdir}/bin/true"

    # test stub — we need real test, use /bin/test or /usr/bin/test
    # Actually, `test` is a bash builtin so the shell script uses the builtin.
    # But we need it on PATH for the Rust binary which runs `test` as a command.
    # Wait — the bash script uses `check test "$VERSION_ID" = 26.04` which runs
    # `test` as a command (check passes "$@" to if "$@"). So both need it.
    # Link to the real one.
    if [ -x /usr/bin/test ]; then
        ln -sf /usr/bin/test "${envdir}/bin/test"
    elif [ -x /bin/test ]; then
        ln -sf /bin/test "${envdir}/bin/test"
    fi

    # env stub — need real env for the `env USE_BAZEL_VERSION=... bazel --version` check
    if [ -x /usr/bin/env ]; then
        ln -sf /usr/bin/env "${envdir}/bin/env"
    elif [ -x /bin/env ]; then
        ln -sf /bin/env "${envdir}/bin/env"
    fi

    # bash itself (the shell script needs it)
    local real_bash
    real_bash="$(command -v bash)"
    ln -sf "${real_bash}" "${envdir}/bin/bash"

    # All 19 tools + bazel + bazelisk
    for tool in git git-lfs gh curl jq python3 node npm npx shellcheck unzip zip xz zstd gcc g++ make tar gpg bazel bazelisk; do
        cat > "${envdir}/bin/${tool}" <<TOOLEOF
#!/bin/sh
exit 0
TOOLEOF
        chmod +x "${envdir}/bin/${tool}"
    done

    # cat, echo, printf, grep, sed, sort, command — needed by bash internally
    for util in cat echo printf grep sed sort command chmod mkdir; do
        local real_path
        real_path="$(command -v "${util}" 2>/dev/null || true)"
        if [ -n "${real_path}" ] && [ -x "${real_path}" ]; then
            ln -sf "${real_path}" "${envdir}/bin/${util}"
        fi
    done

    # Runner home
    cat > "${envdir}/runner/run.sh" <<'RUNEOF'
#!/bin/sh
echo "runner"
RUNEOF
    chmod +x "${envdir}/runner/run.sh"

    cat > "${envdir}/runner/bin/Runner.Listener" <<'LISTEOF'
#!/bin/sh
echo "2.300.0"
LISTEOF
    chmod +x "${envdir}/runner/bin/Runner.Listener"
}

# --- Compare function ---------------------------------------------------------

compare() {
    local label="$1"
    local envdir="$2"
    local extra_env="${3:-}"
    local sh_rc rs_rc

    local run_env=(
        env -i
        PATH="${envdir}/bin"
        HOME="${envdir}"
        OS_RELEASE_PATH="${envdir}/os-release"
        RUNNER_HOME="${envdir}/runner"
    )

    if [ -n "${extra_env}" ]; then
        run_env+=("${extra_env}")
    fi

    "${run_env[@]}" bash "${SH_BIN}" > "${WORK}/sh.stdout" 2> "${WORK}/sh.stderr"
    sh_rc=$?

    "${run_env[@]}" "${RS_BIN}" > "${WORK}/rs.stdout" 2> "${WORK}/rs.stderr"
    rs_rc=$?

    if diff -u "${WORK}/sh.stdout" "${WORK}/rs.stdout" > "${WORK}/diff.stdout" 2>&1 &&
       diff -u "${WORK}/sh.stderr" "${WORK}/rs.stderr" > "${WORK}/diff.stderr" 2>&1 &&
       [ "${sh_rc}" = "${rs_rc}" ]; then
        echo "PASS: ${label}"
        pass=$((pass + 1))
    else
        echo "FAIL: ${label}" >&2
        if [ -s "${WORK}/diff.stdout" ]; then
            echo "  stdout diff:" >&2
            cat "${WORK}/diff.stdout" >&2
        fi
        if [ -s "${WORK}/diff.stderr" ]; then
            echo "  stderr diff:" >&2
            cat "${WORK}/diff.stderr" >&2
        fi
        echo "  exit: sh=${sh_rc} rs=${rs_rc}" >&2
        fail=$((fail + 1))
    fi
}

# --- Test cases ---------------------------------------------------------------

# 1. All passing
ENVDIR="${WORK}/env1"
build_env "${ENVDIR}"
compare "all-passing" "${ENVDIR}"

# 2. Wrong VERSION_ID
ENVDIR="${WORK}/env2"
build_env "${ENVDIR}"
cat > "${ENVDIR}/os-release" <<'EOF'
NAME="Ubuntu"
VERSION_ID="24.04"
ID=ubuntu
EOF
compare "wrong-version-id" "${ENVDIR}"

# 3. Wrong id output
ENVDIR="${WORK}/env3"
build_env "${ENVDIR}"
cat > "${ENVDIR}/bin/id" <<'EOF'
#!/bin/sh
case "$1" in
    -un) echo "ubuntu" ;;
    -u)  echo "1000" ;;
    *)   echo "ubuntu" ;;
esac
EOF
chmod +x "${ENVDIR}/bin/id"
compare "wrong-id" "${ENVDIR}"

# 4. Failing sudo
ENVDIR="${WORK}/env4"
build_env "${ENVDIR}"
cat > "${ENVDIR}/bin/sudo" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "${ENVDIR}/bin/sudo"
compare "failing-sudo" "${ENVDIR}"

# 5. Missing tool (jq removed)
ENVDIR="${WORK}/env5"
build_env "${ENVDIR}"
rm -f "${ENVDIR}/bin/jq"
compare "missing-jq" "${ENVDIR}"

# 6. Non-executable run.sh
ENVDIR="${WORK}/env6"
build_env "${ENVDIR}"
chmod -x "${ENVDIR}/runner/run.sh"
compare "non-executable-run-sh" "${ENVDIR}"

# 7. Failing Runner.Listener
ENVDIR="${WORK}/env7"
build_env "${ENVDIR}"
cat > "${ENVDIR}/runner/bin/Runner.Listener" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "${ENVDIR}/runner/bin/Runner.Listener"
compare "failing-runner-listener" "${ENVDIR}"

# 8. Failing bazel --version
ENVDIR="${WORK}/env8"
build_env "${ENVDIR}"
cat > "${ENVDIR}/bin/bazel" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
    exit 1
fi
exit 0
EOF
chmod +x "${ENVDIR}/bin/bazel"
compare "failing-bazel-version" "${ENVDIR}"

# 9. Custom BAZEL_VERSION
ENVDIR="${WORK}/env9"
build_env "${ENVDIR}"
compare "custom-bazel-version" "${ENVDIR}" "BAZEL_VERSION=10.0.0"

# --- Summary ------------------------------------------------------------------

echo ""
echo "parity_test: ${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ] || exit 1
