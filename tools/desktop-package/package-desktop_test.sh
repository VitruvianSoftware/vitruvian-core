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

set -euo pipefail

SCRIPT_UNDER_TEST="${1:-tools/desktop-package/package-desktop.sh}"
if [[ ! -f "$SCRIPT_UNDER_TEST" ]]; then
  # Check if in runfiles
  if [[ -f "${TEST_SRCDIR}/_main/tools/desktop-package/package-desktop.sh" ]]; then
    SCRIPT_UNDER_TEST="${TEST_SRCDIR}/_main/tools/desktop-package/package-desktop.sh"
  elif [[ -f "${BASH_SOURCE[0]%/*}/package-desktop.sh" ]]; then
    SCRIPT_UNDER_TEST="${BASH_SOURCE[0]%/*}/package-desktop.sh"
  fi
fi

# 1. Source pure library
PACKAGE_DESKTOP_LIB_ONLY=1 . "$SCRIPT_UNDER_TEST"

ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "=== Running unit tests for package-desktop pure helpers ==="

# Test clean_version
v1="$(clean_version "home-speaker-v1.11.0")"
[[ "$v1" == "1.11.0" ]] || fail "clean_version failed for home-speaker tag: got $v1"
ok "clean_version home-speaker-v1.11.0 -> 1.11.0"

v2="$(clean_version "vitruvian-v3.37.1")"
[[ "$v2" == "3.37.1" ]] || fail "clean_version failed for vitruvian tag: got $v2"
ok "clean_version vitruvian-v3.37.1 -> 3.37.1"

v3="$(clean_version "nexus-agent-v1.20.1")"
[[ "$v3" == "1.20.1" ]] || fail "clean_version failed for nexus-agent tag: got $v3"
ok "clean_version nexus-agent-v1.20.1 -> 1.20.1"

v4="$(clean_version "v2.0.4")"
[[ "$v4" == "2.0.4" ]] || fail "clean_version failed for v-tag: got $v4"
ok "clean_version v2.0.4 -> 2.0.4"

v5="$(clean_version "4.5.6")"
[[ "$v5" == "4.5.6" ]] || fail "clean_version failed for raw semver: got $v5"
ok "clean_version 4.5.6 -> 4.5.6"

v6="$(clean_version "nexus-agent-1.20.1")"
[[ "$v6" == "1.20.1" ]] || fail "clean_version failed for tag without v prefix: got $v6"
ok "clean_version nexus-agent-1.20.1 -> 1.20.1"

v7="$(clean_version "vitruvian-v3.38.0-beta.1")"
[[ "$v7" == "3.38.0-beta.1" ]] || fail "clean_version failed for prerelease: got $v7"
ok "clean_version vitruvian-v3.38.0-beta.1 -> 3.38.0-beta.1"

# Test cask_name_for_app
c1="$(cask_name_for_app "HomeSpeaker")"
[[ "$c1" == "home-speaker" ]] || fail "cask_name_for_app HomeSpeaker failed: got $c1"
ok "cask_name_for_app HomeSpeaker -> home-speaker"

c2="$(cask_name_for_app "NexusAgent")"
[[ "$c2" == "nexus-agent" ]] || fail "cask_name_for_app NexusAgent failed: got $c2"
ok "cask_name_for_app NexusAgent -> nexus-agent"

c3="$(cask_name_for_app "Vitruvian")"
[[ "$c3" == "vitruvian" ]] || fail "cask_name_for_app Vitruvian failed: got $c3"
ok "cask_name_for_app Vitruvian -> vitruvian"

c4="$(cask_name_for_app "MyNewDesktopClient")"
[[ "$c4" == "my-new-desktop-client" ]] || fail "cask_name_for_app MyNewDesktopClient failed: got $c4"
ok "cask_name_for_app MyNewDesktopClient -> my-new-desktop-client"

# Test expected_artifact_names
artifacts="$(expected_artifact_names "TestApp" "1.0.0")"
echo "$artifacts" | grep -q "^TestApp-1.0.0-universal.dmg$" || fail "missing universal dmg in expected artifacts"
echo "$artifacts" | grep -q "^TestApp-1.0.0-arm64.dmg$" || fail "missing arm64 dmg in expected artifacts"
echo "$artifacts" | grep -q "^TestApp-1.0.0-x86_64.dmg$" || fail "missing x86_64 dmg in expected artifacts"
echo "$artifacts" | grep -q "^TestApp-1.0.0-universal.zip$" || fail "missing universal zip in expected artifacts"
echo "$artifacts" | grep -q "^TestApp-1.0.0.dmg$" || fail "missing legacy dmg in expected artifacts"
ok "expected_artifact_names produces complete 5-item artifact matrix"

# Test generate_cask_ruby
ruby_cask="$(generate_cask_ruby "test-app" "1.0.0" "fake_sha256" "https://example.com/TestApp-1.0.0-universal.dmg" "TestApp" "A test app" "https://example.com")"

echo "$ruby_cask" | grep -q 'cask "test-app" do' || fail "cask declaration missing"
echo "$ruby_cask" | grep -q 'version "1.0.0"' || fail "version declaration missing"
echo "$ruby_cask" | grep -q 'sha256 "fake_sha256"' || fail "sha256 declaration missing"
echo "$ruby_cask" | grep -q 'url "https://example.com/TestApp-1.0.0-universal.dmg"' || fail "url declaration missing"
echo "$ruby_cask" | grep -q 'name "TestApp"' || fail "name declaration missing"
echo "$ruby_cask" | grep -q 'desc "A test app"' || fail "desc declaration missing"
echo "$ruby_cask" | grep -q 'homepage "https://example.com"' || fail "homepage declaration missing"
echo "$ruby_cask" | grep -q 'app "TestApp.app"' || fail "app bundle declaration missing"
ok "generate_cask_ruby generates valid Homebrew Cask specification"

# Test dry-run packaging flow with mock app
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MOCK_APP="$TMP_DIR/MockApp.app"
mkdir -p "$MOCK_APP/Contents/MacOS"
mkdir -p "$MOCK_APP/Contents/Resources"
echo "#!/bin/sh" > "$MOCK_APP/Contents/MacOS/MockApp"
chmod +x "$MOCK_APP/Contents/MacOS/MockApp"
cat > "$MOCK_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MockApp</string>
    <key>CFBundleShortVersionString</key>
    <string>2.3.4</string>
</dict>
</plist>
EOF

MOCK_DIST="$TMP_DIR/dist"
mkdir -p "$MOCK_DIST"

echo "==> Executing CLI dry-run package test..."
bash "$SCRIPT_UNDER_TEST" \
  --app-path "$MOCK_APP" \
  --dist-dir "$MOCK_DIST" \
  --version "2.3.4" \
  --skip-signing \
  --skip-dmg \
  --dry-run

[[ -f "$MOCK_DIST/MockApp-2.3.4-universal.zip" ]] || fail "universal zip was not created"
[[ -f "$MOCK_DIST/MockApp-2.3.4-universal.zip.sha256" ]] || fail "universal zip checksum was not created"

# Verify that the checksum file uses relative filename and shasum -c succeeds
if command -v shasum >/dev/null 2>&1; then
  (cd "$MOCK_DIST" && shasum -c "MockApp-2.3.4-universal.zip.sha256") >/dev/null 2>&1 || fail "shasum -c failed on generated sidecar"
elif command -v sha256sum >/dev/null 2>&1; then
  (cd "$MOCK_DIST" && sha256sum -c "MockApp-2.3.4-universal.zip.sha256") >/dev/null 2>&1 || fail "sha256sum -c failed on generated sidecar"
fi
ok "checksum validation succeeded on artifact sidecar"

[[ -f "$MOCK_DIST/mock-app.rb" ]] || fail "cask formula mock-app.rb was not created"

grep -q 'version "2.3.4"' "$MOCK_DIST/mock-app.rb" || fail "mock-app.rb missing version"
grep -q 'app "MockApp.app"' "$MOCK_DIST/mock-app.rb" || fail "mock-app.rb missing app bundle"

ok "CLI dry run produced valid universal zip, checksum sidecar, and Cask formula"

# ------------------------------------------------------------------------------
# What a release must hold (pure)
# ------------------------------------------------------------------------------
req="$(required_release_assets "TestApp" "1.0.0" false false "TestApp-1.0.0-tool.zip")"
[[ "$(grep -c . <<<"$req")" == "14" ]] || fail "full contract + one extra should be 14 names, got: $req"
for n in universal.zip macOS.zip universal.dmg arm64.dmg x86_64.dmg tool.zip; do
  grep -Fxq "TestApp-1.0.0-${n}" <<<"$req" || fail "required list lacks TestApp-1.0.0-${n}"
  grep -Fxq "TestApp-1.0.0-${n}.sha256" <<<"$req" || fail "required list lacks the ${n} checksum"
done
grep -Fxq "TestApp-1.0.0.dmg" <<<"$req" || fail "required list lacks the plain dmg"
[[ "$(required_release_assets "TestApp" "1.0.0" true false | grep -c .)" == "4" ]] || fail "--skip-dmg should leave the two zips and their checksums"
[[ "$(required_release_assets "TestApp" "1.0.0" false true | grep -c .)" == "8" ]] || fail "--skip-thinning should drop only the per-arch dmgs"
ok "required_release_assets lists each artifact with its checksum, and follows the skip flags"

[[ -z "$(missing_assets $'a\nb' $'b\na\nc')" ]] || fail "missing_assets reported something when all were present"
[[ "$(missing_assets $'a\nb\nc' $'b')" == $'a\nc' ]] || fail "missing_assets did not name exactly the missing ones"
[[ "$(missing_assets $'a.zip' $'a.zip.sha256')" == "a.zip" ]] || fail "missing_assets matched a longer name"
ok "missing_assets names exactly what is absent"

# ------------------------------------------------------------------------------
# No bare expansion of an array (static; holds on every bash)
#
# macOS ships bash 3.2, where "${a[@]}" of an EMPTY array under `set -u` is an
# "unbound variable" error. Newer bash (the Linux lane) does not reproduce it,
# so this check is what catches a new one there: every [@] expansion outside a
# comment must be the guarded form ${a[@]+"${a[@]}"}.
# ------------------------------------------------------------------------------
bare_array_expansions() {
  grep -n '' "$1" \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\+"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\}"\}//g' \
    | grep -E '\[[@*]\]\}' || true
}
bare="$(bare_array_expansions "$SCRIPT_UNDER_TEST")"
[[ -z "$bare" ]] || fail "bare array expansion (breaks bash 3.2 when the array is empty); write \${a[@]+\"\${a[@]}\"}:
$bare"
printf 'x=()\necho "${x[@]}"\n' > "$TMP_DIR/planted.sh"
[[ -n "$(bare_array_expansions "$TMP_DIR/planted.sh")" ]] || fail "the static check does not see a planted bare expansion"
ok "no bare array expansion in package-desktop.sh (and the check sees a planted one)"

# ------------------------------------------------------------------------------
# The real driver, signing ad hoc, under every bash this machine has
#
# Stand-ins for codesign / security / gh / python3 sit first on PATH, so this
# runs anywhere and signs nothing. On a Mac /bin/bash is 3.2, the bash the
# release runner uses: that run is the one that proves the empty-array case.
# REQUIRE_BASH32=1 (set by the macOS lane in ci.yaml) fails the test if no
# bash 3.x was found, so that lane cannot quietly stop proving it.
# ------------------------------------------------------------------------------
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

STUBS="$TMP_DIR/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/codesign" <<'EOF'
#!/bin/sh
echo "$*" >> "${CODESIGN_LOG:?}"
EOF
cat > "$STUBS/security" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$STUBS/python3" <<'EOF'
#!/bin/sh
echo "argc=$# $*" >> "${PYTHON_LOG:?}"
EOF
# gh: `release upload` records the file's name, `release view` lists them.
cat > "$STUBS/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "release upload")
    name="$(basename "$4")"
    if [ "$name" != "${GH_STUB_DROP:-}" ] && [ -s "$4" ]; then
      echo "$name" >> "${GH_STUB_STATE:?}"
    fi
    ;;
  "release view")
    cat "${GH_STUB_STATE:?}" 2>/dev/null || true
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$STUBS"/*

# The driver finds the downloads sync script beside itself, so it runs from a
# stand-in repository root that has one.
FAKE_ROOT="$TMP_DIR/repo"
mkdir -p "$FAKE_ROOT/tools/desktop-package" "$FAKE_ROOT/tools/sync-downloads"
cp "$SCRIPT_UNDER_TEST" "$FAKE_ROOT/tools/desktop-package/package-desktop.sh"
: > "$FAKE_ROOT/tools/sync-downloads/sync_downloads.py"
DRIVER="$FAKE_ROOT/tools/desktop-package/package-desktop.sh"

CASE_N=0
# run_driver <shell> <driver> [env NAME=VALUE ...] -- <driver args...>
# Leaves: RC, OUT (stdout+stderr), DIST, CODESIGN_LOG, PYTHON_LOG, GH_STUB_STATE.
run_driver() {
  local shell="$1" driver="$2"
  shift 2
  local envs=()
  while [[ "$1" != "--" ]]; do
    envs+=("$1")
    shift
  done
  shift
  CASE_N=$((CASE_N + 1))
  local dir="$TMP_DIR/case-$CASE_N"
  DIST="$dir/dist"
  mkdir -p "$DIST"
  CODESIGN_LOG="$dir/codesign.log"
  PYTHON_LOG="$dir/python.log"
  GH_STUB_STATE="$dir/gh.state"
  : > "$CODESIGN_LOG"
  : > "$PYTHON_LOG"
  if [[ -n "${PRESEED:-}" ]]; then
    echo "tool" > "$DIST/$PRESEED"
  fi
  RC=0
  OUT="$(env -u BUILD_WORKSPACE_DIRECTORY -u GH_TOKEN -u GITHUB_TOKEN -u HOMEBREW_TAP_TOKEN \
    -u SIGNING_IDENTITY -u TAG -u RELEASE_TAG -u GITHUB_ACTIONS \
    PATH="$STUBS:$PATH" CODESIGN_LOG="$CODESIGN_LOG" PYTHON_LOG="$PYTHON_LOG" \
    GH_STUB_STATE="$GH_STUB_STATE" VERIFY_RETRY_SECONDS=0 ${envs[@]+"${envs[@]}"} \
    "$shell" "$driver" --app-path "$MOCK_APP" --dist-dir "$DIST" --version 2.3.4 --skip-dmg "$@" 2>&1)" || RC=$?
}

# A copy of the driver with one line planted after a marker line.
plant() {
  local marker="$1" line="$2" out="$3"
  awk -v m="$marker" -v l="$line" '{ print } index($0, m) == 1 { print l }' "$DRIVER" > "$out"
  grep -Fq -- "$line" "$out" || fail "could not plant a line after: $marker"
}
mkdir -p "$FAKE_ROOT/tools/planted"
plant '# 6. Checksums' 'exit 0' "$FAKE_ROOT/tools/planted/stops-early.sh"
plant 'sign_bundle() {' '  local planted=(); : "${planted[@]}"' "$FAKE_ROOT/tools/planted/bare-array.sh"

for shell in "${SHELLS[@]}"; do
  ver="$("$shell" -c 'echo "$BASH_VERSION"')"
  echo "=== driver under $shell ($ver) ==="

  # Ad hoc signing with no entitlements: the path every release takes, and the
  # one that ended the script on bash 3.2 (`ent_arg[@]: unbound variable`).
  run_driver "$shell" "$DRIVER" -- --dry-run
  [[ "$RC" -eq 0 ]] || fail "[$ver] ad hoc signing, no entitlements: exit $RC
$OUT"
  grep -q 'unbound variable' <<<"$OUT" && fail "[$ver] unbound variable:
$OUT"
  grep -Eq -- '^--force --sign - .*/universal/MockApp\.app$' "$CODESIGN_LOG" || fail "[$ver] the bundle was not signed ad hoc: $(cat "$CODESIGN_LOG")"
  [[ -s "$DIST/MockApp-2.3.4-universal.zip" && -s "$DIST/MockApp-2.3.4-universal.zip.sha256" ]] || fail "[$ver] signed, but no zip + checksum"
  ok "[$ver] ad hoc signing with no entitlements packages the app"

  : > "$TMP_DIR/ent.plist"
  run_driver "$shell" "$DRIVER" -- --dry-run --entitlements "$TMP_DIR/ent.plist"
  [[ "$RC" -eq 0 ]] || fail "[$ver] with entitlements: exit $RC
$OUT"
  grep -Fq -- "--force --entitlements $TMP_DIR/ent.plist --sign - " "$CODESIGN_LOG" || fail "[$ver] entitlements were not passed to codesign: $(cat "$CODESIGN_LOG")"
  ok "[$ver] entitlements, when given, reach codesign"

  # A real release: upload, then read the release back. Not a dry run, so the
  # downloads sync runs with no arguments (a second empty array).
  PRESEED="MockApp-2.3.4-tool.zip" run_driver "$shell" "$DRIVER" GH_TOKEN=stub -- \
    --tag mock-app-v2.3.4 --require-asset MockApp-2.3.4-tool.zip
  [[ "$RC" -eq 0 ]] || fail "[$ver] release run: exit $RC
$OUT"
  [[ "$(sort "$GH_STUB_STATE" | tr '\n' ' ')" == "MockApp-2.3.4-macOS.zip MockApp-2.3.4-macOS.zip.sha256 MockApp-2.3.4-tool.zip MockApp-2.3.4-tool.zip.sha256 MockApp-2.3.4-universal.zip MockApp-2.3.4-universal.zip.sha256 " ]] \
    || fail "[$ver] uploaded set is wrong: $(sort "$GH_STUB_STATE" | tr '\n' ' ')"
  grep -q 'all 6 expected artifacts present (release)' <<<"$OUT" || fail "[$ver] the release was not read back:
$OUT"
  grep -Fxq 'argc=1 '"$FAKE_ROOT/tools/sync-downloads/sync_downloads.py" "$PYTHON_LOG" || fail "[$ver] downloads sync did not run with no extra arguments: $(cat "$PYTHON_LOG")"
  ok "[$ver] a release run uploads every artifact and reads the release back"

  # One upload that never lands: the run must fail and name it.
  PRESEED="MockApp-2.3.4-tool.zip" run_driver "$shell" "$DRIVER" GH_TOKEN=stub GH_STUB_DROP=MockApp-2.3.4-tool.zip -- \
    --tag mock-app-v2.3.4 --require-asset MockApp-2.3.4-tool.zip
  [[ "$RC" -ne 0 ]] || fail "[$ver] an asset missing from the release still exited 0"
  grep -Eq '^ +- MockApp-2\.3\.4-tool\.zip$' <<<"$OUT" || fail "[$ver] the missing asset was not named:
$OUT"
  grep -q 'packaging complete' <<<"$OUT" && fail "[$ver] claimed completion with an asset missing"
  ok "[$ver] an asset missing from the release fails the run, by name"

  # No token: the upload is skipped. That must not look like a release.
  run_driver "$shell" "$DRIVER" -- --tag mock-app-v2.3.4
  [[ "$RC" -ne 0 ]] || fail "[$ver] a release run that uploaded nothing exited 0"
  ok "[$ver] a release run that uploads nothing fails"

  # A promised extra artifact that was never made, in a dry run.
  run_driver "$shell" "$DRIVER" -- --dry-run --require-asset MockApp-2.3.4-tool.zip
  [[ "$RC" -ne 0 ]] || fail "[$ver] a required artifact absent from dist exited 0"
  grep -Eq '^ +- MockApp-2\.3\.4-tool\.zip$' <<<"$OUT" || fail "[$ver] the absent artifact was not named:
$OUT"
  ok "[$ver] a dry run fails when a required artifact is not in dist"

  # A driver that stops half way must never exit 0, whatever stopped it.
  run_driver "$shell" "$FAKE_ROOT/tools/planted/stops-early.sh" -- --dry-run
  [[ "$RC" -ne 0 ]] || fail "[$ver] a driver that stopped before the end exited 0"
  ok "[$ver] stopping before the end is a failure"

  if [[ "${ver%%.*}" -lt 4 ]]; then
    # The exact 1.12.0 / 1.13.0 failure: bash 3.2 ends the script on the bare
    # array, runs the EXIT trap with \$? = 0, and used to exit 0.
    run_driver "$shell" "$FAKE_ROOT/tools/planted/bare-array.sh" -- --dry-run
    grep -q 'unbound variable' <<<"$OUT" || fail "[$ver] the planted bare array did not end the script; the plant is wrong:
$OUT"
    [[ "$RC" -ne 0 ]] || fail "[$ver] an unbound-variable abort exited 0"
    ok "[$ver] an unbound-variable abort exits non-zero (it exited 0 before)"
  fi

  # --verify-only: the workflow's last step.
  PRESEED="MockApp-2.3.4-tool.zip" run_driver "$shell" "$DRIVER" GH_TOKEN=stub -- \
    --tag mock-app-v2.3.4 --require-asset MockApp-2.3.4-tool.zip
  state="$GH_STUB_STATE"
  rc=0
  out="$(PATH="$STUBS:$PATH" GH_STUB_STATE="$state" VERIFY_RETRY_SECONDS=0 "$shell" "$DRIVER" --verify-only \
    --app-name MockApp --tag mock-app-v2.3.4 --skip-dmg --require-asset MockApp-2.3.4-tool.zip 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || fail "[$ver] --verify-only failed on a complete release: $out"
  rc=0
  out="$(PATH="$STUBS:$PATH" GH_STUB_STATE="$state" VERIFY_RETRY_SECONDS=0 "$shell" "$DRIVER" --verify-only \
    --app-name MockApp --tag mock-app-v2.3.4 --require-asset MockApp-2.3.4-tool.zip 2>&1)" || rc=$?
  [[ "$rc" -ne 0 ]] || fail "[$ver] --verify-only passed a release with no dmg"
  grep -Eq '^ +- MockApp-2\.3\.4-universal\.dmg$' <<<"$out" || fail "[$ver] --verify-only did not name the missing dmg: $out"
  : > "$TMP_DIR/empty.state"
  rc=0
  out="$(PATH="$STUBS:$PATH" GH_STUB_STATE="$TMP_DIR/empty.state" VERIFY_RETRY_SECONDS=0 "$shell" "$DRIVER" --verify-only \
    --app-name MockApp --tag mock-app-v2.3.4 --skip-dmg 2>&1)" || rc=$?
  [[ "$rc" -ne 0 ]] || fail "[$ver] --verify-only passed a release with no assets at all"
  ok "[$ver] --verify-only passes a complete release and fails an incomplete or empty one"
done

echo "All package-desktop tests passed successfully!"
