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

# The smoke gate signs its sample event exactly as GitHub does. Checked against
# GitHub's documented X-Hub-Signature-256 test vector: secret
# "It's a Secret to Everybody", payload "Hello, World!".
set -uo pipefail
UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cicd_telemetry_smoke.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find cicd_telemetry_smoke.sh" >&2; exit 1; }
W="$(mktemp -d "${TEST_TMPDIR:-/tmp}/smoke.XXXXXX")"; trap 'rm -rf "$W"' EXIT
printf '%s' "It's a Secret to Everybody" > "$W/secret"
printf '%s' "Hello, World!" > "$W/payload"
got="$(SMOKE_LIB_ONLY=1 bash -c ". '$UNDER_TEST'; sign '$W/secret' '$W/payload'")"
want="sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17"
if [ "$got" = "$want" ]; then echo "PASS signature"; else echo "FAIL signature: got '$got'"; exit 1; fi

# The secret must never appear on any process's command line (visible in ps).
# Shim every tool sign() might call so each records its argv.
mkdir -p "$W/bin"
for tool in openssl python3; do
  real="$(command -v "$tool" || true)"
  [ -n "$real" ] || continue
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/argv"\nexec "%s" "$@"\n' "$W" "$real" > "$W/bin/$tool"
  chmod +x "$W/bin/$tool"
done
PATH="$W/bin:$PATH" SMOKE_LIB_ONLY=1 bash -c ". '$UNDER_TEST'; sign '$W/secret' '$W/payload'" >/dev/null
if grep -qF "It's a Secret to Everybody" "$W/argv" 2>/dev/null; then echo "FAIL secret appeared on a command line"; exit 1; else echo "PASS secret never on a command line"; fi

# Every run must end with a verdict: "✓ PASS" or a "✗" line, never a silent
# exit. Fake kubectl/curl/sleep stand in for the cluster; FAKE_MODE picks what
# breaks. (Under set -e a single failed Prometheus query used to end the run
# with no verdict at all.)
mkdir -p "$W/fake"
cat > "$W/fake/kubectl" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"get secret"*) [ "$FAKE_MODE" = secret_fail ] && { echo "Error from server (Forbidden)" >&2; exit 1; }
                  printf 'c2VjcmV0' ;;
  *prometheus-server-0*) [ "$FAKE_MODE" = prom_down ] && { echo "error: unable to upgrade connection" >&2; exit 1; }
                  echo '{"data":{"result":[{"value":[0,"1"]}]}}' ;;
  *"get pods"*) echo pod/tempo-0 ;;
  *api/search*) echo '{"traces":[{"traceID":"abc123"}]}' ;;
  *api/traces*) echo '{}' ;;
  *) echo "fake kubectl: unexpected: $*" >&2; exit 1 ;;
esac
SH
cat > "$W/fake/curl" <<'SH'
#!/usr/bin/env bash
case "$*" in *X-Hub-Signature-256*) printf 200 ;; *) printf 400 ;; esac
SH
printf '#!/usr/bin/env bash\n' > "$W/fake/sleep"
chmod +x "$W/fake/"*
run_smoke() { # run_smoke <mode> -> sets rc, out, err
  FAKE_MODE="$1" SMOKE_METRIC_WAIT_S=2 PATH="$W/fake:$PATH" KUBECONFIG=/dev/null bash "$UNDER_TEST" >"$W/out" 2>"$W/err"
  rc=$?; out="$(cat "$W/out")"; err="$(cat "$W/err")"
}
fail() { echo "FAIL $1"; echo "  rc=$rc stdout: $out"; echo "  stderr: $err"; exit 1; }

run_smoke ok
if [ "$rc" = 0 ] && grep -qF "✓ PASS" <<<"$(tail -n 1 <<<"$out")"; then
  echo "PASS healthy run ends with PASS"; else fail "healthy run ends with PASS"; fi

run_smoke prom_down
if [ "$rc" != 0 ] && grep -qF "✗ no run count" <<<"$err" && grep -qF "unable to upgrade connection" <<<"$err"; then
  echo "PASS failing Prometheus query ends with a verdict naming the error"
else fail "failing Prometheus query ends with a verdict naming the error"; fi

run_smoke secret_fail
if [ "$rc" != 0 ] && grep -qF "✗ FAIL: unexpected error" <<<"$err"; then
  echo "PASS unexpected failure ends with a verdict"; else fail "unexpected failure ends with a verdict"; fi
