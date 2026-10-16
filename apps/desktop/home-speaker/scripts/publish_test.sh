#!/bin/bash
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

# publish.sh must not report a release it did not make.
#
# HomeSpeaker 1.12.0 and 1.13.0 went out with no files: the packaging helper
# stopped half way, exited 0, and publish.sh printed "completed successfully".
# This runs the real publish.sh in a stand-in app folder, with stand-ins for
# swift / lipo / ditto / git, the two scripts it calls, and the helper, so it
# needs no Xcode and runs on any machine. It runs under every bash it finds;
# on a Mac that includes /bin/bash 3.2, the bash the release runner uses.
set -euo pipefail

ok() { echo "ok: $*"; }
fail() {
	echo "FAIL: $*" >&2
	exit 1
}

PUBLISH="${1:-}"
if [[ -z "$PUBLISH" ]]; then
	for candidate in \
		"${TEST_SRCDIR:-}/_main/apps/desktop/home-speaker/scripts/publish.sh" \
		"${BASH_SOURCE[0]%/*}/publish.sh"; do
		if [[ -f "$candidate" ]]; then
			PUBLISH="$candidate"
			break
		fi
	done
fi
[[ -f "$PUBLISH" ]] || fail "publish.sh not found"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Static, so it holds on every bash: no bare "${a[@]}" (an empty one ends the
# script on bash 3.2 under `set -u`); the guarded form is ${a[@]+"${a[@]}"}.
bare_array_expansions() {
	grep -n '' "$1" |
		grep -vE '^[0-9]+:[[:space:]]*#' |
		sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\+"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\}"\}//g' |
		grep -E '\[[@*]\]\}' || true
}
bare="$(bare_array_expansions "$PUBLISH")"
[[ -z "$bare" ]] || fail "bare array expansion in publish.sh (breaks bash 3.2 when empty):
$bare"
printf 'x=()\necho "${x[@]}"\n' >"$TMP_DIR/planted.sh"
[[ -n "$(bare_array_expansions "$TMP_DIR/planted.sh")" ]] || fail "the static check does not see a planted bare expansion"
ok "no bare array expansion in publish.sh (and the check sees a planted one)"

# The stand-in repository: publish.sh finds everything relative to itself.
ROOT="$TMP_DIR/repo"
APP="$ROOT/apps/desktop/home-speaker"
STUBS="$TMP_DIR/stubs"
FAKE_BIN="$TMP_DIR/swift-bin"
mkdir -p "$APP/scripts" "$ROOT/tools/desktop-package" "$STUBS" "$FAKE_BIN"
cp "$PUBLISH" "$APP/scripts/publish.sh"

cat >"$STUBS/swift" <<'STUB'
#!/bin/sh
for a in "$@"; do
  if [ "$a" = "--show-bin-path" ]; then echo "${FAKE_BIN:?}"; exit 0; fi
done
echo binary > "${FAKE_BIN:?}/HomeSpeaker"
echo binary > "${FAKE_BIN:?}/homespeaker-tool"
STUB
cat >"$STUBS/lipo" <<'STUB'
#!/bin/sh
# lipo <in> -thin <arch> -output <out>   |   lipo -info <in>
if [ "$2" = "-thin" ]; then cp "$1" "$5"; fi
STUB
cat >"$STUBS/ditto" <<'STUB'
#!/bin/sh
cp -R "$1" "$2"
STUB
# No git: publish.sh then finds the root three folders up, the stand-in one.
cat >"$STUBS/git" <<'STUB'
#!/bin/sh
exit 1
STUB
cat >"$APP/scripts/bundle.sh" <<'STUB'
#!/bin/sh
mkdir -p "$3/HomeSpeaker.app/Contents/MacOS"
cp "$1" "$3/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"
STUB
# The zip's stand-in also says which sign-in client it was given: the
# release job sets the two variables for publish.sh, and the real
# zip-tool.sh ships them in the tool's zip.
cat >"$APP/scripts/zip-tool.sh" <<'STUB'
#!/bin/sh
mkdir -p "$3"
echo zip > "$3/HomeSpeaker-$2-tool.zip"
printf '%s|%s\n' "${HOMESPEAKER_GOOGLE_CLIENT_ID:-}" "${HOMESPEAKER_GOOGLE_CLIENT_SECRET:-}" > "${ZIP_CLIENT:?}"
STUB
# The helper's stand-in. HELPER_MODE says how it behaves:
#   good      makes every artifact and checksum, exits 0
#   fails     exits 3
#   nothing   makes nothing, exits 0   (what 1.12.0 and 1.13.0 hit)
#   no-sidecar makes everything but the tool zip's checksum, exits 0
cat >"$ROOT/tools/desktop-package/package-desktop.sh" <<'STUB'
#!/bin/sh
echo "$*" > "${HELPER_ARGS:?}"
dist=""; version=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dist-dir) dist="$2"; shift ;;
    --version) version="$2"; shift ;;
  esac
  shift
done
case "${HELPER_MODE:?}" in
  fails) exit 3 ;;
  nothing) exit 0 ;;
esac
for n in universal.dmg arm64.dmg x86_64.dmg universal.zip; do
  echo data > "$dist/HomeSpeaker-$version-$n"
  echo sum > "$dist/HomeSpeaker-$version-$n.sha256"
done
if [ "$HELPER_MODE" != "no-sidecar" ]; then
  echo sum > "$dist/HomeSpeaker-$version-tool.zip.sha256"
fi
STUB
chmod +x "$STUBS"/* "$APP/scripts"/*.sh "$ROOT/tools/desktop-package/package-desktop.sh"

HELPER_ARGS="$TMP_DIR/helper.args"
ZIP_CLIENT="$TMP_DIR/zip.client"
# run_publish <shell> <helper mode> [TAG=...] -- [publish args]; leaves RC, OUT.
run_publish() {
	local shell="$1" mode="$2"
	shift 2
	local envs=()
	while [[ "$1" != "--" ]]; do
		envs+=("$1")
		shift
	done
	shift
	: >"$HELPER_ARGS"
	RC=0
	OUT="$(env -u TAG -u GH_TOKEN -u GITHUB_TOKEN \
		-u HOMESPEAKER_GOOGLE_CLIENT_ID -u HOMESPEAKER_GOOGLE_CLIENT_SECRET PATH="$STUBS:$PATH" FAKE_BIN="$FAKE_BIN" \
		HELPER_ARGS="$HELPER_ARGS" ZIP_CLIENT="$ZIP_CLIENT" HELPER_MODE="$mode" VERSION=9.9.9 ${envs[@]+"${envs[@]}"} \
		"$shell" "$APP/scripts/publish.sh" "$@" 2>&1)" || RC=$?
}

SHELLS=("bash")
HAVE_BASH3=false
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
	HAVE_BASH3=true
fi
if [[ -x /bin/bash ]] && [[ "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')" -lt 4 ]]; then
	if [[ "$HAVE_BASH3" != "true" || "$(command -v bash)" != "/bin/bash" ]]; then
		SHELLS+=("/bin/bash")
	fi
	HAVE_BASH3=true
fi
if [[ "$HAVE_BASH3" == "true" ]]; then
	echo "bash 3.x present: the empty-array-under-set-u case IS exercised here"
else
	echo "NOTE: no bash 3.x on this machine ($(bash --version | head -1)): the empty-array case is covered here only by the static check above; the macOS lane runs it for real"
	[[ "${REQUIRE_BASH32:-}" != "1" ]] || fail "REQUIRE_BASH32=1 but no bash 3.x was found"
fi

DONE_LINE="HomeSpeaker release packaging completed successfully"
for shell in "${SHELLS[@]}"; do
	ver="$("$shell" -c 'echo "$BASH_VERSION"')"
	echo "=== publish.sh under $shell ($ver) ==="

	# No tag, no --dry-run: nothing extra to pass, the empty array of the
	# bash 3.2 case. It must still run the helper and succeed.
	run_publish "$shell" good --
	[[ "$RC" -eq 0 ]] || fail "[$ver] plain run with a healthy helper: exit $RC
$OUT"
	grep -q "$DONE_LINE" <<<"$OUT" || fail "[$ver] healthy run did not say it finished"
	grep -Fq -- "--require-asset HomeSpeaker-9.9.9-tool.zip" "$HELPER_ARGS" || fail "[$ver] the tool zip was not required of the helper: $(cat "$HELPER_ARGS")"
	grep -Eq -- '--(dry-run|tag)' "$HELPER_ARGS" && fail "[$ver] a plain run passed --dry-run or --tag: $(cat "$HELPER_ARGS")"
	ok "[$ver] a healthy plain run succeeds and requires the tool zip"

	run_publish "$shell" good HOMESPEAKER_GOOGLE_CLIENT_ID=made-up-id HOMESPEAKER_GOOGLE_CLIENT_SECRET=made-up-secret -- # gitleaks:allow
	[[ "$RC" -eq 0 ]] || fail "[$ver] a run with a sign-in client: exit $RC
$OUT"
	[[ "$(cat "$ZIP_CLIENT")" == "made-up-id|made-up-secret" ]] || fail "[$ver] the sign-in client did not reach zip-tool.sh: $(cat "$ZIP_CLIENT")"
	ok "[$ver] the release's sign-in client reaches the tool's zip"

	run_publish "$shell" good TAG=home-speaker-v9.9.9 -- --dry-run
	[[ "$RC" -eq 0 ]] || fail "[$ver] dry run with a tag: exit $RC
$OUT"
	grep -Fq -- "--dry-run --tag home-speaker-v9.9.9" "$HELPER_ARGS" || fail "[$ver] --dry-run and --tag did not reach the helper: $(cat "$HELPER_ARGS")"
	ok "[$ver] --dry-run and the tag reach the helper"

	run_publish "$shell" fails TAG=home-speaker-v9.9.9 --
	[[ "$RC" -ne 0 ]] || fail "[$ver] the helper failed and publish.sh exited 0"
	grep -q "$DONE_LINE" <<<"$OUT" && fail "[$ver] the helper failed and publish.sh said it finished"
	ok "[$ver] a failing helper fails publish.sh"

	run_publish "$shell" nothing TAG=home-speaker-v9.9.9 --
	[[ "$RC" -ne 0 ]] || fail "[$ver] the helper made nothing, exited 0, and publish.sh exited 0"
	grep -q "$DONE_LINE" <<<"$OUT" && fail "[$ver] nothing was packaged and publish.sh said it finished"
	grep -q "left no HomeSpeaker-9.9.9-universal.dmg in dist" <<<"$OUT" || fail "[$ver] the missing files were not named:
$OUT"
	ok "[$ver] a helper that exits 0 having made nothing fails publish.sh"

	run_publish "$shell" no-sidecar -- --dry-run
	[[ "$RC" -ne 0 ]] || fail "[$ver] the tool zip had no checksum and publish.sh exited 0"
	grep -q "left no HomeSpeaker-9.9.9-tool.zip.sha256 in dist" <<<"$OUT" || fail "[$ver] the missing checksum was not named:
$OUT"
	ok "[$ver] a missing tool zip checksum fails publish.sh"
done

echo "All publish.sh tests passed."
