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

# Regression guard for tools/ci/llvm-cache-key.sh.
#
# The load-bearing case is the FIRST one: the two fixtures are the real
# /etc/os-release from GitHub runner images 20260831.293 (Ubuntu 24.04.4) and
# 20260907.300 (24.04.5). The old key -- keyed only on runner.os plus
# hashFiles('MODULE.bazel') -- was IDENTICAL across that pair, so the point
# release kept hitting a 2.2GB entry whose contents Bazel then rejected and
# re-extracted, on every run, with no way to ever save the good one. That is
# the failure seen on #2242. If this test ever passes with a key that ignores
# /etc/os-release, it is not testing anything.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${1:-${HERE}/llvm-cache-key.sh}"

fails=0
ok() { printf '  ok - %s\n' "$1"; }
bad() { printf '  NOT OK - %s\n' "$1" >&2; fails=$((fails + 1)); }

# shellcheck source=/dev/null
source "$SCRIPT"
set +e -u -o pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# Verbatim shape of Ubuntu's /etc/os-release; VERSION/VERSION_ID/PRETTY_NAME
# all move on a point release, which is why the digest moves.
cat >"${tmp}/os-release-24044" <<'EOF'
PRETTY_NAME="Ubuntu 24.04.4 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.4 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
UBUNTU_CODENAME=noble
EOF
sed 's/24\.04\.4/24.04.5/g' "${tmp}/os-release-24044" >"${tmp}/os-release-24045"

MOD=aaaaaaaabbbbbbbbcccccccc

k4="$(llvm_cache_key Linux "$MOD" "${tmp}/os-release-24044")"
k5="$(llvm_cache_key Linux "$MOD" "${tmp}/os-release-24045")"

[ "$k4" != "$k5" ] \
  && ok "a runner-image point release (24.04.4 -> 24.04.5) changes the key" \
  || bad "24.04.4 and 24.04.5 produced the SAME key ($k4) — Bazel would reject the restored contents and re-extract on every run"

again="$(llvm_cache_key Linux "$MOD" "${tmp}/os-release-24044")"
[ "$k4" = "$again" ] \
  && ok "the same os-release gives a stable key (cache actually hits)" \
  || bad "key is not deterministic for identical input ($k4 vs $again)"

kmod="$(llvm_cache_key Linux ffffffff00000000 "${tmp}/os-release-24044")"
[ "$k4" != "$kmod" ] \
  && ok "a MODULE.bazel change still changes the key (llvm_versions bump)" \
  || bad "MODULE.bazel hash is not part of the key"

kmac="$(llvm_cache_key macOS "$MOD" "${tmp}/os-release-24044")"
[ "$k4" != "$kmac" ] \
  && ok "runner.os is still part of the key" \
  || bad "runner.os is not part of the key"

miss1="$(llvm_cache_key Linux "$MOD" "${tmp}/absent")"
miss2="$(llvm_cache_key Linux "$MOD" "${tmp}/absent")"
[ -n "$miss1" ] && [ "$miss1" = "$miss2" ] \
  && ok "an unreadable os-release degrades to a stable key, not an empty or random one" \
  || bad "missing os-release must still yield a stable non-empty key ($miss1 vs $miss2)"

case "$k4" in
  *' '*|*$'\n'*|'') bad "key must be a single bare token usable in a YAML cache key ($k4)" ;;
  *) ok "key is a single bare token" ;;
esac

# The v1 prefix is burned: those entries hold candidates from more than one
# image and Bazel validates none of them. A new scheme must not reuse it.
case "$k4" in
  llvm-contents-v1-*) bad "key still uses the poisoned v1 prefix ($k4)" ;;
  llvm-contents-v*) ok "key uses a fresh cache-scheme prefix" ;;
  *) bad "unexpected key shape ($k4)" ;;
esac

# Fail-closed on a missing digest tool. The first cut of this script used
# `local osrel="$(sha256sum ...)"`, where `local` masks the substitution's exit
# status -- on a box without coreutils it emitted `...-Linux--<modhash>`, an
# EMPTY digest segment that collapses every os-release back onto one key. That
# is the original bug wearing the fix's clothes, and nothing but this test
# noticed it. A key that cannot include its inputs must not be emitted at all.
mkdir -p "${tmp}/emptybin"
if PATH="${tmp}/emptybin" "${BASH}" "$SCRIPT" Linux "$MOD" "${tmp}/os-release-24044" >/dev/null 2>&1; then
  bad "with no sha256 tool on PATH the script emitted a key instead of failing"
else
  ok "no sha256 tool on PATH fails closed rather than emitting a partial key"
fi

case "$k4" in
  *--*) bad "key contains an empty segment ($k4) — a digest is missing" ;;
  *) ok "key has no empty segments" ;;
esac

out="$(bash "$SCRIPT" Linux "$MOD" "${tmp}/os-release-24044")"
[ "$out" = "$k4" ] \
  && ok "executing the script prints the same key the function returns" \
  || bad "main() and llvm_cache_key() disagree ('$out' vs '$k4')"

if [ "$fails" -eq 0 ]; then
  echo "llvm-cache-key: all checks passed"
  exit 0
fi
echo "llvm-cache-key: ${fails} check(s) failed" >&2
exit 1
