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

# Hermetic self-test for tidy.sh: a fake `go` on PATH, synthetic module trees,
# no network, no real toolchain. Pins the behaviours a green run must imply --
# above all that check mode NEVER writes and never reports green on an empty
# sweep, since both would make it a gate that passes when it did nothing.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tidy.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find tidy.sh" >&2; exit 1; }

PASS=0; FAIL=0
check() { # check <name> <condition-result>
  if [ "$2" = "0" ]; then printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1))
  else printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); fi
}

# make_fake_go <bin> <tidy-diff-exit> — a `go` stub that records invocations.
# On `mod tidy -diff` it exits with the requested code (non-zero = drifted) and
# prints a diff-shaped line; on a bare `mod tidy` it mutates go.mod, so the test
# can prove which mode actually wrote.
# Like make_fake_go, but `mod tidy -diff` fails with a module-proxy TRANSPORT
# error for the first $fail_times invocations, then succeeds. Lets the tests
# watch the retry actually happen instead of asserting on a message.
make_fake_go_transient() {
  bin="$1"; fail_times="$2"
  mkdir -p "${bin}"
  echo 0 > "${bin}/attempts"
  cat > "${bin}/go" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${bin}/calls.log"
case "\$*" in
  *"mod tidy -diff"*)
    n=\$(cat "${bin}/attempts"); n=\$((n + 1)); echo "\$n" > "${bin}/attempts"
    if [ "\$n" -le ${fail_times} ]; then
      echo 'go: github.com/pulumi/pulumi-gcp/sdk/v9@v9.34.1: read "https://proxy.golang.org/...": stream error: stream ID 7; INTERNAL_ERROR; received from peer' >&2
      exit 1
    fi
    exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "${bin}/go"
}

make_fake_go() {
  bin="$1"; diff_rc="$2"
  mkdir -p "${bin}"
  cat > "${bin}/go" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${bin}/calls.log"
case "\$*" in
  *"mod tidy -diff"*)
    echo "-google.golang.org/grpc v1.80.0"
    echo "+google.golang.org/grpc v1.82.1"
    exit ${diff_rc} ;;
  *"mod tidy"*)
    echo "// tidied" >> go.mod
    exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "${bin}/go"
}

# make_tree <root> <n> — n synthetic modules under <root>/mN/go.mod.
make_tree() {
  root="$1"; n="$2"
  for i in $(seq 1 "$n"); do
    mkdir -p "${root}/m${i}"
    printf 'module example.com/m%s\n\ngo 1.26.2\n' "$i" > "${root}/m${i}/go.mod"
  done
}

echo "gomod tidy_test:"

# --- 1. syntax. --------------------------------------------------------------
bash -n "${UNDER_TEST}" 2>/dev/null
check "tidy.sh parses" "$?"

# --- 2. check mode is READ-ONLY. ---------------------------------------------
# The whole safety argument for using this as a required gate. If -diff were
# ever swapped for tidy-then-git-diff, this fails.
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_fake_go "${bin}" 1
make_tree "${tmp}/src" 2
before="$(cat "${tmp}/src/m1/go.mod")"
PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src >/dev/null 2>&1
after="$(cat "${tmp}/src/m1/go.mod")"
[ "${before}" = "${after}" ]
check "check mode does not modify go.mod" "$?"

grep -q -- "mod tidy -diff" "${bin}/calls.log" 2>/dev/null
check "check mode uses 'go mod tidy -diff'" "$?"

# --- 3. drift fails, and names the fix. --------------------------------------
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_fake_go "${bin}" 1
make_tree "${tmp}/src" 2
out="$(PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src 2>&1)"; rc=$?
[ "${rc}" -ne 0 ]
check "check mode exits non-zero on drift" "$?"

grep -q "bazel run //tools/gomod:tidy" <<<"${out}"
check "drift message names the fixing command" "$?"

grep -q "grpc v1.82.1" <<<"${out}"
check "drift message includes the offending diff" "$?"

# --- 4. tidy tree passes. ----------------------------------------------------
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_fake_go "${bin}" 0
make_tree "${tmp}/src" 3
PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src >/dev/null 2>&1
check "check mode exits zero when every module is tidy" "$?"

# --- 5. an EMPTY sweep is a failure, not a pass. -----------------------------
# A gate that finds nothing and reports green is worse than no gate: it makes a
# broken invocation (wrong cwd, renamed tree) look like a clean one.
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_fake_go "${bin}" 0
mkdir -p "${tmp}/src"
PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src >/dev/null 2>&1
[ "$?" -ne 0 ]
check "zero modules found is a failure, not green" "$?"

# A root that does not exist at all is likewise fatal.
PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check no-such-dir >/dev/null 2>&1
[ "$?" -ne 0 ]
check "missing root is a failure" "$?"

# --- 5b. an exact `<dir>/go.mod` root names ONE module, not a subtree. --------
# The infra cluster is not subtree-shaped: two modules under
# infrastructure/pulumi consume pkg/secrets through a `replace`, while the other
# 33 go.mods there belong to a different cluster (six of them already untidy on
# main). Sweeping the subtree would red-line main; naming the module covers the
# coupled pair and nothing else. So the exact form must NOT recurse.
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_fake_go "${bin}" 0
mkdir -p "${tmp}/src/nested"
printf 'module example.com/top\n\ngo 1.26.2\n' > "${tmp}/src/go.mod"
printf 'module example.com/nested\n\ngo 1.26.2\n' > "${tmp}/src/nested/go.mod"
out="$(PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src/go.mod 2>&1)"
case "${out}" in *"1 module(s)"*) check "exact <dir>/go.mod root covers exactly one module" 0 ;;
  *) check "exact <dir>/go.mod root covers exactly one module" 1 ;; esac

# ...and the subtree form still recurses, so the two are genuinely distinct.
out="$(PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src 2>&1)"
case "${out}" in *"2 module(s)"*) check "...while the subtree form still recurses" 0 ;;
  *) check "...while the subtree form still recurses" 1 ;; esac

# A named module that does not exist is fatal for the same reason a missing root
# is: silently covering less than the list claims is the false-green this gate
# exists to prevent.
PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src/nope/go.mod >/dev/null 2>&1
[ "$?" -ne 0 ]
check "a named module that does not exist is a failure" "$?"

# --- 6. fix mode DOES write. -------------------------------------------------
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_fake_go "${bin}" 0
make_tree "${tmp}/src" 1
PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" src >/dev/null 2>&1
grep -q "// tidied" "${tmp}/src/m1/go.mod"
check "fix mode rewrites go.mod" "$?"

# --- 7. GOWORK=off reaches the toolchain. ------------------------------------
# Workspace mode resolves against the workspace rather than the module, so it
# computes a different answer than the standalone build example-build runs.
tmp="$(mktemp -d)"; bin="${tmp}/bin"
mkdir -p "${bin}"
cat > "${bin}/go" <<'EOF'
#!/usr/bin/env bash
[ "${GOWORK:-}" = "off" ] || exit 66
exit 0
EOF
chmod +x "${bin}/go"
make_tree "${tmp}/src" 1
PATH="${bin}:${PATH}" GOWORK="" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src >/dev/null 2>&1
check "GOWORK=off is exported to the go toolchain" "$?"

# --- transport failures are retried, and never called drift. -----------------
#
# `go mod tidy -diff` exits non-zero for BOTH "out of sync" and "the proxy fell
# over". Collapsing them made this gate LIE on 2026-08-20: it announced "2 of 58
# module(s) are out of sync ... Fix with: bazel run //tools/gomod:tidy" when
# nothing was out of sync (the same commit re-ran clean at "all 58 tidy").
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_fake_go_transient "${bin}" 2   # fails twice, succeeds on the third
make_tree "${tmp}/src" 1
out="$(PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src 2>&1)"; rc=$?
[ "${rc}" -eq 0 ]
check "a transport failure that clears is retried to success" "$?"
[ "$(cat "${bin}/attempts")" = "3" ]
check "...taking exactly 3 attempts, not 1" "$?"

tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_fake_go_transient "${bin}" 99  # never recovers
make_tree "${tmp}/src" 1
out="$(PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src 2>&1)"; rc=$?
[ "${rc}" -ne 0 ]
check "a permanent transport failure still fails the gate" "$?"
printf '%s' "${out}" | grep -q "could not reach the module proxy"
check "...and is reported as INFRASTRUCTURE, not drift" "$?"
! printf '%s' "${out}" | grep -q "out of sync with their .replace. targets"
check "...so it never claims the modules are out of sync" "$?"
# The message DOES name the tidy command -- to warn against it. Assert the
# negative framing rather than the absence of the string, which an earlier
# version of this test got wrong.
printf '%s' "${out}" | grep -q "Do NOT run"
check "...and warns AGAINST running a tidy that would fix nothing" "$?"
[ "$(cat "${bin}/attempts")" = "3" ]
check "...after bounded retries, not forever" "$?"

# The dangerous inverse: the retry must not slow down or excuse REAL drift.
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_fake_go "${bin}" 1             # a genuine diff, exit 1, no proxy text
make_tree "${tmp}/src" 1
out="$(PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src 2>&1)"; rc=$?
[ "${rc}" -ne 0 ]
check "genuine drift still fails" "$?"
printf '%s' "${out}" | grep -q "out of sync with their .replace. targets"
check "...still reported as drift" "$?"
[ "$(grep -c -- "mod tidy -diff" "${bin}/calls.log")" = "1" ]
check "...on the FIRST attempt — real drift is never retried" "$?"


# --- 8. vendor/ is excluded. -------------------------------------------------
# A vendored go.mod is not a module this repo owns; tidying it is meaningless.
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_fake_go "${bin}" 0
make_tree "${tmp}/src" 1
mkdir -p "${tmp}/src/m1/vendor/example.com/dep"
printf 'module example.com/dep\n' > "${tmp}/src/m1/vendor/example.com/dep/go.mod"
out="$(PATH="${bin}:${PATH}" BUILD_WORKSPACE_DIRECTORY="${tmp}" \
  bash "${UNDER_TEST}" --check src 2>&1)"
grep -q "1 module(s)" <<<"${out}"
check "vendored go.mod is not swept" "$?"

echo
printf '  %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
