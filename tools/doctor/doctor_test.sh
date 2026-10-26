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

# Behavioural test for the `doctor` env-checker. $1 is the program under test:
# doctor.sh (run with bash) or the Rust binary. Each case builds a throwaway
# workspace and a PATH of #!/bin/sh stand-ins, runs the checker, and asserts
# the report rows, the summary line and the exit code.
set -euo pipefail

PROG="${1:?usage: doctor_test.sh <doctor.sh | doctor binary>}"
case "$PROG" in /*) ;; *) PROG="$PWD/$PROG" ;; esac
RUN=("$PROG")
case "$PROG" in *.sh) RUN=("$(command -v bash)" "$PROG") ;; esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SYS="$TMP/sys"
mkdir -p "$SYS"
for u in awk sed grep tr head cut cat; do
  ln -s "$(PATH=/usr/bin:/bin command -v "$u")" "$SYS/$u"
done

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

N=0
# new_case: fresh workspace $WS and stub dir $STUBS.
new_case() {
  N=$((N + 1))
  WS="$TMP/case$N/ws"
  STUBS="$TMP/case$N/stubs"
  mkdir -p "$WS" "$STUBS"
}
stub() { # stub <name> <body>
  printf '#!/bin/sh\n%s\n' "$2" > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}
# go: run the checker in $WS; leaves OUT, ERR, RC.
go() {
  RC=0
  OUT="$(cd "$WS" && env -i PATH="$STUBS:$SYS" HOME="$TMP" TMPDIR="$TMP" \
    BUILD_WORKSPACE_DIRECTORY="$WS" DOCKER_INFO_RC="${DOCKER_INFO_RC:-0}" \
    "${RUN[@]}" "$@" 2> "$TMP/err")" || RC=$?
  ERR="$(cat "$TMP/err")"
}
has() { grep -Eq -- "$1" <<<"$OUT" || fail "$2: no line matching /$1/ in:
$OUT"; }

# 1. Everything pinned matches.
new_case
printf '9.3.0\n' > "$WS/.bazelversion"
printf 'v22.21.1\n' > "$WS/.nvmrc"
printf '{"packageManager": "pnpm@10.20.0"}\n' > "$WS/package.json"
printf 'module x\n\ngo 1.25.5\n' > "$WS/go.mod"
stub bazel "printf 'Bazelisk version: 1.25.0\nBuild label: 9.3.0\n'"
stub node "echo v22.21.1"
stub pnpm "echo 10.20.0"
stub go "echo 'go version go1.25.5 darwin/arm64'"
stub git "echo 'git version 2.54.0'"
go --label my app --required bazel,node,pnpm,go,git --gomod go.mod
[[ "$RC" -eq 0 ]] || fail "all-ok exited $RC: $OUT"
has '^doctor — my app$' "multi-word label"
has '^  ✓  bazel +9\.3\.0 +9\.3\.0 *$' "bazel row"
has '^  ✓  go +1\.25\.5 +1\.25\.5 *$' "go row"
has '^✓ PASS — 5 ok, 1 warn, 0 fail\.$' "summary"
[[ -z "$ERR" ]] || fail "stderr not empty: $ERR"
ok "pinned tools that match pass, with the label joined"

# 2. A required pinned tool off by a minor version fails the run.
new_case
printf '9.3.0\n' > "$WS/.bazelversion"
stub bazel "echo 'Build label: 9.4.1'"
go --required bazel
[[ "$RC" -eq 1 ]] || fail "mismatch exited $RC"
has '^  ✗  bazel +9\.4\.1 +9\.3\.0 +→ fix: install Bazelisk' "mismatch row"
has '^✗ FAIL — 0 ok, 1 warn, 1 fail\. Required checks did not pass\.$' "fail summary"
ok "a required minor mismatch fails"

# 3. The same mismatch, optional, only warns; a patch drift is ok.
new_case
printf '9.3.0\n' > "$WS/.bazelversion"
printf '22.21.1\n' > "$WS/.nvmrc"
stub bazel "echo 'Build label: 9.4.1'"
stub node "echo v22.21.7"
go --required node --optional bazel
[[ "$RC" -eq 0 ]] || fail "optional mismatch exited $RC"
has '^  ⚠  bazel ' "optional warn"
has '^  ✓  node +22\.21\.7 +22\.21\.1 +→ fix: patch differs \(ok\)$' "patch note"
ok "optional mismatch warns; patch drift is ok"

# 4. Missing tools: required fails, optional warns, with hints.
new_case
go --required zig --optional lima
[[ "$RC" -eq 1 ]] || fail "missing required exited $RC"
has '^  ✗  zig +not found +→ fix: install zig$' "generic hint"
has '^  ⚠  lima +not found +→ fix: install Lima' "lima hint"
ok "missing tools fail or warn by tier"

# 5. Docker: present but daemon down.
new_case
# shellcheck disable=SC2016 # the stub's body, expanded when it runs
stub docker 'case "$1" in info) exit "$DOCKER_INFO_RC";; esac; echo "Docker version 29.6.0, build x"'
DOCKER_INFO_RC=1 go --required docker
[[ "$RC" -eq 1 ]] || fail "docker down exited $RC"
has '^  ✗  docker +29\.6\.0 \(daemon down\) +→ fix: start Docker/colima$' "daemon down"
go --optional docker
[[ "$RC" -eq 0 ]] || fail "docker up exited $RC"
has '^  ✓  docker +29\.6\.0 *$' "daemon up"
ok "docker is checked through its daemon"

# 6. Unknown args warn on stderr; the build cache is detected.
new_case
printf '# >>> build cache (managed by tools/remote:setup)\n' > "$WS/user.bazelrc"
go --nope
[[ "$RC" -eq 0 ]] || fail "unknown arg exited $RC"
[[ "$ERR" == "doctor: ignoring unknown arg '--nope'" ]] || fail "unknown arg warning: $ERR"
has '^  ✓  build-cache +configured +shared default$' "build cache"
has '^doctor — vitruvian-core$' "default label"
ok "unknown args warn; a configured build cache is ok"

echo "All doctor tests passed ($PROG)"
