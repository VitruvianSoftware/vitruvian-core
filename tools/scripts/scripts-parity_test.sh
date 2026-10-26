#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Parity test: tools/scripts/{kind-cluster.sh,agy,copilot} vs Rust ports.
# Every scenario stubs external tools (docker, kind, kubectl, npx) so tests
# are hermetic — no real cluster, Docker, or network needed.

set -uo pipefail

SH_KIND="${1:?missing kind-cluster.sh path}"
RS_KIND="${2:?missing kind-cluster rust binary path}"
SH_AGY="${3:?missing agy shell path}"
RS_AGY="${4:?missing agy rust binary path}"
SH_COPILOT="${5:?missing copilot shell path}"
RS_COPILOT="${6:?missing copilot rust binary path}"

for var in SH_KIND RS_KIND SH_AGY RS_AGY SH_COPILOT RS_COPILOT; do
  eval "val=\${${var}}"
  case "${val}" in /*) ;; *) eval "${var}=${PWD}/${val}" ;; esac
done

[ -f "${SH_KIND}" ]    || { echo "missing SH_KIND: ${SH_KIND}" >&2; exit 1; }
[ -x "${RS_KIND}" ]    || { echo "missing RS_KIND: ${RS_KIND}" >&2; exit 1; }
[ -f "${SH_AGY}" ]     || { echo "missing SH_AGY: ${SH_AGY}" >&2; exit 1; }
[ -x "${RS_AGY}" ]     || { echo "missing RS_AGY: ${RS_AGY}" >&2; exit 1; }
[ -f "${SH_COPILOT}" ] || { echo "missing SH_COPILOT: ${SH_COPILOT}" >&2; exit 1; }
[ -x "${RS_COPILOT}" ] || { echo "missing RS_COPILOT: ${RS_COPILOT}" >&2; exit 1; }

BASH_BIN="$(command -v bash)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

pass=0
fail=0

# normalise_argv0 <file>: replace path-like argv0 references with ARGV0
normalise_argv0() {
  local f="$1"
  sed \
    -e 's|Usage: [^ ]*|Usage: ARGV0|g' \
    -e 's|^    [^ ]* create |    ARGV0 create |' \
    -e 's|^    [^ ]* status |    ARGV0 status |' \
    -e 's|^    [^ ]* delete |    ARGV0 delete |' \
    "${f}" > "${f}.norm" && mv "${f}.norm" "${f}"
}

# stub_path: PATH that includes stubs PLUS real bash, coreutils, and grep.
stub_path() {
  echo "${WORK}/bin:$(dirname "${BASH_BIN}"):/usr/bin"
}

# compare: run two commands, normalise argv0, diff stdout+stderr+exit code.
# Usage: compare <label> <sh_cmd...> --- <rs_cmd...>
compare() {
  local label="$1"; shift

  local -a sh_cmd=()
  local -a rs_cmd=()
  local past_sep=0
  for tok in "$@"; do
    if [ "${tok}" = "---" ]; then
      past_sep=1
      continue
    fi
    if [ "${past_sep}" -eq 0 ]; then
      sh_cmd+=("${tok}")
    else
      rs_cmd+=("${tok}")
    fi
  done

  if [ -f "${WORK}/stdin.txt" ]; then
    "${sh_cmd[@]}" <"${WORK}/stdin.txt" >"${WORK}/sh.stdout" 2>"${WORK}/sh.stderr"; local sh_rc=$?
    "${rs_cmd[@]}" <"${WORK}/stdin.txt" >"${WORK}/rs.stdout" 2>"${WORK}/rs.stderr"; local rs_rc=$?
  else
    "${sh_cmd[@]}" </dev/null >"${WORK}/sh.stdout" 2>"${WORK}/sh.stderr"; local sh_rc=$?
    "${rs_cmd[@]}" </dev/null >"${WORK}/rs.stdout" 2>"${WORK}/rs.stderr"; local rs_rc=$?
  fi

  normalise_argv0 "${WORK}/sh.stdout"
  normalise_argv0 "${WORK}/rs.stdout"

  local ok=1
  if ! diff -u "${WORK}/sh.stdout" "${WORK}/rs.stdout" > "${WORK}/diff.stdout" 2>&1; then
    ok=0
  fi
  if ! diff -u "${WORK}/sh.stderr" "${WORK}/rs.stderr" > "${WORK}/diff.stderr" 2>&1; then
    ok=0
  fi
  if [ "${sh_rc}" != "${rs_rc}" ]; then
    ok=0
  fi

  if [ "${ok}" -eq 1 ]; then
    echo "PASS: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label}" >&2
    [ "${sh_rc}" != "${rs_rc}" ] && echo "  exit: sh=${sh_rc} rs=${rs_rc}" >&2
    [ -s "${WORK}/diff.stdout" ] && { echo "  stdout diff:"; cat "${WORK}/diff.stdout"; } >&2
    [ -s "${WORK}/diff.stderr" ] && { echo "  stderr diff:"; cat "${WORK}/diff.stderr"; } >&2
    fail=$((fail + 1))
  fi
}

# ─── Stubs ────────────────────────────────────────────────────────────────────

setup_stubs() {
  rm -rf "${WORK}/bin" "${WORK}/fakehome"
  mkdir -p "${WORK}/bin" "${WORK}/fakehome"
}

make_stub() {
  local name="$1"
  local body="$2"
  cat > "${WORK}/bin/${name}" <<STUBEOF
#!/usr/bin/env bash
${body}
STUBEOF
  chmod +x "${WORK}/bin/${name}"
}

# ─── kind-cluster tests ──────────────────────────────────────────────────────

# 1. help / --help / -h / no-args
setup_stubs
for subcmd in help --help -h; do
  compare "kind-cluster ${subcmd}" \
    bash "${SH_KIND}" "${subcmd}" \
    --- \
    "${RS_KIND}" "${subcmd}"
done
compare "kind-cluster no-args" \
  bash "${SH_KIND}" \
  --- \
  "${RS_KIND}"

# 2. unknown command
compare "kind-cluster unknown-cmd" \
  bash "${SH_KIND}" frobnicate \
  --- \
  "${RS_KIND}" frobnicate

# 3. create — docker info fails
setup_stubs
make_stub docker 'echo "docker fail" >&2; exit 1'
compare "kind-cluster create (docker fails)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" create \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" create

# 4. create — cluster already exists
setup_stubs
make_stub docker 'exit 0'
make_stub kind '
if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
  echo "local-dev-cluster"
  exit 0
fi
exit 0
'
compare "kind-cluster create (already exists)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" create \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" create

# 5. create — cluster does not exist, kind succeeds
setup_stubs
make_stub docker 'exit 0'
make_stub kind '
if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
  echo "other-cluster"
  exit 0
fi
if [ "$1" = "create" ]; then
  exit 0
fi
exit 0
'
make_stub kubectl '
if [ "$1" = "cluster-info" ]; then
  echo "Kubernetes control plane is running"
  exit 0
fi
exit 0
'
compare "kind-cluster create (success)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" create \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" create

# 6. create — kind create cluster fails
setup_stubs
make_stub docker 'exit 0'
make_stub kind '
if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
  echo ""
  exit 0
fi
if [ "$1" = "create" ]; then
  echo "create failed" >&2
  exit 1
fi
exit 0
'
compare "kind-cluster create (kind fails)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" create \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" create

# 7. delete — cluster exists
setup_stubs
make_stub docker 'exit 0'
make_stub kind '
if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
  echo "local-dev-cluster"
  exit 0
fi
if [ "$1" = "delete" ]; then
  exit 0
fi
exit 0
'
compare "kind-cluster delete (exists)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" delete \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" delete

# 8. delete — cluster does not exist
setup_stubs
make_stub docker 'exit 0'
make_stub kind '
if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
  echo ""
  exit 0
fi
exit 0
'
compare "kind-cluster delete (not exists)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" delete \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" delete

# 9. status — cluster exists
setup_stubs
make_stub docker 'exit 0'
make_stub kind '
if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
  echo "local-dev-cluster"
  exit 0
fi
exit 0
'
make_stub kubectl '
if [ "$1" = "config" ] && [ "$2" = "current-context" ]; then
  echo "kind-local-dev-cluster"
  exit 0
fi
if [ "$1" = "cluster-info" ]; then
  echo "Kubernetes control plane is running at https://127.0.0.1:6443"
  exit 0
fi
if [ "$1" = "get" ] && [ "$2" = "nodes" ]; then
  echo "NAME                              STATUS   ROLES           AGE   VERSION"
  echo "local-dev-cluster-control-plane   Ready    control-plane   1d    v1.31.0"
  exit 0
fi
exit 0
'
compare "kind-cluster status (exists)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" status \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" status

# 10. status — cluster does not exist
setup_stubs
make_stub docker 'exit 0'
make_stub kind '
if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
  echo ""
  exit 0
fi
exit 0
'
compare "kind-cluster status (not exists)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" status \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" status

# 11. rename-context — yes response
setup_stubs
make_stub kubectl '
if [ "$1" = "config" ] && [ "$2" = "current-context" ]; then
  echo "kind-local-dev-cluster"
  exit 0
fi
if [ "$1" = "config" ] && [ "$2" = "rename-context" ]; then
  echo "Context renamed."
  exit 0
fi
if [ "$1" = "config" ] && [ "$2" = "use-context" ]; then
  echo "Switched to context \"dev-local\"."
  exit 0
fi
exit 0
'
echo "yes" > "${WORK}/stdin.txt"
compare "kind-cluster rename-context (yes)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" rename-context \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" rename-context
rm -f "${WORK}/stdin.txt"

# 12. rename-context — no response
setup_stubs
make_stub kubectl '
if [ "$1" = "config" ] && [ "$2" = "current-context" ]; then
  echo "kind-local-dev-cluster"
  exit 0
fi
exit 0
'
echo "no" > "${WORK}/stdin.txt"
compare "kind-cluster rename-context (no)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" rename-context \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" rename-context
rm -f "${WORK}/stdin.txt"

# 13. rename-context — empty current context (exit 0, empty output)
setup_stubs
make_stub kubectl '
if [ "$1" = "config" ] && [ "$2" = "current-context" ]; then
  exit 0
fi
exit 0
'
echo "" > "${WORK}/stdin.txt"
compare "kind-cluster rename-context (empty ctx)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" rename-context \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" rename-context
rm -f "${WORK}/stdin.txt"

# 13b. rename-context — kubectl current-context exits non-zero
setup_stubs
make_stub kubectl '
if [ "$1" = "config" ] && [ "$2" = "current-context" ]; then
  exit 1
fi
exit 0
'
echo "" > "${WORK}/stdin.txt"
compare "kind-cluster rename-context (kubectl current-context fails)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" rename-context \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" rename-context
rm -f "${WORK}/stdin.txt"

# 14. rename-context — kubectl rename fails
setup_stubs
make_stub kubectl '
if [ "$1" = "config" ] && [ "$2" = "current-context" ]; then
  echo "kind-local-dev-cluster"
  exit 0
fi
if [ "$1" = "config" ] && [ "$2" = "rename-context" ]; then
  echo "error: rename failed" >&2
  exit 1
fi
exit 0
'
echo "yes" > "${WORK}/stdin.txt"
compare "kind-cluster rename-context (rename fails)" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" rename-context \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" rename-context
rm -f "${WORK}/stdin.txt"

# 15. restart
setup_stubs
make_stub docker 'exit 0'
make_stub kind '
if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
  echo "local-dev-cluster"
  exit 0
fi
if [ "$1" = "delete" ]; then exit 0; fi
if [ "$1" = "create" ]; then exit 0; fi
exit 0
'
make_stub kubectl '
if [ "$1" = "cluster-info" ]; then
  echo "Kubernetes control plane is running"
  exit 0
fi
exit 0
'
compare "kind-cluster restart" \
  env "PATH=$(stub_path)" bash "${SH_KIND}" restart \
  --- \
  env "PATH=$(stub_path)" "${RS_KIND}" restart

# ─── agy tests ───────────────────────────────────────────────────────────────

# 16. AGY_BIN set to executable
setup_stubs
cat > "${WORK}/agy-real" <<'EOF'
#!/usr/bin/env bash
echo "agy-real called with: $*"
exit 0
EOF
chmod +x "${WORK}/agy-real"
compare "agy AGY_BIN set" \
  env "AGY_BIN=${WORK}/agy-real" "HOME=${WORK}/fakehome" "PATH=$(stub_path)" bash "${SH_AGY}" --version \
  --- \
  env "AGY_BIN=${WORK}/agy-real" "HOME=${WORK}/fakehome" "PATH=$(stub_path)" "${RS_AGY}" --version

# 17. HOME/.local/bin/agy exists
setup_stubs
mkdir -p "${WORK}/fakehome/.local/bin"
cat > "${WORK}/fakehome/.local/bin/agy" <<'EOF'
#!/usr/bin/env bash
echo "home-agy called with: $*"
exit 0
EOF
chmod +x "${WORK}/fakehome/.local/bin/agy"
compare "agy HOME/.local/bin/agy" \
  env -u AGY_BIN "HOME=${WORK}/fakehome" "PATH=$(stub_path)" bash "${SH_AGY}" hello world \
  --- \
  env -u AGY_BIN "HOME=${WORK}/fakehome" "PATH=$(stub_path)" "${RS_AGY}" hello world

# 18. PATH lookup
setup_stubs
mkdir -p "${WORK}/fakehome/.local/bin"
make_stub agy 'echo "path-agy called with: $*"; exit 0'
compare "agy PATH lookup" \
  env -u AGY_BIN "HOME=${WORK}/fakehome" "PATH=$(stub_path)" bash "${SH_AGY}" arg1 \
  --- \
  env -u AGY_BIN "HOME=${WORK}/fakehome" "PATH=$(stub_path)" "${RS_AGY}" arg1

# 19. Non-executable skipped
setup_stubs
mkdir -p "${WORK}/fakehome/.local/bin"
echo "not executable" > "${WORK}/fakehome/.local/bin/agy"
chmod -x "${WORK}/fakehome/.local/bin/agy"
compare "agy non-executable skipped (exit 127)" \
  env -u AGY_BIN "HOME=${WORK}/fakehome" "PATH=$(stub_path)" bash "${SH_AGY}" \
  --- \
  env -u AGY_BIN "HOME=${WORK}/fakehome" "PATH=$(stub_path)" "${RS_AGY}"

# 20. Not installed anywhere
setup_stubs
mkdir -p "${WORK}/fakehome/.local/bin"
compare "agy not installed (exit 127)" \
  env -u AGY_BIN "HOME=${WORK}/fakehome" "PATH=$(stub_path)" bash "${SH_AGY}" \
  --- \
  env -u AGY_BIN "HOME=${WORK}/fakehome" "PATH=$(stub_path)" "${RS_AGY}"

# ─── copilot tests ───────────────────────────────────────────────────────────

# 21. No args → npx copilot
setup_stubs
make_stub npx '
echo "npx called: $*"
exit 0
'
compare "copilot no-args" \
  env "PATH=$(stub_path)" bash "${SH_COPILOT}" \
  --- \
  env "PATH=$(stub_path)" "${RS_COPILOT}"

# 22. With args
setup_stubs
make_stub npx '
echo "npx called: $*"
exit 0
'
compare "copilot with-args" \
  env "PATH=$(stub_path)" bash "${SH_COPILOT}" foo bar baz \
  --- \
  env "PATH=$(stub_path)" "${RS_COPILOT}" foo bar baz

# 23. Exit code propagation
setup_stubs
make_stub npx '
exit 42
'
compare "copilot exit-code" \
  env "PATH=$(stub_path)" bash "${SH_COPILOT}" \
  --- \
  env "PATH=$(stub_path)" "${RS_COPILOT}"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "scripts parity: ${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ] || exit 1
