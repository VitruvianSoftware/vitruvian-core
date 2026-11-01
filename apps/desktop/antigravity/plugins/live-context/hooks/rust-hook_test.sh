#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Tests rust-hook.sh, the launcher every hook in hooks.json goes through, on a
# copy of this plugin's folder:
#
# - with Bazel's own rustc (RUST_HOOK_RUSTC, from BUILD) it builds the real
#   hooks/src and each hook answers, as a fresh install would;
# - with a stub rustc it builds once, reuses the binary, rebuilds when a source
#   changes, and does not retry a failed build;
# - with no rustc, or a build that fails, it prints the hook's fallback JSON
#   and says why on stderr;
# - every hooks.json command exists, and names a crate and source that exist.
#
# The test is identical in every plugin; plugin-specific checks are in the
# hook's own Rust tests.

set -u

fails=0
check() {
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"
		echo "  want: $3"
		echo "  got:  $2"
		fails=$((fails + 1))
	fi
}
contains() {
	case "$2" in
	*"$3"*) echo "ok   $1" ;;
	*)
		echo "FAIL $1"
		echo "  want text: $3"
		echo "  got:       $2"
		fails=$((fails + 1))
		;;
	esac
}

# Set by BUILD: Bazel's rustc and the plugin's folder name.
: "${REAL_RUSTC:?}" "${PLUGIN_NAME:?}"
real_rustc=$(cd "$(dirname "$REAL_RUSTC")" && pwd)/$(basename "$REAL_RUSTC")
# HOOKS_JSON (from BUILD) locates the plugin; by default, beside this file.
hooks_json=${HOOKS_JSON:-$(dirname "$0")/../hooks.json}
plugin_src=$(cd "$(dirname "$hooks_json")" && pwd)
plugin_name=$PLUGIN_NAME
tmp=${TEST_TMPDIR:-$(mktemp -d)}
plugin="$tmp/$plugin_name"
rm -rf "$plugin"
mkdir -p "$plugin"
# -L: the runfiles are links to the sources, which the test edits.
cp -RL "$plugin_src/hooks" "$plugin/hooks"
cp "$plugin_src/hooks.json" "$plugin/hooks.json"
chmod -R u+w "$plugin"

export HOME="$tmp/home"
export XDG_CACHE_HOME="$tmp/cache"
export ANTIGRAVITY_APP_DATA_DIR="$tmp/app"
mkdir -p "$HOME" "$ANTIGRAVITY_APP_DATA_DIR/live-context-state"
# Keep live-context's hook off the network: no git or gh probes.
echo '{"injectGit":false,"injectGitHub":false}' \
	>"$ANTIGRAVITY_APP_DATA_DIR/live-context-state/settings.json"
cache="$XDG_CACHE_HOME/antigravity-plugins"

# The hook scripts named in hooks.json, each with the crate, source and
# fallback it hands to rust-hook.sh.
hooks=$(sed -n 's/.*"command": *"\.\/\(hooks\/[^"]*\)".*/\1/p' "$plugin/hooks.json" | sort -u)
[ -n "$hooks" ] || {
	echo "FAIL hooks.json names no hooks"
	exit 1
}

for h in $hooks; do
	[ -x "$plugin/$h" ] && ok=0 || ok=1
	check "$h is executable" "$ok" "0"
	crate=$(sed -n 's/.*rust-hook\.sh" \([a-z_]*\) \([^ ]*\.rs\).*/\1/p' "$plugin/$h")
	main=$(sed -n 's/.*rust-hook\.sh" \([a-z_]*\) \([^ ]*\.rs\).*/\2/p' "$plugin/$h")
	[ -n "$crate" ] && [ -f "$plugin/hooks/src/$main" ] && ok=0 || ok=1
	check "$h runs an existing source (src/$main)" "$ok" "0"
	grep -q "$crate::" "$plugin/hooks/src/$main" && ok=0 || ok=1
	check "src/$main uses crate $crate" "$ok" "0"
done

run_hook() { # run_hook <hook script> <stdin>; stdout to $out, stderr to $err
	printf '%s' "$2" | (cd "$plugin" && sh -c "./$1") >"$tmp/out" 2>"$tmp/err"
	status=$?
	out=$(cat "$tmp/out")
	err=$(cat "$tmp/err")
}

# How many hook binaries (named <plugin>-<hook>-<sha256>) are cached;
# with an argument, only that hook's.
count_bins() {
	n=0
	for f in "$cache/$plugin_name-"*; do
		h=${f##*-}
		rest=${f#"$cache/$plugin_name-"}
		[ -z "${1:-}" ] || [ "$rest" = "$1-$h" ] || continue
		[ "${#h}" -eq 64 ] || continue
		case $h in *[!0-9a-f]*) continue ;; esac
		n=$((n + 1))
	done
	echo "$n"
}

fallback_of() {
	sed -n "s/^[[:space:]]*'\(.*\)'[[:space:]]*\$/\1/p" "$plugin/$1"
}

# --- 1. A real build with Bazel's rustc -----------------------------------
export RUST_HOOK_RUSTC="$real_rustc"
for h in $hooks; do
	run_hook "$h" '{}'
	check "$h builds with rustc and exits 0" "$status" "0"
	# A real answer is JSON and is not the fallback.
	case "$out" in
	"{"*"}") echo "ok   $h answers JSON" ;;
	*)
		echo "FAIL $h answers JSON: $out / $err"
		fails=$((fails + 1))
		;;
	esac
	check "$h: the launcher reports nothing on stderr" "$err" ""
	main=$(sed -n 's/.*rust-hook\.sh" [a-z_]* \([^ ]*\.rs\).*/\1/p' "$plugin/$h")
	check "$h: its binary is in the cache, named by the sources' sha256" \
		"$(count_bins "$(basename "$main" .rs)")" "1"
done

# --- 2. A stub rustc: build once, reuse, rebuild on change ----------------
rm -rf "$cache"
stub="$tmp/stub-rustc"
cat >"$stub" <<'EOF'
#!/bin/sh
echo call >>"$STUB_LOG"
[ -z "${STUB_FAIL:-}" ] || { echo "error: planted failure" >&2; exit 1; }
out=; prev=
for a; do [ "$prev" = "-o" ] && out=$a; prev=$a; done
case " $* " in
*" rlib "*) : >"$out" ;;
*) printf '#!/bin/sh\nprintf stub-hook:\ncat\n' >"$out"; chmod +x "$out" ;;
esac
EOF
chmod +x "$stub"
export RUST_HOOK_RUSTC="$stub"
export STUB_LOG="$tmp/stub.log"
: >"$STUB_LOG"
first=$(echo "$hooks" | head -n 1)

run_hook "$first" '{"x":1}'
check "the built hook gets the payload on stdin" "$out" 'stub-hook:{"x":1}'
check "a build is two rustc calls (library, then hook)" "$(wc -l <"$STUB_LOG" | tr -d ' ')" "2"
run_hook "$first" '{}'
check "a second run reuses the binary" "$(wc -l <"$STUB_LOG" | tr -d ' ')" "2"

before=$(count_bins)
check "the first build left one binary" "$before" "1"
echo "// edited" >>"$plugin/hooks/src/lib.rs"
run_hook "$first" '{}'
check "editing a source rebuilds" "$(wc -l <"$STUB_LOG" | tr -d ' ')" "4"
check "the old binary is removed" "$(count_bins)" "$before"

# --- 3. A build that fails -------------------------------------------------
echo "// edited again" >>"$plugin/hooks/src/lib.rs"
export STUB_FAIL=1
for h in $hooks; do
	: >"$STUB_LOG"
	run_hook "$h" '{}'
	check "$h: a failed build exits 0" "$status" "0"
	check "$h: a failed build prints the fallback" "$out" "$(fallback_of "$h")"
	contains "$h: a failed build says why" "$err" "does not build with"
	calls=$(wc -l <"$STUB_LOG" | tr -d ' ')
	run_hook "$h" '{}'
	check "$h: a failed build is not retried" "$(wc -l <"$STUB_LOG" | tr -d ' ')" "$calls"
	contains "$h: the retry says it did not build" "$err" "did not build with"
done
unset STUB_FAIL
leftover=no
for f in "$cache"/.build.*; do [ -e "$f" ] && leftover=yes; done
check "no build folders are left behind" "$leftover" "no"

# --- 4. No rustc ------------------------------------------------------------
echo "// and again" >>"$plugin/hooks/src/lib.rs"
export RUST_HOOK_RUSTC="$tmp/no-such-rustc"
for h in $hooks; do
	run_hook "$h" '{}'
	check "$h without rustc exits 0" "$status" "0"
	check "$h without rustc prints the fallback" "$out" "$(fallback_of "$h")"
	contains "$h without rustc says so" "$err" "rustc not found"
done

if [ "$fails" -ne 0 ]; then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
