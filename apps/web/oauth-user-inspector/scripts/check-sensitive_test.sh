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

# Parity test: run both the original check-sensitive.sh and the Rust binary
# against the same git staging scenarios and assert identical exit codes.
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

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
WORK="$TEST_TMPDIR/check-sensitive"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"
git init -q
git config user.name test
git config user.email test@example.invalid
git commit -q --allow-empty -m init

# Test 1: clean staging — both exit 0
touch safe.txt
git add safe.txt
sh_rc=0
bash "$sh_script" >/dev/null 2>&1 || sh_rc=$?
rs_rc=0
"$rust_bin" >/dev/null 2>&1 || rs_rc=$?
[ "$sh_rc" -eq 0 ] && [ "$rs_rc" -eq 0 ] && ok "clean staging: both exit 0" || fail "clean: sh=$sh_rc rs=$rs_rc"
git reset -q HEAD safe.txt
rm safe.txt

# Test 2: .env.local staged — both exit 1
touch .env.local
git add .env.local
sh_rc=0
bash "$sh_script" >/dev/null 2>&1 || sh_rc=$?
rs_rc=0
"$rust_bin" >/dev/null 2>&1 || rs_rc=$?
[ "$sh_rc" -eq 1 ] && [ "$rs_rc" -eq 1 ] && ok ".env.local staged: both exit 1" || fail ".env.local: sh=$sh_rc rs=$rs_rc"
git reset -q HEAD .env.local
rm .env.local

# Test 3: dist/ file staged — both exit 1
mkdir -p dist
touch dist/bundle.js
git add dist/bundle.js
sh_rc=0
bash "$sh_script" >/dev/null 2>&1 || sh_rc=$?
rs_rc=0
"$rust_bin" >/dev/null 2>&1 || rs_rc=$?
[ "$sh_rc" -eq 1 ] && [ "$rs_rc" -eq 1 ] && ok "dist/ staged: both exit 1" || fail "dist/: sh=$sh_rc rs=$rs_rc"
git reset -q HEAD dist/
rm -rf dist

# Test 4: dist-server/ file staged — both exit 1
mkdir -p dist-server
touch dist-server/index.js
git add dist-server/index.js
sh_rc=0
bash "$sh_script" >/dev/null 2>&1 || sh_rc=$?
rs_rc=0
"$rust_bin" >/dev/null 2>&1 || rs_rc=$?
[ "$sh_rc" -eq 1 ] && [ "$rs_rc" -eq 1 ] && ok "dist-server/ staged: both exit 1" || fail "dist-server/: sh=$sh_rc rs=$rs_rc"
git reset -q HEAD dist-server/
rm -rf dist-server

# Test 5: bare .env staged — both exit 1
touch .env
git add .env
sh_rc=0
bash "$sh_script" >/dev/null 2>&1 || sh_rc=$?
rs_rc=0
"$rust_bin" >/dev/null 2>&1 || rs_rc=$?
[ "$sh_rc" -eq 1 ] && [ "$rs_rc" -eq 1 ] && ok "bare .env staged: both exit 1" || fail "bare .env: sh=$sh_rc rs=$rs_rc"
git reset -q HEAD .env
rm .env

exit "$failed"
