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

# Parity test: run both the original smoke.sh and the Rust binary side-by-side.
set -euo pipefail

sh_script="$1"
rust_bin="$2"
case "$sh_script" in /*) ;; *) sh_script="$PWD/$sh_script" ;; esac
case "$rust_bin" in /*) ;; *) rust_bin="$PWD/$rust_bin" ;; esac

failed=0
fail() {
	echo "FAIL: $*" >&2
	failed=1
}
ok() { echo "ok: $*"; }

# Test 1: empty CAND — both skip with exit 0
sh_rc=0
CAND="" bash "$sh_script" >/dev/null 2>&1 || sh_rc=$?
rs_rc=0
CAND="" "$rust_bin" >/dev/null 2>&1 || rs_rc=$?
[ "$sh_rc" -eq 0 ] && [ "$rs_rc" -eq 0 ] && ok "empty CAND: both exit 0" || fail "empty CAND: sh=$sh_rc rs=$rs_rc"

# Test 2: unset CAND — both skip with exit 0
sh_rc=0
(
	unset CAND
	bash "$sh_script" >/dev/null 2>&1
) || sh_rc=$?
rs_rc=0
(
	unset CAND
	"$rust_bin" >/dev/null 2>&1
) || rs_rc=$?
[ "$sh_rc" -eq 0 ] && [ "$rs_rc" -eq 0 ] && ok "unset CAND: both exit 0" || fail "unset CAND: sh=$sh_rc rs=$rs_rc"

# Test 3: message parity — both produce identical output on empty CAND
sh_out="$(CAND="" bash "$sh_script" 2>&1)" || true
rs_out="$(CAND="" "$rust_bin" 2>&1)" || true
[ "$sh_out" = "$rs_out" ] && ok "identical skip output on empty CAND" || fail "skip message differs: sh='$sh_out' rs='$rs_out'"

# Test 4: mounted DOM with stubbed curl + google-chrome
STUBS="$TEST_TMPDIR/smoke-stubs"
mkdir -p "$STUBS"
cat >"$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$STUBS/google-chrome" <<'EOF'
#!/usr/bin/env bash
printf '<html><body><h1>Select a provider</h1></body></html>'
EOF
chmod +x "$STUBS/curl" "$STUBS/google-chrome"

sh_out="$(PATH="$STUBS:/usr/bin:/bin" CAND="https://example.test" bash "$sh_script" 2>&1)"
rs_out="$(PATH="$STUBS:/usr/bin:/bin" CAND="https://example.test" "$rust_bin" 2>&1)"
[ "$sh_out" = "$rs_out" ] && ok "mounted DOM: identical output and exit 0" || fail "mounted DOM differs: sh='$sh_out' rs='$rs_out'"

# Test 5: unmounted DOM with stubbed curl + google-chrome
cat >"$STUBS/google-chrome" <<'EOF'
#!/usr/bin/env bash
printf '<html><body>static shell only</body></html>'
EOF
chmod +x "$STUBS/google-chrome"

sh_rc=0
sh_out="$(PATH="$STUBS:/usr/bin:/bin" CAND="https://example.test" bash "$sh_script" 2>&1)" || sh_rc=$?
rs_rc=0
rs_out="$(PATH="$STUBS:/usr/bin:/bin" CAND="https://example.test" "$rust_bin" 2>&1)" || rs_rc=$?
[ "$sh_rc" -eq 1 ] && [ "$rs_rc" -eq 1 ] && [ "$sh_out" = "$rs_out" ] &&
	ok "unmounted DOM: identical output and exit 1" || fail "unmounted DOM differs: sh=($sh_rc) '$sh_out' rs=($rs_rc) '$rs_out'"

exit "$failed"
