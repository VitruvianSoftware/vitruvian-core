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

# Hermetic guard for tools/ci/install-pinned-tool.sh. Fakes `curl` (no network,
# no GitHub-releases dependency — mirrors resolve-deploy-base_test.sh's
# fake-gh pattern) and exercises the real `tar`/`install`/`sha256sum` against
# fixture bytes, so both the --tar and --raw install paths, and the checksum
# verification itself, run for real.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/install-pinned-tool.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

fixtures="$work/fixtures"
mkdir -p "$fixtures"

# fake curl: `curl ... -O <url>` saves a file named after the URL's basename
# into the CURRENT directory (real curl's -O behavior), sourced from a
# fixtures dir keyed by that same basename — no network involved. Must be
# literally named "curl" (not e.g. "fake-curl") so PATH lookup shadows the
# real binary.
mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
if [ -n "${FAKE_CURL_RC:-}" ] && [ "${FAKE_CURL_RC}" != "0" ]; then
  echo "curl: fake transport failure" >&2
  exit "${FAKE_CURL_RC}"
fi
# last argument is always the URL for every invocation this script makes.
url="${@: -1}"
base="${url##*/}"
if [ ! -f "${FIXTURES_DIR}/${base}" ]; then
  echo "curl: no fixture for '${base}' (looked in ${FIXTURES_DIR})" >&2
  exit 22
fi
cp "${FIXTURES_DIR}/${base}" "./${base}"
EOF
chmod +x "$work/bin/curl"

# run <args...> — invokes the script with a fake curl on PATH, a scratch HOME
# (so ~/.local/bin lands somewhere disposable) and a scratch GITHUB_PATH file.
# Prints "rc=<n>" then the captured stdout+stderr, so callers can assert both.
run() {
  local scratch home ghpath
  scratch="$(mktemp -d)"
  home="$scratch/home"
  ghpath="$scratch/github_path"
  mkdir -p "$home"
  : > "$ghpath"
  (
    cd "$scratch" || exit 99
    PATH="$work/bin:$PATH" HOME="$home" GITHUB_PATH="$ghpath" FIXTURES_DIR="$fixtures" \
      bash "$SCRIPT" "$@"
  ) > "$scratch/stdout" 2>"$scratch/stderr"
  local rc=$?
  echo "$scratch"
  return "$rc"
}

# --- fixture setup: a --raw asset + matching checksums file -----------------
raw_asset="mytool_linux_amd64"
printf 'fake-binary-bytes-for-mytool\n' > "$fixtures/$raw_asset"
( cd "$fixtures" && sha256sum "$raw_asset" > "${raw_asset}_SHA256SUMS" )

# --- fixture setup: a --tar asset (contains a member named 'mytool') --------
tar_stage="$work/tar-stage"
mkdir -p "$tar_stage"
printf '#!/bin/sh\necho fake-tar-tool\n' > "$tar_stage/mytool"
chmod +x "$tar_stage/mytool"
( cd "$tar_stage" && tar -czf "$fixtures/mytool_linux_amd64.tar.gz" mytool )
( cd "$fixtures" && sha256sum mytool_linux_amd64.tar.gz > mytool_checksums.txt )

echo "--- --raw happy path ---"
scratch="$(run "https://example.invalid/download" "$raw_asset" "${raw_asset}_SHA256SUMS" "$raw_asset" mytool --raw)"
rc=$?
if [ "$rc" -eq 0 ]; then pass "--raw install exits 0"; else
  fail "--raw install should exit 0, got $rc"; sed 's/^/      /' "$scratch/stderr" >&2
fi
if [ -x "$scratch/home/.local/bin/mytool" ]; then pass "--raw: binary installed and executable"; else
  fail "--raw: binary not installed at expected path"
fi
if grep -qx "$scratch/home/.local/bin" "$scratch/github_path" 2>/dev/null; then
  pass "--raw: GITHUB_PATH gained ~/.local/bin"
else
  fail "--raw: GITHUB_PATH missing the expected line"
fi

echo "--- --tar happy path ---"
scratch="$(run "https://example.invalid/download" mytool_linux_amd64.tar.gz mytool_checksums.txt mytool_linux_amd64.tar.gz mytool --tar)"
rc=$?
if [ "$rc" -eq 0 ]; then pass "--tar install exits 0"; else
  fail "--tar install should exit 0, got $rc"; sed 's/^/      /' "$scratch/stderr" >&2
fi
if [ -x "$scratch/home/.local/bin/mytool" ] && grep -q fake-tar-tool "$scratch/home/.local/bin/mytool"; then
  pass "--tar: archive member extracted as the binary"
else
  fail "--tar: extracted binary missing or wrong content"
fi

echo "--- checksum mismatch fails closed and installs nothing ---"
bad_checksums="$fixtures/${raw_asset}_BAD_SHA256SUMS"
printf '0000000000000000000000000000000000000000000000000000000000000000  %s\n' "$raw_asset" > "$bad_checksums"
scratch="$(run "https://example.invalid/download" "$raw_asset" "${raw_asset}_BAD_SHA256SUMS" "$raw_asset" mytool --raw)"
rc=$?
if [ "$rc" -ne 0 ]; then pass "checksum mismatch exits non-zero"; else
  fail "checksum mismatch should fail the script, got rc=0"
fi
if [ ! -e "$scratch/home/.local/bin/mytool" ]; then
  pass "checksum mismatch: nothing installed"
else
  fail "checksum mismatch: a binary was installed despite the bad checksum"
fi

echo "--- transport failure propagates (no silent success) ---"
scratch2="$(mktemp -d)"
mkdir -p "$scratch2/home"
: > "$scratch2/github_path"
(
  cd "$scratch2" || exit 99
  PATH="$work/bin:$PATH" HOME="$scratch2/home" GITHUB_PATH="$scratch2/github_path" \
    FIXTURES_DIR="$fixtures" FAKE_CURL_RC=1 \
    bash "$SCRIPT" "https://example.invalid/download" "$raw_asset" "${raw_asset}_SHA256SUMS" "$raw_asset" mytool --raw
) > "$scratch2/stdout" 2>"$scratch2/stderr"
rc=$?
if [ "$rc" -ne 0 ]; then pass "curl transport failure exits non-zero"; else
  fail "curl transport failure should fail the script, got rc=0"
fi

echo "--- argument guards ---"
scratch="$(run only one arg)"
rc=$?
[ "$rc" -eq 2 ] && pass "wrong arg count exits 2" || fail "wrong arg count should exit 2, got $rc"

scratch="$(run "https://x" asset checksums pattern name --bogus-mode)"
rc=$?
[ "$rc" -eq 2 ] && pass "bad mode flag exits 2" || fail "bad mode flag should exit 2, got $rc"

echo "--- GITHUB_PATH required ---"
scratch2="$(mktemp -d)"
mkdir -p "$scratch2/home"
(
  cd "$scratch2" || exit 99
  env -u GITHUB_PATH PATH="$work/bin:$PATH" HOME="$scratch2/home" FIXTURES_DIR="$fixtures" \
    bash "$SCRIPT" "https://example.invalid/download" "$raw_asset" "${raw_asset}_SHA256SUMS" "$raw_asset" mytool --raw
) > "$scratch2/stdout" 2>"$scratch2/stderr"
rc=$?
if [ "$rc" -ne 0 ] && grep -q "GITHUB_PATH must be set" "$scratch2/stderr"; then
  pass "missing GITHUB_PATH fails with a clear message"
else
  fail "missing GITHUB_PATH should fail with the GITHUB_PATH message, got rc=$rc"
  sed 's/^/      /' "$scratch2/stderr" >&2
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
